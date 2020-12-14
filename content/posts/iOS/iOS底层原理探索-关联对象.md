---
title: "iOS底层原理探索-关联对象"
date: 2020-10-20T14:35:29+08:00
draft: false
tags: ["iOS"]
url:  "runtime"
---

> 分类有一个局限：无法添加实例变量，但是可以通过关联对象的形式去实现

本文将对关联对象进行解析，包括两方面的内容：

- 使用关联对象为已经存在的类添加属性
- 关联对象在底层的实现

### 属性

当我们在类中声明一个属性时，编译器会自动帮我们生成**实例变量**和 `setter、getter` 方法

当存在非常多的属性时，编译器的工作量岂不是非常大，显然不是这样的

苹果在底层采用**通用原则**的设计模式，为所有的属性提供了同一个入口

- `setter`方法根据修饰符不同调用不同方法，但是最后都会调用`reallySetProperty``
- `getter`方法会调用`objc_getProperty`

`reallySetProperty`实现，在内部是通过`self+内存偏移量`得到`slot`，并根据不同的修饰符将 `newValue`赋值给 `slot`

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

`objc_getProperty`实现，根据`self+内存偏移量`得到`slot`——即`value`，并将 `value` 返回

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

至于哪里调用`reallySetProperty`

通过堆栈可以发现`objc_setProperty_nonatomic_copy`会调用，此时的修饰符为`nonatomic，copy`

而`objc_setProperty_nonatomic_copy`调用则是在`llvm`中

```c++
// 声明
llvm::FunctionCallee GetOptimizedPropertySetFunction(bool atomic,
                                                     bool copy) override {
  return ObjCTypes.getOptimizedSetPropertyFn(atomic, copy);
}

llvm::FunctionCallee getOptimizedSetPropertyFn(bool atomic, bool copy) {
  CodeGen::CodeGenTypes &Types = CGM.getTypes();
  ASTContext &Ctx = CGM.getContext();
  
  SmallVector<CanQualType,4> Params;
  CanQualType IdType = Ctx.getCanonicalParamType(Ctx.getObjCIdType());
  CanQualType SelType = Ctx.getCanonicalParamType(Ctx.getObjCSelType());
  Params.push_back(IdType);
  Params.push_back(SelType);
  Params.push_back(IdType);
  Params.push_back(Ctx.getPointerDiffType()->getCanonicalTypeUnqualified());
  llvm::FunctionType *FTy =
      Types.GetFunctionType(
        Types.arrangeBuiltinFunctionDeclaration(Ctx.VoidTy, Params));
  const char *name;
  if (atomic && copy)
    name = "objc_setProperty_atomic_copy";
  else if (atomic && !copy)
    name = "objc_setProperty_atomic";
  else if (!atomic && copy)
    name = "objc_setProperty_nonatomic_copy";
  else
    name = "objc_setProperty_nonatomic";

  return CGM.CreateRuntimeFunction(FTy, name);
}

// 调用
llvm::FunctionCallee setOptimizedPropertyFn = nullptr;
llvm::FunctionCallee setPropertyFn = nullptr;
if (UseOptimizedSetter(CGM)) {
  // 10.8 and iOS 6.0 code and GC is off
  setOptimizedPropertyFn =
      CGM.getObjCRuntime().GetOptimizedPropertySetFunction(
          strategy.isAtomic(), strategy.isCopy());
  if (!setOptimizedPropertyFn) {
    CGM.ErrorUnsupported(propImpl, "Obj-C optimized setter - NYI");
    return;
  }
}
else {
  setPropertyFn = CGM.getObjCRuntime().GetPropertySetFunction();
  if (!setPropertyFn) {
    CGM.ErrorUnsupported(propImpl, "Obj-C setter requiring atomic copy");
    return;
  }
}
```

### 关联对象的应用

**关联对象的使用**相信已经成为每个 iOS 开发者必备的技能，但是这里还是需要对其介绍

#### @property

`@property`可以说是一个 Objective-C 编程中的『宏』，它有[元编程](https://zh.wikipedia.org/zh/%E5%85%83%E7%BC%96%E7%A8%8B)的思想

```objective-c
@interface Person : NSObject

@property (nonatomic, strong) NSString *name;

@end
```

在类中声明一个`name`属性时，编译器会自动帮我们做三件事：

- 生成实例变量`_name`
- 生成 `getter` 方法 `- (NSString *)name`
- 生成 `setter` 方法 `- (void)setName:`

既然在类中使用`@property`声明一个属性，那么在分类中为什么不可以

```objective-c
@interface NSObject (Test)

@property (nonatomic, strong) NSString *test_name;

@end
 
@implementation NSObject (Test)

@end
```

编译，就报这样的警告：`test_name`属性的存取方法需要手动去实现，或者使用`@dynamic`在运行时实现这些方法

```
Property 'test_name' requires method 'setTest_name:' to be defined - use @dynamic or provide a method implementation in this category

Property 'test_name' requires method 'test_name' to be defined - use @dynamic or provide a method implementation in this category
```

这也意味着，分类中的`@property`并没有自动生成实例变量以及存取方法，而需要手动实现

#### 使用关联对象

下面是通过 Objc运行时提供的关联对象 API 在分类中实现一个伪属性

```objective-c
#import "NSObject+Test.h"
#import <objc/runtime.h>

@implementation NSObject (Test)

- (void)setTest_name:(NSString *)test_name {
    objc_setAssociatedObject(self, @selector(test_name), test_name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)test_name {
    return objc_getAssociatedObject(self, _cmd);
}

@end
```

> 这里的`_cmd`指代当前方法的选择子，也就是`@seletor(test_name)`

使用`objc_getAssociatedObject`和`objc_setAssociatedObject`来模拟『属性』的存取方法，而使用关联对象模拟实例变量

解释两个问题：

- 为什么向方法中传入`@selector(test_name)`
- `OBJC_ASSOCIATION_RETAIN_NONATOMIC`是干什么的

关于第一个问题，先看一下这两个方法的原型

```c++
OBJC_EXPORT void
objc_setAssociatedObject(id _Nonnull object, const void * _Nonnull key,
                         id _Nullable value, objc_AssociationPolicy policy)
    OBJC_AVAILABLE(10.6, 3.1, 9.0, 1.0, 2.0);

OBJC_EXPORT id _Nullable
objc_getAssociatedObject(id _Nonnull object, const void * _Nonnull key)
    OBJC_AVAILABLE(10.6, 3.1, 9.0, 1.0, 2.0);
```

`@selector(test_name)`也就是参数中的`key`，其实可以使用静态指针`static void *`类型的参数来代替

> 这里推荐使用`@selector(test_name)`作为 `key`传入，因为这种方式省略了声明参数的代码，并且能很好地保护 `key` 的唯一性

`OBJC_ASSOCIATION_RETAIN_NONATOMIC`是什么呢？来看一下它的定义

```c++
typedef OBJC_ENUM(uintptr_t, objc_AssociationPolicy) {
    OBJC_ASSOCIATION_ASSIGN = 0,           /**< Specifies a weak reference to the associated object. */
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1, /**< Specifies a strong reference to the associated object. 
                                            *   The association is not made atomically. */
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3,   /**< Specifies that the associated object is copied. 
                                            *   The association is not made atomically. */
    OBJC_ASSOCIATION_RETAIN = 01401,       /**< Specifies a strong reference to the associated object.
                                            *   The association is made atomically. */
    OBJC_ASSOCIATION_COPY = 01403          /**< Specifies that the associated object is copied.
                                            *   The association is made atomically. */
};
```

从定义的注释中，不难看出：不同的`objc_AssociationPolicy`对应了不同的属性修饰符策略

| objc_AssociationPolicy            | modifier          |
| --------------------------------- | ----------------- |
| OBJC_ASSOCIATION_ASSIGN           | assign            |
| OBJC_ASSOCIATION_RETAIN_NONATOMIC | nonatomic, strong |
| OBJC_ASSOCIATION_COPY_NONATOMIC   | nonatomic, copy   |
| OBJC_ASSOCIATION_RETAIN           | atomic, strong    |
| OBJC_ASSOCIATION_COPY             | atomic, copy      |

我们在代码中实现的属性`test_name`就相当于使用了修饰符 `nonatomic` 和 `strong`

#### 总结

`@property`其实有元编程的思想，它能够自动生成**实例变量以及存取方法**，而这三者构成属性这类似于语法糖的概念，提供了更便利的**点语法**来访问属性：

```
self.property <=> [self property]
self.property = value <=> [self setProperty:value]
```

在分类中，因为类的示例变量的布局已经固定，使用`@property`**无法向固定的布局中添加新的实例变量**

因此，我们需要**使用关联对象以及两个方法来模拟构成属性的三个要素**

### 关联对象的底层实现

在运行时提供关联对象的 API 有以下：

- **objc_setAssociatedObject**：使用给定的键和关联策略为给定的对象设置关联的值

- **objc_getAssociatedObject**：返回与给定键的给定对象关联的值
- **objc_removeAssociatedObjects**：删除给定对象的所有关联

#### objc_setAssociatedObject

```c++
void
objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy)
{
    SetAssocHook.get()(object, key, value, policy);
}
```

从源码中可以看出：采用**接口模式**的设计模式，起到对外的接口保持不变，内部逻辑的变化不影响外部的调用的作用

- `SetAssocHook`是一个封装了函数指针的对象，源码定义为：

  ```c++
  static ChainedHookFunction<objc_hook_setAssociatedObject> SetAssocHook{_base_objc_setAssociatedObject};
  ```

- `ChainedHookFunction`是用于线程安全的链式钩子函数的存储

  - 通过 `get()` 返回调用的值
  - 通过 `set()` 注入一个新函数，并返回旧函数，确切地说，`set()`将旧值写入调用方提供的变量
  - `get()` 和 `set()`使用适当的栅栏使得在新值调用前安全地写入变量

  ```c++
  template <typename Fn>
  class ChainedHookFunction {
      std::atomic<Fn> hook{nil};
  
  public:
      ChainedHookFunction(Fn f) : hook{f} { };
  
      Fn get() {
          return hook.load(std::memory_order_acquire);
      }
  
      void set(Fn newValue, Fn *oldVariable)
      {
          Fn oldValue = hook.load(std::memory_order_relaxed);
          do {
              *oldVariable = oldValue;
          } while (!hook.compare_exchange_weak(oldValue, newValue,
                                               std::memory_order_release,
                                               std::memory_order_relaxed));
      }
  };
  ```

因此，`SetAssocHook.get()`返回的是传入的函数指针`_base_objc_setAssociatedObject`

```c++
SetAssocHook.get()(object, key, value, policy) <==> base_objc_setAssociatedObject(object, key, value, policy)
```

底层真正调用的是`_base_objc_setAssociatedObject`

```c++
static void
_base_objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy)
{
  _object_set_associative_reference(object, key, value, policy);
}
```

`_object_set_associative_reference`才是真正实现关联对象存储的函数

```c++
void
_object_set_associative_reference(id object, const void *key, id value, uintptr_t policy)
{
    // This code used to work when nil was passed for object and key. Some code
    // probably relies on that to not crash. Check and handle it explicitly.
    // rdar://problem/44094390
    if (!object && !value) return;

    if (object->getIsa()->forbidsAssociatedObjects())
        _objc_fatal("objc_setAssociatedObject called on instance (%p) of class %s which does not allow associated objects", object, object_getClassName(object));
    //object封装成一个数组结构类型，类型为DisguisedPtr
    DisguisedPtr<objc_object> disguised{(objc_object *)object};//相当于包装了一下 对象object,便于使用
    // 包装一下 policy - value
    ObjcAssociation association{policy, value};

    // retain the new value (if any) outside the lock.
    association.acquireValue();//根据策略类型进行处理
    //局部作用域空间
    {
        //初始化manager变量，相当于自动调用AssociationsManager的析构函数进行初始化
        AssociationsManager manager;//并不是全场唯一，构造函数中加锁只是为了避免重复创建，在这里是可以初始化多个AssociationsManager变量的
    
        AssociationsHashMap &associations(manager.get());//AssociationsHashMap 全场唯一

        if (value) {
            auto refs_result = associations.try_emplace(disguised, ObjectAssociationMap{});//返回的结果是一个类对
            if (refs_result.second) {//判断第二个存不存在，即bool值是否为true
                /* it's the first association we make 第一次建立关联*/
                object->setHasAssociatedObjects();//nonpointerIsa ，标记位true
            }

            /* establish or replace the association 建立或者替换关联*/
            auto &refs = refs_result.first->second; //得到一个空的桶子，找到引用对象类型,即第一个元素的second值
            auto result = refs.try_emplace(key, std::move(association));//查找当前的key是否有association关联对象
            if (!result.second) {//如果结果不存在
                association.swap(result.first->second);
            }
        } else {//如果传的是空值，则移除关联，相当于移除
            auto refs_it = associations.find(disguised);
            if (refs_it != associations.end()) {
                auto &refs = refs_it->second;
                auto it = refs.find(key);
                if (it != refs.end()) {
                    association.swap(it->second);
                    refs.erase(it);
                    if (refs.size() == 0) {
                        associations.erase(refs_it);

                    }
                }
            }
        }
    }

    // release the old value (outside of the lock).
    association.releaseHeldValue();//释放
}
```

首先，注意其中的几个类和数据结构，因为在具体分析这个方法的实现之前，需要了解其中它们的作用：

- **AssociationsManager**

  ```c++
  class AssociationsManager {
      using Storage = ExplicitInitDenseMap<DisguisedPtr<objc_object>, ObjectAssociationMap>;
      static Storage _mapStorage;
  
  public:
      AssociationsManager()   { AssociationsManagerLock.lock(); }
      ~AssociationsManager()  { AssociationsManagerLock.unlock(); }
  
      AssociationsHashMap &get() {
          return _mapStorage.get();
      }
  
      static void init() {
          _mapStorage.init();
      }
  };
  ```

  这是一个管理类，维护着`spinlock_t`和`AssociationsManager`单例，调用构造函数初始化时，会加锁，在析构时会解锁，而 `get`方法用于获取全局的`AssociationsManager`单例

  也就是说 `AssociationsManager` 通过持有一个[自旋锁](https://en.wikipedia.org/wiki/Spinlock) `spinlock_t` 保证对 `AssociationsHashMap` 的操作是线程安全的，即**每次只会有一个线程对 AssociationsHashMap 进行操作**

- **AssociationsHashMap**

  ```c++
  typedef DenseMap<DisguisedPtr<objc_object>, ObjectAssociationMap> AssociationsHashMap;
  
  template <typename T>
  class DisguisedPtr {
      uintptr_t value;
  
      static uintptr_t disguise(T* ptr) {
          return -(uintptr_t)ptr;
      }
    	// ...
  }
  ```

  `DisguisedPtr<T>`是指针伪装模板类，通过运算使指针隐藏于系统工具(如`leaks`工具)，同时保持指针的能力，其作用是通过计算把保存的 `T` 类型的指针隐藏起来，实现指针到整数的映射

  `DisguisedPtr<objc_object>`就是将 `objc_object`类型的指针进行**位运算**「伪装」作为`key`，

  `AssociationsHashMap`用于存储`DisguisedPtr<objc_object>`到`ObjectAssociationMap`的映射

- **ObjectAssociationMap**

  ```c++
  typedef DenseMap<const void *, ObjcAssociation> ObjectAssociationMap;
  ```

  `ObjectAssociationMap`用于存储`const void *`到`ObjcAssociation`的映射

- **ObjcAssociation**

  ```c++
  class ObjcAssociation {
      uintptr_t _policy;
      id _value;
  public:
      ObjcAssociation(uintptr_t policy, id value) : _policy(policy), _value(value) {}
      // ...
  }
  ```

  `ObjcAssociation` 就是真正的关联对象的类，上面的所有数据结构只是为了更好的存储它

**存储**

这里举一个简单列子，说明关联对象在内存中以什么形式存储

```objective-c
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        Person *obj = [Person new];
        objc_setAssociatedObject(obj, @selector(hello), @"Hello", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return 0;
}
```

这里的关联对象 `ObjcAssociation(OBJC_ASSOCIATION_RETAIN_NONATOMIC, @"Hello")`在内存是这样存储的：

![image-20201211153708852](https://w-md.imzsy.design/image-20201211153708852.png)

现在来对`_object_set_associative_reference`进行分析

1. `ObjcAssociation association{policy, value}`创建临时的`ObjcAssociation`对象（用于持有原有的关联对象，方便在方法调用的最后释放值）

2. 调用`acquireValue`对`new_value`进行 `retain` 或 `copy`

   ```c++
   inline void acquireValue() {
       if (_value) {
           switch (_policy & 0xFF) {
           case OBJC_ASSOCIATION_SETTER_RETAIN:
               _value = objc_retain(_value);
               break;
           case OBJC_ASSOCIATION_SETTER_COPY:
               _value = ((id(*)(id, SEL))objc_msgSend)(_value, @selector(copy));
               break;
           }
       }
   }
   ```

3. 初始化一个`AssociationsManager`，并获取唯一的保存关联对象的哈希表`AssociationsHashMap`

4. 先使用 `disguised` 作为 `key`，寻找对应的`ObjectAssociationMap`，并会传入一个空的`ObjectAssociationMap`

   ```c++
   auto refs_result = associations.try_emplace(disguised, ObjectAssociationMap{});
   ```

   - 如果找到，会将找到的`ObjectAssociationMap`进行装配为类对，返回值的 `second = flase`
   - 如果没有找到，将 `disguised` 作为 `key`，传入的空`ObjectAssociationMap`做为值，插入到`AssociationsHashMap`，并装配为类对，返回值的 `second = true`

5. 如果返回的`refs_result.second`为`true`，会调用`setHasAssociatedObjects`——对于`nonpointerIsa`更新`isa`的`has_assoc`为`true`，表明当前对象含有**关联对象**

   ```c++
   inline void
   objc_object::setHasAssociatedObjects()
   {
       if (isTaggedPointer()) return;
   
    retry:
       isa_t oldisa = LoadExclusive(&isa.bits);
       isa_t newisa = oldisa;
       if (!newisa.nonpointer  ||  newisa.has_assoc) {
           ClearExclusive(&isa.bits);
           return;
       }
       newisa.has_assoc = true;
       if (!StoreExclusive(&isa.bits, oldisa.bits, newisa.bits)) goto retry;
   }
   ```

6. 再根据传入的`key`，寻找相应的`ObjectAssociation`，并将临时的`ObjcAssociation`对象传入

   ```c++
   auto &refs = refs_result.first->second; // 相当于获取ObjectAssociationMap
   auto result = refs.try_emplace(key, std::move(association)); // 查找ObjectAssociation
   ```

   这里和上面查找`ObjectAssociationMap`类似

   - 如果找到，则返回的类对`second`为`true`，需要将进行替换`association.swap(result.first->second)`
   - 如果没有找到，则会将`ObjcAssociation`插入到`ObjectAssociationMap`中

7. 最后调用`releaseHeldValue`，将释放关联对象的值

   ```c++
   inline void releaseHeldValue() {
       if (_value && (_policy & OBJC_ASSOCIATION_SETTER_RETAIN)) {
           objc_release(_value);
       }
   }
   ```

到这里，传入 `value` 有值的实现就结束了

**value==nil**

如果传入的 `value == nil`，就说明需要删除对应 `key` 的关联对象，也就是走 `else` 流程

```c++
auto refs_it = associations.find(disguised); // 获取ObjectAssociationMap
if (refs_it != associations.end()) {
    auto &refs = refs_it->second;
    auto it = refs.find(key); // 获取ObjectAssociation
    if (it != refs.end()) {
        association.swap(it->second);
        refs.erase(it); // 擦除ObjectAssociation
        if (refs.size() == 0) { // ObjectAssociationMap为空
            associations.erase(refs_it); // 擦除ObjectAssociationMapc

        }
    }
}
```

该流程中，与前面的唯一不同的就是，需要调用 `erase` 函数，擦除 `ObjectAssociationMap` 中 `key` 对应的节点，如果`ObjectAssociationMap`为空了，还需要从将其从 `AssociationHashMap` 中擦除

#### objc_getAssociatedObject

既然已经对`objc_setAssociatedObject`的实现比较熟悉了，那么对于`objc_getAssociatedObject`就比较容易理解了

`objc_setAssociatedObject`方法的底层真正实现是`_object_get_associative_reference`

```c++
id
objc_getAssociatedObject(id object, const void *key)
{
    return _object_get_associative_reference(object, key);
}
```

而`_object_get_associative_reference`相对来说，实现更简单一点

```c++
id
_object_get_associative_reference(id object, const void *key)
{
    ObjcAssociation association{};//创建空的关联对象

    {
        AssociationsManager manager;//创建一个AssociationsManager管理类
        AssociationsHashMap &associations(manager.get());//获取全局唯一的静态哈希map
        AssociationsHashMap::iterator i = associations.find((objc_object *)object);//找到迭代器，即获取buckets
        if (i != associations.end()) {//如果这个迭代查询器不是最后一个 获取
            ObjectAssociationMap &refs = i->second; //找到ObjectAssociationMap的迭代查询器获取一个经过属性修饰符修饰的value
            ObjectAssociationMap::iterator j = refs.find(key);//根据key查找ObjectAssociationMap，即获取bucket
            if (j != refs.end()) {
                association = j->second;//获取ObjcAssociation
                association.retainReturnedValue();
            }
        }
    }

    return association.autoreleaseReturnedValue();//返回value
}
```

**寻找关联对象的逻辑**

- 创建空的关联对象，`AssociationsManager`管理类

- 获取静态哈希表 `AssociationsHashMap`

- 以`object`为`key`查找`ObjectAssociationMap`

- 以`void *key`为`key`查找`ObjectAssociation`

- 再找到`ObjectAssociation`后，调用`retainReturnedValue`，根据`policy`是否需要`retain`

  ```c++
  inline void retainReturnedValue() {
      if (_value && (_policy & OBJC_ASSOCIATION_GETTER_RETAIN)) {
          objc_retain(_value);
      }
  }
  ```

- 最后返回关联对象的值，会调用一次`autoreleaseReturnedValue`，根据`policy`是否需要`autorelease`

  ```c++
  inline id autoreleaseReturnedValue() {
      if (slowpath(_value && (_policy & OBJC_ASSOCIATION_GETTER_AUTORELEASE))) {
          return objc_autorelease(_value);
      }
      return _value;
  }
  ```

#### objc_removeAssociatedObjects

关于`objc_removeAssociatedObjects`方法，其实现也相对简单

为了加速移除对象的关联对象的速度，我们会通过标记位 `has_assoc` 来避免不必要的方法调用

在确认了对象和关联对象的存在之后，才会调用 `_object_remove_assocations` 方法移除对象上所有的关联对象：

```c++
void objc_removeAssociatedObjects(id object) 
{
    if (object && object->hasAssociatedObjects()) {
        _object_remove_assocations(object);
    }
}
```

`_object_remove_assocations`实现也比较简单

- 将对象包含的所有关联对象加入到一个迭代器中
- 然后对所有的`ObjcAssociation`调用`releaseHeldValue`方法，`release`释放不需要的值

```c++
void
_object_remove_assocations(id object)
{
    ObjectAssociationMap refs{};//创建空的关联对象集合

    {
        AssociationsManager manager;//创建一个AssociationsManager管理类
        AssociationsHashMap &associations(manager.get());//获取全局唯一的静态哈希map
        AssociationsHashMap::iterator i = associations.find((objc_object *)object);//找到迭代器，即获取buckets
        if (i != associations.end()) {//如果这个迭代查询器不是最后一个 获取
            refs.swap(i->second);//获取ObjcAssociation
            associations.erase(i);//删除
        }
    }

    // release everything (outside of the lock).
    for (auto &i: refs) {
        i.second.releaseHeldValue();
    }
}
```

### 总结

**对于应用**

> 分类中对属性的实现其实只是实现了一个看起来像属性的接口而已

分类中手动实现 `setter、getter`，通常需要借助**关联对象**

**对于实现**

关联对象是怎么实现并且管理的：

- 关联对象本质是 `ObjectAssociation` 对象
- 关联对象由 `AssociationsManager` 管理并在 `AssociationsHashMap` 存储
- 对象的指针以及其对应 `ObjectAssociationMap` 以键值对的形式存储在 `AssociationsHashMap` 中
- `ObjectAssociationMap` 则是用于存储关联对象的数据结构
- 对于`nonpointerIsa`, 每一个对象都有一个标记位 `has_assoc` 指示对象是否含有关联对象

整个结构图为：

![关联对象数据结构](https://w-md.imzsy.design/关联对象数据结构.png)