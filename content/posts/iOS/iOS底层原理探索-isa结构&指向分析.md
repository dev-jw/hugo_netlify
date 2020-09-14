---
title: "iOS底层原理探索-isa结构&指向分析"
date: 2020-09-10T10:25:02+08:00
draft: false
tags: ["iOS"]
url:  "isa"
---

在『[iOS底层原理探索-alloc流程分析](https://dev.hjw.best/alloc)』中提了一下`obj->initInstanceIsa(cls, hasCxxDtor)`，本文将对 isa 的进行细说

同样的，先提出几个问题：

- 位域是什么？联合体是什么？联合体和结构体有什么区别
- NSObject的本质是什么？
- isa 是怎么存储类信息？
- isa的走位和 superClass 的走向是怎么样的？
- 类在内存中存在多少份？

### 准备知识

在分析 isa 之前，先补充位域和结构体的知识点

**位域**

位段，C语言允许在一个结构体中以位为单位来指定其成员所占内存长度，这种以位为单位的成员称为「位段」或称「位域」( bit field) 。利用位段能够用较少的位数存储数据

示例：

```c++
// 使用位域声明
struct Struct1 {
    char ch:   1;  //1位
    int  size: 3;  //3位
} Struct1;

struct Struct2 {
    char ch;    //1位
    int  size;  //4位
} Struct2;

sizeof(Struct1); // 返回 4
sizeof(Struct2); // 返回 8
```

**联合体**

当多个数据需要共享内存或者多个数据每次只取其一时，可以利用`联合体(union)`

- 联合体是一个结构
- 它的所有成员相对于基地址的偏移量都为0
- 此结构空间要大到足够容纳最"宽"的成员
- 各变量是“互斥”的——共用一个内存首地址，联合变量可被赋予任一成员值,但每次只能赋一种值, 赋入新值则冲去旧值

**与结构体比较**

结构体每个成员依次存储，联合体中所有成员的偏移地址都是 0，也就是说所有成员是叠在一起的，所以在联合体中某一时刻，只有一个成员有效——**结构体内存大小取决于所有元素，联合体取决于最大那个**

![image-20200911174308964](https://w-md.imzsy.design/image-20200911174308964.png)

### NSObject的本质

源码分析均来自[objc4-781](https://opensource.apple.com/source/objc4/)，且在 Objc2.0 之后

**NSObject的定义**

```objc
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

union isa_t {
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;
    uintptr_t bits;
#if defined(ISA_BITFIELD)
    struct {
        ISA_BITFIELD;  // defined in isa.h
    };
#endif
};
```

把源码的定义转化成类图，如下

![isa定义](https://w-md.imzsy.design/isa定义.png)

从上述源码中，可以看到，**Objective-C 对象都是 C 语言结构体实现的**，在 objc2.0 中，所有的对象都会包含一个 `isa_t` 类型的结构体。

- `objc_object`被`typedef`成了`id`类型，也就是我们平时遇到的`id`类型。这个结构体就只包含了一个`isa_t`类型的结构体
- `objc_class`继承于`objc_object`。所以在 objc_class 中也会包含 `isa_t` 类型的结构体 isa

至此，可以得出结论：**Objective-C中类也是一个对象**

**类的本质是 objc_class 类型的结构体，objc_class 继承与 objc_object**

那么 isa 到底是什么呢？

### isa结构分析

**`isa`的初始化**

那就要从`obj->initInstanceIsa(cls, hasCxxDtor)`之后的流程，继续探索

```objc
inline void 
objc_object::initInstanceIsa(Class cls, bool hasCxxDtor)
{
    ASSERT(!cls->instancesRequireRawIsa());
    ASSERT(hasCxxDtor == cls->hasCxxDtor());

    initIsa(cls, true, hasCxxDtor);
}

inline void 
objc_object::initIsa(Class cls, bool nonpointer, bool hasCxxDtor) 
{ 
    ASSERT(!isTaggedPointer()); 
    
    if (!nonpointer) {
        isa = isa_t((uintptr_t)cls);
    } else {
        ASSERT(!DisableNonpointerIsa);
        ASSERT(!cls->instancesRequireRawIsa());

        isa_t newisa(0);

#if SUPPORT_INDEXED_ISA
        ASSERT(cls->classArrayIndex() > 0);
        newisa.bits = ISA_INDEX_MAGIC_VALUE;
        // isa.magic is part of ISA_MAGIC_VALUE
        // isa.nonpointer is part of ISA_MAGIC_VALUE
        newisa.has_cxx_dtor = hasCxxDtor;
        newisa.indexcls = (uintptr_t)cls->classArrayIndex();
#else
        newisa.bits = ISA_MAGIC_VALUE;
        // isa.magic is part of ISA_MAGIC_VALUE
        // isa.nonpointer is part of ISA_MAGIC_VALUE
        newisa.has_cxx_dtor = hasCxxDtor;
        newisa.shiftcls = (uintptr_t)cls >> 3;
#endif

        // This write must be performed in a single store in some cases
        // (for example when realizing a class because other threads
        // may simultaneously try to use the class).
        // fixme use atomics here to guarantee single-store and to
        // guarantee memory order w.r.t. the class index table
        // ...but not too atomic because we don't want to hurt instantiation
        isa = newisa;
    }
}
```

传入的 `nonpointer` 是 ture，那么会执行 else 中的语句：分别对`bits、has_cxx_dtor、shiftcls`赋值。

**`isa_t` 的具体实现**

```objc
union isa_t {
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;
    uintptr_t bits;
#if defined(ISA_BITFIELD)
    struct {
        ISA_BITFIELD;  // defined in isa.h
    };
#endif
};
```

首先，这是个**联合体**，内部有两个成员，`cls` 和 `bits`，也就是说在初始化 isa 指针时，会有 2 种情况

- 通过 `cls` 初始化，`bits 无默认值`
- 通过 `bits` 初始化，`cls 有默认值`

`ISA_BITFIELD`是一个位域类型的结构体，用于存储类信息以及其他信息，宏定义为

```objective-c
# if __arm64__
#   define ISA_MASK        0x0000000ffffffff8ULL
#   define ISA_MAGIC_MASK  0x000003f000000001ULL
#   define ISA_MAGIC_VALUE 0x000001a000000001ULL
#   define ISA_BITFIELD                                                      \
      uintptr_t nonpointer        : 1;                                       \
      uintptr_t has_assoc         : 1;                                       \
      uintptr_t has_cxx_dtor      : 1;                                       \
      uintptr_t shiftcls          : 33; /*MACH_VM_MAX_ADDRESS 0x1000000000*/ \
      uintptr_t magic             : 6;                                       \
      uintptr_t weakly_referenced : 1;                                       \
      uintptr_t deallocating      : 1;                                       \
      uintptr_t has_sidetable_rc  : 1;                                       \
      uintptr_t extra_rc          : 19
#   define RC_ONE   (1ULL<<45)
#   define RC_HALF  (1ULL<<18)

# elif __x86_64__
#   define ISA_MASK        0x00007ffffffffff8ULL
#   define ISA_MAGIC_MASK  0x001f800000000001ULL
#   define ISA_MAGIC_VALUE 0x001d800000000001ULL
#   define ISA_BITFIELD                                                        \
      uintptr_t nonpointer        : 1;                                         \
      uintptr_t has_assoc         : 1;                                         \
      uintptr_t has_cxx_dtor      : 1;                                         \
      uintptr_t shiftcls          : 44; /*MACH_VM_MAX_ADDRESS 0x7fffffe00000*/ \
      uintptr_t magic             : 6;                                         \
      uintptr_t weakly_referenced : 1;                                         \
      uintptr_t deallocating      : 1;                                         \
      uintptr_t has_sidetable_rc  : 1;                                         \
      uintptr_t extra_rc          : 8
#   define RC_ONE   (1ULL<<56)
#   define RC_HALF  (1ULL<<7)

# else
#   error unknown architecture for packed isa
# endif
```

![2](https://w-md.imzsy.design/2.png)

| 变量名              | 描述                                                         |
| ------------------- | ------------------------------------------------------------ |
| `nonpointer`        | 表示是否对isa指针开启`指针优化`——0：纯isa指针；1：不止是类对象地址，isa 中包含了类信息、对象的引用计数等 |
| `has_assoc`         | `关联对象`标志位                                             |
| `has_cxx_dtor`      | 该对象是否有 C++ 或者 Objc 的析构器，如果有析构函数,则需要做析构逻辑；如果没有，则可以更快的释放对象 |
| `shiftcls`          | **存储类指针的值，即类信息**，在开启指针优化的情况下，在 arm64 架构中有 33 位用来存储类指针 |
| `magic`             | 用于调试器判断当前对象是`真的对象`还是`没有初始化的空间`     |
| `weakly_referenced` | 对象`是否被指向`或者`曾经指向一个 ARC` 的弱变量， 没有弱引用的对象可以更快释放 |
| `deallocating`      | 标志对象是否`正在释放`内存                                   |
| `has_sidetable_rc`  | 当对象`引用技术大于 10` 时，则需要借用该变量存储进位         |
| `extra_rc`          | 表示该对象的引用计数值，实际上是引用计数值减 1。 例如，如果对象的引用计数为 10，那么 extra_rc 为 9 |

**shiftcls关联类**

shiftcls是存储类的指针，而`newisa.shiftcls = (uintptr_t)cls >> 3`这行代码，正是将 `isa` 与当前类 `cls` 关联起来。

`newisa.shiftcls = (uintptr_t)cls >> 3`这行代码是将 `isa` 与当前类 `cls` 关联起来，即将类信息存储到 isa 指针当中。

> 将当前地址右移三位的主要原因是：
>
> 将 Class 指针中无用的后三位清除减小内存的消耗，因为类的指针要按照字节（8 bits）对齐内存，其指针后三位都是没有意义的 0。
>
> 具体可以看『[从 NSObject 的初始化了解 isa](https://github.com/draveness/analyze/blob/master/contents/objc/%E4%BB%8E%20NSObject%20%E7%9A%84%E5%88%9D%E5%A7%8B%E5%8C%96%E4%BA%86%E8%A7%A3%20isa.md#shiftcls)』中的shiftcls分析。

**验证对象的首地址为 isa**

```objective-c
Class object_getClass(id obj)
{
    if (obj) return obj->getIsa();
    else return Nil;
}

inline Class 
objc_object::getIsa() 
{
    return ISA();
}

inline Class 
objc_object::ISA() 
{
    ASSERT(!isTaggedPointer()); 
#if SUPPORT_INDEXED_ISA
    if (isa.nonpointer) {
        uintptr_t slot = isa.indexcls;
        return classForIndex((unsigned)slot);
    }
    return (Class)isa.bits;
#else
    return (Class)(isa.bits & ISA_MASK);
#endif
}
```

通过`object_getClass`方法流程，以及断点追踪，如下：

```ruby
// 打印创建的 isa
(lldb)p newisa
(isa_t) $4 = {
  cls = Person
  bits = 8303516107940105
   = {
    nonpointer = 1
    has_assoc = 0
    has_cxx_dtor = 0
    shiftcls = 536871969
    magic = 59
    weakly_referenced = 0
    deallocating = 0
    has_sidetable_rc = 0
    extra_rc = 0
  }
}

// 根据`object_getClass`实现原理
(lldb) p/x 8303516107940105 & 0x00007ffffffffff8ULL
(unsigned long long) $21 = 0x0000000100002108

// 打印 person 实例对象的首地址
(lldb) x/4gx person
0x100726c80: 0x001d800100002109 0x0000000000000000
0x100726c90: 0x70736e494b575b2d 0x574b57726f746365

(lldb) p/x 0x001d800100002109 & 0x00007ffffffffff8ULL
(unsigned long long) $22 = 0x0000000100002108

// 打印类信息
(lldb) p/x Person.class
(Class) $23 = 0x0000000100002108 Person

// $21、$22、$23 是相同的地址
```

我们可以得出：**实例对象的首地址一定是 `isa`，并且`shiftcls`是存储类的指针**

### isa走位

我们已经知道，类和实例对象中都包含了一个 objc_class类型的 isa，并且首地址一定是 isa。

当对象的**实例方法**被调用的时候，会通过 isa 找到相应的类，再去查找方法。

那调用**类方法**的时候，类的 isa 又是怎么操作的呢？

其实，苹果在这里为了和对象查找方法的机制一致，于是引入了`元类(meta-class)`的概念

> 关于元类，更多具体可以研究这篇文章[What is a meta-class in Objective-C?](http://www.cocoawithlove.com/2010/01/what-is-meta-class-in-objective-c.html)

在引入元类之后，类对象和对象查找方法的机制就完全统一了

- 对象的实例方法调用时，通过对象的 isa 在类中获取方法的实现
- 类对象的类方法调用时，通过类的 isa 在元类中获取方法的实现

**打印类/对象查看isa走向**

![image-20200914134107532](https://w-md.imzsy.design/image-20200914134107532.png)

1. 打印 Person 类，取得 isa
2. Person 类的 isa 进行偏移得到 Person 元类，打印 Person 元类取得 isa
3. Person 元类的 isa 进行偏移得到 NSObject 根元类，打印 NSObject 根元类取得 isa
4. NSObject 根元类的 isa 进行偏移得到 NSObject 根元类本身
5. 打印 NSObject 根类，取得 isa
6. NSObject 根类的 isa 进行偏移得到 NSObject 根元类

**isa走向结论：**

- `实例对象 -> 类对象 -> 元类 -> 根元类 -> 根元类(本身)`
- `NSObject(根类) -> 根元类 -> 根元类(本身)`

对象、类、元类之间的关系，如下图：

![isa流程图](https://w-md.imzsy.design/isa流程图.png)

图中实线是 super_class指针，虚线是isa指针

- Root class(class)其实就是 NSObject，NSObject是没有超类的，所以Root class(class)的superclass指向nil
- 每个Class都有一个isa指针指向唯一的Meta class
- Root class(meta)的superclass指向Root class(class)，也就是NSObject，形成一个回路
- 每个Meta class的isa指针都指向Root class (meta)

那么，类在内存中是不是会存在很多份呢？

**类在内存中只会存在一份**

```objective-c
void validClass() {
    Class class1 = [Person class];
    Class class2 = [Person alloc].class;
    Class class3 = object_getClass([Person alloc]);
    NSLog(@"\n%p\n%p\n%p\n",class1,class2,class3);
}
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        validClass();
    }
    return 0;
}
// 输出
0x100002110
0x100002110
0x100002110
```

输出证明`类在内存中只会存在一个，而实例对象可以存在多个`

### 测试

下面代码输出是什么？

**代码一**

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
    }
return self;
}
@end
```

**代码二**

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
  }
  return 0;
}
```

**代码三**

```objc
@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
- (void)speak;
@end
@implementation Sark
- (void)speak {                            
   NSLog(@"my name's %@", self.name);
}
@end
  
@implementation ViewController
- (void)viewDidLoad {  
   [super viewDidLoad];
  
   id cls = [Sark class];
   void *obj = &cls;
   [(__bridge id)obj speak];
}
@end
```



> 参考文章：
>
> [神经病院Objective-C Runtime 入院第一天—— isa 和Class](https://halfrost.com/objc_runtime_isa_class/)   