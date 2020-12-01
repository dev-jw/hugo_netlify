---
title: "iOS底层原理探索-常见的锁分析"
date: 2020-11-06T20:53:56+08:00
draft: true
tags: ["iOS"]
url:  "Lock"
---

多线程作为开发者必须掌握的技能，在开发中，稍有不慎便会造成线程不安全，保证线程安全的关键——锁

同样的，先提出几个问题：

- 常见锁的类型
- `atomic`原理
- `atomic`修饰的属性绝对安全吗？
- `@synchronized`原理

### 基本概念

**线程安全**

当一个线程操作某个数据的时候，其他的线程不能对其进行操作，直到该线程任务执行完毕

简单地说，就是在同一时刻，对同一个数据操作的线程只能有一个

而线程不安全，则是在同一时刻可以有多个线程对同一个数据进行操作，从而得不到预期的结果

**线程安全检测**

将 `Xcode` 的 `Edit Scheme` 中 `Diagnostics` 下的`Thread Sanitizer`和`Zobime Objects`打开即可

### 锁

锁作为一种非强制的机制，被用来保证线程安全：每一个线程在操作数据前，会先获取锁，并在操作之后释放锁

如果锁已经被占用，其他试图获取锁的线程会等待，直到锁释放

**种类**

在 iOS 中锁的基本种类只有两种

- 互斥锁
- 自旋锁

其他的锁，例如：`条件锁`、`递归锁`都是对这两种锁的封装和实现

**互斥锁**

互斥锁是防止两条线程同时对同一公共资源进行读写的机制。当获取锁操作失败时，线程会进入睡眠，等待锁释放时被唤醒

互斥锁分为：

- 递归锁：可重入锁，同一个线程在锁释放前可再次获取锁，即可以递归调用
- 非递归锁：不可重入，必须等锁释放后才能再次获取锁

**自旋锁**

自旋锁是线程反复检查锁变量是否可用。由于线程在这个过程中保持执行，因此是一种`忙等待`，一旦获取了自旋锁，线程就会一直保持该锁，直到显示释放自旋锁。

自旋锁避免了进程上下文的调度开销，因此对于`线程只会堵塞很短时间的场合`是有效的

### 自旋锁

**OSSpinLock**

自从`OSSpinLock`出现安全问题，在 iOS10 之后就被废弃了。自旋锁之所以不安全，是因为获取锁后，线程会一直处在忙等待状态，造成了任务的优先级反转

而`OSSpinLock`忙等的机制就可能造成高优先级一直 `running等待`，占用 CPU 时间片；而低优先级任务无法抢占时间片，变成迟迟完不成，不释放锁的情况

在`OSSpinLock`被弃用之后，其替代方案是通过`os_unfair_lock`代替`OSSpinLock`，`os_unfair_lock`在加锁时会处于`休眠状态`，而不是自旋锁的忙等状态

**atomic**

`atomic`是属性的修饰符，之前有提及 setter 方法会根据修饰符不同调用不同方法，最后统一调用`reallySetProperty`方法，，其中就有对 `atomic` 和 `nonatomic` 的操作

```c++
static inline void reallySetProperty(id self, SEL _cmd, id newValue, ptrdiff_t offset, bool atomic, bool copy, bool mutableCopy)
{
    if (offset == 0) {
        object_setClass(self, newValue);
        return;
    }

    id oldValue;
    id *slot = (id*) ((char*)self + offset);

    if (copy) {
        newValue = [newValue copyWithZone:nil];
    } else if (mutableCopy) {
        newValue = [newValue mutableCopyWithZone:nil];
    } else {
        if (*slot == newValue) return;
        newValue = objc_retain(newValue);
    }

    if (!atomic) {
        oldValue = *slot;
        *slot = newValue;
    } else {
        spinlock_t& slotlock = PropertyLocks[slot];
        slotlock.lock();
        oldValue = *slot;
        *slot = newValue;        
        slotlock.unlock();
    }

    objc_release(oldValue);
}
```

从源码中可以得出，关于 `atomic` 的逻辑分支：

- `atomic` 修饰的属性会进行`spinlock_t`加锁处理
- `nonatomic`修饰的属性则不会进行加锁

```c++
using spinlock_t = mutex_tt<LOCKDEBUG>;

class mutex_tt : nocopy_t {
    os_unfair_lock mLock;
    ...
}
```

对于 `getter` 方法也是如此：`atomic`修饰的属性会进行加锁处理

```c++
id objc_getProperty(id self, SEL _cmd, ptrdiff_t offset, BOOL atomic) {
    if (offset == 0) {
        return object_getClass(self);
    }

    // Retain release world
    id *slot = (id*) ((char*)self + offset);
    if (!atomic) return *slot;
        
    // Atomic retain release world
    spinlock_t& slotlock = PropertyLocks[slot];
    slotlock.lock();
    id value = objc_retain(*slot);
    slotlock.unlock();
    
    // for performance, we (safely) issue the autorelease OUTSIDE of the spinlock.
    return objc_autoreleaseReturnValue(value);
}
```

`spinlock_t`在底层是通过 `os_unfair_lock` 替代了 `OSSpinLock`进行加锁，从而保证读写的原子性

锁都在`PropertyLocks`中保存着（在 iOS 平台会初始化 8 个，mac 平台 64 个），同时为了防止哈希冲突，还使用加盐操作

在用之前，会把锁都初始化好，在需要用到时，用对象的地址加上成员变量的偏移量为 `key`，从`PropertyLocks`中去取。因此，存取时用的是同一个锁，所以 `atomic` 能保证属性的存取时是线程安全的

> 由于锁是有限的，不同对象，不同属性的读取用的也可能同一个锁

**那么`atomic`修饰的属性绝对安全吗？**

`atomic`在 `getter/setter` 方法中加锁，仅仅保证了读写时的线程安全，并不能保证数据安全

例如，对可变容器使用 `atomic` 修饰时，无法保证容器的修改是线程安全的

> 对于重写 `setter/getter` 方法的 `atomic`修饰的属性，需要依靠我们在重写 `setter/getter` 方法中保证线程安全

**读写锁**

读写锁是一种特殊的自旋锁，它把对共享资源的访问者划分成**读者**和**写者**，读者只对共享资源进行读访问，写者则需要对共享资源进行写操作。

这种锁相对于自旋锁而言，能提高并发性

- 写者是排他性的，⼀个读写锁同时只能有⼀个写者或多个读者（与CPU数相关），但不能同时既有读者⼜有写者。在读写锁保持期间也是抢占失效的
- 如果读写锁当前没有读者，也没有写者，那么写者可以⽴刻获得读写锁，否则它必须⾃旋在那⾥，直到没有任何写者或读者。如果读写锁没有写者，那么读者可以⽴即获得该读写锁，否则读者必须⾃旋在那⾥，直到写者释放该读写锁

```c
#import <pthread.h>
// 全局声明读写锁
pthread_rwlock_t lock;
// 初始化读写锁
pthread_rwlock_init(&lock, NULL);
// 读操作-加锁
pthread_rwlock_rdlock(&lock);
// 读操作-尝试加锁
pthread_rwlock_tryrdlock(&lock);
// 写操作-加锁
pthread_rwlock_wrlock(&lock);
// 写操作-尝试加锁
pthread_rwlock_trywrlock(&lock);
// 解锁
pthread_rwlock_unlock(&lock);
// 释放锁
pthread_rwlock_destroy(&lock);
```

平时很少会直接使用读写锁`pthread_rwlock_t`，更多的是采用其他方式，例如使用[栅栏函数]()实现读写锁

### 互斥锁

#### pthread_mutex

`pthread_mutex`就是互斥锁本身，当锁被占用，而其他线程申请锁时，不是使用忙等，而是阻塞线程并睡眠

```c
#import <pthread.h>
// 全局声明互斥锁
pthread_mutex_t _lock;
// 初始化互斥锁
pthread_mutex_init(&_lock, NULL);
// 加锁
pthread_mutex_lock(&_lock);
// 这里做需要线程安全操作
// ...
// 解锁 
pthread_mutex_unlock(&_lock);
// 释放锁
pthread_mutex_destroy(&_lock);
```

`pthread_mutex`具体使用可以参考[YYKit的YYMemoryCach](https://github.com/ibireme/YYKit/blob/3869686e0e560db0b27a7140188fad771e271508/YYKit/Cache/YYMemoryCache.m)

#### @synchronized分析

`@synchronized`是日常开发中用的比较多的一种互斥锁，使用起来简单方便，但不是所有场景都能使用`@synchronized`，并且它的性能较低

```objective-c
@synchronized (obj) {}
```



**源码分析**

**总结**

#### NSLock分析

**源码**

**注意点**

#### NSRecursiveLock分析

#### NSCondition与NSConditionLock

### 总结

### 最后



请勿外泄 11.0.1 20B50三分区 

16G cloud.189.cn/t/qa6nYzMnUzAb (2qzv) 

32G cloud.189.cn/t/re2MFrB7Frme (23ay) 

7天内有效

