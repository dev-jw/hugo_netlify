---
title: "iOS底层原理探索-isa自测题分析"
date: 2020-09-15T10:45:30+08:00
draft: true
tags: ['iOS']
url:  "isa-question-analysis"
---

首先，我们再来回顾一下题目

### 代码一

```objc
@interface Cat : Animal
@end

@implementation Cat
- (id)init
{
    self = [super init];
    if (self)
    {
        NSLog(@"%@", NSStringFromClass([self class]));
        NSLog(@"%@", NSStringFromClass([super class]));
      
        NSLog(@"%@", NSStringFromClass([self superclass]));
        NSLog(@"%@", NSStringFromClass([super superclass]));
    }
return self;
}
@end
```

打印结果为：`Cat、Cat、Animal、Animal`

> 调用方法本质就是消息发送

先来看 `class` 源码，`class`方法返回类，而 `superclass`方法返回父类

```c++
+ (Class)class {
    return self;
}

- (Class)class {
    return object_getClass(self);
}

Class object_getClass(id obj)
{
    if (obj) return obj->getIsa();
    else return Nil;
}

+ (Class)superclass {
    return self->superclass;
}

- (Class)superclass {
    return [self class]->superclass;
}
```

通过 `clang` 编译

- `[self class]`在底层为`objc_msgSend(self, sel_registerName(class))`
- `[super class]`在底层为`objc_msgSendSuper(slef, class_getSuperclass(objc_getClass("Person")), sel_registerName(class))`

看一下 `objc_msgSendSuper` 定义

```c++
OBJC_EXPORT void
objc_msgSendSuper(void /* struct objc_super *super, SEL op, ... */ )
    OBJC_AVAILABLE(10.0, 2.0, 9.0, 1.0, 2.0);

struct objc_super {
    /// Specifies an instance of a class.
    __unsafe_unretained _Nonnull id receiver;

    /// Specifies the particular superclass of the instance to message. 
#if !defined(__cplusplus)  &&  !__OBJC2__
    /* For compatibility with old objc-runtime.h header */
    __unsafe_unretained _Nonnull Class class;
#else
    __unsafe_unretained _Nonnull Class super_class;
#endif
    /* super_class is the first class to search */
};
```

所以，这两个方法调用的消息接收者都是 `self`， 方法编号都为 `class`

只是 `[super class]` 在底层为`objc_msgSendSuper`，而实际在运行时，真正调用的则是`objc_msgSendSuper2`

综上，`[slef class]`与`[super class]` 的消息查找过程为：`Cat -> Animal -> NSObject`，都返回`Cat`

同理`[self superclass]`与`[super superclass]`的消息查找过程为：`Animal -> NSObject`，返回`Animal`

**完整的回答**

- `[self class]`调用 `class` 的消息流程，拿到实例对象的`isa`——类对象，因为类已经加载到内存，所以读取时是一个字符串类型，这个字符串类型是在 `map_images` 的 `readClass` 时，进行类的重映射，因此打印为 `Cat`
- `[super class]`打印的是`Cat`，这是因为当前的 `super` 是一个**关键字**，在底层实际调用的是`objc_msgSendSuper2`，其消息接收者和 `[self class]` 是一样的，只不过是从父类中开始查找消息而已

### 代码二

```objc
@interface Person : NSObject
@end

@implementation Person
@end

int main(int argc, const char * argv[]) {
  @autoreleasepool {
      BOOL res1 = [(id)[NSObject class] isKindOfClass:[NSObject class]];
      BOOL res2 = [(id)[NSObject class] isMemberOfClass:[NSObject class]];
      BOOL res3 = [(id)[Person class] isKindOfClass:[Person class]];
      BOOL res4 = [(id)[Person class] isMemberOfClass:[Person class]];

      NSLog(@"%d %d %d %d", res1, res2, res3, res4);
    
      BOOL res5 = [(id)[NSObject alloc] isKindOfClass:[NSObject class]];
      BOOL res6 = [(id)[NSObject alloc] isMemberOfClass:[NSObject class]];
      BOOL res7 = [(id)[Person alloc] isKindOfClass:[Person class]];
      BOOL res8 = [(id)[Person alloc] isMemberOfClass:[Person class]];
    
      NSLog(@"%d %d %d %d", res5, res6, res7, res8);
  }
  return 0;
}
```

在打印结果之前，我们先来看一下这两个函数的源码

```objective-c
+ (BOOL)isMemberOfClass:(Class)cls {
    return self->ISA() == cls;
}

- (BOOL)isMemberOfClass:(Class)cls {
    return [self class] == cls;
}

+ (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = self->ISA(); tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

- (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = [self class]; tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

// Calls [obj isKindOfClass]
BOOL
objc_opt_isKindOfClass(id obj, Class otherClass)
{
#if __OBJC2__
    if (slowpath(!obj)) return NO;
    Class cls = obj->getIsa();
    if (fastpath(!cls->hasCustomCore())) {
        for (Class tcls = cls; tcls; tcls = tcls->superclass) {
            if (tcls == otherClass) return YES;
        }
        return NO;
    }
#endif
    return ((BOOL(*)(id, SEL, Class))objc_msgSend)(obj, @selector(isKindOfClass:), otherClass);
}
```

**`+ (BOOL)isKindOfClass:(Class)cls`方法内部流程:**

1. 会调用 `self->ISA()`, 而实际是去调用`objc_object`的 `ISA()` 方法，即返回当前类 self 的元类
2. 在循环中，判断`当前类cls`是否等于 `meta class`
   - 不相等：会执行`tcls = tcls->superclass`，获取 `superclass`，直到 `superclass` 为 nil
   - 相等：返回结果 `ture`

**执行过程：**

`[NSObject Class]`执行完，调用`isKindOfClass`。

- 第一次判断 NSObject 和 NSObject的 meta class是否相等，根据之前 isa 走位图，显然不等

- 第二次循环判断NSObject与meta class的superclass是否相等，同样根据 isa 走位图，可以看到`Root class(meta)` 的superclass 就是 `Root class(class)`，也就是NSObject本身

所以第二次循环相等，于是第一行`res1`输出应该为`YES`

**`- (BOOL)isKindOfClass:(Class)cls`方法内部流程：**

1. 调用 `[self class]`, 去获得 `objec_getClass` 的类，
2. `object_getClass` 的源码实际是去调用当前类的 `obj->getIsa()` 方法， 
3. 在`objc_object`的 `ISA()` 方法中返回元类的指针给`tcls`
4. 在循环中，会先判断`当前类cls`是否等于`meta class`
   - 不相等：会执行`tcls = tcls->superclass`，获取 `superclass`，直到 `superclass` 为 nil
   - 相等：返回结果 `ture`

**执行过程：**

`[Person Class]`执行完，调用`isKindOfClass`。

- 第一次 for 循环，Person 的 Meta Class 与 [Person class] 不相等
- 第二次 for 循环，Person Meta Class 的 superclass 指向的是 NSObject Meta Class，和 [Person class] 不相等
- 第三次 for 循环，NSObject Meta Class 的 superclass 指向的是 NSObject Class，和 [Person class] 不相等
- 第四次 for 循环，NSObject class 的 superclass 指向的是 nil，和 [Person class] 不相等

第四次循环之后，退出循环，所以第三行的`res3`输出为`NO`

### 代码三

```objc
@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
- (void)speak;
@end
@implementation Person
- (void)speak {                            
   NSLog(@"my name's %@", self.name);
}
@end
  
@implementation ViewController
- (void)viewDidLoad {  
   [super viewDidLoad];
  
   id cls = [Person class];
   void *obj = &cls;
   [(__bridge id)obj speak];
}
@end
```

输出为：`my name's <ViewController: 0x7fc4ce904d20>`

内存地址每次运行都不同，但是一定是ViewController

#### 分析

消息发送的本质就是调用`objc_megSend`

```objective-c
id cls = [Person class];
```

首先获取到 `Person` 的类对象，`id` 表示将其转换为一个对象指针，属于关键字，实际类型为`struct objc_object *`

```c++
typedef struct objc_class *Class;
typedef struct objc_object *id;

struct objc_object {
private:
    isa_t isa;
  // ...
}
```

而`[Person class]`返回的类型为 `Class`，即`struct objc_class`

虽然是用 `id`，但是其本质还是`struct objc_class`，即**本质还是类对象**

```objective-c
void *obj = &cls;
```

定义了一个变量 `obj`，指向了 `cls` 的地址，也就说 **obj 就说 cls 的地址**

**clang编译**

```c++
// 简化后的
static void _I_ViewController_viewDidLoad(ViewController * self, SEL _cmd) {
    objc_msgSendSuper((__rw_objc_super){self, class_getSuperclass(objc_getClass("ViewController"))}, sel_registerName("viewDidLoad")); // 1
    id cls = objc_msgSend(objc_getClass("Person"), sel_registerName("class")); // 2
    void *obj = &cls; // 3
    objc_msgSend(obj, sel_registerName("speak")); // 4
}
```

执行过程为：

1. 对应 **[super viewDidLoad]**
2. 对应 **id cls = [Person class];**
3. 对应 **void \*obj = &cls;**
4. 对应 **[(__bridge id)obj speak];**

**objc_msgSend** 会传入两个隐式参数`self`和`_cmd`，想必大家已经很熟悉了

```c++
objc_msgSend(void /* id self, SEL op, ... */ )
    OBJC_AVAILABLE(10.0, 2.0, 9.0, 1.0, 2.0);
```

而 **objc_msgSendSuper** 需要传入另一个结构体 `struct objc_super *`，上面已经提及到了

**变量入栈顺序**

因此，在viewDidLoad中的变量入栈顺序为：

1. `self、_cmd`为函数的隐式参数，依次入栈
2. `superclass`即`class_getSuperclass(objc_getClass("ViewController"))}`入栈
3. `self`
4. `cls`
5. `obj`

验证一下：

```objective-c
@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
- (void)speak;
@end

@implementation Person
- (void)speak {
    NSLog(@"my name's %@", self.name);
}
@end

@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    id cls = [Person class]; // 1
    void *obj = &cls; // 2
  
    NSLog(@"栈区变量");
    void *start = (void *)&self;
    void *end = (void *)&obj;
    long count = (start - end) / 0x8;
    for (long i = 0; i < count; i++) {
        void *address = start - 0x8 * i;
        printf("-----\n"); // 加入调试断点，输出 frame variable address
    }
    NSLog(@"obj speak");
    [(__bridge id)obj speak]; // 3
}
@end
  
// 断点打印
(void *) address = 0x00007ffeeca7d158
(lldb) p *(void **)address
(ViewController *) $2 = 0x00007ffa1b607c30
-----
  
(void *) address = 0x00007ffeeca7d150
(lldb) p *(char **)address
(char *) $3 = 0x0000000114d585cc "viewDidLoad"
-----

(ViewController *) address = 0x00007ffeeca7d148
(lldb) p *(void **)address
(ViewController *) $4 = 0x000000010318c860
-----
  
(void *) address = 0x00007ffeeca7d140
(lldb) p *(void **)address
(ViewController *) $6 = 0x00007ffa1b607c30
  
-----
(Person *) address = 0x00007ffeeca7d138
(lldb) p *(void **)address
(Person *) $7 = 0x000000010318c838  
```

**变量栈示意图**

![image-20201209224430132](https://w-md.imzsy.design/image-20201209224430132.png)

从打印结果可以看到，cls 向上偏移一个指针就是self, 这也正好是ViewController，而 obj 就是 cls 的地址

所以输出为my name is <ViewController: 0x7fc4ce904d20>。

#### 总结

根据这个面试题，我们可以知道 objc 中的对象到底是什么？

结论：

- 在 Objc 中的对象是一个指向 **class_object** 地址的变量，即`id obj = &cls`
- 对象的实例变量 `void *ivar = &obj + offset(N)`


> 参考资料：
>
> [从源代码看 ObjC 中消息的发送](https://github.com/draveness/analyze/blob/master/contents/objc/%E4%BB%8E%E6%BA%90%E4%BB%A3%E7%A0%81%E7%9C%8B%20ObjC%20%E4%B8%AD%E6%B6%88%E6%81%AF%E7%9A%84%E5%8F%91%E9%80%81.md)
>
> [神经病院 Objective-C Runtime 入院第一天—— isa 和 Class](https://halfrost.com/objc_runtime_isa_class/#class)

