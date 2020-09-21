---
title: "iOS底层原理探索-消息发送与转发"
date: 2020-09-18T22:07:29+08:00
draft: true
tags: [iOS]
url:  "message"
---

在`cache_t`中，介绍了方法的缓存，那么方法具体是什么？方法的调用过程又是怎么样的呢？本来将对方法进行分析

同样的，先提出几个问题：

- 什么是 Runtime

- 方法的本质
- 方法快速查找流程
- 方法慢速查找流程

### Runtime

**什么是Runtime**

`Runtime`是一套 API，由 c、c++、汇编一起写成的，为 `Objective-c` 提供了运行时的能力

- 运行时：`代码跑起来，被装载到内存中`的过程，如果此时出错，则程序会崩溃，是一个`动态`阶段
- 编译时：`源代码翻译成机器能识别的代码`的过程，主要是对语言进行最基本的检查报错，即词法分析、语法分析等，是一个`静态`的阶段

**调用Runtime的方式**

- Objective-C Code，如`[person run]`
- NSObject API，如`isKindofClass`

- Runtime APi，如`class_getInstanceSize`

### 方法的本质

通过 clang 编译后，可以看到底层代码：

```objective-c
//main.m中方法的调用
Person *person = [Person alloc];
[person run];

//👇clang编译后的底层实现
Person *person = ((Person *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("Person"), sel_registerName("alloc"));
((void (*)(id, SEL))(void *)objc_msgSend)((id)person, sel_registerName("run"));

```

[person run]会被编译为：`objc_msgSend(person, sel_registerName("run"))`，即`objc_msgSend(消息接收者, 方法编号)`

没错，方法的本质就是**通过`objc_msgSend函数`发送消息**

```objective-c
id objc_msgSend(id self, SEL op, ...)
```

`objc_msgSend`这是一个可变参数函数。第二个参数类型是SEL，在 OC 中是 `selector` 方法选择器

```objective-c
typedef struct objc_selector *SEL;
```

`objc_selector`是一个映射到方法的 C 字符串。需要注意的是`@selector()`选择只与函数名有关。

- 不同类中相同名字的方法所对应的方法选择器是相同的
- 方法名字相同而变量类型不同，也会导致它们具有相同的方法选择器

因此，**OC 是不支持函数重载**

> 如果外部定义了C函数并调用如`void fly() {}`，在clang编译之后还是`fly()`而不是通过`objc_msgSend`去调用。
>
> 因为发送消息就是找函数实现的过程，而C函数可以通过`函数名`——`指针`就可以找到

### 方法查找流程 —— objc_msgSend源码解析

> 消息查找流程其实是通过上层的`方法编号sel`发送消息`objc_msgSend`找到`具体实现imp`的过程

`objc_msgSend`是用汇编写的，是因为：

- C 语言不能通过写一个函数，保留未知的参数，跳转到任意的指针，而汇编有寄存器
- 对于一些调用频率太高的函数或操作，使用汇编来实现，能够提高效率和性能，容易被机器来识别

#### 快速查找流程

在`obj4-781`里面的`objc-msg-arm64.s`文件中，`objc_msgSend`汇编源码：

```asm
/********************************************************************
 *
 * id objc_msgSend(id self, SEL _cmd, ...);
 * IMP objc_msgLookup(id self, SEL _cmd, ...);
 * 
 * objc_msgLookup ABI:
 * IMP returned in x17
 * x16 reserved for our use but not used
 *
 ********************************************************************/

#if SUPPORT_TAGGED_POINTERS
	.data
	.align 3
	.globl _objc_debug_taggedpointer_classes
_objc_debug_taggedpointer_classes:
	.fill 16, 8, 0
	.globl _objc_debug_taggedpointer_ext_classes
_objc_debug_taggedpointer_ext_classes:
	.fill 256, 8, 0
#endif

	ENTRY _objc_msgSend
	UNWIND _objc_msgSend, NoFrame

	cmp	p0, #0			// nil check and tagged pointer check
#if SUPPORT_TAGGED_POINTERS
	b.le	LNilOrTagged		//  (MSB tagged pointer looks negative)
#else
	b.eq	LReturnZero
#endif
	ldr	p13, [x0]		// p13 = isa
	GetClassFromIsa_p16 p13		// p16 = class
LGetIsaDone:
	// calls imp or objc_msgSend_uncached
	CacheLookup NORMAL, _objc_msgSend
```

> p0表示0寄存器的指针，x0 表示它的值。

**分析汇编代码**

进入到`_objc_msgSend`方法

- 比较`p0`是否为空，即消息接收者是否为空
- 判断是否为`tagged_pointers`(小对象类型)，之后会单独分析`tagged_pointers`
- 取出`x0`，存入`p13`寄存器，即从`receiver`中取出`isa`存入`p13`寄存器
- 通过`GetClassFromIsa_p16`，获取`receiver`中的类信息
- 进入`CacheLookup`，根据当前类的缓存查找`imp`——**快速查找流程**

`GetClassFromIsa_p16`汇编源码：

```asm
/********************************************************************
 * GetClassFromIsa_p16 src
 * src is a raw isa field. Sets p16 to the corresponding class pointer.
 * The raw isa might be an indexed isa to be decoded, or a
 * packed isa that needs to be masked.
 *
 * On exit:
 *   $0 is unchanged
 *   p16 is a class pointer
 *   x10 is clobbered
 ********************************************************************/

#if SUPPORT_INDEXED_ISA
	.align 3
	.globl _objc_indexed_classes
_objc_indexed_classes:
	.fill ISA_INDEX_COUNT, PTRSIZE, 0
#endif

.macro GetClassFromIsa_p16 /* src */

#if SUPPORT_INDEXED_ISA
	// Indexed isa
	mov	p16, $0			// optimistically set dst = src
	tbz	p16, #ISA_INDEX_IS_NPI_BIT, 1f	// done if not non-pointer isa
	// isa in p16 is indexed
	adrp	x10, _objc_indexed_classes@PAGE
	add	x10, x10, _objc_indexed_classes@PAGEOFF
	ubfx	p16, p16, #ISA_INDEX_SHIFT, #ISA_INDEX_BITS  // extract index
	ldr	p16, [x10, p16, UXTP #PTRSHIFT]	// load class from array
1:

#elif __LP64__
	// 64-bit packed isa
	and	p16, $0, #ISA_MASK

#else
	// 32-bit raw isa
	mov	p16, $0

#endif

.endmacro
```

`and p16, $0, #ISA_MASK`等同于`isa & ISA_MASK`，也就是获取 isa 指针中 `shiftcls` 中的类信息

`CacheLookup`源码：

```asm
.macro CacheLookup
	//
	// Restart protocol:
	//
	//   As soon as we're past the LLookupStart$1 label we may have loaded
	//   an invalid cache pointer or mask.
	//
	//   When task_restartable_ranges_synchronize() is called,
	//   (or when a signal hits us) before we're past LLookupEnd$1,
	//   then our PC will be reset to LLookupRecover$1 which forcefully
	//   jumps to the cache-miss codepath which have the following
	//   requirements:
	//
	//   GETIMP:
	//     The cache-miss is just returning NULL (setting x0 to 0)
	//
	//   NORMAL and LOOKUP:
	//   - x0 contains the receiver
	//   - x1 contains the selector
	//   - x16 contains the isa
	//   - other registers are set as per calling conventions
	//
LLookupStart$1:

	// p1 = SEL, p16 = isa
	ldr	p11, [x16, #CACHE]				// p11 = mask|buckets

#if CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_HIGH_16
	and	p10, p11, #0x0000ffffffffffff	// p10 = buckets
	and	p12, p1, p11, LSR #48		// x12 = _cmd & mask
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_LOW_4
	and	p10, p11, #~0xf			// p10 = buckets
	and	p11, p11, #0xf			// p11 = maskShift
	mov	p12, #0xffff
	lsr	p11, p12, p11				// p11 = mask = 0xffff >> p11
	and	p12, p1, p11				// x12 = _cmd & mask
#else
#error Unsupported cache mask storage for ARM64.
#endif


	add	p12, p10, p12, LSL #(1+PTRSHIFT)
		             // p12 = buckets + ((_cmd & mask) << (1+PTRSHIFT))

	ldp	p17, p9, [x12]		// {imp, sel} = *bucket
1:	cmp	p9, p1			// if (bucket->sel != _cmd)
	b.ne	2f			//     scan more
	CacheHit $0			// call or return imp
	
2:	// not hit: p12 = not-hit bucket
	CheckMiss $0			// miss if bucket->sel == 0
	cmp	p12, p10		// wrap if bucket == buckets
	b.eq	3f
	ldp	p17, p9, [x12, #-BUCKET_SIZE]!	// {imp, sel} = *--bucket
	b	1b			// loop

3:	// wrap: p12 = first bucket, w11 = mask
#if CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_HIGH_16
	add	p12, p12, p11, LSR #(48 - (1+PTRSHIFT))
					// p12 = buckets + (mask << 1+PTRSHIFT)
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_LOW_4
	add	p12, p12, p11, LSL #(1+PTRSHIFT)
					// p12 = buckets + (mask << 1+PTRSHIFT)
#else
#error Unsupported cache mask storage for ARM64.
#endif

	// Clone scanning loop to miss instead of hang when cache is corrupt.
	// The slow path may detect any corruption and halt later.

	ldp	p17, p9, [x12]		// {imp, sel} = *bucket
1:	cmp	p9, p1			// if (bucket->sel != _cmd)
	b.ne	2f			//     scan more
	CacheHit $0			// call or return imp
	
2:	// not hit: p12 = not-hit bucket
	CheckMiss $0			// miss if bucket->sel == 0
	cmp	p12, p10		// wrap if bucket == buckets
	b.eq	3f
	ldp	p17, p9, [x12, #-BUCKET_SIZE]!	// {imp, sel} = *--bucket
	b	1b			// loop

LLookupEnd$1:
LLookupRecover$1:
3:	// double wrap
	JumpMiss $0

.endmacro
```

分析查找流程：

- `ldr p11, [x16, #CACHE]`：`x16`存储的是 isa，`#CACHE`是个宏定义，表示 16 个字节；`[x16, #CACHE]`表示类对象`内存地址偏移16字节`得到`cache`

- `and p10, p11, #0x0000ffffffffffff`：将 `cache` 和 `0x0000ffffffffffff`进行`&`运算，得到 `buckets` 存入 `p10` 寄存器

- `and p12, p1, p11, LSR #48`：将 `cache` 进行右移 48 位，得到 `mask`，存入 `p11` 并与 `p1` 进行`&`操作，即 `_cmd & mask = sel & mask`得到哈希索引存入 `p12` 寄存器

  ```c++
  static inline mask_t cache_hash(SEL sel, mask_t mask) 
  {
      return (mask_t)(uintptr_t)sel & mask;
  }
  ```

- `add p12, p10, p12, LSL #(1+PTRSHIFT)`：

  - `PTRSHIFT`是宏定义，在 `arm64` 下等于 `3`，*1+PTRSHIFT = 4* 
  - `p10, p12, LSL #(1+PTRSHIFT)`即左移 4 位（结构体 `bucket_t` 占 16 字节，sel、imp 各占 8），`哈希索引*bucket占用内存大小`，得到`buckets`首地址在`实际内存`中的`偏移量`
  - `p12, p10, p12, LSL #(1+PTRSHIFT)`表示通过`buckets`首地址+实际偏移量，获取哈希索引对应的`bucket`

- `ldp p17, p9, [x12]`根据获取的`bucket`，取出其中的`sel`存入`p17`，即`p17 = sel`，取出`imp`存入`p9`，即`p9 = imp`

- 开启第一次循环

  - 比较获取的`bucket`中`sel` 与 `objc_msgSend`的第二个参数的`_cmd(即p1)`是否相等
  - 如果`相等`，则直接跳转至`CacheHit`，即`缓存命中`，返回`imp`
  - 如果不相等，有以下两种情况
    - 如果一直都找不到，直接跳转至`CheckMiss`，因为`$0`是`normal`，会跳转至`__objc_msgSend_uncached`，即进入`慢速查找流程`
    - 如果`根据index获取的bucket` 等于 `buckets的第一个元素`，则`人为`的将`当前bucket设置为buckets的最后一个元素`（通过`buckets首地址+mask右移44位`（等同于左移4位）直接`定位到bucker的最后一个元素`），然后继续向前查找，进行递归循环

- 第二次循环

  - 重复第一次循环的操作，与之唯一不同的是：
    - 如果当前的 `bucket` 等于 `buckes` 的第一个元素，则直接跳转至 `JumpMiss`，此时的`$0`是`normal`，也是直接跳转至`__objc_msgSend_uncached`，即进入`慢速查找流程`

> 两次循环的目的：防止不断循环的过程中多线程并发，正好缓存更新了

在这篇文章[Obj-C Optimization: The faster objc_msgSend](http://www.mulle-kybernetik.com/artikel/Optimization/opti-9.html)中看到了这样一段C版本的objc_msgSend的源码。

```c
#include <objc/objc-runtime.h>

id  c_objc_msgSend( struct objc_class /* ahem */ *self, SEL _cmd, ...)
{
   struct objc_class    *cls;
   struct objc_cache    *cache;
   unsigned int         hash;
   struct objc_method   *method;   
   unsigned int         index;
   
   if( self)
   {
      cls   = self->isa;
      cache = cls->cache;
      hash  = cache->mask;
      index = (unsigned int) _cmd & hash;
      
      do
      {
         method = cache->buckets[ index];
         if( ! method)
            goto recache;
         index = (index + 1) & cache->mask;
      }
      while( method->method_name != _cmd);
      return( (*method->method_imp)( (id) self, _cmd));
   }
   return( (id) self);

recache:
   /* ... */
   return( 0);
}
```

虽然`objc4`的版本有所变化，但是基本的流程上大致是相似的，可以参考理解。

同时，之前分析 cache_t 中的 `cache_t::insert`方法和`objc_msgSend`汇编流程，也是非常的相似的

#### 慢速查找流程



### 总结


