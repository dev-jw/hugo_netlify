---
title: "iOS底层原理探索-类的结构分析"
date: 2020-09-14T16:28:45+08:00
draft: true
tags: ["iOS"]
url:  "Class-structure"
---

在『[iOS底层原理探索-isa结构&指向分析](/isa)』中，我们已经知道：



本文将对类的结构进一步的分析，同样的，先提出几个问题：

- `objc_class` 与 `objc_object` 有什么关系？
- 成员变量和属性有什么区别？
- 实例方法与类方法的归属问题？

### 类的本质

**类的本质是 objc_class 类型的结构体，objc_class 继承与 objc_object**

我们再来看一下：**NSObject的定义**

```Objective-C
typedef struct objc_class *Class;
typedef struct objc_object *id;

@interface NSObject <NSObject> {
    Class isa  OBJC_ISA_AVAILABILITY;
}
```

`objc_class`的定义

```objc
struct objc_class : objc_object {
    // Class ISA;
    Class superclass;
    cache_t cache;             // formerly cache pointer and vtable
    class_data_bits_t bits;    // class_rw_t * plus custom rr/alloc flags
  	// 去掉了部分的方法
};
```

`objc_object`的定义

```objc
struct objc_object {
  private:
      isa_t isa;
  }
}
```

仔细比较 `NSObject` 和 `objc_object`，两者非常的相似，可以总结为：

- `NSObject`是 `objc_object` 的仿写，和 `objc_object`定义是一样的，在底层会被编译成 `objc_object`
- 所以，`NSObject类`是 Objective-C 的 `objc_object`

### 类的结构

从 `objc_class` 中定义，结构体有 4 个成员变量：isa、superclass、cache、bits

**Class ISA**

这是继承于 `objc_object` 而来的，指向的是当前的类，占 8 字节

**Class superclass**

父类，superclass是 `Class` 类型，占 8 字节

**cache_t cache**

`cache_t`的定义

```C++
struct cache_t {
#if CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_OUTLINED
    explicit_atomic<struct bucket_t *> _buckets;
    explicit_atomic<mask_t> _mask;
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_HIGH_16
    explicit_atomic<uintptr_t> _maskAndBuckets;
    mask_t _mask_unused;
    
#if __LP64__
    uint16_t _flags;
#endif
    uint16_t _occupied;
```

正如所见的，cache_t 是一个结构体，内存长度由所有元素决定：

- `_buckets` | `_maskAndBuckets`：`bucket_t*`是结构体指针，`uintptr_t`也是指针，8 字节
- `_mask` | `_mask_unused`：`mask_t`是 `int` 类型，占 4 个字节
- `_flags`：`uint16_t`类型，uint16_t是 `unsigned short` 的别名，占 2个字节
- `_occupied`：`uint16_t`类型，uint16_t是 `unsigned short` 的别名，占 2个字节

因此，`cache_t` 占用 16 字节

**class_data_bits_t bits**



### 类的属性方法

