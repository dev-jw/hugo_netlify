---
title: "iOS底层原理探索-Block分析"
date: 2020-11-09T20:12:50+08:00
draft: false
tags: ["iOS"]
url:  "block"
---

`Block`在日常开发中的使用，相信每一位iOS开发者都是非常熟悉，那么关于`block`的下面几个问题，是否已经掌握，能够快速给出答案呢

- `Block`的分类有哪些？
- 循环引用的产生与解决？
- `Block`本质是什么？
- `Block`是怎么捕获外界变量的？
- `__block`的底层原理是什么？

### block定义与分类

**定义**

带有自动变量（局部变量）的匿名函数叫做`Block`，又叫做`匿名函数`、`代码块`

不同语言中的叫法：

| 程序语言 | Block的名称        |
| -------- | ------------------ |
| C        | Blcok              |
| Ruby     | Blcok              |
| JS       | Anonymous function |
| Java     | Lambda             |
| Python   | Lambda             |

**分类**

根据`Block`存储的内存区域不同，分为：全局`Block`、栈`Block`、堆`Block`三种形式

* 全局 Block：`__NSGlobalBlock__`，存储在**已初始化数据(.data)区**

  ```objective-c
  void(^block)(void) = ^{
      NSLog(@"block");
  };
  NSLog(@"block:%@", block);
  
  --------------------输出结果：-------------------
  block: <__NSGlobalBlock__: 0x10b39f088>
  ```

* 栈 Block：`__NSMallocBlock__`，存储在**栈(stack)区**

  ```objective-c
  //    int a = 0;
  //    NSLog(@"%@", ^{
  //        NSLog(@"%d", a);
  //    });
  // iOS14之前，输出的是栈 Block
  // 经过 iOS14 优化，这一块已经变为堆 block
  
  // iOS14之后，栈 block
  int a = 0;
  void(^__weak block)(void) = ^{
      NSLog(@"%d", a);
  };
  NSLog(@"block: %@", block);
  
  --------------------输出结果：-------------------
  block: <__NSStackBlock__: 0x7ffee9324558>
  ```

  

* 堆block：`__NSMallocBlock__`，存储在**堆(heap)区**

  ```objective-c
  int a = 0;
  void(^block)(void) = ^{
      NSLog(@"%d", a);
  };
  
  NSLog(@"block: %@", block);
  
  --------------------输出结果：-------------------
  block: <__NSMallocBlock__: 0x6000038a8ed0>
  ```

总结：

- 不捕获外界变量的 block 是全局 Block：`__NSGlobalBlock__`

- 捕获外界变量的 block

  - **弱引用修饰**是栈 block：`__NSMallocBlock__`

  - **强引用修饰**是堆 block：`__NSMallocBlock__`

除此之外，还有三种系统级别的block类型（能在[libclosure](https://opensource.apple.com/tarballs/libclosure/)源码中看到）

```c
void * _NSConcreteStackBlock[32] = { 0 };
void * _NSConcreteMallocBlock[32] = { 0 };
void * _NSConcreteAutoBlock[32] = { 0 };
void * _NSConcreteFinalizingBlock[32] = { 0 };
void * _NSConcreteGlobalBlock[32] = { 0 };
void * _NSConcreteWeakBlockVariable[32] = { 0 };
```

### block循环引用

**循环引用的分析**

循环引用经典案例：

```objective-c
self.name = @"block";
self.block = ^{
    NSLog(@"%@", self.name);
};
```

编译器会发出警告

```
Capturing 'self' strongly in this block is likely to lead to a retain cycle
```

产生循环引用问题的关键所在是什么呢？

通过代码，可以发现：

- `self`持有`block`
- `block`持有`self`(self.name)

这样也就是 `self->block->self` 的循环引用

循环引用会导致什么样的后果呢？

通常，正常释放时：**对象A**发送`dealloc`信号让**对象B** 进行`dealloc`

![image-20201116152542511](https://w-md.imzsy.design/image-20201116152542511.png)

当存在循环引用时：**对象A**与**对象B**相互引用，引用计数不能减为 0，`dealloc`就不会被调用

![image-20201116153042577](https://w-md.imzsy.design/image-20201116153042577.png)

**循环引用的解决方法**

- 强弱共舞

   ```objective-c
   __weak typeof(self) weakSelf = self;
   self.name = @"block";
   self.block = ^{
       NSLog(@"%@", weakSelf.name);
   };
   ```

   使用**中介者模式** `__weak typeof(self) weakSelf = self;` 将循环引用改为：`weakself -> self -> block -> weakself`

   看起来还是一个「引用环」，但是 `weakSelf -> self` 是弱引用——引用计数不处理，使用 `Weak表`管理，所以在析构时，`self` 能够调用 `dealloc`

   > 但这并不是最好的解决方案，仍然存在着问题

   在 `block` 内部存在**延时函数**
   
   ```objective-c
   __weak typeof(self) weakSelf = self;
   self.name = @"block";
   self.block = ^{
       dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                    (int64_t)(3.0 * NSEC_PER_SEC)),
                      dispatch_get_main_queue(),
                      ^{
           NSLog(@"%@", weakSelf.name);
       });
   };
   ```
   
   如果在调用 `block` 之后，释放了 `self`，那么 3 秒后 `weakSelf` 指向的 `self` 已经变为 nil，那么打印结果也只能是 `null`
   
   因此，就需要加入**强引用**
   
   ```objective-c
   __weak typeof(self) weakSelf = self;
   self.name = @"block";
   self.block = ^{
       __strong typeof(weakSelf) strongSelf = weakSelf;
       dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                    (int64_t)(3.0 * NSEC_PER_SEC)),
                      dispatch_get_main_queue(),
                      ^{
           NSLog(@"%@", strongSelf.name);
       });
   };
   ```
   
   通过再加一层临时的强引用`__strong typeof(weakSelf) strongSelf = weakSelf`，将引用链改为：`strongSelf -> weakself -> self -> block -> strongSelf`
   
   看起来仍然是一个循环引用，但实际上`strongSelf`是临时变量，当 block 作用域结束后就会释放，从而会打破循环引用，进行正常释放

- 引入其他中间者

  既然有「自动置空」，那么也可以「手动置空」

  ```objective-c
  __block ViewController *vc = self;
  self.name = @"block";
  self.block = ^{
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                   (int64_t)(3.0 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(),
                     ^{
          NSLog(@"%@", vc.name);
          vc = nil;
      });
  };
  ```

  这也是通过**中介者模式**打破循环引用的方式——使用 `vc` 作为中介者代替 `self`

  此时的引用链为：`vc -> self -> block -> vc`（vc在用完之后，手动置空）

- 不引用

  ```objective-c
  self.block = ^(ViewController *vc) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                   (int64_t)(3.0 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(),
                     ^{
          NSLog(@"%@", vc.name);
      });
  };
  ```

  将使用`当前 vc`作为参数传入 `block` 时，就不会出现持有的情况，同时还能使用 `self` 的属性，避免循环引用

**补充说明**

- `Masonry`中是否存在循环引用？

  `Masonry`使用的 block 是当作参数传递的，即使 block 内部持有 self，设置布局的 view 持有 block，但是 block 不持有 view。

  当 block 执行完后就会释放，self 的引用计数-1，所以 block 也不会持有 self，所以不会产生循环引用

- `[UIView animateWithDuration: animations:]`中是否存在循环引用？

  `UIView动画`是类方法，不被 self 持有（即 self 持有 view，但 view 没有实例化），所以不会循环引用

### block底层分析

**本质**

```c
#include "stdio.h"

int main(){
    int a = 10;
    void(^block)(void) = ^{
        printf("Block - %d",a);
    };
    block();
    return 0;
}
```

通过 `clang` ，使用 `clang -rewrite-objc main.c -o main.cpp`， 将上面代码编译成 `c++` 文件，查看底层实现

```c++
int main(){
    int a = 10;
    void(*block)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, 
                                                           &__main_block_desc_0_DATA, 
                                                           a));
    ((void (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);
    return 0;
}
```

block声明中，不难发现为`__main_block_impl_0`类型，这是 C++ 中的构造函数

`__main_block_impl_0`的定义

```c++
struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  int a;
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int _a, int flags=0) : a(_a) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
```

因此，`block` 的本质是个`__main_block_impl_0`的结构体对象，这也是可以用`%@`打印 block 的原因

构造函数正是将`block`具体实现`__main_block_func_0`，作为参数 `fp` 传递并保存到了 `impl`

**为什么需要Block()** 

`((**void** (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);`

函数调用正是调用保存在 `impl` 中的 `FuncPtr`

这就是说明了，block 声明只是将 block 实现进行保存，函数实现则需要自行调用

**自动捕获外界变量**

在上面的例子中，变量 a 在底层仍然是 **int**类型，并作为`__main_block_impl_0`构造函数的参数，并且保存在`__main_block_impl_0`结构体的成员变量 a 中

对于block函数实现：`__main_block_func_0`

```c++
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
    int a = __cself->a; // bound by copy
    printf("Block - %d",a);
}
```

不难看出：

- `__cself`即`__main_block_impl_0`的指针，block 本身
- `int a = __cself->a`即 `int a = block->a`
- 由于 a 是一个成员变量，所以只是**值拷贝**

由于是值拷贝，不难直接对捕获的外界变量进行操作，如`a++`

**__block 修饰外界变量**

```c
int main(){
    __block int a = 10;
    void(^block)(void) = ^{
        printf("Block - %d",a);
    };
    block();
    return 0;
}
```

在底层被编译为：

```c++
int main(){
    __attribute__((__blocks__(byref))) __Block_byref_a_0 a = {(void*)0,(__Block_byref_a_0 *)&a, 0, sizeof(__Block_byref_a_0), 10};
    void(*block)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, 
                                                           &__main_block_desc_0_DATA, 
                                                           (__Block_byref_a_0 *)&a, 
                                                           570425344));
    ((void (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);
    return 0;
}
```

此时的`__main_block_impl_0`结构体为：

```c++
struct __main_block_impl_0 {
    struct __block_impl impl;
    struct __main_block_desc_0* Desc;
    __Block_byref_a_0 *a; // by ref
    __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, __Block_byref_a_0 *_a, int flags=0) : a(_a->__forwarding) {
        impl.isa = &_NSConcreteStackBlock;
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
    }
};
```

而函数实现`__main_block_func_0`为：

```c++
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
    __Block_byref_a_0 *a = __cself->a; // bound by ref
    
    printf("Block - %d",(a->__forwarding->a));
}
```

`__Block_byref_a_0`结构体：

```c++
struct __Block_byref_a_0 {
    void *__isa;
    __Block_byref_a_0 *__forwarding;
    int __flags;
    int __size;
    int a;
};
```

`__block`修饰的变量，通过编译在底层会生成`__Block_byref_a_0`的结构体，且将结构体的指针地址作为`__main_block_impl_0`构造函数的参数，被保存到`__main_block_impl_0`结构体中，这正是指针拷贝

### block底层源码分析

借助汇编调用堆栈，不难发现运行时的 block 会进入`objc_retainBlock`，进而走到`_Block_copy`函数

> 借助[libclosure-74](https://opensource.apple.com/source/libclosure/libclosure-74/)源码，配置一份可编译调试的源码，方便探究 `Block`

Block结构体`Block_layout`（等同于 `clang` 编译出来的`__Block_byref_a_0`）

```c++
#define BLOCK_DESCRIPTOR_1 1
struct Block_descriptor_1 {
    uintptr_t reserved;
    uintptr_t size;
};

#define BLOCK_DESCRIPTOR_2 1
struct Block_descriptor_2 {
    // requires BLOCK_HAS_COPY_DISPOSE
    BlockCopyFunction copy;
    BlockDisposeFunction dispose;
};

#define BLOCK_DESCRIPTOR_3 1
struct Block_descriptor_3 {
    // requires BLOCK_HAS_SIGNATURE
    const char *signature;
    const char *layout;     // contents depend on BLOCK_HAS_EXTENDED_LAYOUT
};

// Block 结构体
struct Block_layout {
    void *isa;
    volatile int32_t flags; // contains ref count
    int32_t reserved;
    BlockInvokeFunction invoke;
    struct Block_descriptor_1 *descriptor;
    // imported variables
};
```

其中`Block_layout`是基础 block 结构

- `isa`：表明 block 的类型

- `flags`：标识符，记录了一些信息， 类似 isa 结构中的位域

  ```c++
  enum {
      BLOCK_DEALLOCATING =      (0x0001),  // runtime
      BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
      BLOCK_NEEDS_FREE =        (1 << 24), // runtime
      BLOCK_HAS_COPY_DISPOSE =  (1 << 25), // compiler
      BLOCK_HAS_CTOR =          (1 << 26), // compiler: helpers have C++ code
      BLOCK_IS_GC =             (1 << 27), // runtime
      BLOCK_IS_GLOBAL =         (1 << 28), // compiler
      BLOCK_USE_STRET =         (1 << 29), // compiler: undefined if !BLOCK_HAS_SIGNATURE
      BLOCK_HAS_SIGNATURE  =    (1 << 30), // compiler
      BLOCK_HAS_EXTENDED_LAYOUT=(1 << 31)  // compiler
  };
  
  - 第1位：释放标记，一般常用BLOCK_NEEDS_FREE做位与操作，一同传入flags，告知该block可释放
  - 第16位：存储引用计数的值，是一个可选参数
  - 第24位：低16位是否有效的标志，程序根据它来决定是否增加或减少引用计数位的值
  - 第25位：是否拥有拷贝辅助函数；决定 Block_descriptor_2
  - 第26位：是否拥有block析构函数
  - 第27位：标志是否有垃圾回收
  - 第28位：标志是否是全局block
  - 第29位：与BLOCK_USE_START相对，判断当前block是否拥有一个签名
  - 第30位：标志是否有签名
  - 第31位：标志是否有拓展，决定 Block_descriptor_3
  ```

- `invoke`：是一个函数指针，指向 block 的执行代码

- `descriptor`：block 的附加信息，比如保留变量数、block 的大小、进行 `copy` 会 `dispose` 的辅助函数指针

  - `Block_descriptor_1`是必定存在的信息
  - 而部分block则拥有`Block_descriptor_2`和`Block_descriptor_3`结构

对于部分 block 拥有`Block_descriptor_2`和`Block_descriptor_3`结构，是根据其构造函数所体现的

```c++
// copy 和 dispose 函数
static struct Block_descriptor_2 * _Block_descriptor_2(struct Block_layout *aBlock)
{
    if (! (aBlock->flags & BLOCK_HAS_COPY_DISPOSE)) return NULL;
    uint8_t *desc = (uint8_t *)aBlock->descriptor;
    desc += sizeof(struct Block_descriptor_1);
    return (struct Block_descriptor_2 *)desc;
}

// 签名相关
static struct Block_descriptor_3 * _Block_descriptor_3(struct Block_layout *aBlock)
{
    if (! (aBlock->flags & BLOCK_HAS_SIGNATURE)) return NULL;
    uint8_t *desc = (uint8_t *)aBlock->descriptor;
    desc += sizeof(struct Block_descriptor_1);
    if (aBlock->flags & BLOCK_HAS_COPY_DISPOSE) {
        desc += sizeof(struct Block_descriptor_2);
    }
    return (struct Block_descriptor_3 *)desc;
}
```

如果`aBlock->flags & BLOCK_HAS_COPY_DISPOSE`条件满足，那么存在`Block_descriptor_2`，`Block_descriptor_2`可以通过`Block_descriptor_1`内存偏移得到

同样的，`aBlock->flags & BLOCK_HAS_SIGNATURE`条件满足，那么存在`Block_descriptor_3`，`Block_descriptor_3`则可以根据`Block_descriptor_1`和`Block_descriptor_2`内存偏移得到

因此，block 的内存布局应该长这样：

![image-20201117191449285](https://w-md.imzsy.design/image-20201117191449285.png)

**block签名**

在`Block_descriptor_3`中，有`signature`成员变量，在`_Block_copy`加入断点，打印一下全局 Block

```shell
<__NSGlobalBlock__: 0x100004030>
 signature: "v8@?0"
 invoke   : 0x100003ef0 (/Users/zsy/Library/Developer/Xcode/DerivedData/Blocks-apixiageymqzowcvafsoicordsqh/Build/Products/Debug/BlockDemo`__main_block_invoke)
```

这里的`signature: "v8@?0"`便是 block 的签名

通过`[NSMethodSignature signatureWithObjCTypes:"v8@?0"]`打印

```shell
<NSMethodSignature: 0x3b5569f7a14d3061>
    number of arguments = 1
    frame size = 224
    is special struct return? NO
    # 无返回值
    return value: -------- -------- -------- --------
        type encoding (v) 'v'
        flags {}
        modifiers {}
        frame {offset = 0, offset adjust = 0, size = 0, size adjust = 0}
        memory {offset = 0, size = 0}
    # 参数
    argument 0: -------- -------- -------- --------
        # encoding = (@),类型是 @?
        type encoding (@) '@?'
        flags {isObject, isBlock}
        modifiers {}
        frame {offset = 0, offset adjust = 0, size = 8, size adjust = 0}
        # 所在偏移位置是8字节
        memory {offset = 0, size = 8}
```

block的签名信息类似方法的签名，因此可以更加签名，对 block 进行 Hook

### __block的原理（三次拷贝）

#### 第一次拷贝：栈block -> 堆block

通过`_Block_copy`函数，打印 block 结果如下

```shell
#_Block_copy 调用前
<__NSStackBlock__: 0x7ffeefbff478>
 signature: "v8@?0"
 invoke   : 0x100003ef0 (/Users/zsy/Library/Developer/Xcode/DerivedData/Blocks-apixiageymqzowcvafsoicordsqh/Build/Products/Debug/BlockDemo`__main_block_invoke)

#_Block_copy 调用后
<__NSMallocBlock__: 0x100705560>
 signature: "v8@?0"
 invoke   : 0x100003ef0 (/Users/zsy/Library/Developer/Xcode/DerivedData/Blocks-apixiageymqzowcvafsoicordsqh/Build/Products/Debug/BlockDemo`__main_block_invoke)
```

是的，函数`_Block_copy`正是将`栈 Block`拷贝到`堆 Block`的关键所在，具体的函数实现如下：

```c++
// Copy, or bump refcount, of a block.  If really copying, call the copy helper if present.
// block的拷贝操作: 栈Block -> 堆Block
void *_Block_copy(const void *arg) {
    struct Block_layout *aBlock;

    if (!arg) return NULL;
    
    // The following would be better done as a switch statement
    aBlock = (struct Block_layout *)arg;
    if (aBlock->flags & BLOCK_NEEDS_FREE) {
        // latches on high
        latching_incr_int(&aBlock->flags);
        return aBlock;
    }
    else if (aBlock->flags & BLOCK_IS_GLOBAL) {
        return aBlock;
    }
    else {
        // Its a stack block.  Make a copy.
        struct Block_layout *result =
            (struct Block_layout *)malloc(aBlock->descriptor->size);
        if (!result) return NULL;
        memmove(result, aBlock, aBlock->descriptor->size); // bitcopy first
#if __has_feature(ptrauth_calls)
        // Resign the invoke pointer as it uses address authentication.
        result->invoke = aBlock->invoke;
#endif
        // reset refcount
        result->flags &= ~(BLOCK_REFCOUNT_MASK|BLOCK_DEALLOCATING);    // XXX not needed
        result->flags |= BLOCK_NEEDS_FREE | 2;  // logical refcount 1
        _Block_call_copy_helper(result, aBlock);
        // Set isa last so memory analysis tools see a fully-initialized object.
        result->isa = _NSConcreteMallocBlock;
        return result;
    }
}
```

整个流程分为：

1. 通过 `flags`标识位`BLOCK_NEEDS_FREE`——存储引用计数的值是否有效
   - 当栈 block 进入函数时，`aBlock->flags & BLOCK_NEEDS_FREE` 为 0，因此，拷贝为堆 block时，会重新设置引用计数
   - 当堆 block 进入函数时，通过函数`latching_incr_int`，改变引用计数，并返回 block
2. 判断是否是全局 Block——如果是，直接返回
3. 栈 block -> 堆 block 
   - 通过 `malloc` 在堆区申请开辟内存空间
   - 通过 `memove` 将数据从栈区拷贝到堆区
   - 设置 `invoke`
   - 重置引用计数
   - 将 block 的 `isa` 标记为`_NSConcreteMallocBlock`

#### 第二次拷贝：捕获外界变量的操作

```c++
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->a, (void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/);}

static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
  void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};
```

在**__block捕获外部变量**时，在底层`__main_block_impl_0`构造函数中，还会传递`main_block_desc_0_DATA`

而`__main_block_desc_0_DATA`内部会传递`__main_block_copy_0`函数、`__main_block_dispose_0`函数

- `__main_block_copy_0`函数会调用`_Block_object_assign`
- `__main_block_dispose_0`函数会调用`_Block_object_dispose`

**_Block_object_assign**

```c++
// _Block_object_assign((void*)&dst->a, (void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/); 传递的参数
void _Block_object_assign(void *destArg, const void *object, const int flags) {
    const void **dest = (const void **)destArg;
    switch (os_assumes(flags & BLOCK_ALL_COPY_DISPOSE_FLAGS)) {
      case BLOCK_FIELD_IS_OBJECT:
        /*******
        id object = ...;
        [^{ object; } copy];
        ********/

        _Block_retain_object(object);
        *dest = object;
        break;

      case BLOCK_FIELD_IS_BLOCK:
        /*******
        void (^object)(void) = ...;
        [^{ object; } copy];
        ********/

        *dest = _Block_copy(object);
        break;
    
      case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
      case BLOCK_FIELD_IS_BYREF:
        /*******
         // copy the onstack __block container to the heap
         // Note this __weak is old GC-weak/MRC-unretained.
         // ARC-style __weak is handled by the copy helper directly.
         __block ... x;
         __weak __block ... x;
         [^{ x; } copy];
         ********/

        *dest = _Block_byref_copy(object);
        break;
        
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT:
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK:
        /*******
         // copy the actual field held in the __block container
         // Note this is MRC unretained __block only. 
         // ARC retained __block is handled by the copy helper directly.
         __block id object;
         __block void (^object)(void);
         [^{ object; } copy];
         ********/

        *dest = object;
        break;

      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_WEAK:
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK  | BLOCK_FIELD_IS_WEAK:
        /*******
         // copy the actual field held in the __block container
         // Note this __weak is old GC-weak/MRC-unretained.
         // ARC-style __weak is handled by the copy helper directly.
         __weak __block id object;
         __weak __block void (^object)(void);
         [^{ object; } copy];
         ********/

        *dest = object;
        break;

      default:
        break;
    }
}
```

根据`flags & BLOCK_ALL_COPY_DISPOSE_FLAGS`进到不同分支来处理捕获到的变量

| 枚举值                | 数值 | 含义                                                         |
| --------------------- | :--: | ------------------------------------------------------------ |
| BLOCK_FIELD_IS_OBJECT |  3   | 对象                                                         |
| BLOCK_FIELD_IS_BLOCK  |  7   | block变量                                                    |
| BLOCK_FIELD_IS_BYREF  |  8   | __block修饰的结构体                                          |
| BLOCK_FIELD_IS_WEAK   |  16  | __weak修饰的变量                                             |
| BLOCK_BYREF_CALLER    | 128  | 处理block_byref内部对象内存的时候 会加的一个额外的标记，配合上面的枚举一起使用 |

根据源码不难看出：

- `BLOCK_FIELD_IS_OBJECT`：交给系统 ARC 处理，并拷贝对象指针，即引用计数+1
- `BLOCK_FIELD_IS_BLOCK`：调用`_Block_copy`函数，将 block 从栈区拷贝到堆区
- `BLOCK_FIELD_IS_BYREF`：调用`_Block_byref_copy`函数，进行内存拷贝、引用计数的处理

**_Block_byref_copy**

```c++
static struct Block_byref *_Block_byref_copy(const void *arg) {
    
    //强转为Block_byref结构体类型，保存一份
    struct Block_byref *src = (struct Block_byref *)arg;

    if ((src->forwarding->flags & BLOCK_REFCOUNT_MASK) == 0) {
        // src points to stack 申请内存
        struct Block_byref *copy = (struct Block_byref *)malloc(src->size);
        copy->isa = NULL;
        // byref value 4 is logical refcount of 2: one for caller, one for stack
        copy->flags = src->flags | BLOCK_BYREF_NEEDS_FREE | 4;
        //block内部持有的Block_byref 和 外界的Block_byref 所持有的对象是同一个，这也是为什么__block修饰的变量具有修改能力
        //copy 和 scr 的地址指针达到了完美的同一份拷贝，目前只有持有能力
        copy->forwarding = copy; // patch heap copy to point to itself
        src->forwarding = copy;  // patch stack to point to heap copy
        copy->size = src->size;
        //如果有copy能力
        if (src->flags & BLOCK_BYREF_HAS_COPY_DISPOSE) {
            // Trust copy helper to copy everything of interest
            // If more than one field shows up in a byref block this is wrong XXX
            //Block_byref_2是结构体，__block修饰的可能是对象，对象通过byref_keep保存，在合适的时机进行调用
            struct Block_byref_2 *src2 = (struct Block_byref_2 *)(src+1);
            struct Block_byref_2 *copy2 = (struct Block_byref_2 *)(copy+1);
            copy2->byref_keep = src2->byref_keep;
            copy2->byref_destroy = src2->byref_destroy;

            if (src->flags & BLOCK_BYREF_LAYOUT_EXTENDED) {
                struct Block_byref_3 *src3 = (struct Block_byref_3 *)(src2+1);
                struct Block_byref_3 *copy3 = (struct Block_byref_3*)(copy2+1);
                copy3->layout = src3->layout;
            }
            //等价于 __Block_byref_id_object_copy
            (*src2->byref_keep)(copy, src);
        }
        else {
            // Bitwise copy.
            // This copy includes Block_byref_3, if any.
            memmove(copy+1, src+1, src->size - sizeof(*src));
        }
    }
    // already copied to heap
    else if ((src->forwarding->flags & BLOCK_BYREF_NEEDS_FREE) == BLOCK_BYREF_NEEDS_FREE) {
        latching_incr_int(&src->forwarding->flags);
    }
    
    return src->forwarding;
}
```

整个过程：

- 将传入的对象，强转为`Block_byref`结构体
- 判断是否将对象拷贝到堆区
  - 如果已经拷贝过了，则处理引用计数
  - 如果没有拷贝，则需要申请内存`Block_byref *copy`，并且让`copy->forwarding`和`src->forwarding`都指向同一个对象，在也是为什么`__block`修饰的对象具备修改能力的原因

**Block_byref结构体的内存布局**

![image-20201117210815025](https://w-md.imzsy.design/image-20201117210815025.png)

#### 第三次拷贝：拷贝对象

在`_Block_byref_copy`函数中，将`Block_byref`对象从栈拷贝到堆时，如果对象的`flags`具有`BLOCK_BYREF_HAS_COPY_DISPOSE`标识时，即`__block`修饰的对象内部还存在对象，那么需要对内部的对象也进行拷贝

`(*src2->byref_keep)(copy, src)`就是对象拷贝

`byref_keep`的定义

```c++
struct Block_byref {
    void *isa;
    struct Block_byref *forwarding;
    volatile int32_t flags; // contains ref count
    uint32_t size;
};

// __Block 修饰的结构体 byref_keep 和 byref_destroy 函数 - 来处理里面持有对象的保持和销毁
struct Block_byref_2 {
    // requires BLOCK_BYREF_HAS_COPY_DISPOSE
    BlockByrefKeepFunction byref_keep;
    BlockByrefDestroyFunction byref_destroy;
};

struct Block_byref_3 {
    // requires BLOCK_BYREF_LAYOUT_EXTENDED
    const char *layout;
};
```

重新 `clang` 对下面的代码编译看一看

```objective-c
#import <Foundation/Foundation.h>
int main(){
    __block NSString *name = [NSString stringWithFormat:@"test"];
    void(^block)(void) = ^{
        name = @"name";
        NSLog(@"Block: %@", name);
    };
    block();
    return 0;
}
```

编译结果：

- 编译后的`Block_byref`结构体，多了`__Block_byref_id_object_copy_131`和`__Block_byref_id_object_dispose_131`
- `__Block_byref_name_0`结构体，多了`__Block_byref_id_object_copy`和`__Block_byref_id_object_dispose`

```c++
int main(){
    __attribute__((__blocks__(byref))) __Block_byref_name_0 name = {
        (void*)0,
        (__Block_byref_name_0 *)&name,
        33554432,
        sizeof(__Block_byref_name_0),
        __Block_byref_id_object_copy_131,
        __Block_byref_id_object_dispose_131,
        ((NSString * _Nonnull (*)(id, SEL, NSString * _Nonnull, ...))(void *)objc_msgSend)((id)objc_getClass("NSString"), sel_registerName("stringWithFormat:"), (NSString *)&__NSConstantStringImpl__var_folders_qs_68kbrd0j4790ypksky9f_kgr0000gn_T_main_1106ed_mi_0)};

    void(*block)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, (__Block_byref_name_0 *)&name, 570425344));

    ((void (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);
    return 0;
}

struct __Block_byref_name_0 {
  void *__isa;
__Block_byref_name_0 *__forwarding;
 int __flags;
 int __size;
 void (*__Block_byref_id_object_copy)(void*, void*);
 void (*__Block_byref_id_object_dispose)(void*);
 NSString *name;
};

static void __Block_byref_id_object_copy_131(void *dst, void *src) {
 _Block_object_assign((char*)dst + 40, *(void * *) ((char*)src + 40), 131);
}

static void __Block_byref_id_object_dispose_131(void *src) {
 _Block_object_dispose(*(void * *) ((char*)src + 40), 131);
}
```

没错，这里的`__Block_byref_id_object_copy_131`正是`byref_keep`

第三次拷贝正是调用`__Block_byref_id_object_copy_131`方法，而本质是调用`_Block_object_assign`，`(char*)dst + 40`其实是通过内存平移，传入成员变量 `name`

**总结**

通过`libclosure-74`可编译源码断点调试，关键方法的执行顺序：`_Block_copy -> _Block_byref_copy -> *src2->byref_keep (即_Block_object_assign)`

这就是`__block的三次拷贝`

- 第一次拷贝：通过`_Block_copy`函数，将对象从栈区拷贝到堆区
- 第二次拷贝：通过`_Block_byref_copy`函数，将对象拷贝为`Block_byref`结构体
- 第三次拷贝：调用对象的`byref_keep`函数，实际是调用`_Block_object_assign`函数，对`__block`修饰的`当前变量`拷贝

**_Block_object_dispose**

`_Block_object_dispose`和`_Block_object_assign`非常类似，主要是负责 block 的释放操作

```c++
// When Blocks or Block_byrefs hold objects their destroy helper routines call this entry point
// to help dispose of the contents 当Blocks或Block_byrefs持有对象时，其销毁助手例程将调用此入口点以帮助处置内容
void _Block_object_dispose(const void *object, const int flags) {
    switch (os_assumes(flags & BLOCK_ALL_COPY_DISPOSE_FLAGS)) {
      case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
      case BLOCK_FIELD_IS_BYREF://__block修饰的变量，即bref类型的
        // get rid of the __block data structure held in a Block
        _Block_byref_release(object);
        break;
      case BLOCK_FIELD_IS_BLOCK://block类型的变量
        _Block_release(object) ;
        break;
      case BLOCK_FIELD_IS_OBJECT://普通对象
        _Block_release_object(object);
        break;
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT:
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK:
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_WEAK:
      case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK  | BLOCK_FIELD_IS_WEAK:
        break;
      default:
        break;
    }
}

static void _Block_byref_release(const void *arg) {
    struct Block_byref *byref = (struct Block_byref *)arg;

    // dereference the forwarding pointer since the compiler isn't doing this anymore (ever?)
    byref = byref->forwarding;
    
    if (byref->flags & BLOCK_BYREF_NEEDS_FREE) {
        int32_t refcount = byref->flags & BLOCK_REFCOUNT_MASK;
        os_assert(refcount);
        if (latching_decr_int_should_deallocate(&byref->flags)) {
            if (byref->flags & BLOCK_BYREF_HAS_COPY_DISPOSE) {
                struct Block_byref_2 *byref2 = (struct Block_byref_2 *)(byref+1);
                (*byref2->byref_destroy)(byref);
            }
            free(byref);
        }
    }
}
```

通过源码，不难得出下面的结论

- 如果是释放对象就什么也不做（自动释放）
- 如果是`__block`修饰，就将指向指回原来的区域并使用`free`释放

> 参考资料：
>
> [libclosure-74](https://opensource.apple.com/source/libclosure/libclosure-74/)
>
> [可编译调试源码](https://github.com/dev-jw/objc_debug/tree/master/libclosure-74)

