---
title: "iOS底层原理探索-类的结构分析"
date: 2020-09-14T16:28:45+08:00
draft: false
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
  	
    class_rw_t *data() const {
        return bits.data();
    }
    ...
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

从 `objc_class` 中定义，结构体有 4 个成员变量：`isa、superclass、cache、bits`

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

> 关于 `cache_t`会在后续进行详细展开说明

**class_data_bits_t bits**

`class_data_bits_t`的定义

```objective-c
struct class_data_bits_t {
    friend objc_class;
  
    // Values are the FAST_ flags above.
    uintptr_t bits;
private:
  bool getBit(uintptr_t bit) const
  {
      return bits & bit;
  }
  ...
public:

  class_rw_t* data() const {
      return (class_rw_t *)(bits & FAST_DATA_MASK);
  }
  ...
}
```

`class_rw_t`的定义

```objective-c
struct class_rw_t {
    // Be warned that Symbolication knows the layout of this structure.
    uint32_t flags;
    uint16_t witness;
#if SUPPORT_INDEXED_ISA
    uint16_t index;
#endif

    explicit_atomic<uintptr_t> ro_or_rw_ext;

    Class firstSubclass;
    Class nextSiblingClass;

private:
    using ro_or_rw_ext_t = objc::PointerUnion<const class_ro_t *, class_rw_ext_t *>;
}
```

`class_rw_ext_t`的定义

```objective-c
struct class_rw_ext_t {
    const class_ro_t *ro;
    method_array_t methods;
    property_array_t properties;
    protocol_array_t protocols;
    char *demangledName;
    uint32_t version;
};
```

`class_ro_t`的定义

```objective-c
struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif

    const uint8_t * ivarLayout;
    
    const char * name;
    method_list_t * baseMethodList;
    protocol_list_t * baseProtocols;
    const ivar_list_t * ivars;

    const uint8_t * weakIvarLayout;
    property_list_t *baseProperties;
}
```

![image-20200916164750486](https://w-md.imzsy.design/image-20200916164750486.png)

在 objc_class 结构体中的注释写到 `class_data_bits_t`相当于 `class_rw_t`指针加上 `rr/alloc` 的标志。

同时，也向外面提供了便捷方法用于返回其中的 `class_rw_t *` 指针

```objective-c
class_rw_t *data() const {
    return bits.data();
}
```

### 类的属性、方法、协议

Objc 类的属性、方法、以及遵循的协议都放在 class_rw_t 中，class_ro_t是一个指向常量的指针，存储由编译器决定的属性、方法和遵守的协议。`rw-readwrite, ro-readonly`

**在编译期**

类的结构中的 `class_data_bits_t *data` 指向的是一个 `class_ro_t *`指针

**在运行时**

调用 `realizeClassWithoutSwift` 方法，会做一下 3 件事情：

1.  从`class_data_bits_t`调用 data 方法，将结果从 `class_rw_t` 强制转换为 `class_ro_t` 指针
2.  初始化一个 class_rw_t 结构体
3.  设置结构体 ro 的值以及 flag

最后，调用 methodizeClass 方法，将类中的属性、协议、方法都加载进来。

#### 查看属性、方法的分布

```objective-c
@interface Person : NSObject
{
    NSString *nickName;
}
@property (nonatomic, copy) NSString *name;

+ (void)walk;
- (void)run;
@end

@implementation Person
+ (void)walk {};
- (void)run {};
@end
```

上面我们已经知道了，`isa`与`bits`的内存偏移为 32 位，即`bits`的地址是`类的内存首地址`+`isa、superclass、cache 的内存长度`

```ruby
(lldb) p/x Person.class
(Class) $1 = 0x0000000100003228 Person
(lldb) p (class_data_bits_t *)0x0000000100003248
(class_data_bits_t *) $2 = 0x0000000100003248
```

根据`data()`方法，获取 `class_rw_t`

```ruby
(lldb) p $2->data()
(class_rw_t *) $4 = 0x0000000101c46110
(lldb) p *$4
(class_rw_t) $5 = {
  flags = 2148007936
  witness = 1
  ro_or_rw_ext = {
    std::__1::atomic<unsigned long> = 4294979784
  }
  firstSubclass = nil
  nextSiblingClass = NSUUID
}
```

> 781 的源码和之前的源码不太一样，这里并不能直接读取到 methods、properties、protocols

**类的属性**

```ruby
(lldb) p $5.properties()
(const property_array_t) $13 = {
  list_array_tt<property_t, property_list_t> = {
     = {
      list = 0x00000001000031c0
      arrayAndFlag = 4294980032
    }
  }
}
(lldb) p $13.list
(property_list_t *const) $14 = 0x00000001000031c0
(lldb) p *$14
(property_list_t) $15 = {
  entsize_list_tt<property_t, property_list_t, 0> = {
    entsizeAndFlags = 16
    count = 1
    first = (name = "name", attributes = "T@\"NSString\",C,N,V_name")
  }
}

(lldb) p $15.get(0)
(property_t) $16 = (name = "name", attributes = "T@\"NSString\",C,N,V_name")
```

通过上面的方式，就可以拿到所想要 `property_t` 属性列表，其中 count 是指总共的属性数量。

之前，分析了成员变量存储在 `class_ro_t` 中，我们也来打印一下看看

```ruby
(lldb) p $5.ro()
(const class_ro_t *) $18 = 0x00000001000030c8
(lldb) p *$18
(const class_ro_t) $19 = {
  flags = 388
  instanceStart = 8
  instanceSize = 24
  reserved = 0
  ivarLayout = 0x0000000100001e6f "\x02"
  name = 0x0000000100001e68 "Person"
  baseMethodList = 0x0000000100003110
  baseProtocols = 0x0000000000000000
  ivars = 0x0000000100003178
  weakIvarLayout = 0x0000000000000000
  baseProperties = 0x00000001000031c0
  _swiftMetadataInitializer_NEVER_USE = {}
}
```

接着，打印 `ivars`

```ruby
(lldb) p $19.ivars
(const ivar_list_t *const) $20 = 0x0000000100003178
(lldb) p *$20
(const ivar_list_t) $21 = {
  entsize_list_tt<ivar_t, ivar_list_t, 0> = {
    entsizeAndFlags = 32
    count = 2
    first = {
      offset = 0x00000001000031f0
      name = 0x0000000100001e76 "nickName"
      type = 0x0000000100001ebe "@\"NSString\""
      alignment_raw = 3
      size = 8
    }
  }
}
```

同样的，输出每一个`ivar_list`的每一个元素

```ruby
(lldb) p $21.get(0)
(ivar_t) $22 = {
  offset = 0x00000001000031f0
  name = 0x0000000100001e76 "nickName"
  type = 0x0000000100001ebe "@\"NSString\""
  alignment_raw = 3
  size = 8
}
(lldb) p $21.get(1)
(ivar_t) $23 = {
  offset = 0x00000001000031f8
  name = 0x0000000100001e7f "_name"
  type = 0x0000000100001ebe "@\"NSString\""
  alignment_raw = 3
  size = 8
}
```

除了成员变量 nickName 之外，编译器会在底层自动将属性生成一个成员变量（前缀_+属性名）

**类的方法**

查看源码，关于 `class_rw_t` 部分，知道通过`methods()、properties()、protocols()`分别获取方法、属性、协议

```ruby
(lldb) p $5.methods()
(const method_array_t) $6 = {
  list_array_tt<method_t, method_list_t> = {
     = {
      list = 0x0000000100003110
      arrayAndFlag = 4294979856
    }
  }
}

(lldb) p $6.list
(method_list_t *const) $7 = 0x0000000100003110
(lldb) p $7
(method_list_t *const) $7 = 0x0000000100003110
(lldb) p *$7
(method_list_t) $8 = {
  entsize_list_tt<method_t, method_list_t, 3> = {
    entsizeAndFlags = 26
    count = 4
    first = {
      name = ".cxx_destruct"
      types = 0x0000000100001eb6 "v16@0:8"
      imp = 0x0000000100001970 (ObjcTest`-[Person .cxx_destruct] at main.m:29)
    }
  }
}
```

通过上面的方式，就可以拿到所想要 `method_list` 方法列表，其中 count 是指总共的方法数量，分别打印一下

```ruby
(lldb) p $8.get(0)
(method_t) $9 = {
  name = ".cxx_destruct"
  types = 0x0000000100001eb6 "v16@0:8"
  imp = 0x0000000100001970 (ObjcTest`-[Person .cxx_destruct] at main.m:29)
}
(lldb) p $8.get(1)
(method_t) $10 = {
  name = "name"
  types = 0x0000000100001eca "@16@0:8"
  imp = 0x0000000100001910 (ObjcTest`-[Person name] at main.m:16)
}
(lldb) p $8.get(2)
(method_t) $11 = {
  name = "setName:"
  types = 0x0000000100001ed2 "v24@0:8@16"
  imp = 0x0000000100001940 (ObjcTest`-[Person setName:] at main.m:16)
}
(lldb) p $8.get(3)
(method_t) $12 = {
  name = "run"
  types = 0x0000000100001eb6 "v16@0:8"
  imp = 0x0000000100001900 (ObjcTest`-[Person run] at main.m:31)
}
```

方法`method_t`的定义

```objectivec
struct method_t {
    SEL name;
    const char *types;
    IMP imp;

    struct SortBySELAddress :
        public std::binary_function<const method_t&,
                                    const method_t&, bool>
    {
        bool operator() (const method_t& lhs,
                         const method_t& rhs)
        { return lhs.name < rhs.name; }
    };
};
```

里面包含3个成员变量。

- SEL是方法的名字name
- types是Type Encoding类型编码，类型可参考[Type Encoding](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html)，在此不细说
- IMP是一个函数指针，指向的是函数的具体实现

> 在runtime中消息传递和转发的目的就是为了找到IMP，并执行函数

系统在底层会添加 c++的`.cxx_destruct`方法，同时编译器还为属性生成了一个 `setter` 方法和 `getter` 方法，现在会有一个疑问：Person的类方法 walk 去哪里了？

在上面，已经有介绍关于类和元类的概念，那么对于类方法的归属：**`类方法`可以理解成`元类`的`实例方法`**，因此，类方法存储`元类`中

### 总结

- 成员变量存放在`ivar`
- 属性存放在`property`，同时也会存一份在`ivar`，并生成`setter`、`getter`方法
- 实例方法存放在`类`里面`methods`
- 类方法存放在`元类`里面`methods`

> 参考资料：
>
> [深入解析 ObjC 中方法的结构](https://github.com/draveness/analyze/blob/master/contents/objc/%E6%B7%B1%E5%85%A5%E8%A7%A3%E6%9E%90%20ObjC%20%E4%B8%AD%E6%96%B9%E6%B3%95%E7%9A%84%E7%BB%93%E6%9E%84.md#%E6%B7%B1%E5%85%A5%E8%A7%A3%E6%9E%90-objc-%E4%B8%AD%E6%96%B9%E6%B3%95%E7%9A%84%E7%BB%93%E6%9E%84)