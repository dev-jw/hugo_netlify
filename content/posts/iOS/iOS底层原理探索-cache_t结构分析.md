---
title: "iOS底层原理探索-cache_t结构分析"
date: 2020-09-17T17:56:00+08:00
draft: false
tags: ["iOS"]
url:  "cache_t"
---

之前介绍了类的结构，但还剩下 `cache_t cache` 没有进行分析，本来将对 `cache_t` 进行研究

同样地，还是先提出几个问题：

- `mask`的作用是什么
- `capacity`的变化是怎么样
- 缓存扩容的时机是什么？
- `bucket`与`mask、capacity、sel、imp`的关系

### cache_t 结构

**cache_t 的源码定义**

```objective-c
struct cache_t {
#if CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_OUTLINED
    explicit_atomic<struct bucket_t *> _buckets;
    explicit_atomic<mask_t> _mask;
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_HIGH_16
    explicit_atomic<uintptr_t> _maskAndBuckets;
    mask_t _mask_unused;
    
    // How much the mask is shifted by.
    static constexpr uintptr_t maskShift = 48;
    
    // Additional bits after the mask which must be zero. msgSend
    // takes advantage of these additional bits to construct the value
    // `mask << 4` from `_maskAndBuckets` in a single instruction.
    static constexpr uintptr_t maskZeroBits = 4;
    
    // The largest mask value we can store.
    static constexpr uintptr_t maxMask = ((uintptr_t)1 << (64 - maskShift)) - 1;
    
    // The mask applied to `_maskAndBuckets` to retrieve the buckets pointer.
    static constexpr uintptr_t bucketsMask = ((uintptr_t)1 << (maskShift - maskZeroBits)) - 1;
    
    // Ensure we have enough bits for the buckets pointer.
    static_assert(bucketsMask >= MACH_VM_MAX_ADDRESS, "Bucket field doesn't have enough bits for arbitrary pointers.");
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_LOW_4
    // _maskAndBuckets stores the mask shift in the low 4 bits, and
    // the buckets pointer in the remainder of the value. The mask
    // shift is the value where (0xffff >> shift) produces the correct
    // mask. This is equal to 16 - log2(cache_size).
    explicit_atomic<uintptr_t> _maskAndBuckets;
    mask_t _mask_unused;

    static constexpr uintptr_t maskBits = 4;
    static constexpr uintptr_t maskMask = (1 << maskBits) - 1;
    static constexpr uintptr_t bucketsMask = ~maskMask;
#else
#error Unknown cache mask storage type.
#endif
    
#if __LP64__
    uint16_t _flags;
#endif
    uint16_t _occupied;
  
  ...
}
```

3 个宏定义分别指：

- `CACHE_MASK_STORAGE_OUTLINED` 表示运行的环境 `模拟器` 或者 `macOS`
- `CACHE_MASK_STORAGE_HIGH_16` 表示运行环境是 `64`位的`真机`
- `CACHE_MASK_STORAGE_LOW_4` 表示运行环境是 `非64`位 的`真机`

> `explicit_atomic`是指C++11 并发操作，内部定义为`struct explicit_atomic : public std::atomic<T>`是一个模板类，这里不详细展开

因此，我们只分析 macOS 部分，简化后的源码为：

```objective-c
struct cache_t {
    struct bucket_t * _buckets;
    mask_t _mask;
    uint16_t _flags;
    uint16_t _occupied;
}
```

`_buckets`：存储 bucket 的容器

`_mask`：分配用来缓存 bucket 的总数

`_occupied`：记录当前实际占用的缓存 bucket 个数

**`bucket_t`的源码定义**

```objective-c
struct bucket_t {
private:
    // IMP-first is better for arm64e ptrauth and no worse for arm64.
    // SEL-first is better for armv7* and i386 and x86_64.
#if __arm64__
    explicit_atomic<uintptr_t> _imp;
    explicit_atomic<SEL> _sel;
#else
    explicit_atomic<SEL> _sel;
    explicit_atomic<uintptr_t> _imp;
#endif
}
```

从`bucket_t`的定义中可以发现：**bucket_t是作为存储 sel 和 imp 的对象容器**

因此，整个关系为：

![image-20200920184855382](https://w-md.imzsy.design/image-20200920184855382.png)

**通过 LLDB 打印 cache**

```objective-c
@interface Person : NSObject

- (void)doFirst;
- (void)doSecond;
- (void)doThird;

@end

@implementation Person

- (void)doFirst {}
- (void)doSecond {}
- (void)doThird {}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        FXPerson *p = [[Person alloc] init];
        Class cls = object_getClass(p);
        
        [p doFirst];
        [p doSecond];
        [p doThird];
    }
    return 0;
}
```

根据类的结构，打印 cache，只要通过类的首地址，再平移 isa 的内存长度和 superclass 的内存长度即可

```ruby
(lldb) p/x Person.class
(Class) $0 = 0x0000000100008198 Person

// 首地址 + 16 字节
(lldb) p (cache_t *)0x00000001000081a8
(cache_t *) $1 = 0x00000001000081a8
```

- 在调用 `doFirst` 之前

  ```ruby
  (lldb) p *$1
  (cache_t) $2 = {
    _buckets = {
      std::__1::atomic<bucket_t *> = {
        Value = 0x0000000100346460
      }
    }
    _mask = {
      std::__1::atomic<unsigned int> = {
        Value = 0
      }
    }
    _flags = 32784
    _occupied = 0
  }
  ```

  - `_mask`为0
  - `_occupied`为0
  - `_butkets`为 null

- 调用了 `doFirst`之后

  ```ruby
  (lldb) p *$1
  (cache_t) $3 = {
    _buckets = {
      std::__1::atomic<bucket_t *> = {
        Value = 0x0000000100706470
      }
    }
    _mask = {
      std::__1::atomic<unsigned int> = {
        Value = 3
      }
    }
    _flags = 32784
    _occupied = 1
  }
  ```

  - `_mask`为 3
  - `_occupied`为 1
  - `_butkets`为 `doFirst`

- 调用 `doSecond` 之后

  ```ruby
  (lldb) p *$1
  (cache_t) $4 = {
    _buckets = {
      std::__1::atomic<bucket_t *> = {
        Value = 0x0000000100706470
      }
    }
    _mask = {
      std::__1::atomic<unsigned int> = {
        Value = 3
      }
    }
    _flags = 32784
    _occupied = 2
  }
  ```

  - `_mask`为 3
  - `_occupied`为 2
  - `_butkets`为 `doFirst、doSecond`

- 调用 `doThird` 之后

  ```ruby
  (lldb) p *$1
  (cache_t) $5 = {
    _buckets = {
      std::__1::atomic<bucket_t *> = {
        Value = 0x00000001006386e0
      }
    }
    _mask = {
      std::__1::atomic<unsigned int> = {
        Value = 7
      }
    }
    _flags = 32784
    _occupied = 1
  }
  ```

  - `_mask`为 7
  - `_occupied`为 1
  - `_butkets`为 `doThird`

通过调式的过程，产生了几个疑问：

1. `_mask`和`_occupied`为什么这么变化
2. `_buckets`中的`doFirst、doSecond`，为什么在调用`doThird`之后没了

为了解决上面的疑问，我们需要继续探索，切入点：`_mask`和`_occupied`的改变时机

### 方法缓存

在cache_t源码的定义中发现`void incrementOccupied()`正是我们下一步探索的目标，通过全局搜索，可以发现`incrementOccupied()`函数，只在`cache_t::insert`中被调用。

**`cache_t::insert`的方法实现**

```c++
ALWAYS_INLINE
void cache_t::insert(Class cls, SEL sel, IMP imp, id receiver)
{
#if CONFIG_USE_CACHE_LOCK
    cacheUpdateLock.assertLocked();
#else
    runtimeLock.assertLocked();
#endif

    ASSERT(sel != 0 && cls->isInitialized());

    // Use the cache as-is if it is less than 3/4 full
    // 计算新的缓存占用
    mask_t newOccupied = occupied() + 1;
    unsigned oldCapacity = capacity(), capacity = oldCapacity;
  	
    // 判断是否需要对缓存扩容
    if (slowpath(isConstantEmptyCache())) {
        // Cache is read-only. Replace it.
        if (!capacity) capacity = INIT_CACHE_SIZE;
        reallocate(oldCapacity, capacity, /* freeOld */false);
    }
    else if (fastpath(newOccupied + CACHE_END_MARKER <= capacity / 4 * 3)) {
        // Cache is less than 3/4 full. Use it as-is.
    }
    else {
        capacity = capacity ? capacity * 2 : INIT_CACHE_SIZE;
        if (capacity > MAX_CACHE_SIZE) {
            capacity = MAX_CACHE_SIZE;
        }
        reallocate(oldCapacity, capacity, true);
    }
    // 存储 sel 和 imp
    bucket_t *b = buckets();
    mask_t m = capacity - 1;
    mask_t begin = cache_hash(sel, m);
    mask_t i = begin;

    // Scan for the first unused slot and insert there.
    // There is guaranteed to be an empty slot because the
    // minimum size is 4 and we resized at 3/4 full.
    do {
        if (fastpath(b[i].sel() == 0)) {
            incrementOccupied();
            b[i].set<Atomic, Encoded>(sel, imp, cls);
            return;
        }
        if (b[i].sel() == sel) {
            // The entry was added to the cache by some other thread
            // before we grabbed the cacheUpdateLock.
            return;
        }
    } while (fastpath((i = cache_next(i, m)) != begin));

    cache_t::bad_cache(receiver, (SEL)sel, cls);
}
```

这个方法，看上去比较复杂，但主要实现的功能：

1. 计算新的缓存占用
2. 缓存扩容
3. 根据 hash 算法，将 sel 和 imp 存入buckets

**计算新的缓存**

`occupied()`函数会返回当前的缓存占用大小，在此基础上加 1，得到新的缓存占用大小`newOccupied`

`capacity()`函数：`return mask() ? mask()+1 : 0;`

在当前 mask 值的基础上加 1，得到当前的最大缓存容量 `capacity`

**判断是否需要对缓存扩容**

- 如果缓存为空，调用`reallocate`方法，申请内存
- 如果新的缓存占用大小 `<=` 缓存容量的四分之三，则进行 sel 和 imp 的存储
- 如果缓存不为空，且新的缓存占用大小 `>` 缓存容量的四分之三，则需要进行扩容并覆盖之前的缓存

**缓存扩容**

`reallocate`方法

```c++
ALWAYS_INLINE
void cache_t::reallocate(mask_t oldCapacity, mask_t newCapacity, bool freeOld)
{
    bucket_t *oldBuckets = buckets();
    bucket_t *newBuckets = allocateBuckets(newCapacity);

    // Cache's old contents are not propagated. 
    // This is thought to save cache memory at the cost of extra cache fills.
    // fixme re-measure this

    ASSERT(newCapacity > 0);
    ASSERT((uintptr_t)(mask_t)(newCapacity-1) == newCapacity-1);

    setBucketsAndMask(newBuckets, newCapacity - 1);
    
    if (freeOld) {
        cache_collect_free(oldBuckets, oldCapacity);
    }
}

```

- `allocateBuckets`函数内部会调用 `calloc` 去开辟内存空间，`newCapacity`是传入的缓存最大容量
- `setBucketsAndMask`函数会根据系统环境，将 buckets 和 mask 进行赋值
  - 如果是真机，会将 buckets和 mask 存入`_maskAndBuckets`中，并将`_occupied`设置为 0
  - 如果是不是甄姬，则正常存储 buckets 和 mask，`_occupied`置为 0
- `cache_collect_free`函数，会将原始的缓存进行销毁回收

> 为什么使用cache_collect_free消除记忆，而不是重新读写、内存拷贝的方式？
>
> 一是重新读写不安全；二是抹掉速度快

**存储sel和imp**

```c++
// 获取当前缓存中的 buckets
bucket_t *b = buckets();
// 获取 mask 值
mask_t m = capacity - 1;
// 根据 sel 和 mask 值进行 hash，计算存储索引位置beign
mask_t begin = cache_hash(sel, m);
mask_t i = begin;
```

- `cache_hash`内部实现：`return (mask_t)(uintptr_t)sel & mask;`即根据当前的 mask 值和传入 sel 进行**与操作**，得到初始索引 `begin`进行哈希查找
- 在`do-while`循环里遍历整个`buckets`
  - 如果`b[i].sel() == 0`，说明在索引i的位置上还没有缓存过方法，可以进行缓存，且`occupied`加 1
  - 如果`b[i].sel() == sel`，说明在索引i的位置上方法与传入的方法相同，则返回
  - 如果`b[i].sel()`不等于 `0` 且不等于传入的`sel`，则调用`cache_next`方法，重新进行计算新的索引给 `i`，继续进行哈希查找
  - 如果没有找到，则缓存有问题，调用 `bad_cache`

`cache_next`解决哈希冲突

```c++
#if __arm__  ||  __x86_64__  ||  __i386__
// objc_msgSend has few registers available.
// Cache scan increments and wraps at special end-marking bucket.
#define CACHE_END_MARKER 1
static inline mask_t cache_next(mask_t i, mask_t mask) {
    return (i+1) & mask;
}

#elif __arm64__
// objc_msgSend has lots of registers available.
// Cache scan decrements. No end marker needed.
#define CACHE_END_MARKER 0
static inline mask_t cache_next(mask_t i, mask_t mask) {
    return i ? i-1 : mask;
}
```

### 疑问点

**`mask`的作用**

- `mask` 是作为 `cache_t` 的成员变量存在，它表示缓存总容量的大小减一的值

- `mask` 对于 `bucket` 来说，是参与哈希算法的关键，用于计算缓存索引位置

**`occupied`的变化**

`_occupied`表示当前 cahce 中缓存`bucket`的占用大小 (即可以理解为缓存存储了`sel-imp`的的`个数`)

**capacity的变化**

`capacity`的变化主要发生在扩容的时候，当缓存已经占满了四分之三的时候，会进行两倍原来缓存空间大小的扩容，这一步是为了避免哈希冲突

**为什么是在 3/4 时进行扩容**

在哈希这种数据结构里面，有一个概念用来表示空位的多少叫做`装载因子`——装载因子越大，说明空闲位置越少，冲突越多，散列表的性能会下降

负载因子是`3/4`的时候，空间利用率比较高，而且避免了相当多的Hash冲突，提升了空间效率

具体可以阅读[HashMap的负载因子为什么默认是0.75？](https://baijiahao.baidu.com/s?id=1656137152537394906&wfr=spider&for=pc)

**方法缓存是否有序**

方法缓存是无序的，因为是用哈希算法来计算缓存下标——下标值取决于`key` 和`mask`的值

**bucket与mask、capacity、sel、imp的关系**

类`cls`拥有属性`cache_t`，

`cache_t`中的`buckets`有多个`bucket`——存储`bucket_t`结构体（方法实现`imp`和方法编号`sel`）

`mask`对于`bucket`来说，主要是用来在缓存查找时的哈希算法

### 总结  

`cache_t`中的`bucket_t *_buckets`其实就是一个散列表，用来存储`Method`的链表。

`Cache`的作用主要是为了优化方法调用的性能。

当对象`receiver`调用方法`message`时

- 首先根据对象`receiver`的`isa`指针查找到它对应的类
- 然后在类的`methodLists`中搜索方法，
  - 如果没有找到，就使用`superclass`指针到父类中的`methodLists`查找，一旦找到就调用方法。
  - 如果没有找到，有可能消息转发，也可能忽略它。

但这样查找方式效率太低，因为往往一个类大概只有`20%`的方法经常被调用，占总调用次数的`80%`。

所以使用`Cache`来缓存经常调用的方法，当调用方法时，优先在`Cache`查找，如果没有找到，再到`methodLists`查找。