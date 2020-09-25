---
title: "iOS底层原理探索-方法动态解析和消息转发"
date: 2020-09-23T20:04:52+08:00
draft: true
tags: [iOS]
url:  "message-forward"
---



#### 动态方法解析

```c++
if (slowpath(behavior & LOOKUP_RESOLVER)) {
    behavior ^= LOOKUP_RESOLVER;
    return resolveMethod_locked(inst, sel, cls, behavior);
}

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

`lookUpImpOrNil`内部还是会去调用`lookUpImpOrForward`去查找有没有传入的`sel`的实现，最终会走到`done_nolock`，且`imp == forward_imp`，即`imp == _objc_msgForward_impcache`，返回 nil

> 这里需要打开读锁，因为开发者可能会在这里动态增加方法实现，所以不需要缓存结果。
>
> 这里锁被打开，可能会出现线程问题，所以在尾部调用`lookUpImpOrForward`，重新执行一遍之前查找的过程。

再回到`resolveMethod_locked`的实现中，如果`lookUpImpOrNil`返回`nil`，就代表在父类中的缓存中没有找到`resolveClassMethod`方法，于是需要再调用一次`resolveInstanceMethod`方法。保证给`sel`添加上了对应的`IMP`。

回到`lookUpImpOrForward`方法中，如果也没有找到`IMP`的实现，那么`method resolver`也没用了，只能进入消息转发阶段。

进入这个阶段之前，imp变成`_objc_msgForward_impcache`。最后再加入缓存中。

> 



#### 消息转发

**`_objc_msgForward_impcache`定义**

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



### 总结

Objective-C 的消息机制分为三个阶段：

- 消息查找阶段：
  - 快速查找：从类、父类等的方法缓存中查找方法
  - 慢速查找：从类、父类等的方法列表中查找方法
- 动态解析阶段：如果消息查找阶段没有找到方法，会进入方法动态解析阶段，动态的添加方法实现
  - 实例方法：通过`resolveInstanceMethod`进行方法动态解析
  - 类方法：通过`resolveClassMethod`进行方法动态解析
- 消息转发阶段：如果没有实现动态解析方法，则会进入消息转发阶段，将方法转发给可以处理消息的接受者来处理