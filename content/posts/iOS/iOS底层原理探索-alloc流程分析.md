---
title: "iOS底层原理探索-alloc流程分析"
date: 2020-09-04T11:29:07+08:00
draft: false
tags: ["iOS"]
url:  "alloc"
---

首先，我们抛出几个问题，带着这些问题去探索 alloc 流程，可以加深我们对 alloc 流程的理解

- alloc 究竟做了什么
- alloc 过程中如何确定对象开辟内存的大小
- alloc、init、new 的区别是什么
- `NSObject`类和继承 `NSObject` 类的alloc流程有什么区别

**准备工作**

在开始之前，我们需要先对**objc源码**进行配置，并且编译。具体过程，可以参考这篇文章：『[objc源码编译调试](https://juejin.im/post/6844903959161733133)』

#### alloc 流程分析

**alloc流程图**

![image-20200909151920112](https://w-md.imzsy.design/image-20200909151920112.png)

通过 alloc 流程图，我们可以得出：调用 `alloc` 的时候，会先来到 `objc_alloc` 方法。

> 这里有个疑问：
>
> 明明调用的是 alloc 方法，为什么会进到 objc_alloc 方法中呢？
>
> 这是因为在 `llvm` 中，对一些特殊的入口进行了修饰，比如：调用 alloc 方法，实际会调用 objc_alloc 方法。

**llvm 对于特殊入口alloc的修饰处理**

```cpp
static Optional<llvm::Value *>
tryGenerateSpecializedMessageSend(CodeGenFunction &CGF, QualType ResultType,
                                  llvm::Value *Receiver,
                                  const CallArgList& Args, Selector Sel,
                                  const ObjCMethodDecl *method,
                                  bool isClassMessage) {
  auto &CGM = CGF.CGM;
  if (!CGM.getCodeGenOpts().ObjCConvertMessagesToRuntimeCalls)
    return None;

  auto &Runtime = CGM.getLangOpts().ObjCRuntime;
  switch (Sel.getMethodFamily()) {
  case OMF_alloc:
    if (isClassMessage &&
        Runtime.shouldUseRuntimeFunctionsForAlloc() &&
        ResultType->isObjCObjectPointerType()) {
        // [Foo alloc] -> objc_alloc(Foo) or
        // [self alloc] -> objc_alloc(self)
        if (Sel.isUnarySelector() && Sel.getNameForSlot(0) == "alloc")
          // 调用下面的转换方法
          return CGF.EmitObjCAlloc(Receiver, CGF.ConvertType(ResultType));
        // [Foo allocWithZone:nil] -> objc_allocWithZone(Foo) or
        // [self allocWithZone:nil] -> objc_allocWithZone(self)
        if (Sel.isKeywordSelector() && Sel.getNumArgs() == 1 &&
            Args.size() == 1 && Args.front().getType()->isPointerType() &&
            Sel.getNameForSlot(0) == "allocWithZone") {
          const llvm::Value* arg = Args.front().getKnownRValue().getScalarVal();
          if (isa<llvm::ConstantPointerNull>(arg))
            return CGF.EmitObjCAllocWithZone(Receiver,
                                             CGF.ConvertType(ResultType));
          return None;
        }
    }
    break;
    ...
}
  
llvm::Value *CodeGenFunction::EmitObjCAlloc(llvm::Value *value,
                                            llvm::Type *resultType) {
  return emitObjCValueOperation(*this, value, resultType,
                                CGM.getObjCEntrypoints().objc_alloc,
                                "objc_alloc");
}
```

我们通过打印调用堆栈信息，可以发现 `NSObject`类和继承 `NSObject` 类并不相同

- `NSObject` 的 alloc 流程：

  ```shell
  * thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 4.2
    * frame #0: 0x000000010031c5be libobjc.A.dylib`objc_alloc [inlined] callAlloc(cls=NSObject, checkNil=true, allocWithZone=false) at NSObject.mm:1704:9
      frame #1: 0x000000010031c5be libobjc.A.dylib`objc_alloc(cls=NSObject) at NSObject.mm:1730
      frame #2: 0x0000000100000e9b ObjcTest`main(argc=1, argv=0x00007ffeefbff5d0) at main.m:33:25 [opt]
      frame #3: 0x00007fff6824fcc9 libdyld.dylib`start + 1
  ```

- 继承 `NSObject` 类的 alloc 流程：

  ```shell
  * thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 4.1
    * frame #0: 0x00000001002c1c8e libobjc.A.dylib`_objc_rootAlloc [inlined] callAlloc(cls=Person, checkNil=false, allocWithZone=true) at NSObject.mm:1704:9
      frame #1: 0x00000001002c1c8e libobjc.A.dylib`_objc_rootAlloc(cls=Person) at NSObject.mm:1723
      frame #2: 0x000000010031e409 libobjc.A.dylib`+[NSObject alloc](self=Person, _cmd="alloc") at NSObject.mm:2321:12
      frame #3: 0x000000010031c665 libobjc.A.dylib`objc_alloc [inlined] callAlloc(cls=Person, checkNil=true, allocWithZone=false) at NSObject.mm:1714:12
      frame #4: 0x000000010031c5be libobjc.A.dylib`objc_alloc(cls=Person) at NSObject.mm:1730
      frame #5: 0x0000000100000eab ObjcTest`main(argc=1, argv=0x00007ffeefbff5d0) at main.m:35:26 [opt]
      frame #6: 0x00007fff6824fcc9 libdyld.dylib`start + 1
  ```

上面的堆栈信息，可以验证我们为什么调用 alloc 方法，会先进到 objc_alloc。

但是，这里有一个新的问题：**为什么继承 NSObject 的会调用两次 alloc 方法？**

##### 核心函数理解

- `callAlloc`

```c++
// Call [cls alloc] or [cls allocWithZone:nil], with appropriate 
// shortcutting optimizations.
static ALWAYS_INLINE id
callAlloc(Class cls, bool checkNil, bool allocWithZone=false)
{
#if __OBJC2__    
  	// 希望编译器进行优化——这里表示cls大概率是有值的，编译器可以不用每次都读取 return nil 指令
    if (slowpath(checkNil && !cls)) return nil;
 		// fastpath(x)表示x很可能不为0，
    // cls->ISA()->hasCustomAWZ() 表示 当前类是否有自定义 +allocWithZone 实现
		if (fastpath(!cls->ISA()->hasCustomAWZ())) {
        return _objc_rootAllocWithZone(cls, nil);
    }
#endif

    // No shortcuts available.
    if (allocWithZone) {
        return ((id(*)(id, SEL, struct _NSZone *))objc_msgSend)(cls, @selector(allocWithZone:), nil);
    }
  	// 调用 alloc
    return ((id(*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
}

```

**slowpath & fastpath**

这两个都是 objc 源码中定义的宏，其中的`__builtin_expect`指令是由`gcc`引入的，

- 目的：编译器可以对代码进行优化，以减少指令跳转带来的性能下降。即性能优化

- 作用：`允许程序员将最有可能执行的分支告诉编译器`

- 指令的写法为：`__builtin_expect(EXP, N)`，表示 `EXP==N的概率很大`

```c++
// fastpath(x)表示x很可能不为0
#define fastpath(x) (__builtin_expect(bool(x), 1))
// slowpath(x)表示x很可能为0
#define slowpath(x) (__builtin_expect(bool(x), 0))
```

- `fastpath`定义为`__builtin_expect((x),1)`表示 `x 的值为真的可能性更大`
  - 即执行`if` 里面语句的机会更大 

- `slowpath`定义为`__builtin_expect((x),0)`表示 `x 的值为假的可能性更大`
  - 即执行 `else` 里面语句的机会更大

> 在日常的开发中，也可以通过设置来`优化编译器`，达到`性能优化`的目的，设置的路径为：`Build Setting` --> `Optimization Level` --> `Debug` --> 将`None` 改为 `fastest` 或者 `smallest`

**为什么继承 NSObject 的会调用两次 alloc 方法？**

现在，我们来回答上面的问题，在进入 `callAlloc` 方法中，

- 当 cls 为 NSObject 时，会进入到调用`_objc_rootAllocWithZone`方法的语句
- 当 cls 为 继承 NSObject 的类时
  - 第一次进入 `callAlloc` 方法
    - 并不会进入到调用`_objc_rootAllocWithZone`方法，
    - 会来到`return ((id(*)(id, SEL))objc_msgSend)(cls, @selector(alloc))`语句，对应堆栈信息中的 `objc_alloc [inlined] callAlloc(cls=Person, checkNil=true, allocWithZone=false) at NSObject.mm:1714:12`
  - 第二次进入 `callAlloc` 方法，会进入到调用`_objc_rootAllocWithZone`方法的语句

> 总结一下：当继承 NSObject 的类 alloc 时，
>
> 1. 先进入 `objc_alloc -> callAlloc`，这是第一次进入`callAlloc`方法，会向系统发生 alloc 消息
> 2. `alloc->callAlloc->_objc_rootAllocWithZone`，这是第二次进入`callAlloc`方法，也就是上面流提及的 alloc 流程
>
> 

- `_class_createInstanceFromZone`

```C++
/***********************************************************************
* class_createInstance
* fixme
* Locking: none
*
* Note: this function has been carefully written so that the fastpath
* takes no branch.
**********************************************************************/
static ALWAYS_INLINE id
_class_createInstanceFromZone(Class cls, size_t extraBytes, void *zone,
                              int construct_flags = OBJECT_CONSTRUCT_NONE,
                              bool cxxConstruct = true,
                              size_t *outAllocatedSize = nil)
{
    ASSERT(cls->isRealized());

    // Read class's info bits all at once for performance
  	// hasCxxCtor()是判断当前class或者superclass是否有.cxx_construct 构造方法的实现
    bool hasCxxCtor = cxxConstruct && cls->hasCxxCtor();
  
    // hasCxxDtor()是判断判断当前class或者superclass是否有.cxx_destruct 析构方法的实现
    bool hasCxxDtor = cls->hasCxxDtor();
  
  	// anAllocNonpointer()是具体标记某个类是否支持优化的isa
    bool fast = cls->canAllocNonpointer();
    size_t size;

  	// instanceSize()获取类的大小（传入额外字节的大小）
    size = cls->instanceSize(extraBytes);
    if (outAllocatedSize) *outAllocatedSize = size;

    id obj;
    if (zone) {
      	// 开辟内存
        obj = (id)malloc_zone_calloc((malloc_zone_t *)zone, 1, size);
    } else {
        // 开辟内存
        obj = (id)calloc(1, size);
    }
    if (slowpath(!obj)) {
        if (construct_flags & OBJECT_CONSTRUCT_CALL_BADALLOC) {
            return _objc_callBadAllocHandler(cls);
        }
        return nil;
    }

    if (!zone && fast) {
      // 初始化isa，将类与 isa 关联
        obj->initInstanceIsa(cls, hasCxxDtor);
    } else {
        // Use raw pointer isa on the assumption that they might be
        // doing something weird with the zone or RR.
          
      	// 初始化isa
				obj->initIsa(cls);
    }

    if (fastpath(!hasCxxCtor)) {
        return obj;
    }

    construct_flags |= OBJECT_CONSTRUCT_FREE_ONFAILURE;
  	// 便利构造
    return object_cxxConstructFromClass(obj, cls, construct_flags);
}
```

![image-20200909102959562](https://w-md.imzsy.design/image-20200909102959562.png)

这个方法是整个 alloc 流程中的关键点，实现的主要功能如下：

1. `instanceSize`: 计算类所需要开辟的内存空间
2. `calloc`: 向系统申请开辟内存
3. `initInstanceIsa: 初始化 `isa` 指针，并将 `isa` 与当前 `cls` 类进行关联

#### 内存字节对齐

计算一个类所需要开辟的内存大小的流程如下

- 进入`instanceSize`方法，根据缓存进行快速计算内存
- 进入`fastInstanceSize`方法
  - `_flags` ：存储类的属性所占用的内存大小，会根据属性的个数，进行改变
  -  `FAST_CACHE_ALLOC_MASK`：存储实例的字节对齐大小+`ALLOC_DELTA16`的位与实例大小占用的位相同，因此，使用遮罩操作提前大小
- 接着进入`align16`方法，进行 **16字节内存对齐**

```C++

// 16 字节对齐算法
static inline size_t align16(size_t x) {
    return (x + size_t(15)) & ~size_t(15);
}

// 获取类的大小
size_t instanceSize(size_t extraBytes) const {
  	// 从源码779.1版本，新增加的判断
    if (fastpath(cache.hasFastInstanceSize(extraBytes))) {
        return cache.fastInstanceSize(extraBytes);
    }
	
  	// 779.1 以下的 8 字节对齐
    size_t size = alignedInstanceSize() + extraBytes;
    // CF requires all objects be at least 16 bytes.
    if (size < 16) size = 16;
    return size;
}

size_t fastInstanceSize(size_t extra) const
{
    ASSERT(hasFastInstanceSize(extra));
    // gcc的内建函数 __builtin_constant_p 用于判断一个值是否为编译时常数，如果参数EXP 的值是常数，函数返回 1，否则返回 0
    if (__builtin_constant_p(extra) && extra == 0) {
        return _flags & FAST_CACHE_ALLOC_MASK16;
    } else {
        size_t size = _flags & FAST_CACHE_ALLOC_MASK;
        // remove the FAST_CACHE_ALLOC_DELTA16 that was added
        // by setFastInstanceSize              
        return align16(size + extra - FAST_CACHE_ALLOC_DELTA16);
    }
}

// 8 字节对齐
static inline uint32_t word_align(uint32_t x) {
    return (x + WORD_MASK) & ~WORD_MASK;
}


uint32_t unalignedInstanceSize() const {
    ASSERT(isRealized());
    // 获取这个类所有属性内存的大小
    return data()->ro->instanceSize;
}

// 获取类所需要的内存大小
uint32_t alignedInstanceSize() const {
    return word_align(unalignedInstanceSize());
}

```

**字节对齐算法解析**

```
假如： x = 9,

 x + 15 = 9 + 15 = 24
 15 二进制 ：0000 1111 = 15 （8+4+2+1）
 ~15 : 1111 0000
 24二进制为  : 0001 1000
  
 1111 0000
 0001 1000
---------------
 0001 0000 = 16

 所以 x = 16    也就是 16的倍数对齐，即 16 字节对齐

```

总结：**对象大小为 16 字节，必定是 16 的倍数**

提出有个疑问：为什么要进行 16 字节对齐呢？

- 通常内存是由一个个字节组成的，cpu在存取数据时，并不是以字节为单位存储，而是以`块`为单位存取，块的大小为内存存取力度。频繁存取字节未对齐的数据，会极大降低cpu的性能，所以可以通过`减少存取次数`来`降低cpu的开销`
- 16字节对齐，是由于在一个对象中，第一个属性`isa`占`8`字节，当然一个对象肯定还有其他属性，当无属性时，会预留8字节，即16字节对齐，如果不预留，相当于这个对象的isa和其他对象的isa紧挨着，容易造成访问混乱
- 16字节对齐后，可以`加快CPU读取速度`，同时使`访问更安全`，不会产生访问混乱的情况

这是**空间换时间**的做法。

#### init & new

通过源码可以发现，`init`实际什么也没做，只是返回了`强转的 self`

这是采用工厂设计模式，提供给开发者一个接口

```objective-c
// Replaced by CF (throws an NSException)
+ (id)init {
    return (id)self;
}

- (id)init {
    return _objc_rootInit(self);
}

id
_objc_rootInit(id obj)
{
    // In practice, it will be hard to rely on this function.
    // Many classes do not properly chain -init calls.
    return obj;
}

```

> 重写子类时
>
> self = [super init]
>
> 这样写的好处是，子类先继承父类的属性，再判断是否为空，为空则直接返回nil

**对于 new**

内部实现相当于：先执行 alloc，再执行 init

所以，在初始化代码上，可能会比较简洁。但是一般在开发中并不推荐直接使用 new。

> 因为扩展性则不高，当我们重写 init 方法做一些自定义操作，用 new 初始化可能会无法走到自定义的部分

```objc
// 先调用alloc，再init
+ (id)new {
    return [callAlloc(self, false/*checkNil*/) init];
}
```



