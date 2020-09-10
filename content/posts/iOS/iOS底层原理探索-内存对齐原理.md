---
title: "iOS底层原理探索-内存对齐原理"
date: 2020-09-07T20:07:19+08:00
draft: false
tags: ["iOS"]
url:  "alignment-size"
---

在『[iOS底层原理探索-alloc流程分析](/alloc)』一文中讲了底层对象创建的流程，本来将探索对象的属性在内存中的排列。

同样的，先提出几个问题：

- 为什么声明属性的前后顺序会影响对象的内存排列呢？
- `sizeof`、`class_getInstanceSize`、`malloc_size`分别是什么？
- 不是说对象最少为16字节，为什么`class_getInstanceSize`还能输出8字节？
- 一个 NSObject 对象占用多少内存？

> 本文主要探索的是 Objective-C 的对象属性，在内存中的排列，Swift 可以参考[这篇文章](https://swiftunboxed.com/internals/size-stride-alignment/)

### 内存大小

让我们先来两个简单的结构体：

```c++
struct Person {
    double age;
}Person;

struct PersonBaseInfo {
    double height;
    double weight;
}PersonBaseInfo;
```

直觉告诉我们，`PersonBaseInfo`的实例比`Person`更大（占用更多的内存空间）

那么，我们怎么来验证呢？

**内存大小**

我们通过`sizeof`获取内存大小

```c++
// 结构体类型的内存大小
size_t struct_p_size = sizeof(Person);
  
// 结构体实例对象的内存大小
struct Person instance_p;
instance_p.age = 20.0;
size_t instance_p_size = sizeof(instance_p);
```

在这两种情况下，`struct_p_size`和`instance_p_size`的大小均为 8。

毫无疑问，`PersonBaseInfo`的内存大小是 16。

结构体的内存大小似乎非常直观——计算每个成员变量的大小之和

那么如果是下面这样的结构呢

```c++
struct Person {
    double age;
  	bool sex
}Person;
```

按上面的方式来计算内存：

```c++
size_t struct_p_size = sizeof(Person);
// struct_p_size = 8 + 1 = 9

struct Person instance_p;
instance_p.age = 20.0;
instance_p.sex = true;
size_t instance_p_size = sizeof(instance_p);
// instance_p_size = 8 + 1 = 9
```

看起来好像没有问题！[真的是这样吗？😈]

### 内存布局

当我们在单个缓冲区（例如数组）中处理多个实例时，类型的跨度变得很重要。

如果我们有一组连续的 Person 实例，每个 Person 实例的大小为 9 字节，那么在内存的分布会如下图所示

![image-20200910140143470](https://w-md.imzsy.design/image-20200910140143470.png)

显然，在计算机中并不是这样的。

想象一下，如果有许多占用内存大小不一的结构，那么对于存储与读取会变得异常麻烦。

**步幅**

是确定两个元素之间的距离，该距离将大于或等于某个特定的内存大小

例如：Person 的大小不再是 9，而应该是 16，在内存中的分布应该像这样：

![image-20200910140945478](https://w-md.imzsy.design/image-20200910140945478.png)

也就是说，如果有一个指针指向第一个元素，并且想移至第二个元素，则跨度就是指针前进所需的字节距离数。

### 内存对齐

对象的属性要内存对齐，对象本身也需要进行内存对齐

**内存对齐原则**

- 数据成员对齐原则: 结构(struct)(或联合(union))的数据成员，第一个数据成员放在offset为0的地方，以后每个数据成员存储的起始位置要 从该成员大小或者成员的子成员大小

- 结构体作为成员：如果一个结构里有某些结构体成员，则结构体成员要从 其内部最大元素大小的整数倍地址开始存储

- 收尾工作：结构体的总大小，也就是sizeof的结果，必须是其内部最大 成员的整数倍，不足的要补⻬

> 内存对齐原则其实可以简单理解为`min(m,n)`——m为当前开始的位置，n为所占位数。当m是n的整数倍时，条件满足；否则m位空余，m+1，继续min算法。

我们对上面的 Person 进行一些修改

```c++
struct Person1 {
    double age;
    int idCard;
    bool sex;
}Person;

struct Person2 {
    int idCard;
    double age;
    bool sex;
}Person;
```

我们只是对结构体中的属性进行了顺序调整，通过`sizeof`分别得到`16`和`24`

现在，新的问题：**仅仅只是改变了属性的顺序，为什么内存的大小就改变了呢？**

![image-20200910150313856](https://w-md.imzsy.design/image-20200910150313856.png)

根据内存对齐原则，计算 `Person1` 的内存如下：

`Person1`

- `age`：占 8 个字节，从 0 开始，此时 `min(0,8)`，即 0-7 存储 `age`
- `idCard`：占 4 个字节，从 8 开始，此时 `min(8,4)`，能够整除 4，即 8-11 存储 `idCard`
- `sex`：占 1 个字节，从 12 开始，此时 `min(12, 1)`，能够整除 1，即 12 存储 `sex`

内存大小为 13 个字节，最大变量的字节数为 8，所以 13 向上取整到 16，因为 16 是 最小的满足 8 的整数倍，所以 `Person1` 的内存大小为 16 bytes

`Person2`:

- `idCard`：占 4 个字节，从 0 开始，此时 `min(0,4)`，即 0-3 存储 `idCard`
- `age`：占 8 个字节，从 4 开始，此时 `min(4,8)` 并不满足整除条件直至`min(8,8)`，即 8-15 存储 `age`
- `sex`：占 1 个字节，从 16 开始，此时 `min(16, 1)`，能够整除 1，即 16 存储 `sex`

内存大小为 8 + 8 + 1 = 17 个字节，最大变量的字节数为 8，同理，所以 `Person2` 的内存大小为 24 bytes

通过上面的例子，我们不难发现，通过改变属性的顺序，是能够达到优化内存的，也就是**内存重排**

[搜狐公众号的一篇推送——内存布局（讲的很详细，推荐阅读）](https://mp.weixin.qq.com/s/Dp8LefBG2ZYFF0cCUzoNZg)

### NSObject对象的内存大小

获取NSObject对象的内存大小，需要用到以下几个函数：

`sizeof`:确切地说并不算函数，它是一个运算符，在编译时就可以获取类型所占内存的大小

`class_getInstanceSize`:依赖于`<objc/runtime.h>`，返回创建一个实例对象所需内存大小

`malloc_size`:依赖于`<malloc/malloc.h>`，返回系统实际分配的内存大小

```objc
NSObject *obj = [NSObject alloc];
size_t pSize = sizeof(obj);
size_t gSize  = class_getInstanceSize(NSObject.class);
size_t mSize = malloc_size((__bridge const void *)(obj));

NSLog(@"class_getInstanceSize = %zd", gSize);
NSLog(@"malloc_size = %zd", mSize);
NSLog(@"sizeOf = %zd", pSize);
```

打印结果：

```ruby
class_getInstanceSize = 8
malloc_size = 16
sizeOf = 8
```

在之前 alloc 流程中，我们计算对象的内存时采用的是 `16 字节对齐`，那么为什么通过`class_getInstanceSize`会返回 8 字节呢？

**class_getInstanceSize**

我们通过 objc源码，探索一下具体的实现

```c++
size_t class_getInstanceSize(Class cls)
{
    if (!cls) return 0;
    return cls->alignedInstanceSize();
}

// Class's ivar size rounded up to a pointer-size boundary.
uint32_t alignedInstanceSize() const {
    return word_align(unalignedInstanceSize());
}

// May be unaligned depending on class's ivars.
uint32_t unalignedInstanceSize() const {
    ASSERT(isRealized());
    return data()->ro()->instanceSize;
}

static inline uint32_t word_align(uint32_t x) {
    return (x + WORD_MASK) & ~WORD_MASK;
}
```

通过注释，不难看出，返回实例对象中成员变量内存大小。即`class_getInstanceSize`就是获取实例对象中成员变量的内存大小。

**malloc_size**

这个函数主要获取系统实际分配的内存大小，具体的底层实现也可以在源码`libmalloc`找到，具体如下：

```c++
size_t
malloc_size(const void *ptr)
{
	size_t size = 0;

	if (!ptr) {
		return size;
	}

	(void)find_registered_zone(ptr, &size);
	return size;
}
```

核心的方法是`find_registered_zone`，由于该方法涉及到虚拟内存分配的流程，过于复杂，就不再详细展开了。

理解一点，`malloc_size`是获取系统实际分配的内存大小

**sizeof**

sizeof是操作符，不是函数，它的作用对象是数据类型，主要作用于编译时。

因此，它作用于变量时，也是对其类型进行操作。得到的结果是该数据类型占用空间大小，即size_t类型。

sizeof 只会计算类型所占用的内存大小，不会关心具体的对象的内存布局。

### 小结

对于一个对象来说，真正的对齐方式是 8 字节对齐，8 字节对齐已经满足对象的需求了，但是苹果系统为例防止一切的容错，采用的是 16 字节对齐的内存，主要是因为采用 8 字节对齐时，对象会在连续内存中紧挨着，而 16 字节则比较宽松，利于以后的扩展性

- 系统分配 16 个字节给 NSObject 对象（通过 malloc_size 函数获得）

- NSObject 对象内部只使用了 8 个字节的空间（通过class_getInstanceSize函数）

