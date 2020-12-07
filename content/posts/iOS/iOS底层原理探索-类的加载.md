---
title: "iOS底层原理探索-类的加载"
date: 2020-10-13T14:21:19+08:00
draft: false
tags: ["iOS"]
url:  "class-load"
---

在『[iOS底层原理探索-dyld加载流程](/dyld-load)』中，介绍了 App 启动时刻的一些操作。

那么关于类的加载具体是在什么时候呢？同样的，以下几个问题会帮助对本文的理解：

- `_objc_init`具体做了什么
- `readClass`具体做了什么
- `realizeClassWithoutSwift`具体做了什么
- 类的加载过程——非懒加载
- 类的加载过程——懒加载

### _objc_init

```c++
/***********************************************************************
* _objc_init
* Bootstrap initialization. Registers our image notifier with dyld.
* Called by libSystem BEFORE library initialization time
**********************************************************************/

void _objc_init(void)
{
    static bool initialized = false;
    if (initialized) return;
    initialized = true;
    
    // fixme defer initialization until an objc-using image is found?
    environ_init();
    tls_init();
    static_init();
    runtime_init();
    exception_init();
    cache_init();
    _imp_implementationWithBlock_init();

    _dyld_objc_notify_register(&map_images, load_images, unmap_image);

#if __OBJC2__
    didCallDyldNotifyRegister = true;
#endif
}
```

先看**源码**，逐行分析

#### environ_init()

这个函数会读取影响运行时的环境变量，如果需要，还可以打印环境变量帮助。

```c++
if (PrintHelp  ||  PrintOptions) {
    if (PrintHelp) {
        _objc_inform("Objective-C runtime debugging. Set variable=YES to enable.");
        _objc_inform("OBJC_HELP: describe available environment variables");
        if (PrintOptions) {
            _objc_inform("OBJC_HELP is set");
        }
        _objc_inform("OBJC_PRINT_OPTIONS: list which options are set");
    }
    if (PrintOptions) {
        _objc_inform("OBJC_PRINT_OPTIONS is set");
    }

    for (size_t i = 0; i < sizeof(Settings)/sizeof(Settings[0]); i++) {
        const option_t *opt = &Settings[i];            
        if (PrintHelp) _objc_inform("%s: %s", opt->env, opt->help);
        if (PrintOptions && *opt->var) _objc_inform("%s is set", opt->env);
    }
}
```

这里列了所有的[环境变量](https://w-md.imzsy.design/%E7%8E%AF%E5%A2%83%E5%8F%98%E9%87%8F%E6%B1%87%E6%80%BB.pdf)，当然也可以通过终端输入`export OBJC_HELP=1`查看 

常用的环境变量如：

- `OBJC_PRINT_LOAD_METHODS`：打印所有的`+load`方法

- `OBJC_DISABLE_NONPOINTER_ISA`：控制 `isa` 优化开关

#### tls_init()

这个函数主要是本地线程池的初始化，关于线程 key 的绑定

```c++
void tls_init(void)
{
#if SUPPORT_DIRECT_THREAD_KEYS // 本地线程池
    pthread_key_init_np(TLS_DIRECT_KEY, &_objc_pthread_destroyspecific); // 初始init
#else
    _objc_pthread_key = tls_create(&_objc_pthread_destroyspecific); // 析构
#endif
}
```

#### static_init()

通过函数注释可知，主要是运行 **C++ 静态构造函数**（只会运行系统级别的构造函数）

在 Dyld 调用我们的静态构造函数之前，`libc`调用`_objc_init()`方法，也就说**系统的C++构造函数 优先于 自定义的C++构造函数**

```c++
/***********************************************************************
* static_init
* Run C++ static constructor functions.
* libc calls _objc_init() before dyld would call our static constructors, 
* so we have to do it ourselves.
**********************************************************************/
static void static_init()
{
    size_t count;
    auto inits = getLibobjcInitializers(&_mh_dylib_header, &count);
    for (size_t i = 0; i < count; i++) {
        inits[i]();
    }
}
```

#### runtime_init()

运行时的初始化，主要分为两个操作：

- 开辟存储分类的表
- 开辟存储类的表

```c++
void runtime_init(void)
{
    objc::unattachedCategories.init(32);
    objc::allocatedClasses.init();
}
```

#### exception_init()

初始化 `libobjc` 的异常处理系统，注册异常处理的回调，从而监控异常的处理

```c++
/***********************************************************************
* exception_init
* Initialize libobjc's exception handling system.
* Called by map_images().
**********************************************************************/
void exception_init(void)
{
    old_terminate = std::set_terminate(&_objc_terminate);
}
```

当产生 `crash` 时，会来到`_objc_terminate`方法，走到 `uncaught_handler` 抛出异常

```c++
/***********************************************************************
* _objc_terminate
* Custom std::terminate handler.
*
* The uncaught exception callback is implemented as a std::terminate handler. 
* 1. Check if there's an active exception
* 2. If so, check if it's an Objective-C exception
* 3. If so, call our registered callback with the object.
* 4. Finally, call the previous terminate handler.
**********************************************************************/
static void (*old_terminate)(void) = nil;
static void _objc_terminate(void)
{
    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: terminating");
    }

    if (! __cxa_current_exception_type()) {
        // No current exception.
        (*old_terminate)();
    }
    else {
        // There is a current exception. Check if it's an objc exception.
        @try {
            __cxa_rethrow();
        } @catch (id e) {
            // It's an objc object. Call Foundation's handler, if any.
            (*uncaught_handler)((id)e);
            (*old_terminate)();
        } @catch (...) {
            // It's not an objc object. Continue to C++ terminate.
            (*old_terminate)();
        }
    }
}
```

在底层`objc_setExceptionMatcher`函数会将传入的 `fn` 赋值给`uncaught_handler`，经过封装在上层调用的是`NSSetUncaughtExceptionHandler`方法，

```c++
/***********************************************************************
* objc_setExceptionMatcher
* Set a handler for matching Objective-C exceptions. 
* Returns the previous handler. 
**********************************************************************/
objc_exception_matcher
objc_setExceptionMatcher(objc_exception_matcher fn)
{
    objc_exception_matcher result = exception_matcher;
    exception_matcher = fn;
    return result;
}
```

**关于 Crash**

造成 Crash 的主要原因就是收到未处理的信号，而这个信号来源于三个地方：

- kernel内核
- 其他进行
- App本身

相应的，crash 也分为了 3 类

- Mach异常：底层内核级异常。用户态的开发者可以直接通过 Mach API 设置 Thread、task、host 的异常端口，捕获 Mach 异常
- Unix异常：BSD信号，如果开发者没有捕获 Mach 异常，则会被 host 层的方法 ux_exception() 将异常转换为对应的 UNIX 信号，并通过 threadsignal() 将信号投递到出错线程。通过方法 `signal(x, fn)` 捕获
- NSException应用异常：未被不捕获的 Objective-C 异常，导致程序向自身发送了 `SIGABRT` 信号而崩溃，可以通过 `try-catch` 或者`NSSetUncaughtExceptionHandler`捕获

**Crash拦截**

在日常开发中，会针对 Crash 进行拦截处理，其本质就是通过`NSSetUncaughtExceptionHandler`注册异常捕获函数`fn`。

当发送异常时，`fn`函数就会被调用，在函数中，收集崩溃日志、线程保活等操作

> [Crash拦截Demo](https://github.com/dev-jw/CrashDemo/blob/master/CrashDemo/UncaughtExceptionHandler.m)

#### cache_init()

缓存初始化

```c++
void cache_init()
{
#if HAVE_TASK_RESTARTABLE_RANGES
    mach_msg_type_number_t count = 0;
    kern_return_t kr;

    while (objc_restartableRanges[count].location) {
        count++;
    }

    kr = task_restartable_ranges_register(mach_task_self(),
                                          objc_restartableRanges, count);
    if (kr == KERN_SUCCESS) return;
    _objc_fatal("task_restartable_ranges_register failed (result 0x%x: %s)",
                kr, mach_error_string(kr));
#endif // HAVE_TASK_RESTARTABLE_RANGES
}
```

#### _imp_implementationWithBlock_init()

启动回调机制，通常不会做什么，因为一切都是懒初始化的，但是对于某些进程，我们需要急切地加载`libobjc-trampolines.dylib`

```c++
void
_imp_implementationWithBlock_init(void)
{
#if TARGET_OS_OSX
    // Eagerly load libobjc-trampolines.dylib in certain processes. Some
    // programs (most notably QtWebEngineProcess used by older versions of
    // embedded Chromium) enable a highly restrictive sandbox profile which
    // blocks access to that dylib. If anything calls
    // imp_implementationWithBlock (as AppKit has started doing) then we'll
    // crash trying to load it. Loading it here sets it up before the sandbox
    // profile is enabled and blocks it.
    //
    // This fixes EA Origin (rdar://problem/50813789)
    // and Steam (rdar://problem/55286131)
    if (__progname &&
        (strcmp(__progname, "QtWebEngineProcess") == 0 ||
         strcmp(__progname, "Steam Helper") == 0)) {
        Trampolines.Initialize();
    }
#endif
}
```

#### _dyld_objc_notify_register

`_dyld_objc_notify_register`函数声明

```c++
//
// Note: only for use by objc runtime
// Register handlers to be called when objc images are mapped, unmapped, and initialized.
// Dyld will call back the "mapped" function with an array of images that contain an objc-image-info section.
// Those images that are dylibs will have the ref-counts automatically bumped, so objc will no longer need to
// call dlopen() on them to keep them from being unloaded.  During the call to _dyld_objc_notify_register(),
// dyld will call the "mapped" function with already loaded objc images.  During any later dlopen() call,
// dyld will also call the "mapped" function.  Dyld will call the "init" function when dyld would be called
// initializers in that image.  This is when objc calls any +load methods in that image.
//
void _dyld_objc_notify_register(_dyld_objc_notify_mapped    mapped,
                                _dyld_objc_notify_init      init,
                                _dyld_objc_notify_unmapped  unmapped);
```

从注释中，不难得出：

- 仅供`objc运行时`使用
- 注册处理程序，以便在映射、取消映射和初始化 objc 镜像时调用
- `dyld`将会通过一个包含objc-image-info的镜像文件的数组回调`mapped`函数

三个参数含义如下：

- `map_images`：dyld 将 image 加载内存时，会触发该函数
- `load_images`：dyld 初始化 image 会触发该函数
- `unmap_image`：dyld 将 image 移除时，会触发该函数

而这个三个参数，会在`registerObjCNotifiers`函数中，分别地保存到`sNotifyObjCMapped`、`sNotifyObjCInit`、`sNotifyObjCUnmapped`

得到以下等价关系：

- `sNotifyObjCMapped` == `mapped` == `map_images`
- `sNotifyObjCInit` == `init` == `load_images`
- `sNotifyObjCUnmapped` == `unmapped` == `unmap_image`

**调用时机**

在上一篇中，分析了 `load_images` 的调用时机，再来看一下 `map_images` 的调用时机

在 dyld 源码中搜索`sNotifyObjCMapped`，发现是在`notifyBatchPartial`函数中调用的

```c++
static void notifyBatchPartial(dyld_image_states state, bool orLater, dyld_image_state_change_handler onlyHandler, bool preflightOnly, bool onlyObjCMappedNotification)
{
    std::vector<dyld_image_state_change_handler>* handlers = stateToHandlers(state, sBatchHandlers);
    if ( (handlers != NULL) || ((state == dyld_image_state_bound) && (sNotifyObjCMapped != NULL)) ) {
        ...
        if ( imageCount != 0 ) {
            ...
            if ( objcImageCount != 0 ) {
                    dyld3::ScopedTimer timer(DBG_DYLD_TIMING_OBJC_MAP, 0, 0, 0);
                    uint64_t t0 = mach_absolute_time();
                    // 调用sNotifyObjCMapped
                    (*sNotifyObjCMapped)(objcImageCount, paths, mhs);
                    uint64_t t1 = mach_absolute_time();
                    ImageLoader::fgTotalObjCSetupTime += (t1-t0);
                }
            }
        }
      ...
    }
}
```

`notifyBatchPartial`又是在`registerObjCNotifiers`中被调用的

```c++
void registerObjCNotifiers(_dyld_objc_notify_mapped mapped, _dyld_objc_notify_init init, _dyld_objc_notify_unmapped unmapped)
{
	// record functions to call
	sNotifyObjCMapped	= mapped;
	sNotifyObjCInit		= init;
	sNotifyObjCUnmapped = unmapped;

	// call 'mapped' function with all images mapped so far
	try {
		notifyBatchPartial(dyld_image_state_bound, true, NULL, false, true);
	}
	catch (const char* msg) {
		// ignore request to abort during registration
	}

	// <rdar://problem/32209809> call 'init' function on all images already init'ed (below libSystem)
	for (std::vector<ImageLoader*>::iterator it=sAllImages.begin(); it != sAllImages.end(); it++) {
		ImageLoader* image = *it;
		if ( (image->getState() == dyld_image_state_initialized) && image->notifyObjC() ) {
			dyld3::ScopedTimer timer(DBG_DYLD_TIMING_OBJC_INIT, (uint64_t)image->machHeader(), 0, 0);
			(*sNotifyObjCInit)(image->getRealPath(), image->machHeader());
		}
	}
}
```

因此，`map_images` 是先于 `load_images` 执行

#### dyld与Objc关联

综合**dyld的加载流程**，dyld 与 Objc 的关联流程图

![dyld&objc](https://w-md.imzsy.design/dyld&objc.png)

### map_images

```c++
/***********************************************************************
* map_images
* Process the given images which are being mapped in by dyld.
* Calls ABI-agnostic code after taking ABI-specific locks.
*
* Locking: write-locks runtimeLock
**********************************************************************/
void
map_images(unsigned count, const char * const paths[],
           const struct mach_header * const mhdrs[])
{
    mutex_locker_t lock(runtimeLock);
    return map_images_nolock(count, paths, mhdrs);
}
```

`map_images` 调用 `map_images_nolock`

```c++
void
map_images_nolock(unsigned mhCount, const char * const mhPaths[],
                  const struct mach_header * const mhdrs[])
{
    //...省略

    // Find all images with Objective-C metadata.查找所有带有Objective-C元数据的映像
    hCount = 0;

    // Count classes. Size various table based on the total.计算类的个数
    int totalClasses = 0;
    int unoptimizedTotalClasses = 0;
    //代码块：作用域，进行局部处理，即局部处理一些事件
    {
        //...省略
    }
    
    //...省略

    if (hCount > 0) {
        //加载镜像文件
        _read_images(hList, hCount, totalClasses, unoptimizedTotalClasses);
    }

    firstTime = NO;
    
    // Call image load funcs after everything is set up.一切设置完成后，调用镜像加载功能。
    for (auto func : loadImageFuncs) {
        for (uint32_t i = 0; i < mhCount; i++) {
            func(mhdrs[i]);
        }
    }
}
```

该函数是在镜像加载到内存时触发调用的，其主要作用是`Mach-O`文件中**类信息**加载到内存中，核心逻辑都在`_read_images`函数

#### _read_images

通过源码，该函数主要分为以下几个操作：

- 创建表
- 修复预编译阶段的@selector的混乱问题
- 类的重映射
- 修复重映射
- 修复一些消息
- 当类里面有协议时：readProtocol 读取协议
- 修复没有被加载的协议
- 分类处理
- 类的加载处理
- 没有被处理的类，优化那些被侵犯的类

##### 创建表

在`doneOnce`流程中通过`NXCreateMapTable` 创建表，存放类信息，即创建一张类的`哈希表``gdb_objc_realized_classes`，其目的是为了类查找方便、快捷

```c++
if (!doneOnce) {
     
    //...省略
    
    // namedClasses
    // Preoptimized classes don't go in this table.
    // 4/3 is NXMapTable's load factor
    int namedClassesSize = 
        (isPreoptimized() ? unoptimizedTotalClasses : totalClasses) * 4 / 3;
    // 创建表（哈希表key-value），目的是查找快
    gdb_objc_realized_classes =
        NXCreateMapTable(NXStrValueMapPrototype, namedClassesSize);

    ts.log("IMAGE TIMES: first time tasks");
}
```

- `gdb_objc_realized_classes`存储不在共享缓存且已命名的所有类，其容量是类数量的4/3

```c++
// This is a misnomer: gdb_objc_realized_classes is actually a list of 
// named classes not in the dyld shared cache, whether realized or not.
NXMapTable *gdb_objc_realized_classes;  // exported for debuggers in objc-gdb.h
```

##### 修复预编译阶段的@selector的混乱问题

主要是通过通过`_getObjc2SelectorRefs`拿到`Mach-O`中的静态段`__objc_selrefs`，遍历列表调用`sel_registerNameNoLock`将`SEL`添加到`namedSelectors`哈希表中

```c++
// Fix up @selector references 修复@selector引用
//sel 不是简单的字符串，而是带地址的字符串
static size_t UnfixedSelectors;
{
    mutex_locker_t lock(selLock);
    for (EACH_HEADER) {
        if (hi->hasPreoptimizedSelectors()) continue;

        bool isBundle = hi->isBundle();
        //通过_getObjc2SelectorRefs拿到Mach-O中的静态段__objc_selrefs
        SEL *sels = _getObjc2SelectorRefs(hi, &count);
        UnfixedSelectors += count;
        for (i = 0; i < count; i++) { //列表遍历
            const char *name = sel_cname(sels[i]);
            //注册sel操作，即将sel添加到
            SEL sel = sel_registerNameNoLock(name, isBundle);
            if (sels[i] != sel) {//当sel与sels[i]地址不一致时，需要调整为一致的
                sels[i] = sel;
            }
        }
    }
}
```

- `_getObjc2SelectorRefs`：表示获取`Mach-O`中的静态段`__objc_selrefs`，还有其他的 Section 获取方法

  ```c++
  #define GETSECT(name, type, sectname)                                   \
      type *name(const headerType *mhdr, size_t *outCount) {              \
          return getDataSection<type>(mhdr, sectname, nil, outCount);     \
      }                                                                   \
      type *name(const header_info *hi, size_t *outCount) {               \
          return getDataSection<type>(hi->mhdr(), sectname, nil, outCount); \
      }
  //      function name                 content type     section name
  GETSECT(_getObjc2SelectorRefs,        SEL,             "__objc_selrefs"); 
  GETSECT(_getObjc2MessageRefs,         message_ref_t,   "__objc_msgrefs"); 
  GETSECT(_getObjc2ClassRefs,           Class,           "__objc_classrefs");
  GETSECT(_getObjc2SuperRefs,           Class,           "__objc_superrefs");
  GETSECT(_getObjc2ClassList,           classref_t const,      "__objc_classlist");
  GETSECT(_getObjc2NonlazyClassList,    classref_t const,      "__objc_nlclslist");
  GETSECT(_getObjc2CategoryList,        category_t * const,    "__objc_catlist");
  GETSECT(_getObjc2CategoryList2,       category_t * const,    "__objc_catlist2");
  GETSECT(_getObjc2NonlazyCategoryList, category_t * const,    "__objc_nlcatlist");
  GETSECT(_getObjc2ProtocolList,        protocol_t * const,    "__objc_protolist");
  GETSECT(_getObjc2ProtocolRefs,        protocol_t *,    "__objc_protorefs");
  GETSECT(getLibobjcInitializers,       UnsignedInitializer, "__objc_init_func");
  ```

- `sel_registerNameNoLock`：将 `sel` 插入 `namedSelectors` 哈希表中

  ```c++
  SEL sel_registerNameNoLock(const char *name, bool copy) {
      return __sel_registerName(name, 0, copy);  // NO lock, maybe copy
  }
  
  static SEL __sel_registerName(const char *name, bool shouldLock, bool copy) 
  {
      SEL result = 0;
  
      if (shouldLock) selLock.assertUnlocked();
      else selLock.assertLocked();
  
      if (!name) return (SEL)0;
  
      result = search_builtins(name);
      if (result) return result;
      
      conditional_mutex_locker_t lock(selLock, shouldLock);
      auto it = namedSelectors.get().insert(name);//sel插入表
      if (it.second) {
          // No match. Insert.
          *it.first = (const char *)sel_alloc(name, copy);
      }
      return (SEL)*it.first;
  }
  ```

##### 类的重映射

从Mach-O中取出所有类，遍历处理

```c++
// Discover classes. Fix up unresolved future classes. Mark bundle classes.
bool hasDyldRoots = dyld_shared_cache_some_image_overridden();
//读取类：readClass
for (EACH_HEADER) {
    if (! mustReadClasses(hi, hasDyldRoots)) {
        // Image is sufficiently optimized that we need not call readClass()
        continue;
    }
    //从编译后的类列表中取出所有类，即从Mach-O中获取静态段__objc_classlist，是一个classref_t类型的指针
    classref_t const *classlist = _getObjc2ClassList(hi, &count);

    bool headerIsBundle = hi->isBundle();
    bool headerIsPreoptimized = hi->hasPreoptimizedClasses();

    for (i = 0; i < count; i++) {
        Class cls = (Class)classlist[i];//此时获取的cls只是一个地址
        Class newCls = readClass(cls, headerIsBundle, headerIsPreoptimized); //读取类，经过这步后，cls获取的值才是一个名字
        //经过调试，并未执行if里面的流程
        //初始化所有懒加载的类需要的内存空间，但是懒加载类的数据现在是没有加载到的，连类都没有初始化
        if (newCls != cls  &&  newCls) {
            // Class was moved but not deleted. Currently this occurs 
            // only when the new class resolved a future class.
            // Non-lazily realize the class below.
            //将懒加载的类添加到数组中
            resolvedFutureClasses = (Class *)
                realloc(resolvedFutureClasses, 
                        (resolvedFutureClassCount+1) * sizeof(Class));
            resolvedFutureClasses[resolvedFutureClassCount++] = newCls;
        }
    }
}
ts.log("IMAGE TIMES: discover classes");
```

关于 `readClass` 函数, 下面会详细分析

##### 修复重映射

将未映射 Class 和 Super Class 重映射，

- 调用`_getObjc2ClassRefs`获取类的引用
- 调用`_getObjc2SuperRefs`获取父类的引用
- 通过`remapClassRef`进行重映射，被

```c++
// Fix up remapped classes 修正重新映射的类
// Class list and nonlazy class list remain unremapped.类列表和非惰性类列表保持未映射
// Class refs and super refs are remapped for message dispatching.类引用和超级引用将重新映射以进行消息分发
//经过调试，并未执行if里面的流程
//将未映射的Class 和 Super Class重映射，被remap的类都是懒加载的类
if (!noClassesRemapped()) {
    for (EACH_HEADER) {
        Class *classrefs = _getObjc2ClassRefs(hi, &count);//Mach-O的静态段 __objc_classrefs
        for (i = 0; i < count; i++) {
            remapClassRef(&classrefs[i]);
        }
        // fixme why doesn't test future1 catch the absence of this?
        classrefs = _getObjc2SuperRefs(hi, &count);//Mach_O中的静态段 __objc_superrefs
        for (i = 0; i < count; i++) {
            remapClassRef(&classrefs[i]);
        }
    }
}
```

##### 修复一些消息

通过`_getObjc2MessageRefs`获取到静态段`__objc_selrefs`，`fixupMessageRef`遍历将函数指针进行注册，并fix为新的函数指针

```c++
#if SUPPORT_FIXUP
    // Fix up old objc_msgSend_fixup call sites
    for (EACH_HEADER) {
        // _getObjc2MessageRefs 获取Mach-O的静态段 __objc_msgrefs
        message_ref_t *refs = _getObjc2MessageRefs(hi, &count);
        if (count == 0) continue;

        if (PrintVtables) {
            _objc_inform("VTABLES: repairing %zu unsupported vtable dispatch "
                         "call sites in %s", count, hi->fname());
        }
        //经过调试，并未执行for里面的流程
        //遍历将函数指针进行注册，并fix为新的函数指针
        for (i = 0; i < count; i++) {
            fixupMessageRef(refs+i);
        }
    }

    ts.log("IMAGE TIMES: fix up objc_msgSend_fixup");
#endif
```

##### 当类里面有协议时：readProtocol 读取协议

```c++
// Discover protocols. Fix up protocol refs. 发现协议。修正协议参考
//遍历所有协议列表，并且将协议列表加载到Protocol的哈希表中
for (EACH_HEADER) {
    extern objc_class OBJC_CLASS_$_Protocol;
    //cls = Protocol类，所有协议和对象的结构体都类似，isa都对应Protocol类
    Class cls = (Class)&OBJC_CLASS_$_Protocol;
    ASSERT(cls);
    //获取protocol哈希表 -- protocol_map
    NXMapTable *protocol_map = protocols();
    bool isPreoptimized = hi->hasPreoptimizedProtocols();

    // Skip reading protocols if this is an image from the shared cache
    // and we support roots
    // Note, after launch we do need to walk the protocol as the protocol
    // in the shared cache is marked with isCanonical() and that may not
    // be true if some non-shared cache binary was chosen as the canonical
    // definition
    if (launchTime && isPreoptimized && cacheSupportsProtocolRoots) {
        if (PrintProtocols) {
            _objc_inform("PROTOCOLS: Skipping reading protocols in image: %s",
                         hi->fname());
        }
        continue;
    }

    bool isBundle = hi->isBundle();
    //通过_getObjc2ProtocolList 获取到Mach-O中的静态段__objc_protolist协议列表，
    //即从编译器中读取并初始化protocol
    protocol_t * const *protolist = _getObjc2ProtocolList(hi, &count);
    for (i = 0; i < count; i++) {
        //通过添加protocol到protocol_map哈希表中
        readProtocol(protolist[i], cls, protocol_map, 
                     isPreoptimized, isBundle);
    }
}
```

- 通过`protocols()`创建`protocol_map`哈希表

  ```c++
  /***********************************************************************
  * protocols
  * Returns the protocol name => protocol map for protocols.
  * Locking: runtimeLock must read- or write-locked by the caller
  **********************************************************************/
  static NXMapTable *protocols(void)
  {
      static NXMapTable *protocol_map = nil;
      
      runtimeLock.assertLocked();
  
      INIT_ONCE_PTR(protocol_map, 
                    NXCreateMapTable(NXStrValueMapPrototype, 16), 
                    NXFreeMapTable(v) );
  
      return protocol_map;
  }
  ```

- 通过`_getObjc2ProtocolList`获取到Mach-O中的静态段`__objc_protolist`协议列表

- 循环遍历协议列表，通过`readProtocol`方法将协议添加到`protocol_map`哈希表中

##### 修复没有被加载的协议

```c++
// Fix up @protocol references
// Preoptimized images may have the right 
// answer already but we don't know for sure.
for (EACH_HEADER) {
    // At launch time, we know preoptimized image refs are pointing at the
    // shared cache definition of a protocol.  We can skip the check on
    // launch, but have to visit @protocol refs for shared cache images
    // loaded later.
    if (launchTime && cacheSupportsProtocolRoots && hi->isPreoptimized())
        continue;
    //_getObjc2ProtocolRefs 获取到Mach-O的静态段 __objc_protorefs
    protocol_t **protolist = _getObjc2ProtocolRefs(hi, &count);
    for (i = 0; i < count; i++) {//遍历
        //比较当前协议和协议列表中的同一个内存地址的协议是否相同，如果不同则替换
        remapProtocolRef(&protolist[i]);//经过代码调试，并未执行
    }
}
```

- 通过 `_getObjc2ProtocolRefs` 获取到Mach-O的静态段 `__objc_protorefs`

  > *上面的_getObjc2ProtocolList*并不是同一个东西

- 遍历通过`remapProtocolRef`修复协议，`remapProtocolRef`比较`当前协议和协议列表中的同一个内存地址的协议是否相同`，如果`不同则替换`

  ```c++
  /***********************************************************************
  * remapProtocolRef
  * Fix up a protocol ref, in case the protocol referenced has been reallocated.
  * Locking: runtimeLock must be read- or write-locked by the caller
  **********************************************************************/
  static size_t UnfixedProtocolReferences;
  static void remapProtocolRef(protocol_t **protoref)
  {
      runtimeLock.assertLocked();
      //获取协议列表中统一内存地址的协议
      protocol_t *newproto = remapProtocol((protocol_ref_t)*protoref);
      if (*protoref != newproto) {//如果当前协议 与 同一内存地址协议不同，则替换
          *protoref = newproto;
          UnfixedProtocolReferences++;
      }
  }
  ```

##### 分类处理

```c++
// Discover categories. Only do this after the initial category
// attachment has been done. For categories present at startup,
// discovery is deferred until the first load_images call after
// the call to _dyld_objc_notify_register completes. rdar://problem/53119145
if (didInitialAttachCategories) {
    for (EACH_HEADER) {
        load_categories_nolock(hi);
    }
}
```

通过注释可知：需要在分类初始化并将数据加载到类后才执行，对于运行时出现的分类，将分类的发现推迟到对`_dyld_objc_notify_register`的调用完成后的`第一个load_images`调用为止

##### 类的加载处理

首先，苹果官方对于非懒加载类的定义是

> NonlazyClass is all about a class implementing or not a +load method.

即实现`+load`方法的类是非懒加载类，否则就是懒加载类

所以，这里的类正是`非懒加载类`

```c++
// Realize non-lazy classes (for +load methods and static instances) 
// 实现非懒加载的类，对于load方法和静态实例变量
for (EACH_HEADER) {
    //通过_getObjc2NonlazyClassList获取Mach-O的静态段__objc_nlclslist非懒加载类表
    classref_t const *classlist = 
        _getObjc2NonlazyClassList(hi, &count);
    for (i = 0; i < count; i++) {
        Class cls = remapClass(classlist[i]);
        
        /** 为探索自己定义的类，辅助代码
         const char *mangledName  = cls->mangledName();
         const char *PersonName = "Person";

         if (strcmp(mangledName, PersonName) == 0) {
             auto kc_ro = (const class_ro_t *)cls->data();
             printf("_getObjc2NonlazyClassList: 这个是我要研究的 %s \n", PersonName);
         }
         **/
      
        if (!cls) continue;

        addClassTableEntry(cls);//插入表，但是前面已经插入过了，所以不会重新插入

        if (cls->isSwiftStable()) {
            if (cls->swiftMetadataInitializer()) {
                _objc_fatal("Swift class %s with a metadata initializer "
                            "is not allowed to be non-lazy",
                            cls->nameForLogging());
            }
            // fixme also disallow relocatable classes
            // We can't disallow all Swift classes because of
            // classes like Swift.__EmptyArrayStorage
        }
        //实现当前的类，因为前面readClass读取到内存的仅仅只有地址+名称，类的data数据并没有加载出来
        //实现所有非懒加载的类(实例化类对象的一些信息，例如rw)
        realizeClassWithoutSwift(cls, nil);
    }
}
```

非懒加载类的加载流程：

- `_getObjc2NonlazyClassList`获取Mach-O的静态段`__objc_nlclslist`非懒加载类表
- `addClassTableEntry`再加载一遍——如果已添加就不会添加进去，确保整个结构都被添加
- `realizeClassWithoutSwift`实现当前的类，加载类的`data`数据，在**类的重映射**中`readClass`只加载`地址+类名`

##### 没有被处理的类，优化那些被侵犯的类

主要是实现没有被处理的类，优化被侵犯的类

```c++
// Realize newly-resolved future classes, in case CF manipulates them
if (resolvedFutureClasses) {
    for (i = 0; i < resolvedFutureClassCount; i++) {
        Class cls = resolvedFutureClasses[i];
        if (cls->isSwiftStable()) {
            _objc_fatal("Swift class is not allowed to be future");
        }
        //实现类
        realizeClassWithoutSwift(cls, nil);
        cls->setInstancesRequireRawIsaRecursively(false/*inherited*/);
    }
    free(resolvedFutureClasses);
}

ts.log("IMAGE TIMES: realize future classes");

if (DebugNonFragileIvars) {
    //实现所有类
    realizeAllClasses();
}
```

### readClass

在执行`readClass`之前，`cls`只是一个地址，而经过该函数，`cls`则成为了一个类的名称，那么 `realClass` 具体是做了什么

```c++
Class readClass(Class cls, bool headerIsBundle, bool headerIsPreoptimized)
{
    const char *mangledName = cls->mangledName();
    // 当前类的父类中存在丢失的 weak-linked 类
    if (missingWeakSuperclass(cls)) {
        // No superclass (probably weak-linked). 
        // Disavow any knowledge of this subclass.
        if (PrintConnecting) {
            _objc_inform("CLASS: IGNORING class '%s' with "
                         "missing weak-linked superclass", 
                         cls->nameForLogging());
        }
        addRemappedClass(cls, nil);
        cls->superclass = nil;
        return nil;
    }
    
    cls->fixupBackwardDeployingStableSwift();

    Class replacing = nil;
    if (Class newCls = popFutureNamedClass(mangledName)) {
        // This name was previously allocated as a future class.
        // Copy objc_class to future class's struct.
        // Preserve future's rw data block.
        
        if (newCls->isAnySwift()) {
            _objc_fatal("Can't complete future class request for '%s' "
                        "because the real class is too big.", 
                        cls->nameForLogging());
        }
        
        class_rw_t *rw = newCls->data();
        const class_ro_t *old_ro = rw->ro();
        memcpy(newCls, cls, sizeof(objc_class));
        rw->set_ro((class_ro_t *)newCls->data());
        newCls->setData(rw);
        freeIfMutable((char *)old_ro->name);
        free((void *)old_ro);
        
        addRemappedClass(cls, newCls);
        
        replacing = cls;
        cls = newCls;
    }
    
    if (headerIsPreoptimized  &&  !replacing) {
        // class list built in shared cache
        // fixme strict assert doesn't work because of duplicates
        // ASSERT(cls == getClass(name));
        ASSERT(getClassExceptSomeSwift(mangledName));
    } else {
        addNamedClass(cls, mangledName, replacing);
        addClassTableEntry(cls);
    }

    // for future reference: shared cache never contains MH_BUNDLEs
    if (headerIsBundle) {
        cls->data()->flags |= RO_FROM_BUNDLE;
        cls->ISA()->data()->flags |= RO_FROM_BUNDLE;
    }
    
    return cls;
}
```

- 当前类的父类中存在丢失的 `weak-linked` 类，则返回 `nil`

- 通常情况下，是不会进入`popFutureNamedClass(mangledName)`判断，这是专门针对未来的待处理的类的特殊操作

- `addNamedClass`：将当前类添加到已创建的`gdb_objc_realized_classes`哈希表（存储类）

  ```c++
  static void addNamedClass(Class cls, const char *name, Class replacing = nil)
  {
      runtimeLock.assertLocked();
      Class old;
      if ((old = getClassExceptSomeSwift(name))  &&  old != replacing) {
          inform_duplicate(name, old, cls);
  
          // getMaybeUnrealizedNonMetaClass uses name lookups.
          // Classes not found by name lookup must be in the
          // secondary meta->nonmeta table.
          addNonMetaClass(cls);
      } else {
          NXMapInsert(gdb_objc_realized_classes, name, cls);
      }
      ASSERT(!(cls->data()->flags & RO_META));
  
      // wrong: constructed classes are already realized when they get here
      // ASSERT(!cls->isRealized());
  }
  ```

- `addClassTableEntry`：当前类已经初始化，所以要添加到`allocatedClasses`哈希表（runtime_init函数中初始化）

  ```c++
  static void
  addClassTableEntry(Class cls, bool addMeta = true)
  {
      runtimeLock.assertLocked();
  
      // This class is allowed to be a known class via the shared cache or via
      // data segments, but it is not allowed to be in the dynamic table already.
      auto &set = objc::allocatedClasses.get();
  
      ASSERT(set.find(cls) == set.end());
  
      if (!isKnownClass(cls))
          set.insert(cls);
      if (addMeta)
          addClassTableEntry(cls->ISA(), false);
  }
  ```

通过 `readClass` 函数，将 Mach-O 中的类读取到内存中，也就是插入相应的哈希表，但是只保存两个信息：地址和名词，并没有读取并加载`data`数据

### realizeClassWithoutSwift

这个函数是类加载`data`数据的核心所在，主要包含几个操作：

- 读取`data`数据，设置`ro、rw`
- 递归调用`realizeClassWithoutSwift`完善`类的继承链`
- 调用`methodizeClass`，完善类信息（方法、分类的方法、属性列表、协议列表）

#### 读取data数据

读取类的`data`数据，并强转为`ro`，然后初始化`rw`，将`ro`拷贝一份到`rw`中的`ro`


> 关于 `ro` 和 `rw` 结构，可以在[『iOS底层原理探索-类的结构分析』](/Class-structure)查看

- `ro`表示readOnly，是在编译时就已经确定了内存
- `rw`表示`readWrite`，由于其动态性，可能会往类中添加属性、方法、添加协议

> 在**WWDC 2020**中对内存优化的说明：[Advancements in the Objective-C runtime - WWDC 2020 - Videos - Apple Developer](https://links.jianshu.com/go?to=https%3A%2F%2Fdeveloper.apple.com%2Fvideos%2Fplay%2Fwwdc2020%2F10163%2F)
>
> 由于 `rw` 是存储运行时产生的数据，但并不是所有的类都会在运行时修改。因此，在`class_rw_t` 加入 `class_rw_ext_t`结构，当需要时，才会分配内存
>
> 所以，`rw`属于`dirty memory`，`ro`属于`clean memory`


```c++
// fixme verify class is not in an un-dlopened part of the shared cache?
// ro -- clean memory，在编译时就已经确定了内存
auto ro = (const class_ro_t *)cls->data(); //读取类结构的bits属性
auto isMeta = ro->flags & RO_META; //判断元类
if (ro->flags & RO_FUTURE) {
    // This was a future class. rw data is already allocated.
    rw = cls->data(); //dirty memory 进行赋值
    ro = cls->data()->ro();
    ASSERT(!isMeta);
    cls->changeInfo(RW_REALIZED|RW_REALIZING, RW_FUTURE);
} else { 
    // 此时将数据读取进来了，也赋值完毕了
    // Normal class. Allocate writeable class data.
    rw = objc::zalloc<class_rw_t>(); // 申请开辟zalloc -- rw
    rw->set_ro(ro);// rw中的ro设置为临时变量ro
    rw->flags = RW_REALIZED|RW_REALIZING|isMeta;
    cls->setData(rw);// 将cls的data赋值为rw形式
}
```

#### 递归调用realizeClassWithoutSwift

递归调用`realizeClassWithoutSwift`完善类的继承链，并处理当前类、父类、元类

```c++
if (!cls) return nil;
if (cls->isRealized()) return cls;
...
supercls = realizeClassWithoutSwift(remapClass(cls->superclass));
metacls = realizeClassWithoutSwift(remapClass(cls->ISA()));
...
// Update superclass and metaclass in case of remapping
cls->superclass = supercls;
cls->initClassIsa(metacls);
...
// Connect this class to its superclass's subclass lists
if (supercls) {
    addSubclass(supercls, cls);
} else {
    addRootClass(cls);
}
```

- `realizeClassWithoutSwift`递归调用，当 isa 找到根元类之后，根元类的 isa 是指向自己，并不会返回 nil

  - 如果类不存在，则返回 nil
  - 如果类已经实现，则直接返回

- 如果有父类，调用`addSubclass`将当前类添加为父类的子类

  ```c++
  static void addSubclass(Class supercls, Class subcls)
  {
      runtimeLock.assertLocked();
  
      if (supercls  &&  subcls) {
          ASSERT(supercls->isRealized());
          ASSERT(subcls->isRealized());
  
          objc_debug_realized_class_generation_count++;
          
          subcls->data()->nextSiblingClass = supercls->data()->firstSubclass;
          supercls->data()->firstSubclass = subcls;
          
          ...
      }
  }
  ```

#### 调用methodizeClass

```c++
static void methodizeClass(Class cls, Class previously)
{
    runtimeLock.assertLocked();

    bool isMeta = cls->isMetaClass();
    auto rw = cls->data(); // 初始化一个rw
    auto ro = rw->ro();
    auto rwe = rw->ext();
    
    ...

    // Install methods and properties that the class implements itself.
    // 添加方法
    method_list_t *list = ro->baseMethods();//获取ro的baseMethods
    if (list) {
        prepareMethodLists(cls, &list, 1, YES, isBundleClass(cls));//methods进行排序
        if (rwe) rwe->methods.attachLists(&list, 1);//对rwe进行处理
    }
    // 加入属性
    property_list_t *proplist = ro->baseProperties;
    if (rwe && proplist) {
        rwe->properties.attachLists(&proplist, 1);
    }
    // 加入协议
    protocol_list_t *protolist = ro->baseProtocols;
    if (rwe && protolist) {
        rwe->protocols.attachLists(&protolist, 1);
    }

    // Root classes get bonus method implementations if they don't have 
    // them already. These apply before category replacements.
    if (cls->isRootMetaclass()) {
        // root metaclass
        addMethod(cls, @selector(initialize), (IMP)&objc_noop_imp, "", NO);
    }

    // Attach categories.
    // 加入分类中的方法
    if (previously) {
        if (isMeta) {
            objc::unattachedCategories.attachToClass(cls, previously,
                                                     ATTACH_METACLASS);
        } else {
            // When a class relocates, categories with class methods
            // may be registered on the class itself rather than on
            // the metaclass. Tell attachToClass to look for those.
            objc::unattachedCategories.attachToClass(cls, previously,
                                                     ATTACH_CLASS_AND_METACLASS);
        }
    }
    objc::unattachedCategories.attachToClass(cls, cls,
                                             isMeta ? ATTACH_METACLASS : ATTACH_CLASS);
    ....
}
```

根据源码，`methodizeClass`主要是从`ro`中读取`方法列表（包括分类）、属性列表、协议列表`赋值给`rw`

下面以添加方法列表为例

- 获取 `ro` 的 `baseMethodList`，即方法列表
- 调用`prepareMethodLists`对方法列表进行排序
- 调用`rwe`中`methods`的`attachLists`插入方法

**方法排序**

> 在慢速查找流程中，方法的查找是根据二分查找算法，即`SEL-IMP`存储是有序的
>
> 具体查找过程可在[『iOS底层原理探索-消息查找』](/message)查看

`prepareMethodLists`正是将从 `ro` 中读取到的方法列表进行排序，排序的关键函数是`fixupMethodList`，根据函数实现，不难发现排序的依据：`selector address`

```c++
static void 
prepareMethodLists(Class cls, method_list_t **addedLists, int addedCount,
                   bool baseMethods, bool methodsFromBundle)
{
    ...

    // Add method lists to array.
    // Reallocate un-fixed method lists.
    // The new methods are PREPENDED to the method list array.

    for (int i = 0; i < addedCount; i++) {
        method_list_t *mlist = addedLists[i];
        ASSERT(mlist);

        // Fixup selectors if necessary
        if (!mlist->isFixedUp()) {
            fixupMethodList(mlist, methodsFromBundle, true/*sort*/);//排序
        }
    }
    
    ...
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
```

**attachLists**

方法、属性、协议都是直接通过`attachLists`插入的，这是因为这三者的数据结构都是类似的，都是二维数组

```c++
struct method_list_t : entsize_list_tt<method_t, method_list_t, 0x3> 

struct property_list_t : entsize_list_tt<property_t, property_list_t, 0> 

struct protocol_list_t {
    // count is pointer-sized by accident.
    uintptr_t count;
    protocol_ref_t list[0]; // variable-size

    size_t byteSize() const {
        return sizeof(*this) + count*sizeof(list[0]);
    }

    protocol_list_t *duplicate() const {
        return (protocol_list_t *)memdup(this, this->byteSize());
    }
    ...
}
```

再来看一下具体插入操作

```c++
void attachLists(List* const * addedLists, uint32_t addedCount) {
    if (addedCount == 0) return;

    if (hasArray()) {
        // many lists -> many lists
        //计算数组中旧lists的大小
        uint32_t oldCount = array()->count;
        //计算新的容量大小 = 旧数据大小+新数据大小
        uint32_t newCount = oldCount + addedCount;
        //根据新的容量大小，开辟一个数组，类型是 array_t，通过array()获取
        setArray((array_t *)realloc(array(), array_t::byteSize(newCount)));
        //设置数组大小
        array()->count = newCount;
        //旧的数据从 addedCount 数组下标开始 存放旧的lists，大小为 旧数据大小 * 单个旧list大小
        memmove(array()->lists + addedCount, array()->lists, 
                oldCount * sizeof(array()->lists[0]));
        //新数据从数组 首位置开始存储，存放新的lists，大小为 新数据大小 * 单个list大小
        memcpy(
               array()->lists, addedLists, 
               addedCount * sizeof(array()->lists[0]));
    }
    else if (!list  &&  addedCount == 1) {
        // 0 lists -> 1 list
        list = addedLists[0];//将list加入mlists的第一个元素，此时的list是一个一维数组
    } 
    else {
        // 1 list -> many lists 有了一个list，有往里加很多list
        //获取旧的list
        List* oldList = list;
        uint32_t oldCount = oldList ? 1 : 0;
        //计算容量和 = 旧list个数+新lists的个数
        uint32_t newCount = oldCount + addedCount;
        //开辟一个容量和大小的集合，类型是 array_t，即创建一个数组，放到array中，通过array()获取
        setArray((array_t *)malloc(array_t::byteSize(newCount)));
        //设置数组的大小
        array()->count = newCount;
        //判断old是否存在，old肯定是存在的，将旧的list放入到数组的末尾
        if (oldList) array()->lists[addedCount] = oldList;
        // memcpy（开始位置，放什么，放多大） 是内存平移，从数组起始位置存入新的list
        //其中array()->lists 表示首位元素位置
        memcpy(array()->lists, addedLists, 
               addedCount * sizeof(array()->lists[0]));
    }
}
```

不难看出，分为三种情况：

- （多对多）：如果当前调用`attachLists`的`list_array_tt`二维数组中有多个一维数组
  - 计算原来的容量，即`oldCount`
  - 计算新的容量 = `oldCount` + `addedCount`
  - `realloc`对容器进行重新分配大小
  - 通过`memmove`将原来的数据移动至容器的末尾
  - 将新的数据`memcpy`拷贝到容器的起始位置
- （零多一）：如果调用`attachLists`的`list_array_tt`二维数组为空且新增大小数目为 1
  - 直接赋值`attachLists`的第一个`list`
- （一对多）：如果当前调用`attachLists`的`list_array_tt`二维数组只有一个一维数组
  - 获取旧的list
  - 计算新的容量 = `oldCount` + `addedCount`
  - `malloc`开辟新的内存，大小为新的容量和
  - 直接将`旧lists`赋值到`新array()`最后一个位置
  - 把新的数据`memcpy`拷贝到容器的起始位置

> `memmove`和`memcpy`的区别在于：
>
> - 在不知道需要平移的内存大小时，需要`memmove`进行内存平移，保证安全
> - `memcpy`从原内存地址的起始位置开始拷贝若干个字节到目标内存地址中，速度快

**关于 `rwe` 的说明**

首先，在`realizeClassWithoutSwift`中通过`rw->set_ro(ro)`为 `rwe` 的 `ro`赋值，因此 `rwe` 是已经存在的

所以，在执行`attachLists`时

- 此时的 `rwe` 的 `methods` 没有数据，也就是 `0 对 1` 流程
- 当`加入一个分类`时，此时 `rwe` 中的 `methods` 只有一个 `list`，也就是 `1 对多` 流程
- 再`加入一个分类`时，此时 `rwe` 中的 `methods` 有两个 `list`，也就是 `多对多` 流程

#### 懒加载类

上面的加载过程，主要是非懒加载的类，那么对于懒加载呢，也就是`+load`没有实现的类

既然是懒加载，那么只有在使用时才会加入到内存中，而调用懒加载类，也就是向其发生消息，回顾之前`lookUpImpOrForward`函数

```c++
IMP lookUpImpOrForward(Class cls, SEL sel, id inst, 
                       bool initialize, bool cache, bool resolver)
{
    ...
    if (!cls->isRealized()) {
        cls = realizeClassMaybeSwiftAndLeaveLocked(cls, runtimeLock);
        // runtimeLock may have been dropped but is now locked again
    }
    ...
}

static Class
realizeClassMaybeSwiftAndLeaveLocked(Class cls, mutex_t& lock)
{
    return realizeClassMaybeSwiftMaybeRelock(cls, lock, true);
}

static Class
realizeClassMaybeSwiftMaybeRelock(Class cls, mutex_t& lock, bool leaveLocked)
{
    lock.assertLocked();

    if (!cls->isSwiftStable_ButAllowLegacyForNow()) {
        // Non-Swift class. Realize it now with the lock still held.
        // fixme wrong in the future for objc subclasses of swift classes
        realizeClassWithoutSwift(cls, nil);
        if (!leaveLocked) lock.unlock();
    } else {
        // Swift class. We need to drop locks and call the Swift
        // runtime to initialize it.
        lock.unlock();
        cls = realizeSwiftClass(cls);
        ASSERT(cls->isRealized());    // callback must have provoked realization
        if (leaveLocked) lock.lock();
    }

    return cls;
}
```

对于懒加载类，会在首次发送消息时，整个函数调用栈为：`lookUpImpOrForward` -> `realizeClassMaybeSwiftAndLeaveLocked` -> `realizeClassMaybeSwiftMaybeRelock` -> `realizeClassWithoutSwift`

没错，最终也是会来到`realizeClassWithoutSwift`进行类的加载

### 总结

**非懒加载类**

从 **dyld 加载**到**_objc_init()**，完善了类加载的前期准备工作，而进入 `realizeClassWithoutSwift` 才去进行类的加载

在`_read_images`函数中，两个关键函数`readClass`和`realizeClassWithoutSwift`

- `readClass`：读取类，将类的地址与名称，进行重映射
- `realizeClassWithoutSwift`：完善类信息，将类的方法、属性、协议等数据加载到内存中
  - `methodizeClass`：对类的方法列表排序，并加载到内存
  - `attachCategories`：分类的数据加载，再后续篇章中分析

**懒加载类**

类的加载推迟到第一次发生消息的时候，最终也是调用`realizeClassWithoutSwift`

