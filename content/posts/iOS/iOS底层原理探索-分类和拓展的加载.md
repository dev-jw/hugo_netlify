---
title: "iOS底层原理探索-分类和拓展的加载"
date: 2020-10-16T20:02:39+08:00
draft: false
tags: ["iOS"]
url: "category"
---

上篇文章[iOS底层原理探索-类的加载](/class-load)分析了`类的加载`过程，理解了类是如何从 Mach-O 加载到内存中，但是还没有对`attachCategories`详细展开，而这个函数正是分类的加载的入口

（请先对`类的加载过程`有了一定了解之后再开启本文）

同样的，提出几个问题：

- 分类的本质是什么
- 分类与类的几种搭配加载过程
- 类拓展的加载
- `initalize`的分析

### 分类的本质

为了探索分类的本质，我们需要借助 `clang` 查看分类在底层究竟是什么

创建一个类，以及其分类

```objective-c
@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSNumber *age;

- (void)doFirst;
- (void)doSecond;
@end

@implementation Person
+ (void)load {
}

- (void)doFirst {}
- (void)doSecond {}
@end

@interface Person (Test)

@property (nonatomic, copy) NSString *test_name;
@property (nonatomic, assign) NSString *test_age;

- (void)test_doFirst;
- (void)test_doSecond;
@end

@implementation Person (Test)

- (void)test_doFirst {
    NSLog(@"%s", __func__);
}

- (void)test_doSecond {
    NSLog(@"%s", __func__);
}

@end
```

`clang` 编译，首先可以得出分类是存储在 Mach-O 的 `__DATA` 段的 `__objc_catlist`

```c++
static struct _category_t *L_OBJC_LABEL_CATEGORY_$ [1] __attribute__((used, section ("__DATA, __objc_catlist,regular,no_dead_strip")))= {
	&_OBJC_$_CATEGORY_Person_$_Test,
};
```

然后是 Person 的分类结构为`_category_t`

```c++
static struct _category_t _OBJC_$_CATEGORY_Person_$_Test __attribute__ ((used, section ("__DATA,__objc_const"))) = 
{
	"Person",
	0, // &OBJC_CLASS_$_Person,
	(const struct _method_list_t *)&_OBJC_$_CATEGORY_INSTANCE_METHODS_Person_$_Test,
	0,
	0,
	(const struct _prop_list_t *)&_OBJC_$_PROP_LIST_Person_$_Test,
};
```

再来看一下`_category_t`在底层具体结构为

```c++
struct _category_t {
	const char *name;
	struct _class_t *cls;
	const struct _method_list_t *instance_methods;
	const struct _method_list_t *class_methods;
	const struct _protocol_list_t *protocols;
	const struct _prop_list_t *properties;
};
```

而在objc源码中的结构为

```c++
struct category_t {
    const char *name;
    classref_t cls;
    struct method_list_t *instanceMethods;
    struct method_list_t *classMethods;
    struct protocol_list_t *protocols;
    struct property_list_t *instanceProperties;
    // Fields below this point are not always present on disk.
    struct property_list_t *_classProperties;

    method_list_t *methodsForMeta(bool isMeta) {
        if (isMeta) return classMethods;
        else return instanceMethods;
    }

    property_list_t *propertiesForMeta(bool isMeta, struct header_info *hi);
    
    protocol_list_t *protocolsForMeta(bool isMeta) {
        if (isMeta) return nullptr;
        else return protocols;
    }
};
```

那么，我们也就得出了分类的本质是一个`category_t`的结构体，其内部成员有：

- `name`：类的名字，并不是分类的名字
- `cls`：类对象
- `instanceMethods`：分类上存储的实例方法
- `classMethods`：分类上存储的类方法
- `protocols`：分类上所实现的协议
- `instanceProperties`：分类所定义的实例属性，不会实现`set、get`，因此通常是通过关联对象的方式实现
- `_classProperties`：分类所定义的类属性

> 分类的方法为什么要分为实例方法和类方法存储呢？
>
> 答：因为类和元类在编译期间，已经确定好了内存布局，即实例方法存储在类中，类方法存储在元类中，而分类是在运行时才加入的，所以需要将方法加载到对应的位置

### 分类的加载

前面我们已经分析过**懒加载类**和**非懒加载类**的加载时机并不一样

对于分类，同样有**懒加载分类**和**非懒加载分类**

因此，就出现这样四种组合情况：

- 懒加载类 + 懒加载分类
- 非懒加载类 + 懒加载分类
- 懒加载类 + 非懒加载分类
- 非懒加载类 + 非懒加载分类

**研究各种组合下的分类加载流程**

#### 懒加载类 + 懒加载分类

> 主类、分类都不实现`+load`

**懒加载类的加载时机**是在类第一次发送消息，也就是`lookUpImpOrForward -> realizeClassMaybeSwiftAndLeaveLocked -> realizeClassMaybeSwiftMaybeRelock -> realizeClassWithoutSwift`

在`readClass`加入调试代码，并下断点

![image-20201209150540453](https://w-md.imzsy.design/image-20201209150540453.png)

终端打印 `test_ro` 中的 `baseMethodList`, 可以得到所有的方法，其中也包括分类的

那么，可以得出结论：**懒加载分类**在**编译时**就已经确定了，当**懒加载类**在慢速消息查找流程中通过`realizeClassWithoutSwift`加载，会将 Mach-O 数据的数据段读取到内存，其中包括分类数据

#### 非懒加载类 + 懒加载分类

> 主类实现`+load`，分类不实现

**非懒加载**是在应用启动时刻——PreMain阶段加载的，即 `map_images -> readClass -> realizeClassWithoutSwift`，那么同样只要在`readClass`中打印 `test_ro` 的 `baseMethodList`，打印结果中，同样含有分类的方法

这也说明了，懒加载分类，不管是懒加载类还是懒加载分类，都在编译时就确定了

#### 非懒加载类 + 非懒加载分类

> 主类、分类均实现`+load`

在上一篇文章中提到：在`methodizeClass`中的`attachToClass`方法会去加载分类

通过`attachToClass`源码实现，`attachCategories`便是分类的加载

```c++
void attachToClass(Class cls, Class previously, int flags)
{
    runtimeLock.assertLocked();
    ASSERT((flags & ATTACH_CLASS) ||
           (flags & ATTACH_METACLASS) ||
           (flags & ATTACH_CLASS_AND_METACLASS));

    auto &map = get();
    auto it = map.find(previously);

    if (it != map.end()) {
        category_list &list = it->second;
        if (flags & ATTACH_CLASS_AND_METACLASS) {
            int otherFlags = flags & ~ATTACH_CLASS_AND_METACLASS;
            attachCategories(cls, list.array(), list.count(), otherFlags | ATTACH_CLASS);
            attachCategories(cls->ISA(), list.array(), list.count(), otherFlags | ATTACH_METACLASS);
        } else {
            attachCategories(cls, list.array(), list.count(), flags);
        }
        map.erase(it);
    }
}
```

现在的问题：什么时候`attachCategories`会被调用

通过全局搜索，发现有两个地方会调用`attachCategories`

- `attachToClass`
- `load_categories_nolock`

而根据断点调试，`attachToClass`不会执行到`if`流程，即`attachCategories`不会被调用，除非类加载两次

`load_categories_nolock`又有两次被调用

- `loadAllCategories`
- `_read_images`

同样地，断点调试发现，`_read_images`并不会进入，而`loadAllCategories`又是在`load_images`中被调用的

因此，分类的加载流程为：`load_images -> loadAllCategories -> load_categories_nolock -> attachCategories`

- **非懒加载分类**是在 `load_images` 时加载的
- **懒加载类**是在`map_images`时加载的

#### 懒加载类 + 非懒加载分类

> 主类不实现，分类实现`+load`

同样的，在`realizeClassWithoutSwift`加入调试代码，并下断点

但是，可以发现的是，在类并没有发送第一次消息时，就已经来到断点了

> 那么懒加载类为什么会提前被加载，`realizeClassWithoutSwift`又是在什么时刻被调用的

先在 `readClass` 加入同样的调试代码，并且此时打印 `test_ro`，不能得到分类中的方法

再到`attachCategories`下断点，断点进入时，通过 `bt` 打印函数堆栈：`load_images -> loadAllCategories -> load_categories_nolock -> attachCategories` 

那么也就说明了，**懒加载分类**在当类为**懒加载类**时，会迫使主类提前加载，即懒加载类变为非懒加载类

#### 类和分类加载总结

- 懒加载类 + 懒加载分类
  - 类的加载：第一次发送消息
  - 分类的加载：编译时
- 非懒加载类 + 懒加载分类
  - 类的加载：`_read_images`
  - 分类的加载：编译时
- 非懒加载类 + 非懒加载分类
  - 类的加载：`_read_images`
  - 分类的加载：`load_image`
- 懒加载类 + 非懒加载分类
  - 类的加载：在`_read_images`中完成类的重映射操作，而在`load_image`中实现数据的加载
  - 分类的加载：`load_image`

#### 类和分类的同名方法调用

> 当类和分类中，有同名的方法时，那么会调用哪个方法

在上一篇文章中，提到过`prepareMethodLists`中的`fixupMethodList`会对方法进行排序

```c++
static void 
prepareMethodLists(Class cls, method_list_t **addedLists, int addedCount,
                   bool baseMethods, bool methodsFromBundle)
{
    runtimeLock.assertLocked();

    if (addedCount == 0) return;

    // There exist RR/AWZ/Core special cases for some class's base methods.
    // But this code should never need to scan base methods for RR/AWZ/Core:
    // default RR/AWZ/Core cannot be set before setInitialized().
    // Therefore we need not handle any special cases here.
    if (baseMethods) {
        ASSERT(cls->hasCustomAWZ() && cls->hasCustomRR() && cls->hasCustomCore());
    }

    // Add method lists to array.
    // Reallocate un-fixed method lists.
    // The new methods are PREPENDED to the method list array.

    for (int i = 0; i < addedCount; i++) {
        method_list_t *mlist = addedLists[i];
        ASSERT(mlist);

        // Fixup selectors if necessary
        if (!mlist->isFixedUp()) {
            fixupMethodList(mlist, methodsFromBundle, true/*sort*/);
        }
    }

    // If the class is initialized, then scan for method implementations
    // tracked by the class's flags. If it's not initialized yet,
    // then objc_class::setInitialized() will take care of it.
    if (cls->isInitialized()) {
        objc::AWZScanner::scanAddedMethodLists(cls, addedLists, addedCount);
        objc::RRScanner::scanAddedMethodLists(cls, addedLists, addedCount);
        objc::CoreScanner::scanAddedMethodLists(cls, addedLists, addedCount);
    }
}

static void 
fixupMethodList(method_list_t *mlist, bool bundleCopy, bool sort)
{
    runtimeLock.assertLocked();
    ASSERT(!mlist->isFixedUp());

    // fixme lock less in attachMethodLists ?
    // dyld3 may have already uniqued, but not sorted, the list
    if (!mlist->isUniqued()) {
        mutex_locker_t lock(selLock);
    
        // Unique selectors in list.
        for (auto& meth : *mlist) {
            const char *name = sel_cname(meth.name);
            meth.name = sel_registerNameNoLock(name, bundleCopy);
        }
    }

    // Sort by selector address.
    if (sort) {
        method_t::SortBySELAddress sorter;
        std::stable_sort(mlist->begin(), mlist->end(), sorter);
    }
    
    // Mark method list as uniqued and sorted
    mlist->setFixedUp();
}

struct method_t {
    SEL name;
    const char *types;
    MethodListIMP imp;

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

根据排序规则可得：当方法同名时，会根据方法的 `name` 进行排序

再来分析`attachCategories`

```c++
static void
attachCategories(Class cls, const locstamped_category_t *cats_list, uint32_t cats_count,
                 int flags)
{
    if (slowpath(PrintReplacedMethods)) {
        printReplacements(cls, cats_list, cats_count);
    }
    if (slowpath(PrintConnecting)) {
        _objc_inform("CLASS: attaching %d categories to%s class '%s'%s",
                     cats_count, (flags & ATTACH_EXISTING) ? " existing" : "",
                     cls->nameForLogging(), (flags & ATTACH_METACLASS) ? " (meta)" : "");
    }

    /*
     * Only a few classes have more than 64 categories during launch.
     * This uses a little stack, and avoids malloc.
     *
     * Categories must be added in the proper order, which is back
     * to front. To do that with the chunking, we iterate cats_list
     * from front to back, build up the local buffers backwards,
     * and call attachLists on the chunks. attachLists prepends the
     * lists, so the final result is in the expected order.
     */
    constexpr uint32_t ATTACH_BUFSIZ = 64;
    method_list_t   *mlists[ATTACH_BUFSIZ];
    property_list_t *proplists[ATTACH_BUFSIZ];
    protocol_list_t *protolists[ATTACH_BUFSIZ];

    uint32_t mcount = 0;
    uint32_t propcount = 0;
    uint32_t protocount = 0;
    bool fromBundle = NO;
    bool isMeta = (flags & ATTACH_METACLASS);
    auto rwe = cls->data()->extAllocIfNeeded();

    for (uint32_t i = 0; i < cats_count; i++) {
        auto& entry = cats_list[i];

        method_list_t *mlist = entry.cat->methodsForMeta(isMeta);
        if (mlist) {
            if (mcount == ATTACH_BUFSIZ) {
                prepareMethodLists(cls, mlists, mcount, NO, fromBundle);
                rwe->methods.attachLists(mlists, mcount);
                mcount = 0;
            }
            mlists[ATTACH_BUFSIZ - ++mcount] = mlist;
            fromBundle |= entry.hi->isBundle();
        }

        property_list_t *proplist =
            entry.cat->propertiesForMeta(isMeta, entry.hi);
        if (proplist) {
            if (propcount == ATTACH_BUFSIZ) {
                rwe->properties.attachLists(proplists, propcount);
                propcount = 0;
            }
            proplists[ATTACH_BUFSIZ - ++propcount] = proplist;
        }

        protocol_list_t *protolist = entry.cat->protocolsForMeta(isMeta);
        if (protolist) {
            if (protocount == ATTACH_BUFSIZ) {
                rwe->protocols.attachLists(protolists, protocount);
                protocount = 0;
            }
            protolists[ATTACH_BUFSIZ - ++protocount] = protolist;
        }
    }

    if (mcount > 0) {
        prepareMethodLists(cls, mlists + ATTACH_BUFSIZ - mcount, mcount, NO, fromBundle);
        rwe->methods.attachLists(mlists + ATTACH_BUFSIZ - mcount, mcount);
        if (flags & ATTACH_EXISTING) flushCaches(cls);
    }

    rwe->properties.attachLists(proplists + ATTACH_BUFSIZ - propcount, propcount);

    rwe->protocols.attachLists(protolists + ATTACH_BUFSIZ - protocount, protocount);
}
```

没错，分类添加方法、属性、协议也是通过`attachLists`，而其内部是通过`memmove、memcpy`

所以得出：

- 分类并不会覆盖主类已有的方法

- 分类的方法被放到新方法列表的前面，而类的方法被放倒了新列表的后面

  当运行时在进行方法查找时，会优先找到分类的方法，返回`imp`

**分类与主类同名方法调用顺序**

- 类和分类方法同名时，必定响应分类方法（不管类和分类是否实现`+load`）
- 类和多个分类方法同名时
  - 如果分类没有实现或全都`+load`方法，响应的是**编译器**最后一个分类，即`Compile Sources`中的最后一个分类
  - 如果分类中其中一个实现`+load`，那么响应的是编译器中最后的一个非懒加载分类

### load_images

`load_image`源码

```c++
void
load_images(const char *path __unused, const struct mach_header *mh)
{
    if (!didInitialAttachCategories && didCallDyldNotifyRegister) {
        didInitialAttachCategories = true;
        loadAllCategories();
    }

    // Return without taking locks if there are no +load methods here.
    if (!hasLoadMethods((const headerType *)mh)) return;

    recursive_mutex_locker_t lock(loadMethodLock);

    // Discover load methods
    {
        mutex_locker_t lock2(runtimeLock);
        prepare_load_methods((const headerType *)mh);
    }

    // Call +load methods (without runtimeLock - re-entrant)
    call_load_methods();
}
```

`loadAllCategories`之前分析了，主要是负责加载分类的

除此之外，还有两个关键的函数：

- `prepare_load_methods`：发现 load 方法
- `call_load_methods`：调用 load 方法

#### prepare_load_methods

```c++
void prepare_load_methods(const headerType *mhdr)
{
    size_t count, i;

    runtimeLock.assertLocked();

    classref_t const *classlist = 
        _getObjc2NonlazyClassList(mhdr, &count);
    for (i = 0; i < count; i++) {
        schedule_class_load(remapClass(classlist[i]));
    }

    category_t * const *categorylist = _getObjc2NonlazyCategoryList(mhdr, &count);
    for (i = 0; i < count; i++) {
        category_t *cat = categorylist[i];
        Class cls = remapClass(cat->cls);
        if (!cls) continue;  // category for ignored weak-linked class
        if (cls->isSwiftStable()) {
            _objc_fatal("Swift class extensions and categories on Swift "
                        "classes are not allowed to have +load methods");
        }
        realizeClassWithoutSwift(cls, nil);
        ASSERT(cls->ISA()->isRealized());
        add_category_to_loadable_list(cat);
    }
}
```

- 通过`_getObjc2NonlazyClassList`从 Mach-O 中读取所有的非懒加载类遍历调用`schedule_class_load`

  ```c++
  static void schedule_class_load(Class cls)
  {
      if (!cls) return;
      ASSERT(cls->isRealized());  // _read_images should realize
  
      if (cls->data()->flags & RW_LOADED) return;
  
      // Ensure superclass-first ordering
      schedule_class_load(cls->superclass);
  
      add_class_to_loadable_list(cls);
      cls->setInfo(RW_LOADED); 
  }
  
  // 保存 +load 方法
  void add_class_to_loadable_list(Class cls)
  {
      IMP method;
  
      loadMethodLock.assertLocked();
  
      method = cls->getLoadMethod();
      if (!method) return;  // Don't bother if cls has no +load method
      
      if (PrintLoading) {
          _objc_inform("LOAD: class '%s' scheduled for +load", 
                       cls->nameForLogging());
      }
      
      if (loadable_classes_used == loadable_classes_allocated) {
          loadable_classes_allocated = loadable_classes_allocated*2 + 16;
          loadable_classes = (struct loadable_class *)
              realloc(loadable_classes,
                                loadable_classes_allocated *
                                sizeof(struct loadable_class));
      }
      
      loadable_classes[loadable_classes_used].cls = cls;
      loadable_classes[loadable_classes_used].method = method;
      loadable_classes_used++;
  }
  ```

  内部递归调用`schedule_class_load`，根据类的继承链递归去发现父类的`+load`方法，以确保父类的`+load`方法优先加载

  再调用`add_class_to_loadable_list`把类的`+load`方法存在`loadable_classes`

- 通过`_getObjc2NonlazyCategoryList`从 Mach-O 中读取所有的非懒加载分类遍历

  - 通过`realizeClassWithoutSwift`来防止类没有初始化（若已经初始化了则不影响）
  - 调用`add_category_to_loadable_list`加载分类中的`+load`方法到`loadable_categories`

#### call_load_methods

```c++
void call_load_methods(void)
{
    static bool loading = NO;
    bool more_categories;

    loadMethodLock.assertLocked();

    // Re-entrant calls do nothing; the outermost call will finish the job.
    if (loading) return;
    loading = YES;

    void *pool = objc_autoreleasePoolPush();

    do {
        // 1. Repeatedly call class +loads until there aren't any more
        while (loadable_classes_used > 0) {
            call_class_loads();
        }

        // 2. Call category +loads ONCE
        more_categories = call_category_loads();

        // 3. Run more +loads if there are classes OR more untried categories
    } while (loadable_classes_used > 0  ||  more_categories);

    objc_autoreleasePoolPop(pool);

    loading = NO;
}

// 调用类的+load
static void call_class_loads(void)
{
    int i;
    
    // Detach current loadable list.
    struct loadable_class *classes = loadable_classes;
    int used = loadable_classes_used;
    loadable_classes = nil;
    loadable_classes_allocated = 0;
    loadable_classes_used = 0;
    
    // Call all +loads for the detached list.
    for (i = 0; i < used; i++) {
        Class cls = classes[i].cls;
        load_method_t load_method = (load_method_t)classes[i].method;
        if (!cls) continue; 

        if (PrintLoading) {
            _objc_inform("LOAD: +[%s load]\n", cls->nameForLogging());
        }
        (*load_method)(cls, @selector(load));
    }
    
    // Destroy the detached list.
    if (classes) free(classes);
}

// 调用分类的+load
static bool call_category_loads(void)
{
    int i, shift;
    bool new_categories_added = NO;
    
    // Detach current loadable list.
    struct loadable_category *cats = loadable_categories;
    int used = loadable_categories_used;
    int allocated = loadable_categories_allocated;
    loadable_categories = nil;
    loadable_categories_allocated = 0;
    loadable_categories_used = 0;

    // Call all +loads for the detached list.
    for (i = 0; i < used; i++) {
        Category cat = cats[i].cat;
        load_method_t load_method = (load_method_t)cats[i].method;
        Class cls;
        if (!cat) continue;

        cls = _category_getClass(cat);
        if (cls  &&  cls->isLoadable()) {
            if (PrintLoading) {
                _objc_inform("LOAD: +[%s(%s) load]\n", 
                             cls->nameForLogging(), 
                             _category_getName(cat));
            }
            (*load_method)(cls, @selector(load));
            cats[i].cat = nil;
        }
    }

    // Compact detached list (order-preserving)
    shift = 0;
    for (i = 0; i < used; i++) {
        if (cats[i].cat) {
            cats[i-shift] = cats[i];
        } else {
            shift++;
        }
    }
    used -= shift;

    // Copy any new +load candidates from the new list to the detached list.
    new_categories_added = (loadable_categories_used > 0);
    for (i = 0; i < loadable_categories_used; i++) {
        if (used == allocated) {
            allocated = allocated*2 + 16;
            cats = (struct loadable_category *)
                realloc(cats, allocated *
                                  sizeof(struct loadable_category));
        }
        cats[used++] = loadable_categories[i];
    }

    // Destroy the new list.
    if (loadable_categories) free(loadable_categories);

    // Reattach the (now augmented) detached list. 
    // But if there's nothing left to load, destroy the list.
    if (used) {
        loadable_categories = cats;
        loadable_categories_used = used;
        loadable_categories_allocated = allocated;
    } else {
        if (cats) free(cats);
        loadable_categories = nil;
        loadable_categories_used = 0;
        loadable_categories_allocated = 0;
    }

    if (PrintLoading) {
        if (loadable_categories_used != 0) {
            _objc_inform("LOAD: %d categories still waiting for +load\n",
                         loadable_categories_used);
        }
    }

    return new_categories_added;
}
```

`do-while`循环中主要做 3 个操作：

- 循环调用`类的+load`方法，直到调用完
- 调用一次`分类中的+load`
- 如果有类或更多未尝试的分类，则运行更多的`+load`

> 使用**自动释放池**管理内存，关于自动释放池，在后续篇章会详细展开

## initalize分析

关于`initalize`的苹果官方文档定义为：Initializes the class before it receives its first message.

> [`initalize`定义](https://developer.apple.com/documentation/objectivec/nsobject/1418639-initialize?language=objc)

即在接收到第一个消息之前初始化该类

那么，我们在 objc源码中 `lookUpImpOrForward`查看

```c++
IMP lookUpImpOrForward(Class cls, SEL sel, id inst, 
                       bool initialize, bool cache, bool resolver)
{
    ...
    if (initialize && !cls->isInitialized()) {
        cls = initializeAndLeaveLocked(cls, inst, runtimeLock);
        ...
    }
    ...
}

static Class initializeAndLeaveLocked(Class cls, id obj, mutex_t& lock)
{
    return initializeAndMaybeRelock(cls, obj, lock, true);
}

static Class initializeAndMaybeRelock(Class cls, id inst,
                                      mutex_t& lock, bool leaveLocked)
{
    ···
    initializeNonMetaClass(nonmeta);
    ···
}
```

`lookUpImpOrForward -> initializeAndLeaveLocked -> initializeAndMaybeRelock -> initializeNonMetaClass`

在`initializeNonMetaClass`递归调用父类`initialize`，然后调用`callInitialize`

```c++
void initializeNonMetaClass(Class cls)
{
    ...
    supercls = cls->superclass;
    if (supercls  &&  !supercls->isInitialized()) {
        initializeNonMetaClass(supercls);
    }
    ...
    {
            callInitialize(cls);

            if (PrintInitializing) {
                _objc_inform("INITIALIZE: thread %p: finished +[%s initialize]",
                             pthread_self(), cls->nameForLogging());
            }
        }
    ...
}
```

`callInitialize`是一个普通的消息发送

```C++
void callInitialize(Class cls)
{
    ((void(*)(Class, SEL))objc_msgSend)(cls, SEL_initialize);
    asm("");
}
```

关于`initalize`的结论：

- `initialize`在类或者其子类的第一个方法被调用前（发送消息前）调用
- 只在类中添加`initialize`但不使用的情况下，是不会调用`initialize`
- 父类的`initialize`方法会比子类先执行
- 当子类未实现`initialize`方法时，会调用父类`initialize`方法；子类实现`initialize`方法时，会覆盖父类`initialize`方法
- 当有多个分类都实现了`initialize`方法，会覆盖类中的方法，只执行一个(会执行最后被加载到内存中的分类的方法)

### 类拓展

类拓展 `extension` 又称为`匿名的分类`，同样可以为类增加属性和方法

在开始的类中，加入类拓展

```objective-c
@interface Person ()

@property (nonatomic, copy) NSString *ex_name;
@property (nonatomic, assign) NSNumber *ex_age;

- (void)ex_doFirst;
- (void)ex_doSecond;
@end
```

`clang` 编译

```c++
static struct /*_ivar_list_t*/ {
	unsigned int entsize;  // sizeof(struct _prop_t)
	unsigned int count;
	struct _ivar_t ivar_list[4];
} _OBJC_$_INSTANCE_VARIABLES_Person __attribute__ ((used, section ("__DATA,__objc_const"))) = {
	sizeof(_ivar_t),
	4,
	{{(unsigned long int *)&OBJC_IVAR_$_Person$_name, "_name", "@\"NSString\"", 3, 8},
	 {(unsigned long int *)&OBJC_IVAR_$_Person$_age, "_age", "@\"NSNumber\"", 3, 8},
	 {(unsigned long int *)&OBJC_IVAR_$_Person$_ex_name, "_ex_name", "@\"NSString\"", 3, 8},
	 {(unsigned long int *)&OBJC_IVAR_$_Person$_ex_age, "_ex_age", "@\"NSNumber\"", 3, 8}}
};

static struct /*_method_list_t*/ {
	unsigned int entsize;  // sizeof(struct _objc_method)
	unsigned int method_count;
	struct _objc_method method_list[19];
} _OBJC_$_INSTANCE_METHODS_Person __attribute__ ((used, section ("__DATA,__objc_const"))) = {
	sizeof(_objc_method),
	19,
	{{(struct objc_selector *)"doFirst", "v16@0:8", (void *)_I_Person_doFirst},
	{(struct objc_selector *)"doSecond", "v16@0:8", (void *)_I_Person_doSecond},
	{(struct objc_selector *)"ex_doFirst", "v16@0:8", (void *)_I_Person_ex_doFirst},
	{(struct objc_selector *)"name", "@16@0:8", (void *)_I_Person_name},
	{(struct objc_selector *)"setName:", "v24@0:8@16", (void *)_I_Person_setName_},
	{(struct objc_selector *)"age", "@16@0:8", (void *)_I_Person_age},
	{(struct objc_selector *)"setAge:", "v24@0:8@16", (void *)_I_Person_setAge_},
	{(struct objc_selector *)"ex_name", "@16@0:8", (void *)_I_Person_ex_name},
	{(struct objc_selector *)"setEx_name:", "v24@0:8@16", (void *)_I_Person_setEx_name_},
	{(struct objc_selector *)"ex_age", "@16@0:8", (void *)_I_Person_ex_age},
	{(struct objc_selector *)"setEx_age:", "v24@0:8@16", (void *)_I_Person_setEx_age_},
	{(struct objc_selector *)"name", "@16@0:8", (void *)_I_Person_name},
	{(struct objc_selector *)"setName:", "v24@0:8@16", (void *)_I_Person_setName_},
	{(struct objc_selector *)"age", "@16@0:8", (void *)_I_Person_age},
	{(struct objc_selector *)"setAge:", "v24@0:8@16", (void *)_I_Person_setAge_},
	{(struct objc_selector *)"ex_name", "@16@0:8", (void *)_I_Person_ex_name},
	{(struct objc_selector *)"setEx_name:", "v24@0:8@16", (void *)_I_Person_setEx_name_},
	{(struct objc_selector *)"ex_age", "@16@0:8", (void *)_I_Person_ex_age},
	{(struct objc_selector *)"setEx_age:", "v24@0:8@16", (void *)_I_Person_setEx_age_}}
};
```

可以看到，类拓展中的属性已经被加入到 `ivar_list_t` 中，方法`ex_doFirst`被加入到了 `method_list_t`，`ex_doSecond`没有被加入是因为没有在主类中实现

因此

- 类拓展在编译时会作为类的一部分进行编译

- 类拓展只是声明，依赖于当前主类，方法需要在主类 `.m` 文件中实现

### 类拓展与分类的区别

**分类**

- 为某个类添加方法、协议、属性（一般使用关联对象），通常用来为系统的类拓展方法或者把复杂类根据功能拆分到不同的文件里

**类拓展**

- 为某个类添加原来没有的成员变量、属性、方法（方法只是声明，需要实现），通常用来扩展私有属性，或者把`.h`的**只读属性**重写**可读写**的

**区别**

- 分类是在运行时，才把分类的信息合并到类信息中，而类拓展是在编译时
- 分类声明的属性，只会生成 `setter/getter` 方法的声明，不会自动生成**成员变量**和`setter/getter` 方法的实现，而类拓展可以
- 分类不可以为类添加实例变量，而类拓展可以
- 分类可以为类添加方法的实现，而类拓展只能声明方法，而不能实现

**分类的局限点**

- 无法为类添加实例变量，但可通过关联对象进行实现
- 分类的方法若和类中原来的方法实现重名，会优先调用分类中的方法
- 多个分类的方法重名，会调用最后编译的那个分类的方法实现