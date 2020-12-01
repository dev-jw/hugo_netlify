---
title: "iOS底层原理探索-类的加载"
date: 2020-10-13T14:21:19+08:00
draft: true
tags: ["iOS"]
url:  "class-load"
---

在『[iOS底层原理探索-dyld加载流程](/dyld-load)』中，介绍了 App 启动时刻的一些操作。

那么关于类的加载具体是在什么时候呢？同样的，以下几个问题会帮助对本文的理解：

- `_objc_init`具体做了什么
- 类的加载过程——非懒加载
- 类的加载过程——懒加载

### _objc_init

**源码**

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

逐行分析

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

这里列了所有的[环境变量](/#)，当然也可以通过终端输入`export OBJC_HELP=1`查看 

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

初始化 libobjc 的异常处理系统，注册异常处理的回调，从而监控异常的处理

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



#### _imp_implementationWithBlock_init()

SHA256:EsHut8ICgitgX5OqGbBDkyaMnclO0mYMqq8YgWRFbcE

#### _dyld_objc_notify_register



### map_images



#### _read_images



`realizeClassWithoutSwift`

