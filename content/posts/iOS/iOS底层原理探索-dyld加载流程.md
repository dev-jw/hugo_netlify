---
title: "iOS底层原理探索-dyld加载流程"
date: 2020-09-25T21:51:41+08:00
draft: false
tags: ["iOS"]
url:  "dyld-load"
---

我们都知道程序的入口函数是 `main.m` 文件里的 `main函数`，但这并不是一个 App 的生命起点，在进入 `main函数`之前还进行了许多的操作，本文将对这些操作进行梳理

同样的，提出几个问题：

- 静态库与动态库的区别
- dyld 是什么
- dyld 加载过程

### 静态库与动态库

Objective-C 是动态语言，得益于特有的 **Runtime** 机制，同时，也是编译型语言，需要通过编译器将源代码编译成机器码，链接各个模块的机器码和依赖库，串联起来生成可执行文件`mach-o`

##### 编译过程

> 事实上，这个过程分解为4个步骤，分别是预处理(Prepressing)、编译(Compilation)、汇编(Assembly)和链接(Linking).------ 摘自《程序员的自我修养-- 链接、装载与库》

Xcode 通常帮我们做了以下几件事：

- 预编译：处理代码中的`#开头`的预编译指令，比如删除`#define`并展开宏定义，将`#include`包含的文件插入到该指令位置等
- 编译：对预编译处理过的文件进行词法分析、语法分析和语义分析，并进行源代码优化，然后生成汇编代码
- 汇编：通过汇编器将汇编代码转换为机器可以执行的指令，并生成目标文件`.o文件`
- 链接：将目标文件链接成可执行文件。这个过程中，链接器会将不同的目标文件链接起来，因为目标文件需要依赖别的框架，比如经常调用 Foundation 框架和 UIKit 框架

![编译过程](https://w-md.imzsy.design/编译过程.png)

> ```ruby
> `Foundation`和`UIKit`这种可以共享代码、实现代码的复用统称为`库`
> 
> 它是可执行代码的二进制文件，可以被操作系统写入内存，它又分为`静态库`和`动态库
> ```

##### 静态库

`静态库`是指在链接生成可执行文件时，从这个单独的文件中『拷贝』它自己需要的内容到最终的可执行文件中，如`.a、.lib`都是静态库

##### 动态库

`动态库`是指在链接时不拷贝到可执行文件中，而是程序运行时由系统加在到内存中，供系统调用，系统只需加载一次，多次使用，共用节省内存。

如`.dylib`、`.framework`都是动态库

> **系统的framework是动态的，开发者创建的framework是静态的**

### dyld

**dyld简介**

`dyld(The dynamic link editor)`是苹果的动态链接器，负责程序的链接及加载工作，是苹果操作系统的重要组成部分，存在于MacOS系统的`(/usr/lib/dyld)`目录下。

在应用被编译打包成可执行文件格式的`Mach-O`文件之后 ，交由`dyld`负责链接，加载程序

**dyld_shared_cache**

由于不止一个程序需要使用`UIKit`系统动态库，所以不可能在每个程序加载时都去加载所有的系统动态库。

为了优化程序启动速度和利用动态库缓存，苹果从`iOS3.1`之后，将所有系统库（私有与公有）编译成一个大的缓存文件，这就是`dyld_shared_cache`，该缓存文件存在iOS系统下的`/System/Library/Caches/com.apple.dyld/`目录下

### dyld加载流程

分别在 `main函数`和 ViewController 的`+load`函数打断点，看一下断点进入位置，以及调用堆栈

可以发现，断点会先进入到`+load函数`，并且堆栈如下：

```ruby
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
  * frame #0: 0x0000000101d4aaec NSProxyTest`+[ViewController load](self=ViewController, _cmd="load") at ViewController.m:18:1
    frame #1: 0x00007fff201805e3 libobjc.A.dylib`load_images + 1442
    frame #2: 0x0000000101d63e54 dyld_sim`dyld::notifySingle(dyld_image_states, ImageLoader const*, ImageLoader::InitializerTimingList*) + 425
    frame #3: 0x0000000101d72887 dyld_sim`ImageLoader::recursiveInitialization(ImageLoader::LinkContext const&, unsigned int, char const*, ImageLoader::InitializerTimingList&, ImageLoader::UninitedUpwards&) + 437
    frame #4: 0x0000000101d70bb0 dyld_sim`ImageLoader::processInitializers(ImageLoader::LinkContext const&, unsigned int, ImageLoader::InitializerTimingList&, ImageLoader::UninitedUpwards&) + 188
    frame #5: 0x0000000101d70c50 dyld_sim`ImageLoader::runInitializers(ImageLoader::LinkContext const&, ImageLoader::InitializerTimingList&) + 82
    frame #6: 0x0000000101d642a9 dyld_sim`dyld::initializeMainExecutable() + 199
    frame #7: 0x0000000101d68d50 dyld_sim`dyld::_main(macho_header const*, unsigned long, int, char const**, char const**, char const**, unsigned long*) + 4431
    frame #8: 0x0000000101d631c7 dyld_sim`start_sim + 122
    frame #9: 0x0000000110dc285c dyld`dyld::useSimulatorDyld(int, macho_header const*, char const*, int, char const**, char const**, char const**, unsigned long*, unsigned long*) + 2308
    frame #10: 0x0000000110dc04f4 dyld`dyld::_main(macho_header const*, unsigned long, int, char const**, char const**, char const**, unsigned long*) + 837
    frame #11: 0x0000000110dbb227 dyld`dyldbootstrap::start(dyld3::MachOLoaded const*, int, char const**, dyld3::MachOLoaded const*, unsigned long*) + 453
    frame #12: 0x0000000110dbb025 dyld`_dyld_start + 37
```

可以看出，首先调用 `dyld` 中的 `_dyld_start` 函数，再接着调用`dyldbootstrap::start()`函数

这里需要借助 [dyld源码](https://opensource.apple.com/tarballs/dyld/)来查看函数的具体实现

#### _dyld_start

通过搜索`_dyld_start`，可以发现是在`dyldStartup.s`汇编文件内，从汇编注释可以看到会去调用`dyldbootstrap::start()`函数

![_dyld_start](https://w-md.imzsy.design/_dyld_start.png)

#### dyldbootstrap::start()

```c++
uintptr_t start(const struct macho_header* appsMachHeader, int argc, const char* argv[], 
				intptr_t slide, const struct macho_header* dyldsMachHeader,
				uintptr_t* startGlue)
{
	// if kernel had to slide dyld, we need to fix up load sensitive locations
	// we have to do this before using any global variables
    // 获取 slide
    slide = slideOfMainExecutable(dyldsMachHeader);
    bool shouldRebase = slide != 0;
#if __has_feature(ptrauth_calls)
    shouldRebase = true;
#endif
    if ( shouldRebase ) {
        // 根据 slide 确定是否 rebase
        rebaseDyld(dyldsMachHeader, slide);
    }

	// allow dyld to use mach messaging
    // 初始化 mach 消息
	mach_init();

	// kernel sets up env pointer to be just past end of agv array
	const char** envp = &argv[argc+1];
	
	// kernel sets up apple pointer to be just past end of envp array
	const char** apple = envp;
	while(*apple != NULL) { ++apple; }
	++apple;

	// set up random value for stack canary
    // 保护栈溢出
	__guard_setup(apple);

#if DYLD_INITIALIZER_SUPPORT
	// run all C++ initializers inside dyld
	runDyldInitializers(dyldsMachHeader, slide, argc, argv, envp, apple);
#endif

	// now that we are done bootstrapping dyld, call dyld's main
    // 完成引导，调用 dyld::main 函数
    // appsSlide 获取偏移值，传给 main 函数
	uintptr_t appsSlide = slideOfMainExecutable(appsMachHeader);
	return dyld::_main(appsMachHeader, appsSlide, argc, argv, envp, apple, startGlue);
}
```

在这里主要做了四个操作

- 根据 `dyldsMachHeader` 计算出 `slide`，通过 `slide` 判断是否需要重定位；

  `slide` 是根据 `ASLR技术` 计算出的一个随机值，使程序每一次运行的偏移值都不一样，防止攻击者通过固定地址发起恶意攻击

- `mach_init()`初始化（允许 dyld 使用 mach 消息传递）

- 栈溢出保护

- 计算 `appsMachHeader` 的偏移，调用 `dyld::main()` 函数

#### dyld::main()

内核加载 `dyld` 并跳转到 `__dyld_start` 设置一些寄存器信息之后，会调用此函数。

`dyld::main()` 函数实现是加载 `dyld` 的主要步骤 

```c++
uintptr_t
_main(const macho_header* mainExecutableMH, uintptr_t mainExecutableSlide, 
        int argc, const char* argv[], const char* envp[], const char* apple[], 
        uintptr_t* startGlue)
{
    // Grab the cdHash of the main executable from the environment
    // 第一步，设置运行环境
    uint8_t mainExecutableCDHashBuffer[20];
    const uint8_t* mainExecutableCDHash = nullptr;
    if ( hexToBytes(_simple_getenv(apple, "executable_cdhash"), 40, mainExecutableCDHashBuffer) )
        // 获取主程序的hash
        mainExecutableCDHash = mainExecutableCDHashBuffer;
    // Trace dyld's load
    notifyKernelAboutImage((macho_header*)&__dso_handle, _simple_getenv(apple, "dyld_file"));
#if !TARGET_IPHONE_SIMULATOR
    // Trace the main executable's load
    notifyKernelAboutImage(mainExecutableMH, _simple_getenv(apple, "executable_file"));
#endif
    uintptr_t result = 0;
    // 获取主程序的macho_header结构
    sMainExecutableMachHeader = mainExecutableMH;
    // 获取主程序的slide值
    sMainExecutableSlide = mainExecutableSlide;
    CRSetCrashLogMessage("dyld: launch started");
    // 设置上下文信息
    setContext(mainExecutableMH, argc, argv, envp, apple);
    // Pickup the pointer to the exec path.
    // 获取主程序路径
    sExecPath = _simple_getenv(apple, "executable_path");
    // <rdar://problem/13868260> Remove interim apple[0] transition code from dyld
    if (!sExecPath) sExecPath = apple[0];
    if ( sExecPath[0] != '/' ) {
        // have relative path, use cwd to make absolute
        char cwdbuff[MAXPATHLEN];
        if ( getcwd(cwdbuff, MAXPATHLEN) != NULL ) {
            // maybe use static buffer to avoid calling malloc so early...
            char* s = new char[strlen(cwdbuff) + strlen(sExecPath) + 2];
            strcpy(s, cwdbuff);
            strcat(s, "/");
            strcat(s, sExecPath);
            sExecPath = s;
        }
    }
    // Remember short name of process for later logging
    // 获取进程名称
    sExecShortName = ::strrchr(sExecPath, '/');
    if ( sExecShortName != NULL )
        ++sExecShortName;
    else
        sExecShortName = sExecPath;
    
    // 配置进程受限模式
    configureProcessRestrictions(mainExecutableMH);
    // 检测环境变量
    checkEnvironmentVariables(envp);
    defaultUninitializedFallbackPaths(envp);
    // 如果设置了DYLD_PRINT_OPTS则调用printOptions()打印参数
    if ( sEnv.DYLD_PRINT_OPTS )
        printOptions(argv);
    // 如果设置了DYLD_PRINT_ENV则调用printEnvironmentVariables()打印环境变量
    if ( sEnv.DYLD_PRINT_ENV ) 
        printEnvironmentVariables(envp);
    // 获取当前程序架构
    getHostInfo(mainExecutableMH, mainExecutableSlide);
    //-------------第一步结束-------------
    
    // load shared cache
    // 第二步，加载共享缓存
    // 检查共享缓存是否开启，iOS必须开启
    checkSharedRegionDisable((mach_header*)mainExecutableMH);
    if ( gLinkContext.sharedRegionMode != ImageLoader::kDontUseSharedRegion ) {
        mapSharedCache();
    }
    ...
    try {
        // add dyld itself to UUID list
        addDyldImageToUUIDList();
        // instantiate ImageLoader for main executable
        // 第三步 实例化主程序
        sMainExecutable = instantiateFromLoadedImage(mainExecutableMH, mainExecutableSlide, sExecPath);
        gLinkContext.mainExecutable = sMainExecutable;
        gLinkContext.mainExecutableCodeSigned = hasCodeSignatureLoadCommand(mainExecutableMH);
        // Now that shared cache is loaded, setup an versioned dylib overrides
    #if SUPPORT_VERSIONED_PATHS
        checkVersionedPaths();
    #endif
        // dyld_all_image_infos image list does not contain dyld
        // add it as dyldPath field in dyld_all_image_infos
        // for simulator, dyld_sim is in image list, need host dyld added
#if TARGET_IPHONE_SIMULATOR
        // get path of host dyld from table of syscall vectors in host dyld
        void* addressInDyld = gSyscallHelpers;
#else
        // get path of dyld itself
        void*  addressInDyld = (void*)&__dso_handle;
#endif
        char dyldPathBuffer[MAXPATHLEN+1];
        int len = proc_regionfilename(getpid(), (uint64_t)(long)addressInDyld, dyldPathBuffer, MAXPATHLEN);
        if ( len > 0 ) {
            dyldPathBuffer[len] = '\0'; // proc_regionfilename() does not zero terminate returned string
            if ( strcmp(dyldPathBuffer, gProcessInfo->dyldPath) != 0 )
                gProcessInfo->dyldPath = strdup(dyldPathBuffer);
        }
        // load any inserted libraries
        // 第四步 加载插入的动态库
        if  ( sEnv.DYLD_INSERT_LIBRARIES != NULL ) {
            for (const char* const* lib = sEnv.DYLD_INSERT_LIBRARIES; *lib != NULL; ++lib)
                loadInsertedDylib(*lib);
        }
        // record count of inserted libraries so that a flat search will look at 
        // inserted libraries, then main, then others.
        // 记录插入的动态库数量
        sInsertedDylibCount = sAllImages.size()-1;
        // link main executable
        // 第五步 链接主程序
        gLinkContext.linkingMainExecutable = true;
#if SUPPORT_ACCELERATE_TABLES
        if ( mainExcutableAlreadyRebased ) {
            // previous link() on main executable has already adjusted its internal pointers for ASLR
            // work around that by rebasing by inverse amount
            sMainExecutable->rebase(gLinkContext, -mainExecutableSlide);
        }
#endif
        link(sMainExecutable, sEnv.DYLD_BIND_AT_LAUNCH, true, ImageLoader::RPathChain(NULL, NULL), -1);
        sMainExecutable->setNeverUnloadRecursive();
        if ( sMainExecutable->forceFlat() ) {
            gLinkContext.bindFlat = true;
            gLinkContext.prebindUsage = ImageLoader::kUseNoPrebinding;
        }
        // link any inserted libraries
        // do this after linking main executable so that any dylibs pulled in by inserted 
        // dylibs (e.g. libSystem) will not be in front of dylibs the program uses
        // 第六步 链接插入的动态库
        if ( sInsertedDylibCount > 0 ) {
            for(unsigned int i=0; i < sInsertedDylibCount; ++i) {
                ImageLoader* image = sAllImages[i+1];
                link(image, sEnv.DYLD_BIND_AT_LAUNCH, true, ImageLoader::RPathChain(NULL, NULL), -1);
                image->setNeverUnloadRecursive();
            }
            // only INSERTED libraries can interpose
            // register interposing info after all inserted libraries are bound so chaining works
            for(unsigned int i=0; i < sInsertedDylibCount; ++i) {
                ImageLoader* image = sAllImages[i+1];
                image->registerInterposing();
            }
        }
        // <rdar://problem/19315404> dyld should support interposition even without DYLD_INSERT_LIBRARIES
        for (long i=sInsertedDylibCount+1; i < sAllImages.size(); ++i) {
            ImageLoader* image = sAllImages[i];
            if ( image->inSharedCache() )
                continue;
            image->registerInterposing();
        }
        ...
        // apply interposing to initial set of images
        for(int i=0; i < sImageRoots.size(); ++i) {
            sImageRoots[i]->applyInterposing(gLinkContext);
        }
        gLinkContext.linkingMainExecutable = false;
        
        // <rdar://problem/12186933> do weak binding only after all inserted images linked
        // 第七步 执行弱符号绑定
        sMainExecutable->weakBind(gLinkContext);
        // If cache has branch island dylibs, tell debugger about them
        if ( (sSharedCacheLoadInfo.loadAddress != NULL) && (sSharedCacheLoadInfo.loadAddress->header.mappingOffset >= 0x78) && (sSharedCacheLoadInfo.loadAddress->header.branchPoolsOffset != 0) ) {
            uint32_t count = sSharedCacheLoadInfo.loadAddress->header.branchPoolsCount;
            dyld_image_info info[count];
            const uint64_t* poolAddress = (uint64_t*)((char*)sSharedCacheLoadInfo.loadAddress + sSharedCacheLoadInfo.loadAddress->header.branchPoolsOffset);
            // <rdar://problem/20799203> empty branch pools can be in development cache
            if ( ((mach_header*)poolAddress)->magic == sMainExecutableMachHeader->magic ) {
                for (int poolIndex=0; poolIndex < count; ++poolIndex) {
                    uint64_t poolAddr = poolAddress[poolIndex] + sSharedCacheLoadInfo.slide;
                    info[poolIndex].imageLoadAddress = (mach_header*)(long)poolAddr;
                    info[poolIndex].imageFilePath = "dyld_shared_cache_branch_islands";
                    info[poolIndex].imageFileModDate = 0;
                }
                // add to all_images list
                addImagesToAllImages(count, info);
                // tell gdb about new branch island images
                gProcessInfo->notification(dyld_image_adding, count, info);
            }
        }
        CRSetCrashLogMessage("dyld: launch, running initializers");
        ...
        // run all initializers
        // 第八步 执行初始化方法
        initializeMainExecutable(); 
        // notify any montoring proccesses that this process is about to enter main()
        dyld3::kdebug_trace_dyld_signpost(DBG_DYLD_SIGNPOST_START_MAIN_DYLD2, 0, 0);
        notifyMonitoringDyldMain();
        // find entry point for main executable
        // 第九步 查找入口点并返回
        result = (uintptr_t)sMainExecutable->getThreadPC();
        if ( result != 0 ) {
            // main executable uses LC_MAIN, needs to return to glue in libdyld.dylib
            if ( (gLibSystemHelpers != NULL) && (gLibSystemHelpers->version >= 9) )
                *startGlue = (uintptr_t)gLibSystemHelpers->startGlueToCallExit;
            else
                halt("libdyld.dylib support not present for LC_MAIN");
        }
        else {
            // main executable uses LC_UNIXTHREAD, dyld needs to let "start" in program set up for main()
            result = (uintptr_t)sMainExecutable->getMain();
            *startGlue = 0;
        }
    }
    catch(const char* message) {
        syncAllImages();
        halt(message);
    }
    catch(...) {
        dyld::log("dyld: launch failed\n");
    }
    ...
    
    return result;
}
```

简化之后的代码，整个加载过程可细分为九个步骤

- 第一步：设置运行环境
- 第二步：加载共享缓存
- 第三步：实例化主程序
- 第四步：加载插入的动态库
- 第五步：链接主程序
- 第六步：链接插入的动态库
- 第七步：执行弱符号绑定
- 第八步：执行初始化方法
- 第九步：查找入口点并返回

##### 设置运行环境

这一步主要是设置运行参数、环境变量等。

代码在开始的时候，将入参 `mainExecutableMH` 赋值给 `sMainExecutableMachHeader`，这是一个 `macho_header` 结构体，表示的是当前主程序的 `Mach-O` 头部信息，加载器依据 `Mach-O` 头部信息就可以解析整个文件信息

接着调用 `setContext()` 设置上下文信息，包括一些回调函数、参数、标志信息等。

```c++
static void setContext(const macho_header* mainExecutableMH, int argc, const char* argv[], const char* envp[], const char* apple[])
{
   gLinkContext.loadLibrary         = &libraryLocator;
   gLinkContext.terminationRecorder = &terminationRecorder;
   ...
}
```

设置的回调函数都是 dyld 模块自身实现的，如 `loadLibrary()`函数实际调用的是 `libraryLocator()`，负责加载动态库

```c++
static void configureProcessRestrictions(const macho_header* mainExecutableMH)
{
    sEnvMode = envNone; // 受限模式
    gLinkContext.requireCodeSignature = true; // 需要代码签名
    uint32_t flags;
    if ( csops(0, CS_OPS_STATUS, &flags, sizeof(flags)) != -1 ) {
        // 启用代码签名
        if ( flags & CS_ENFORCEMENT ) {
            // get_task_allow
            if ( flags & CS_GET_TASK_ALLOW ) {
                // Xcode built app for Debug allowed to use DYLD_* variables
                // Xcode调试时允许使用DYLD_*环境变量
                sEnvMode = envAll; // 非受限模式
            }
            else {
                // Development kernel can use DYLD_PRINT_* variables on any FairPlay encrypted app
                uint32_t secureValue = 0;
                size_t   secureValueSize = sizeof(secureValue);
                if ( (sysctlbyname("kern.secure_kernel", &secureValue, &secureValueSize, NULL, 0) == 0) && (secureValue == 0) && isFairPlayEncrypted(mainExecutableMH) ) {
                    sEnvMode = envPrintOnly;
                }
            }
        }
        else {
            // Development kernel can run unsigned code
            // 内核开发运行运行非签名代码
            sEnvMode = envAll; // 非受限模式
            gLinkContext.requireCodeSignature = false; // 无需代码签名
        }
    }
    // 如果设置了uid、gid则变成受限模式
    if ( issetugid() ) {
        sEnvMode = envNone;
    }
}
```

`configureProcessRestrictions()`用来配置进程是否受限，代码逻辑比较简单，`sEnvMode`默认等于`envNone`（即受限模式）

- 如果设置了`get_task_allow`权限或者是内核开发时会设置成`envAll`

- 如果设置了`uid`和`gid`则立即变成受限模式

```c++
static void checkEnvironmentVariables(const char* envp[])
{
   if ( sEnvMode == envNone )
      return;
   const char** p;
   for(p = envp; *p != NULL; p++) {
      const char* keyEqualsValue = *p;
       if ( strncmp(keyEqualsValue, "DYLD_", 5) == 0 ) {
         const char* equals = strchr(keyEqualsValue, '=');
         if ( equals != NULL ) {
            strlcat(sLoadingCrashMessage, "\n", sizeof(sLoadingCrashMessage));
            strlcat(sLoadingCrashMessage, keyEqualsValue, sizeof(sLoadingCrashMessage));
            const char* value = &equals[1];
            const size_t keyLen = equals-keyEqualsValue;
            char key[keyLen+1];
            strncpy(key, keyEqualsValue, keyLen);
            key[keyLen] = '\0';
            if ( (sEnvMode == envPrintOnly) && (strncmp(key, "DYLD_PRINT_", 11) != 0) )
               continue;
            // 处理并设置环境变量
            processDyldEnvironmentVariable(key, value, NULL);
         }
      }
      else if ( strncmp(keyEqualsValue, "LD_LIBRARY_PATH=", 16) == 0 ) {
         const char* path = &keyEqualsValue[16];
         sEnv.LD_LIBRARY_PATH = parseColonList(path, NULL);
      }
   }
   ...
}
```

`checkEnvironmentVariables()`检测环境变量，如果`sEnvMode`为`envNone`就直接返回，否则调用`processDyldEnvironmentVariable()`处理并设置环境变量

最后是调用`getHostInfo()`获取当前程序架构，至此，第一步的准备工作就完成了

> `DYLD_*`开头的是环境变量，如：
>
> ```c++
> // 如果设置了DYLD_PRINT_OPTS则调用printOptions()打印参数
> if ( sEnv.DYLD_PRINT_OPTS )
>     printOptions(argv);
> // 如果设置了DYLD_PRINT_ENV则调用printEnvironmentVariables()打印环境变量
> if ( sEnv.DYLD_PRINT_ENV ) 
>     printEnvironmentVariables(envp);
> ```
>
> 只要在 Xcode 中配置一下，即可使这些环境变量生效，在 App 启动时就会打印相关参数

##### 加载共享缓存

先调用`checkSharedRegionDisable()`检查共享缓存是否禁用

该函数的iOS实现部分仅有一句注释，从注释我们可以推断iOS必须开启共享缓存才能正常工作

```c++
static void checkSharedRegionDisable(const mach_header* mainExecutableMH)
{
   // iOS cannot run without shared region
}
```

接着会调用`mapSharedCache()`加载共享缓存，而`mapSharedCache()`实际是调用 `loadDyldCache()`

```c++
bool loadDyldCache(const SharedCacheOptions& options, SharedCacheLoadInfo* results)
{
    results->loadAddress        = 0;
    results->slide              = 0;
    results->cachedDylibsGroup  = nullptr;
    results->errorMessage       = nullptr;
    if ( options.forcePrivate ) {
        // mmap cache into this process only
        // 仅加载到当前进程
        return mapCachePrivate(options, results);
    }
    else {
        // fast path: when cache is already mapped into shared region
        // 共享缓存已加载，不做任何处理
        if ( reuseExistingCache(options, results) )
            return (results->errorMessage != nullptr);
        // slow path: this is first process to load cache
        // 当前进程首次加载共享缓存
        return mapCacheSystemWide(options, results);
    }
}
```

从代码可以看出，共享缓存加载分为：

- 仅加载到当前进程，调用`mapCachePrivate()`
- 共享缓存已加载，不做任何处理
- 当前进行首次加载共享缓存，调用`mapCacheSystemWide()`

`mapCachePrivate()`、`mapCacheSystemWide()`里面就是具体的共享缓存解析逻辑，感兴趣的读者可以详细分析。

##### 实例化主程序

这里会将主程序的 `Mach-O` 加载到内存，并实例化一个 `ImageLoader` 对象

```c++
static ImageLoaderMachO* instantiateFromLoadedImage(const macho_header* mh, uintptr_t slide, const char* path)
{
  // try mach-o loader
  // 尝试加载MachO
  if ( isCompatibleMachO((const uint8_t*)mh, path) ) {
    ImageLoader* image = ImageLoaderMachO::instantiateMainExecutable(mh, slide, path, gLinkContext);
    addImage(image);
    return (ImageLoaderMachO*)image;
  }
  
  throw "main executable not a known format";
}
```

`instantiateFromLoadedImage()`首先调用`isCompatibleMachO()`检测 Mach-O 头部的 `magic`、`cputype`、`cpusubtype` 等相关属性，判断 Mach-O 文件的兼容性，如果兼容，则调用 `ImageLoaderMachO::instantiateMainExecutable()`实例化主程序的`ImageLoader`

```c++
ImageLoader* ImageLoaderMachO::instantiateMainExecutable(const macho_header* mh, uintptr_t slide, const char* path, const LinkContext& context)
{
  bool compressed;
  unsigned int segCount;
  unsigned int libCount;
  const linkedit_data_command* codeSigCmd;
  const encryption_info_command* encryptCmd;
  sniffLoadCommands(mh, path, false, &compressed, &segCount, &libCount, context, &codeSigCmd, &encryptCmd);
  // instantiate concrete class based on content of load commands
  if ( compressed ) 
    return ImageLoaderMachOCompressed::instantiateMainExecutable(mh, slide, path, segCount, libCount, context);
  else
#if SUPPORT_CLASSIC_MACHO
    return ImageLoaderMachOClassic::instantiateMainExecutable(mh, slide, path, segCount, libCount, context);
#else
    throw "missing LC_DYLD_INFO load command";
#endif
}
```

这个函数首先会调用`sniffLoadCommands()`函数来获取一些数据，包括：

- `compressed`：若 Mach-O 存在 `LC_DYLD_INFO` 和 `LC_DYLD_INFO_ONLY` 加载命令，则说明是压缩类型的 Mach-O

  ```c++
  switch (cmd->cmd) {
  case LC_DYLD_INFO:
  case LC_DYLD_INFO_ONLY:
      if ( cmd->cmdsize != sizeof(dyld_info_command) )
          throw "malformed mach-o image: LC_DYLD_INFO size wrong";
      dyldInfoCmd = (struct dyld_info_command*)cmd;
      // 存在LC_DYLD_INFO或者LC_DYLD_INFO_ONLY则表示是压缩类型的Mach-O
      *compressed = true;
      break;
      ...
  }
  ```

- `segCount`: 根据 `LC_SEGMENT_COMMAND` 加载命令来统计段数量，这里抛出的错误日志也说明了段的数量不能超过 255 个

  ```c++
  case LC_SEGMENT_COMMAND:
      segCmd = (struct macho_segment_command*)cmd;
  ...
      if ( segCmd->vmsize != 0 )
          *segCount += 1;
  if ( *segCount > 255 )
      dyld::throwf("malformed mach-o image: more than 255 segments in %s", path);
  ```

- `libCount`：根据`LC_LOAD_DYLIB`、`LC_LOAD_WEAK_DYLIB`、`LC_REEXPORT_DYLIB`、`LC_LOAD_UPWARD_DYLIB` 这几个加载命令来统计库的数量， 库的数量不能超过 4095 个

  ```c++
  case LC_LOAD_DYLIB:
  case LC_LOAD_WEAK_DYLIB:
  case LC_REEXPORT_DYLIB:
  case LC_LOAD_UPWARD_DYLIB:
  *libCount += 1;
  if ( *libCount > 4095 )
      dyld::throwf("malformed mach-o image: more than 4095 dependent libraries in %s", path);
  ```

- `codeSigCmd`：通过解析`LC_CODE_SIGNATURE`来获取代码签名加载命令

  ```c++
  case LC_CODE_SIGNATURE:
  *codeSigCmd = (struct linkedit_data_command*)cmd;
  break;
  ```

- `encryptCmd`：通过`LC_ENCRYPTION_INFO`和`LC_ENCRYPTION_INFO_64`来获取段的加密信息

  ```c++
  case LC_ENCRYPTION_INFO:
  ...
  *encryptCmd = (encryption_info_command*)cmd;
  break;
  case LC_ENCRYPTION_INFO_64:
  ...
  *encryptCmd = (encryption_info_command*)cmd;
  break;
  ```

`ImageLoader`是抽象类，其子类负责把 Mach-O 文件实例化为 image。

当`sniffLoadCommands()`解析完以后，根据`compressed`的值来觉得调用哪个子类进行实例化

这个过程，可以用下图来直观描述

![image-20201008175315434](https://w-md.imzsy.design/image-20201008175315434.png)

这里以`ImageLoaderMachOCompressed::instantiateMainExecutable()`为例来看一下实现

```c++
// create image for main executable
ImageLoaderMachOCompressed* ImageLoaderMachOCompressed::instantiateMainExecutable(const macho_header* mh, uintptr_t slide, const char* path, 
                                    unsigned int segCount, unsigned int libCount, const LinkContext& context)
{
  ImageLoaderMachOCompressed* image = ImageLoaderMachOCompressed::instantiateStart(mh, path, segCount, libCount);
  // set slide for PIE programs
  image->setSlide(slide);
  // for PIE record end of program, to know where to start loading dylibs
  if ( slide != 0 )
    fgNextPIEDylibAddress = (uintptr_t)image->getEnd();
  image->disableCoverageCheck();
  image->instantiateFinish(context);
  image->setMapped(context);
  if ( context.verboseMapping ) {
    dyld::log("dyld: Main executable mapped %s\n", path);
    for(unsigned int i=0, e=image->segmentCount(); i < e; ++i) {
      const char* name = image->segName(i);
      if ( (strcmp(name, "__PAGEZERO") == 0) || (strcmp(name, "__UNIXSTACK") == 0)  )
        dyld::log("%18s at 0x%08lX->0x%08lX\n", name, image->segPreferredLoadAddress(i), image->segPreferredLoadAddress(i)+image->segSize(i));
      else
        dyld::log("%18s at 0x%08lX->0x%08lX\n", name, image->segActualLoadAddress(i), image->segActualEndAddress(i));
    }
  }
  return image;
}
```

总结为 4 步：

- `ImageLoaderMachOCompressed::instantiateStart()`创建`ImageLoaderMachOCompressed`对象
- `image->disableCoverageCheck()`禁用段覆盖检测
- `image->instantiateFinish()`内部调用顺序：
  - 调用`parseLoadCmds()`解析加载命令，
  - 调用`this->setDyldInfo()`设置动态库链接信息，
  - 调用`this->setSymbolTableInfo()`设置符号表相关信息
- `image->setMapped()`函数注册通知回调、计算执行时间等等

在调用完`ImageLoaderMachO::instantiateMainExecutable()`后继续调用`addImage()`，将`image`加入到`sAllImages`全局镜像列表，并将`image`映射到申请的内存中

```c++
static void addImage(ImageLoader* image)
{
  // add to master list
    allImagesLock();
        sAllImages.push_back(image);
    allImagesUnlock();
  
  // update mapped ranges
  uintptr_t lastSegStart = 0;
  uintptr_t lastSegEnd = 0;
  for(unsigned int i=0, e=image->segmentCount(); i < e; ++i) {
    if ( image->segUnaccessible(i) ) 
      continue;
    uintptr_t start = image->segActualLoadAddress(i);
    uintptr_t end = image->segActualEndAddress(i);
    if ( start == lastSegEnd ) {
      // two segments are contiguous, just record combined segments
      lastSegEnd = end;
    }
    else {
      // non-contiguous segments, record last (if any)
      if ( lastSegEnd != 0 )
        addMappedRange(image, lastSegStart, lastSegEnd);
      lastSegStart = start;
      lastSegEnd = end;
    }   
  }
  if ( lastSegEnd != 0 )
    addMappedRange(image, lastSegStart, lastSegEnd);
  if ( gLinkContext.verboseLoading || (sEnv.DYLD_PRINT_LIBRARIES_POST_LAUNCH && (sMainExecutable!=NULL) && sMainExecutable->isLinked()) ) {
    dyld::log("dyld: loaded: %s\n", image->getPath());
  }
  
}
```

到这里，初始化主程序就完成了

##### 加载插入动态库

加载环境变量`DYLD_INSERT_LIBRARIES`中配置的动态库，先判断`DYLD_INSERT_LIBRARIES`中是否存在要加载的动态库，如果存在则调用 `loadInsertedDylib()` 函数依次加载

```c++
if  ( sEnv.DYLD_INSERT_LIBRARIES != NULL ) {
  for (const char* const* lib = sEnv.DYLD_INSERT_LIBRARIES; *lib != NULL; ++lib)
    loadInsertedDylib(*lib);
}
```

`loadInsertedDylib()`内部设置了一个 `LoadContext` 参数，调用了 `load()` 函数

```c++
ImageLoader* load(const char* path, const LoadContext& context, unsigned& cacheIndex)
{
    ...
    // try all path permutations and check against existing loaded images
    ImageLoader* image = loadPhase0(path, orgPath, context, cacheIndex, NULL);
    if ( image != NULL ) {
        CRSetCrashLogMessage2(NULL);
        return image;
    }
    // try all path permutations and try open() until first success
    std::vector<const char*> exceptions;
    image = loadPhase0(path, orgPath, context, cacheIndex, &exceptions);
#if !TARGET_IPHONE_SIMULATOR
    // <rdar://problem/16704628> support symlinks on disk to a path in dyld shared cache
    if ( image == NULL)
        image = loadPhase2cache(path, orgPath, context, cacheIndex, &exceptions);
#endif
    ...
}
```

`load()` 函数实现为一系列的`loadPhase*()`函数，`loadPhase0()`~`loadPhase1()`函数会按照下图顺序搜索动态库，并调用不同函数来继续处理

![image-20201008181008709](https://w-md.imzsy.design/image-20201008181008709.png)

当内部调用到`loadPhase5load()`函数的时候，会先在共享缓存中搜寻

- 存在则使用`ImageLoaderMachO::instantiateFromCache()`来实例化`ImageLoader`
- 不存在则通过`loadPhase5open()`打开文件并读取数据到内存后，再调用`loadPhase6()`，通过`ImageLoaderMachO::instantiateFromFile()`实例化`ImageLoader`，最后调用`checkandAddImage()`验证镜像并将其加入到全局镜像列表中

##### 链接主程序

调用 `link()`函数将实例化后的主程序进行动态修正，让二进制变为可正常执行的状态

`link()`函数内部调用了`ImageLoader::link()`函数

```c++
void ImageLoader::link(const LinkContext& context, bool forceLazysBound, bool preflightOnly, bool neverUnload, const RPathChain& loaderRPaths, const char* imagePath)
{
  ...
  uint64_t t0 = mach_absolute_time();
  // 递归加载加载主程序所需依赖库
  this->recursiveLoadLibraries(context, preflightOnly, loaderRPaths, imagePath);
  ...
  uint64_t t1 = mach_absolute_time();
  context.clearAllDepths();
  // 递归刷新依赖库的层级
  this->recursiveUpdateDepth(context.imageCount());
  uint64_t t2 = mach_absolute_time();
  // 递归进行rebase
  this->recursiveRebase(context);
  uint64_t t3 = mach_absolute_time();
  // 递归绑定符号表
  this->recursiveBind(context, forceLazysBound, neverUnload);
  uint64_t t4 = mach_absolute_time();
  if ( !context.linkingMainExecutable )
      // 弱符号绑定
      this->weakBind(context);
  uint64_t t5 = mach_absolute_time(); 
  context.notifyBatch(dyld_image_state_bound, false);
  uint64_t t6 = mach_absolute_time(); 
  std::vector<DOFInfo> dofs;
  // 注册DOF节
  this->recursiveGetDOFSections(context, dofs);
  context.registerDOFs(dofs);
  uint64_t t7 = mach_absolute_time(); 
  ...
}
```

主要做了以下几个事情：

- `recursiveLoadLibraries()` 根据`LC_LOAD_DYLIB`加载命令把所有依赖库加载进内存
- `recursiveUpdateDepth()` 递归刷新依赖库的层级
- `recursiveRebase()` 由于`ASLR`的存在，必须递归对主程序以及依赖库进行重定位操作
- `recursiveBind()` 把主程序二进制和依赖进来的动态库全部执行符号表绑定
- `weakBind()` 如果链接的不是主程序二进制的话，会在此时执行弱符号绑定，主程序二进制则在`link()`完后再执行弱符号绑定，后面会进行分析
- `recursiveGetDOFSections()`、`context.registerDOFs()` 注册`DOF`（DTrace Object Format）节

##### 链接插入的动态库

这一步和链接主程序一样，将前面调用`addImage()`函数保存在 `sAllImages` 中的动态库列表循环取出并调用`link()`进行链接

> `sAllImages`中保存的第一项是主程序的镜像，所以要从`i+1`的位置开始，取到的才是动态库的`ImageLoader`

```c++
ImageLoader* image = sAllImages[i+1];
```

循环调用每个镜像的`registerInterposing()`函数，该函数会遍历Mach-O的`LC_SEGMENT_COMMAND`加载命令，读取`__DATA`,`__interpose`，并将读取到的信息保存到`fgInterposingTuples`中，接着调用`applyInterposing()`函数，内部经由`doInterpose()`虚函数进行替换操作

这里以 `ImageLoaderMachOCompressed::doInterpose()` 函数为例：

内部分别调用`eachBind()` 和 `eachLazyBind()`，具体处理函数是`interposeAt()`，该函数调用`interposedAddress()`在`fgInterposingTuples`中查找需要替换的符号地址，进行最终的符号地址替换

```c++
void ImageLoaderMachOCompressed::doInterpose(const LinkContext& context)
{
    // update prebound symbols
    eachBind(context, &ImageLoaderMachOCompressed::interposeAt);
    eachLazyBind(context, &ImageLoaderMachOCompressed::interposeAt);
}
uintptr_t ImageLoaderMachOCompressed::interposeAt(const LinkContext& context, uintptr_t addr, uint8_t type, const char*, 
                                                uint8_t, intptr_t, long, const char*, LastLookup*, bool runResolver)
{
    if ( type == BIND_TYPE_POINTER ) {
        uintptr_t* fixupLocation = (uintptr_t*)addr;
        uintptr_t curValue = *fixupLocation;
        uintptr_t newValue = interposedAddress(context, curValue, this);
        if ( newValue != curValue) {
            *fixupLocation = newValue;
        }
    }
    return 0;
}
```

##### 执行弱符号绑定

`weakBind()`首先通过`getCoalescedImages()`合并所有动态库的弱符号到一个列表里，然后调用`initializeCoalIterator()`对需要绑定的弱符号进行排序，接着调用`incrementCoalIterator()`读取`dyld_info_command`结构的`weak_bind_off`和`weak_bind_size`字段，确定弱符号的数据偏移与大小，最终进行弱符号绑定，代码如下：

```c++
bool ImageLoaderMachOCompressed::incrementCoalIterator(CoalIterator& it)
{
    if ( it.done )
        return false;
    
    if ( this->fDyldInfo->weak_bind_size == 0 ) {
        /// hmmm, ld set MH_WEAK_DEFINES or MH_BINDS_TO_WEAK, but there is no weak binding info
        it.done = true;
        it.symbolName = "~~~";
        return true;
    }
    const uint8_t* start = fLinkEditBase + fDyldInfo->weak_bind_off;
    const uint8_t* p = start + it.curIndex;
    const uint8_t* end = fLinkEditBase + fDyldInfo->weak_bind_off + this->fDyldInfo->weak_bind_size;
    uintptr_t count;
    uintptr_t skip;
    uintptr_t segOffset;
    while ( p < end ) {
        uint8_t immediate = *p & BIND_IMMEDIATE_MASK;
        uint8_t opcode = *p & BIND_OPCODE_MASK;
        ++p;
        switch (opcode) {
            case BIND_OPCODE_DONE:
                it.done = true;
                it.curIndex = p - start;
                it.symbolName = "~~~"; // sorts to end
                return true;
        }
        break;
        ...
    }
    ...
    return true;
}
```

##### 执行初始化方法

这一步由`initializeMainExecutable()`完成，`dyld`会优先初始化动态库，然后初始化主程序

该函数首先执行`runInitializers()`，内部再依次调用`processInitializers()`、`recursiveInitialization()`

在`recursiveInitialization()`函数里找到了`notifySingle()`函数：

```c++
context.notifySingle(dyld_image_state_dependents_initialized, this, &timingInfo);
```

接着跟进`notifySingle`函数，看到下面处理代码：

```c++
if ( (state == dyld_image_state_dependents_initialized) && (sNotifyObjCInit != NULL) && image->notifyObjC() ) {
    uint64_t t0 = mach_absolute_time();
    (*sNotifyObjCInit)(image->getRealPath(), image->machHeader());
    uint64_t t1 = mach_absolute_time();
    uint64_t t2 = mach_absolute_time();
    uint64_t timeInObjC = t1-t0;
    uint64_t emptyTime = (t2-t1)*100;
    if ( (timeInObjC > emptyTime) && (timingInfo != NULL) ) {
        timingInfo->addTime(image->getShortName(), timeInObjC);
    }
}
```

关心的只有`sNotifyObjCInit`这个回调，继续寻找赋值的地方：

```c++
void registerObjCNotifiers(_dyld_objc_notify_mapped mapped, _dyld_objc_notify_init init, _dyld_objc_notify_unmapped unmapped)
{
    // record functions to call
    sNotifyObjCMapped   = mapped;
    sNotifyObjCInit     = init;
    sNotifyObjCUnmapped = unmapped;
    ...
```

接着找`registerObjCNotifiers`函数调用，最终找到这里：

```c++
void _dyld_objc_notify_register(_dyld_objc_notify_mapped    mapped,
                                _dyld_objc_notify_init      init,
                                _dyld_objc_notify_unmapped  unmapped)
{
    dyld::registerObjCNotifiers(mapped, init, unmapped);
}
```

那么究竟是谁调用了`_dyld_objc_notify_register()`

静态分析已经无法得知，只能对`_dyld_objc_notify_register`下个符号断点，打印堆栈来探索一下了

```ruby
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 3.2
  * frame #0: 0x00007fff2025bda1 libdyld.dylib`_dyld_objc_notify_register
    frame #1: 0x00007fff2018dbdb libobjc.A.dylib`_objc_init + 1092
    frame #2: 0x000000010bed1110 libdispatch.dylib`_os_object_init + 13
    frame #3: 0x000000010bee047d libdispatch.dylib`libdispatch_init + 303
    frame #4: 0x00007fff531d286f libSystem.B.dylib`libSystem_initializer + 252
    frame #5: 0x000000010bc8794b dyld_sim`ImageLoaderMachO::doModInitFunctions(ImageLoader::LinkContext const&) + 537
    frame #6: 0x000000010bc87d34 dyld_sim`ImageLoaderMachO::doInitialization(ImageLoader::LinkContext const&) + 40
    frame #7: 0x000000010bc82899 dyld_sim`ImageLoader::recursiveInitialization(ImageLoader::LinkContext const&, unsigned int, char const*, ImageLoader::InitializerTimingList&, ImageLoader::UninitedUpwards&) + 455
    frame #8: 0x000000010bc82806 dyld_sim`ImageLoader::recursiveInitialization(ImageLoader::LinkContext const&, unsigned int, char const*, ImageLoader::InitializerTimingList&, ImageLoader::UninitedUpwards&) + 308
    frame #9: 0x000000010bc80bb0 dyld_sim`ImageLoader::processInitializers(ImageLoader::LinkContext const&, unsigned int, ImageLoader::InitializerTimingList&, ImageLoader::UninitedUpwards&) + 188
    frame #10: 0x000000010bc80c50 dyld_sim`ImageLoader::runInitializers(ImageLoader::LinkContext const&, ImageLoader::InitializerTimingList&) + 82
    frame #11: 0x000000010bc74263 dyld_sim`dyld::initializeMainExecutable() + 129
    frame #12: 0x000000010bc78d50 dyld_sim`dyld::_main(macho_header const*, unsigned long, int, char const**, char const**, char const**, unsigned long*) + 4431
    frame #13: 0x000000010bc731c7 dyld_sim`start_sim + 122
    frame #14: 0x0000000110dac85c dyld`dyld::useSimulatorDyld(int, macho_header const*, char const*, int, char const**, char const**, char const**, unsigned long*, unsigned long*) + 2308
    frame #15: 0x0000000110daa4f4 dyld`dyld::_main(macho_header const*, unsigned long, int, char const**, char const**, char const**, unsigned long*) + 837
    frame #16: 0x0000000110da5227 dyld`dyldbootstrap::start(dyld3::MachOLoaded const*, int, char const**, dyld3::MachOLoaded const*, unsigned long*) + 453
    frame #17: 0x0000000110da5025 dyld`_dyld_start + 37
```

从调用栈看到是`libobjc.A.dylib`的`_objc_init`函数调用了`_dyld_objc_notify_register()`

从 objc源码中，找到`_objc_init`函数

```c++
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

这里注册的 init 回调函数就是 `load_images()`，回调函数`load_images()`里面会调用`call_load_methods()`来执行所有的`+load()`方法，这也就验证了，为什么一开始`+load()`函数会比 `main()` 函数先执行

从文章一开始的堆栈中可以看到`notifySingle()`之后调用`doInitialization()`

```c++
// initialize this image
// 调用constructor()
bool hasInitializers = this->doInitialization(context);
```

`doInitialization()`内部调用顺序

- `doImageInit`来执行镜像的初始化函数，也就是`LC_ROUTINES_COMMAND`中记录的函数，
- `doModInitFunctions()`方法来解析并执行`_DATA_`,`__mod_init_func`这个`section`中保存的函数

`_mod_init_funcs`中保存的是全局`C++`对象的构造函数以及所有带`__attribute__`((constructor)的C函数

我们在 `main()` 函数中加入以下代码

```objective-c
#import "AppDelegate.h"

__attribute__((constructor))  void init_func1() {
    printf("%s\n", __FUNCTION__);
}


__attribute__((constructor))  void init_func2() {
    printf("%s\n", __FUNCTION__);
}

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        NSLog(@"main");
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
```

输出：

```ruby
2020-09-25 19:12:41.850546+0800 DyldTest[14523:25898716] load
init_func1
init_func2
2020-09-25 19:12:41.851222+0800 DyldTest[14523:25898716] main
```

##### 查找程序入口点并返回

这一步调用主程序镜像的`getThreadPC()`，从加载命令读取`LC_MAIN`入口，如果没有`LC_MAIN`就调用`getMain()`读取`LC_UNIXTHREAD`，找到后就跳到入口点指定的地址并返回

至此，整个 dyld 的加载过程就分析完了

### dyld 加载流程图

![dyld加载过程](https://w-md.imzsy.design/dyld加载过程.png)



### 参考资料

> [dyld启动流程](https://leylfl.github.io/2018/05/28/dyld启动流程/)
>
> [WWDC2019之启动时间与Dyld3](http://www.zoomfeng.com/blog/launch-optimize-from-wwdc2019.html)
>
> [App Startup Time: Past, Present, and Future](https://developer.apple.com/videos/play/wwdc2017/413/)
>
> [dyld详解](https://www.dllhook.com/post/238.html)