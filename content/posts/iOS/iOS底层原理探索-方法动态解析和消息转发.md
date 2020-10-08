---
title: "iOS底层原理探索-方法动态解析和消息转发"
date: 2020-09-23T20:04:52+08:00
draft: false
tags: [iOS]
url:  "message-forward"
---

在上一篇文章讲了方法查找的过程，简单提及在找不到 IMP 的时候，会进行**动态方法解析**和**消息转发**，本文将对这两个过程进行详细的分析。

同样的，先提出几个问题：

- 动态方法解析是什么
- 消息快速转发流程
- 消息慢速转发流程

在慢速消息查找后，即从父类找到 NSObject 都没有IMP，那么就会来到**动态方法解析**

#### 动态方法解析

只有`behavior`不为`LOOKUP_RESOLVER`时，才会进**动态方法解析**

```objective-c
// No implementation found. Try method resolver once.

if (slowpath(behavior & LOOKUP_RESOLVER)) {
    behavior ^= LOOKUP_RESOLVER;
    return resolveMethod_locked(inst, sel, cls, behavior);
}
```

在进入该流程后，会将`behavior`并上`LOOKUP_RESOLVER`，那么也就说：`动态方法解析只会进行一次`

**resolveMethod_locked**

```c++
static NEVER_INLINE IMP
resolveMethod_locked(id inst, SEL sel, Class cls, int behavior)
{
    runtimeLock.assertLocked();
    ASSERT(cls->isRealized());

    runtimeLock.unlock();

    if (! cls->isMetaClass()) {
        // try [cls resolveInstanceMethod:sel]
        resolveInstanceMethod(inst, sel, cls);
    } 
    else {
        // try [nonMetaClass resolveClassMethod:sel]
        // and [cls resolveInstanceMethod:sel]
        resolveClassMethod(inst, sel, cls);
        if (!lookUpImpOrNil(inst, sel, cls)) {
            resolveInstanceMethod(inst, sel, cls);
        }
    }

    // chances are that calling the resolver have populated the cache
    // so attempt using it
    return lookUpImpOrForward(inst, sel, cls, behavior | LOOKUP_CACHE);
}
```

`resolveMethod_locked`函数首先会判断是否是`meta class`类

- 不是元类，就执行`resolveInstanceMethod`方法
- 是元类，执行`resolveClassMethod`方法

> 这里需要打开读锁，因为开发者可能会在这里动态增加方法实现，所以不需要缓存结果。
>
> 这里锁被打开，可能会出现线程问题，所以在尾部调用`lookUpImpOrForward`，重新执行一遍之前查找的过程。

**lookUpImpOrNil**

```c++
static inline IMP
lookUpImpOrNil(id obj, SEL sel, Class cls, int behavior = 0)
{
    return lookUpImpOrForward(obj, sel, cls, behavior | LOOKUP_CACHE | LOOKUP_NIL);
}
```

`lookUpImpOrNil`内部还是会去调用`lookUpImpOrForward`去查找有没有传入的`sel`的实现，最终会走到`done_nolock`，且`imp == forward_imp`，即`imp == _objc_msgForward_impcache`，最终返回 nil

再回到`resolveMethod_locked`的实现中，如果`lookUpImpOrNil`返回`nil`，就代表在父类中的缓存中没有找到`resolveClassMethod`方法，于是需要再调用一次`resolveInstanceMethod`方法。保证给`sel`添加上了对应的`IMP`。

**resolveInstanceMethod**

对于**实例方法**没有找到 `IMP` 时，会调用`resolveInstanceMethod`方法

```c++
static void resolveInstanceMethod(id inst, SEL sel, Class cls)
{
    runtimeLock.assertUnlocked();
    ASSERT(cls->isRealized());
    SEL resolve_sel = @selector(resolveInstanceMethod:);

    if (!lookUpImpOrNil(cls, resolve_sel, cls->ISA())) {
        // Resolver not implemented.
        return;
    }

    BOOL (*msg)(Class, SEL, SEL) = (typeof(msg))objc_msgSend;
    bool resolved = msg(cls, resolve_sel, sel);

    // Cache the result (good or bad) so the resolver doesn't fire next time.
    // +resolveInstanceMethod adds to self a.k.a. cls
    IMP imp = lookUpImpOrNil(inst, sel, cls);

    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] "
                         "dynamically resolved to %p", 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }
        else {
            // Method resolver didn't add anything?
            _objc_inform("RESOLVE: +[%s resolveInstanceMethod:%s] returned YES"
                         ", but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}
```

主要过程为：

- 检查类cls中是否有`resolveInstanceMethod`方法实现
  - 如果找到，则调用
  - 如果没有找到，则调用`lookUpImpOrNil`再次查找当前实例方法imp，找到就填充缓存，找不到就返回

**resolveClassMethod**

```c++
static void resolveClassMethod(id inst, SEL sel, Class cls)
{
    runtimeLock.assertUnlocked();
    ASSERT(cls->isRealized());
    ASSERT(cls->isMetaClass());

    if (!lookUpImpOrNil(inst, @selector(resolveClassMethod:), cls)) {
        // Resolver not implemented.
        return;
    }

    Class nonmeta;
    {
        mutex_locker_t lock(runtimeLock);
        nonmeta = getMaybeUnrealizedNonMetaClass(cls, inst);
        // +initialize path should have realized nonmeta already
        if (!nonmeta->isRealized()) {
            _objc_fatal("nonmeta class %s (%p) unexpectedly not realized",
                        nonmeta->nameForLogging(), nonmeta);
        }
    }
    BOOL (*msg)(Class, SEL, SEL) = (typeof(msg))objc_msgSend;
    bool resolved = msg(nonmeta, @selector(resolveClassMethod:), sel);

    // Cache the result (good or bad) so the resolver doesn't fire next time.
    // +resolveClassMethod adds to self->ISA() a.k.a. cls
    IMP imp = lookUpImpOrNil(inst, sel, cls);

    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] "
                         "dynamically resolved to %p", 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }
        else {
            // Method resolver didn't add anything?
            _objc_inform("RESOLVE: +[%s resolveClassMethod:%s] returned YES"
                         ", but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}
```

对于**类方法**没有找到 `IMP` 时，会调用`resolveClassMethod`方法，与**实例方法**类似

**总结**

**动态方法解析**是指可以在运行时动态地为一个方法提供实现，即子类重写`resolveInstanceMethod`或`resolveClassMethod`

- `实例方法`可以重写`resolveInstanceMethod`添加 IMP
- `类方法`可以重写`resolveClassMethod`向元类添加 IMP，根据 isa 走位也可以在 NSObject 分类中重写`resolveInstanceMethod`
- **动态方法解析**只要在任意一步`lookUpImpOrNil`查找到`imp`就不会查找下去——即`本类`做了动态方法决议，不会走到`NSObjct分类`的动态方法决议

那么把所有崩溃都在 NSObject 分类中处理，加以前缀区分业务逻辑，岂不是一劳永逸？显然这是不可能的，原因如下：

- 统一处理，耦合度太高
- 逻辑处理过多
- 在 NSObject 分类动态方法解析之前已经做了处理
- SDK 封装的时候需要给一个容错空间

再回到`lookUpImpOrForward`方法中，如果也没有找到`IMP`的实现，`method resolver`也没用了，则只能进入消息转发阶段。

#### 消息转发

`_objc_msgForward_impcache`是一个标记，这个标记用来表示在父类的缓存中停止继续查找。

汇编实现，会跳转到`__objc_msgForward`

```asm
STATIC_ENTRY __objc_msgForward_impcache

b	__objc_msgForward

END_ENTRY __objc_msgForward_impcache

ENTRY __objc_msgForward

adrp	x17, __objc_forward_handler@PAGE
ldr	p17, [x17, __objc_forward_handler@PAGEOFF]
TailCallFunctionPointer x17

END_ENTRY __objc_msgForward

```

`__objc_msgForward`是消息转发阶段的入口，本质是调用`__objc_forward_handler`函数

```c++
// Default forward handler halts the process.
__attribute__((noreturn, cold)) void
objc_defaultForwardHandler(id self, SEL sel)
{
    _objc_fatal("%c[%s %s]: unrecognized selector sent to instance %p "
                "(no message forward handler is installed)", 
                class_isMetaClass(object_getClass(self)) ? '+' : '-', 
                object_getClassName(self), sel_getName(sel), self);
}
void *_objc_forward_handler = (void*)objc_defaultForwardHandler;
```

当我们给一个对象发送一个没有实现的方法时，如果其父类也没有这个方法，则会崩溃，报错信息类似于这样：

`unrecognized selector sent to instance`，然后接着会跳出一些堆栈信息。而这些信息正是从这里而来

```ruby
2020-09-23 20:12:00.376415+0800 ObjcTest[3044:4851366] -[Person run]: unrecognized selector sent to instance 0x10073c7b0
2020-09-23 20:12:00.377984+0800 ObjcTest[3044:4851366] *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[Person run]: unrecognized selector sent to instance 0x10073c7b0'
*** First throw call stack:
(
	0   CoreFoundation                      0x00007fff33a95b57 __exceptionPreprocess + 250
	1   libobjc.A.dylib                     0x00000001002e9820 objc_exception_throw + 48
	2   CoreFoundation                      0x00007fff33b14be7 -[NSObject(NSObject) __retain_OA] + 0
	3   CoreFoundation                      0x00007fff339fa3bb ___forwarding___ + 1427
	4   CoreFoundation                      0x00007fff339f9d98 _CF_forwarding_prep_0 + 120
	5   ObjcTest                            0x0000000100003c34 main + 68
	6   libdyld.dylib                       0x00007fff6dab3cc9 start + 1
	7   ???                                 0x0000000000000001 0x0 + 1
)
libc++abi.dylib: terminating with uncaught exception of type NSException
```

仔细看一下堆栈信息，崩溃之前底层还调用了`___forwarding___`和`_CF_forwarding_prep_0`等方法，但是`CoreFoundation库`不开源。

```objective-c
extern void instrumentObjcMessageSends(BOOL flag);

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        FXSon *son = [[FXSon alloc] init];
        
        instrumentObjcMessageSends(true);
        [son doInstanceNoImplementation];
        instrumentObjcMessageSends(false);
    }
}
```

根据`log_and_fill_cache`方法缓存，不难发现`objcMsgLogEnabled`会记录所有方法调用，那么我们可以借助它来看一下在崩溃前具体调用了哪些方法

```
+ Person NSObject resolveInstanceMethod:
+ Person NSObject resolveInstanceMethod:
- Person NSObject forwardingTargetForSelector:
- Person NSObject forwardingTargetForSelector:
- Person NSObject methodSignatureForSelector:
- Person NSObject methodSignatureForSelector:
- Person NSObject class
+ Person NSObject resolveInstanceMethod:
+ Person NSObject resolveInstanceMethod:
- Person NSObject doesNotRecognizeSelector:
- Person NSObject doesNotRecognizeSelector:
- Person NSObject class
...
```

在**动态方法解析**与`doesNotRecognizeSelector`崩溃之间，就是**消息转发**

- 快速消息转发：`forwardingTargetForSelector`
- 慢速消息转发：`methodSignatureForSelector`

##### 快速消息转发

当前的 SEL 无法找到相应的 IMP 时，可以通过重写`- (id)forwardingTargetForSelector:(SEL)aSelector`方法，将消息的接受者缓存一个可以处理该消息的对象

```objective-c
- (id)forwardingTargetForSelector:(SEL)aSelector
{
    if(aSelector == @selector(Method:)){
        return otherObject;
    }
    return [super forwardingTargetForSelector:aSelector];
}
```

当然也可以替换类方法，那就是重写`+ (id)forwardingTargetForSelector:(SEL)aSelector`方法，返回的是一个类对象

```objective-c
+ (id)forwardingTargetForSelector:(SEL)aSelector {
    if(aSelector == @selector(xxx)) {
        return NSClassFromString(@"Class name");
    }
    return [super forwardingTargetForSelector:aSelector];
}
```

这一步是替换消息接收者，找备援消息接收者，如果这一步返回的是 `nil`，那么补救措施就无用了。

此时会进入慢速消息转发流程，**Runtime**会向对象发送 `methodSignatureForSelector` 消息，并取到返回的方法签名用于生成 `NSInvocation` 对象。

##### 慢速消息转发

为接下来的慢速消息转发生成一个`NSMethodSignature`对象。

`NSMethodSignature` 对象会被包装成 `NSInvocation` 对象，`forwardInvocation:` 方法里就可以对 `NSInvocation` 进行处理了。

```objective-c
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector{
    NSLog(@"%s -- %@",__func__,NSStringFromSelector(aSelector));
    if (aSelector == @selector(doInstanceNoImplementation)) {
        return [NSMethodSignature signatureWithObjCTypes:"v@:"];
    }
    return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    if ([someOtherObject respondsToSelector:
         [anInvocation selector]])
        [anInvocation invokeWithTarget:someOtherObject];
    else
        [super forwardInvocation:anInvocation];
}
```

实现上面的方法后，若发现某个调用不应由本类处理，则会调用超类的同名

这样，继承链中的每个类都有机会处理该方法调用的请求，一直到 NSObject 根类

如果 NSObject 也不能处理该条消息，那么就是真的无法挽救了，只能抛出`doesNotRecognizeSelector`崩溃异常

#### 消息转发流程图

![消息转发](https://w-md.imzsy.design/消息转发.png)

#### 简单 AOP 例子

利用 Runtime 消息转发机制创建一个动态代理，通过这个动态代理来转发消息。

这里需要借助基类 `NSProxy`

`NSProxy`类和`NSObject`同为`OC`里面的基类，但是`NSProxy`类是一种抽象的基类，无法直接实例化，可用于实现代理模式。

它通过实现一组经过简化的方法，代替目标对象捕捉和处理所有的消息。

`NSProxy`类也同样实现了NSObject的协议声明的方法，而且它有两个必须实现的方法。

```objective-c
- (void)forwardInvocation:(NSInvocation *)invocation;
- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)sel NS_SWIFT_UNAVAILABLE("NSInvocation and related APIs not available");
```

另外还需要说明的是，`NSProxy`类的子类必须声明并实现至少一个`init`方法，这样才能符合OC中创建和初始化对象的惯例。

**Foundation**框架里面也含有多个`NSProxy`类的具体实现类。

- `NSDistantObject`类：定义其他应用程序或线程中对象的代理类。
- `NSProtocolChecker`类：定义对象，使用这话对象可以限定哪些消息能够发送给另外一个对象。

具体例子代码，请查看[这里](https://github.com/dev-jw/AOP)

### 测试

下面的代码会？`Compile Error` / `Runtime Crash` / `NSLog...`?

```objective-c
@interface NSObject (Sark)
+ (void)foo;
- (void)foo;
@end

@implementation NSObject (Sark)
- (void)foo
{
  NSLog(@"IMP: -[NSObject(Sark) foo]");
}

@end

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    [NSObject foo];
    [[NSObject new] foo];
}
 return 0;
}
```

### 总结

Objective-C 的消息机制分为三个阶段：

- 消息查找阶段：
  - 快速查找：从类、父类等的方法缓存中查找方法
  - 慢速查找：从类、父类等的方法列表中查找方法
- 动态解析阶段：如果消息查找阶段没有找到方法，会进入方法动态解析阶段，动态的添加方法实现
  - 实例方法：通过`resolveInstanceMethod`进行方法动态解析
  - 类方法：通过`resolveClassMethod`进行方法动态解析
- 消息转发阶段：如果没有实现动态解析方法，则会进入消息转发阶段，将方法转发给可以处理消息的接受者来处理
  - 快速消息转发：实现`forwardingTargetForSelector`方法，替换消息接收者
  - 慢速消息转发：实现`methodSignatureForSelector`方法，返回方法签名，再在`forwardInvocation`进行消息处理

动态方法解析、快速消息转发和慢速消息转发，正是当崩溃时，我们可以有三次挽救的机会