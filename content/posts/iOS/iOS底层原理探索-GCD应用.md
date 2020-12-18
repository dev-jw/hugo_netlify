---
title: "iOS底层原理探索-GCD应用"
date: 2020-11-03T20:47:18+08:00
draft: false
tags: ["iOS"]
url:  "gcd-project"
---

在iOS多线程开发中，GCD是最为常用的一种方案，本文将对其的使用进行介绍

同样的，提几个问题：

- 什么是 GCD
- 函数与队列
- GCD常见的应用

### GCD简介

GCD全称是`Grand Central Dispatch`，它是纯 C 语言，并且提供了非常多强大的函数

**GCD的优势**

- GCD是苹果公司为`多核的并行运算`提出的`解决方案`
- GCD会`自动利用`更多的`CPU内核`（比如双核、四核）
- GCD会`自动管理`线程的`生命周期`（创建线程、调度任务、销毁线程）
- 程序员只需要告诉GCD想要执行什么任务，不需要编写任何线程管理代码

> 我们要关注的点：GCD的核心——`将任务添加到队列，并且指定执行任务的函数`

例如：下面这段 GCD 代码

```objective-c
dispatch_async(dispatch_queue_create("com.GCD.Queue", NULL), ^{
   NSLog(@"GCD基本使用");
});
```

可以将上面代码拆分为：`任务 + 队列 + 函数` 三部分

```objective-c
//********GCD基础写法********
//创建任务
dispatch_block_t block = ^{
    NSLog(@"hello GCD");
};

//创建串行队列
dispatch_queue_t queue = dispatch_queue_create("com.GCD.Queue", NULL);

//将任务添加到队列，并指定函数执行
dispatch_async(queue, block);
```

- `dispatch_block_t`创建任务，使用 block 封装任务
- `dispatch_queue_t`创建队列
- `dispatch_async`将任务添加到队列

### 函数与队列

#### 函数

在 GCD 中执行任务的方式有两种

- 同步函数执行 —— `dispatch_sync`
  - 必须等到当前语句执行完毕，才会执行下一条语句
  - 不会开启线程，即不具备开启新线程的能力
  - 在当前线程中执行 block 任务
- 异步函数执行 —— `dispatch_async`
  - 不用等待当前语句执行完毕，就可以执行下一条语句
  - 会开启线程执行 block 任务，即具备开启新线程的能力（并不一定开启新线程，与任务所指定的队列类型有关）

所以，两种执行任务的函数主要区别是：

- 是否等待队列的任务执行完毕
- 是否具备开启新线程的能力

#### 队列

多线程中的队列是指**执行任务的等待队列**，即用来存放任务的队列

在 GCD 中，队列主要分为：

- 串行队列——Serial Dispatch Queue
- 并发队列——Concurrent Dispatch Queue

![image-20201218161055440](https://w-md.imzsy.design/image-20201218161055440.png)

**串行队列**

每次只有一个任务被执行，等待上一个任务执行完毕再执行下一个，即同一时刻只调度一个任务执行

- `dispatch_queue_create("xxx", DISPATCH_QUEUE_SERIAL)`创建串行队列
- `dispatch_queue_create("xxx", NULL)`也可以创建串行队列

**并发队列**

一次可以并发执行多个任务，即同一时刻可以调度多个任务执行，开启多个线程，并同时执行任务

- `dispatch_queue_create("xxx", DISPATCH_QUEUE_CONCURRENT)`创建并发队列
- 并发队列的并发功能只在异步函数下才有效

**主队列**

Main Dispatch Queue，专门用来在主线程上调度任务的串行队列，依赖于主线程、主RunLoop，在 main 函数调用之前自动创建

- 使用`dispatch_get_main_queue()`获取主队列
- 如果当前主线程正在执行任务，那么无论主队列中当前被添加什么任务，都不会被调度
- 通常在返回主线程，更新UI时使用

**全局并发队列**

Global Dispatch Queue，系统提供的并发队列

- 在使用多线程开发时，如果对队列没有特殊需求，`在执行异步任务时，可以直接使用全局队列`
- 获取全局并发队列，最简单的是`dispatch_get_global_queue(0, 0)`
  - 第一个参数表示`队列优先级`，默认优先级为`DISPATCH_QUEUE_PRIORITY_DEFAULT=0`，在ios9之后，已经被`服务质量（quality-of-service）`取代
  - 第二个参数使用0

```objective-c
//全局并发队列的获取方法
dispatch_queue_t globalQueue = dispatch_get_global_queue(0, 0);

//优先级从高到低（对应的服务质量）依次为
- DISPATCH_QUEUE_PRIORITY_HIGH       -- QOS_CLASS_USER_INITIATED
- DISPATCH_QUEUE_PRIORITY_DEFAULT    -- QOS_CLASS_DEFAULT
- DISPATCH_QUEUE_PRIORITY_LOW        -- QOS_CLASS_UTILITY
- DISPATCH_QUEUE_PRIORITY_BACKGROUND -- QOS_CLASS_BACKGROUND
```

### 函数与队列的不同组合

![image-20201218162830254](https://w-md.imzsy.design/image-20201218162830254.png)

#### 串行队列+同步函数

任务按顺序的在当前线程执行，不会开辟新线程

```objective-c
- (void)serialSync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_queue_create("com.xxx.my_queue", NULL);
    
    for (int i = 0; i < 10; i++) {
        dispatch_sync(my_queue, ^{
            NSLog(@"串行 + 同步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600003b64fc0>{number = 1, name = main}
// 串行 + 同步: 0 - <NSThread: 0x600003b64fc0>{number = 1, name = main}
// 串行 + 同步: 1 - <NSThread: 0x600003b64fc0>{number = 1, name = main}
// ...按顺序输出
--------------------输出结果：-------------------
```

#### 串行队列+异步函数

任务按顺序地执行，会开辟新线程

```objective-c
- (void)serialAsync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_queue_create("com.xxx.my_queue", NULL);
    
    for (int i = 0; i < 10; i++) {
        dispatch_async(my_queue, ^{
            NSLog(@"串行 + 异步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600003b64fc0>{number = 1, name = main}
// 串行 + 同步: 0 - <NSThread: 0x6000009b8880>{number = 6, name = (null)}
// 串行 + 同步: 1 - <NSThread: 0x6000009b8880>{number = 6, name = (null)}
// ...按顺序输出
--------------------输出结果：-------------------
```

#### 并发队列+同步函数

任务按顺序的执行，不会开辟线程

```objective-c
- (void)concurrentSync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_queue_create("com.xxx.my_queue", DISPATCH_QUEUE_CONCURRENT);
    
    for (int i = 0; i < 10; i++) {
        dispatch_sync(my_queue, ^{
            NSLog(@"并行 + 同步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600003b64fc0>{number = 1, name = main}
// 并行 + 同步：0 - <NSThread: 0x600003b64fc0>{number = 1, name = main}
// 并行 + 同步：1 - <NSThread: 0x600003b64fc0>{number = 1, name = main}
// ...按顺序输出
--------------------输出结果：-------------------
```

#### 并发队列+异步函数

任务乱序执行，会开辟线程

```objective-c
- (void)concurrentAsync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_queue_create("com.xxx.my_queue", DISPATCH_QUEUE_CONCURRENT);
    
    for (int i = 0; i < 10; i++) {
        dispatch_async(my_queue, ^{
            NSLog(@"并行 + 异步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600002a9cd40>{number = 1, name = main}
// 并行 + 异步：0 - <NSThread: 0x600000de9800>{number = 4, name = (null)}
// 并行 + 异步：2 - <NSThread: 0x600000df4940>{number = 5, name = (null)}
// 并行 + 异步：1 - <NSThread: 0x600000dc0140>{number = 3, name = (null)}
// 并行 + 异步：3 - <NSThread: 0x600000d9a980>{number = 6, name = (null)}
// 并行 + 异步：4 - <NSThread: 0x600000d86380>{number = 7, name = (null)}
// ...乱序输出
--------------------输出结果：-------------------
```

#### 主队列+同步函数

```objective-c
- (void)mainSync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_get_main_queue();
    
    for (int i = 0; i < 10; i++) {
        dispatch_sync(my_queue, ^{
            NSLog(@"主队列 + 同步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600001980d40>{number = 1, name = main}
// 崩溃...
--------------------输出结果：-------------------
```

会出现死锁，原因如下：

- 主队列有两个任务，顺序为：`NSLog任务`，`同步Blcok`
- 执行NSLog任务后，执行同步Block，会将任务1（即i=1时）加入到主队列，主队列顺序为：`NSLog任务 - 同步block - 任务1`
- `任务1`的执行需要`等待同步block执行完毕`才会执行，而`同步block`的执行需要`等待任务1执行完毕`，所以就造成了`任务互相等待`的情况，即造成`死锁崩溃`

#### 主队列+异步函数

任务按顺序地执行，不会开辟线程

```objective-c
- (void)mainAsync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_get_main_queue();
    
    for (int i = 0; i < 10; i++) {
        dispatch_async(my_queue, ^{
            NSLog(@"主队列 + 异步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600001980d40>{number = 1, name = main}
// 主队列 + 异步：0 -<NSThread: 0x600001980d40>{number = 1, name = main}
// 主队列 + 异步：1 -<NSThread: 0x600001980d40>{number = 1, name = main}
// ...按顺序输出
--------------------输出结果：-------------------
```

#### 全局队列+同步函数

任务按顺序地执行，不会开辟线程

```objective-c
- (void)globalSync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_get_global_queue(0, 0);

    for (int i = 0; i < 10; i++) {
        dispatch_sync(my_queue, ^{
            NSLog(@"全局队列 + 同步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x6000037cc1c0>{number = 1, name = main}
// 全局队列 + 同步：0 - <NSThread: 0x6000037cc1c0>{number = 1, name = main}
// 全局队列 + 同步：1 - <NSThread: 0x6000037cc1c0>{number = 1, name = main}
// ...按顺序输出
--------------------输出结果：-------------------

```

#### 全局队列+异步函数

任务乱序地执行，会开辟线程

```objective-c
- (void)globalAsync {
    NSLog(@"主线程-%@", [NSThread currentThread]);
    dispatch_queue_t my_queue = dispatch_get_global_queue(0, 0);

    for (int i = 0; i < 10; i++) {
        dispatch_async(my_queue, ^{
            NSLog(@"全局队列 +  异步：%d - %@", i, [NSThread currentThread]);
        });
    }
}

--------------------输出结果：-------------------
// 主线程-<NSThread: 0x600002f5c880>{number = 1, name = main}
// 全局队列 +  异步：1 - <NSThread: 0x600002f047c0>{number = 5, name = (null)}
// 全局队列 +  异步：0 - <NSThread: 0x600002f50300>{number = 4, name = (null)}
// 全局队列 +  异步：2 - <NSThread: 0x600002f24200>{number = 6, name = (null)}
// 全局队列 +  异步：3 - <NSThread: 0x600002f30400>{number = 7, name = (null)}
// ...乱序输出
--------------------输出结果：-------------------

```

**总结一下**

| 函数\队列 | 串行队列             | 并发队列             | 主队列               | 全局队列             |
| --------- | -------------------- | -------------------- | -------------------- | -------------------- |
| 同步函数  | 顺序执行，不开辟线程 | 顺序执行，不开辟线程 | 死锁                 | 顺序执行，不开辟线程 |
| 异步函数  | 顺序执行，开辟线程   | 乱序执行，开辟线程   | 顺序执行，不开辟线程 | 乱序执行，开辟线程   |

### dispatch_after

`dispatch_after`表示在某队列中的block延迟加入到队列，而不是延迟执行

例如：在主队列上延迟执行任务，延迟 1s 显示弹窗提示

```objc
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    NSLog(@"2秒后输出");
});
```

### dispatch_once

`dispatch_once`保证在App运行期间，block中的代码只执行一次

常用于`单例、method-Swizzling`

```objective-c
static dispatch_once_t onceToken;
dispatch_once(&onceToken, ^{
    // 任务
});
```

### dispatch_apply

`dispatch_apply`将指定的Block追加到指定的队列中重复执行，并等到全部的处理执行结束——相当于线程安全的for循环

应用场景：用来拉取网络数据后提前算出各个控件的大小，防止绘制时计算，提高表单滑动流畅性

- 添加到串行队列中——按序执行
- 添加到主队列中——死锁
- 添加到并发队列中——乱序执行
- 添加到全局队列中——乱序执行

```objective-c
- (void)test {
    /**
     param1：重复次数
     param2：追加的队列
     param3：执行任务
     */
    dispatch_queue_t queue = dispatch_queue_create("X", DISPATCH_QUEUE_SERIAL);
    NSLog(@"dispatch_apply前");
    dispatch_apply(10, queue, ^(size_t index) {
        NSLog(@"dispatch_apply的线程%zu-%@", index, [NSThread currentThread]);
    });
    NSLog(@"dispatch_apply后");
}
--------------------输出结果：-------------------
// dispatch_apply前
// dispatch_apply的线程0-<NSThread: 0x6000019f8d40>{number = 1, name = main}
// ...是否按序输出与串行队列还是并发队列有关
// dispatch_apply后
--------------------输出结果：-------------------
```

### dispatch_group_t

`dispatch_group_t`：调度组将任务分组执行，能监听任务组完成，并设置等待时间

常见的使用方式有两种

- 使用`dispatch_group_async + dispatch_group_notify`

  ```objective-c
  - (void)testGroup {
      /*
       dispatch_group_t：调度组将任务分组执行，能监听任务组完成，并设置等待时间
  
       应用场景：多个接口请求之后刷新页面
       */
      
      dispatch_group_t group = dispatch_group_create();
      dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
      
      dispatch_group_async(group, queue, ^{
          NSLog(@"请求一完成");
      });
      
      dispatch_group_async(group, queue, ^{
          NSLog(@"请求二完成");
      });
      
      dispatch_group_notify(group, dispatch_get_main_queue(), ^{
          NSLog(@"刷新页面");
      });
  }
  ```

- 使用`dispatch_group_enter + dispatch_group_leave + dispatch_group_notify`

  ```objective-c
  - (void)testGroup {
      /*
       dispatch_group_enter和dispatch_group_leave成对出现，使进出组的逻辑更加清晰
       */
      dispatch_group_t group = dispatch_group_create();
      dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
      
      dispatch_group_enter(group);
      dispatch_async(queue, ^{
          NSLog(@"请求一完成");
          dispatch_group_leave(group);
      });
      
      dispatch_group_enter(group);
      dispatch_async(queue, ^{
          NSLog(@"请求二完成");
          dispatch_group_leave(group);
      });
      
      dispatch_group_notify(group, dispatch_get_main_queue(), ^{
          NSLog(@"刷新界面");
      });
  }
  ```

  在这种方式上，还可以增加超时`dispatch_group_wait`

  ```objective-c
  - (void)testGroup {
      /*
       long dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout)
  
       group：需要等待的调度组
       timeout：等待的超时时间（即等多久）
          - 设置为DISPATCH_TIME_NOW意味着不等待直接判定调度组是否执行完毕
          - 设置为DISPATCH_TIME_FOREVER则会阻塞当前调度组，直到调度组执行完毕
  
  
       返回值：为long类型
          - 返回值为0——在指定时间内调度组完成了任务
          - 返回值不为0——在指定时间内调度组没有按时完成任务
  
       */
      dispatch_group_t group = dispatch_group_create();
      dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
      
      dispatch_group_enter(group);
      dispatch_async(queue, ^{
          NSLog(@"请求一完成");
          dispatch_group_leave(group);
      });
      
      dispatch_group_enter(group);
      dispatch_async(queue, ^{
          NSLog(@"请求二完成");
          dispatch_group_leave(group);
      });
      
  //    long timeout = dispatch_group_wait(group, DISPATCH_TIME_NOW);
  //    long timeout = dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
      long timeout = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 1 *NSEC_PER_SEC));
      NSLog(@"timeout = %ld", timeout);
      if (timeout == 0) {
          NSLog(@"按时完成任务");
      }else{
          NSLog(@"超时");
      }
      
      dispatch_group_notify(group, dispatch_get_main_queue(), ^{
          NSLog(@"刷新界面");
      });
  }
  ```

### 栅栏函数

栅栏函数能将多个任务进行分组——等栅栏前**追加到队列中**的任务执行完毕后，再将栅栏后的任务追加到队列中

简而言之，就是先执行`栅栏前任务`，再执行`栅栏任务`，最后执行`栅栏后任务`

**应用场景**：`同步锁`

栅栏函数主要有两种：

- **dispatch_barrier_sync**：前面的任务执行完毕才会来到这里
- **dispatch_barrier_async**：作用相同，但是这个会堵塞线程，影响后面的任务执行

#### 串行队列使用栅栏函数

```objective-c
- (void)testBarrier {
    //串行队列使用栅栏函数
    dispatch_queue_t queue = dispatch_queue_create("X", DISPATCH_QUEUE_SERIAL);
    
    NSLog(@"开始 - %@", [NSThread currentThread]);
    dispatch_async(queue, ^{
        sleep(2);
        NSLog(@"延迟2s的任务1 - %@", [NSThread currentThread]);
    });
    NSLog(@"第一次结束 - %@", [NSThread currentThread]);
    
    //栅栏函数的作用是将队列中的任务进行分组，所以我们只要关注任务1、任务2
    dispatch_barrier_async(queue, ^{
        NSLog(@"------------栅栏任务------------%@", [NSThread currentThread]);
    });
    NSLog(@"栅栏结束 - %@", [NSThread currentThread]);
    
    dispatch_async(queue, ^{
        sleep(2);
        NSLog(@"延迟2s的任务2 - %@", [NSThread currentThread]);
    });
    NSLog(@"第二次结束 - %@", [NSThread currentThread]);
}
```

不使用栅栏函数

```objective-c
开始——<NSThread: 0x600001068900>{number = 1, name = main}
第一次结束——<NSThread: 0x600001068900>{number = 1, name = main}
第二次结束——<NSThread: 0x600001068900>{number = 1, name = main}
延迟2s的任务1——<NSThread: 0x600001025ec0>{number = 3, name = (null)}
延迟1s的任务2——<NSThread: 0x600001025ec0>{number = 3, name = (null)}
```

使用栅栏函数

```objective-c
开始——<NSThread: 0x6000001bcf00>{number = 1, name = main}
第一次结束——<NSThread: 0x6000001bcf00>{number = 1, name = main}
栅栏结束——<NSThread: 0x6000001bcf00>{number = 1, name = main}
第二次结束——<NSThread: 0x6000001bcf00>{number = 1, name = main}
延迟2s的任务1——<NSThread: 0x6000001fcf00>{number = 5, name = (null)}
----------栅栏任务----------<NSThread: 0x6000001bcf00>{number = 1, name = main}
延迟1s的任务2——<NSThread: 0x6000001fcf00>{number = 5, name = (null)}
```

**总结**

由于`串行队列 + 异步函数`，任务是按顺序执行的，所以使用栅栏函数没有意义

#### 并发队列使用栅栏函数

```objective-c
- (void)testBarrier {
    //并发队列使用栅栏函数
    
    dispatch_queue_t queue = dispatch_queue_create("X", DISPATCH_QUEUE_CONCURRENT);
    
    NSLog(@"开始 - %@", [NSThread currentThread]);
    dispatch_async(queue, ^{
        sleep(2);
        NSLog(@"延迟2s的任务1 - %@", [NSThread currentThread]);
    });
    NSLog(@"第一次结束 - %@", [NSThread currentThread]);
    
    //由于并发队列异步执行任务是乱序执行完毕的，所以使用栅栏函数可以很好的控制队列内任务执行的顺序
    dispatch_barrier_async(queue, ^{
        NSLog(@"------------栅栏任务------------%@", [NSThread currentThread]);
    });
    NSLog(@"栅栏结束 - %@", [NSThread currentThread]);
    
    dispatch_async(queue, ^{
        sleep(2);
        NSLog(@"延迟2s的任务2 - %@", [NSThread currentThread]);
    });
    NSLog(@"第二次结束 - %@", [NSThread currentThread]);
}
```

不使用栅栏函数

```objective-c
开始——<NSThread: 0x600002384f00>{number = 1, name = main}
第一次结束——<NSThread: 0x600002384f00>{number = 1, name = main}
第二次结束——<NSThread: 0x600002384f00>{number = 1, name = main}
延迟1s的任务2——<NSThread: 0x6000023ec300>{number = 5, name = (null)}
延迟2s的任务1——<NSThread: 0x60000238c180>{number = 7, name = (null)}
```

使用栅栏函数

```objective-c
开始——<NSThread: 0x600000820bc0>{number = 1, name = main}
第一次结束——<NSThread: 0x600000820bc0>{number = 1, name = main}
栅栏结束——<NSThread: 0x600000820bc0>{number = 1, name = main}
第二次结束——<NSThread: 0x600000820bc0>{number = 1, name = main}
延迟2s的任务1——<NSThread: 0x600000863c80>{number = 4, name = (null)}
----------栅栏任务----------<NSThread: 0x600000863c80>{number = 4, name = (null)}
延迟1s的任务2——<NSThread: 0x600000863c80>{number = 4, name = (null)}
```

**总结**

由于`并发队列+异步函数`，任务是乱序执行的，使用栅栏函数可以控制队列内的任务执行顺序

#### `dispatch_barrier_async`与`dispatch_barrier_sync`

如果将案例二中的`dispatch_barrier_async`改成`dispatch_barrier_sync`

那么输出变为：

```objective-c
开始——<NSThread: 0x600001040d40>{number = 1, name = main}
第一次结束——<NSThread: 0x600001040d40>{number = 1, name = main}
延迟2s的任务1——<NSThread: 0x60000100ce40>{number = 6, name = (null)}
----------栅栏任务----------<NSThread: 0x600001040d40>{number = 1, name = main}
栅栏结束——<NSThread: 0x600001040d40>{number = 1, name = main}
第二次结束——<NSThread: 0x600001040d40>{number = 1, name = main}
延迟1s的任务2——<NSThread: 0x60000100ce40>{number = 6, name = (null)}
```

所以，**dispatch_barrier_async可以控制队列中任务的执行顺序，而dispatch_barrier_sync不仅阻塞了队列的执行，也阻塞了线程的执行（尽量少用）**

#### 栅栏函数注意点

`尽量使用自定义的并发队列`：

- 使用`全局队列`起不到`栅栏函数`的作用
- 使用`全局队列`时由于对全局队列造成堵塞，可能致使系统其他调用全局队列的地方也堵塞从而导致崩溃（并不是只有你在使用这个队列）

`栅栏函数只能控制同一并发队列`：比如，在使用AFNetworking做网络请求时为什么不能用栅栏函数起到同步锁堵塞的效果，因为AFNetworking内部有自己的队列

### dispatch_semaphore_t

信号量主要用于同步锁，用于控制 GCD 最大并发数

- `dispatch_semaphore_create()`：创建信号量
- `dispatch_semaphore_wait()`：等待信号量，信号量减1。当信号量`< 0`时会阻塞当前线程，根据传入的等待时间决定接下来的操作——如果**永久等待**将等到`信号（signal）`才执行下去
- `dispatch_semaphore_signal()`：释放信号量，信号量加1。当信号量`>= 0` 会执行wait之后的代码

```objective-c
- (void)testSemaphore { 
    dispatch_queue_t queue = dispatch_queue_create("X", DISPATCH_QUEUE_CONCURRENT);
    
    for (int i = 0; i < 10; i++) {
        dispatch_async(queue, ^{
            NSLog(@"当前 - %d， 线程 - %@", i, [NSThread currentThread]);
        });
    }
  
    sleep(2);
    NSLog(@"------------------");
    //利用信号量来改写
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    for (int i = 0; i < 10; i++) {
        dispatch_async(queue, ^{
            NSLog(@"当前 - %d， 线程 - %@", i, [NSThread currentThread]);
            
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }
}

// 输出
当前 - 0， 线程 - <NSThread: 0x60000043e140>{number = 6, name = (null)}
当前 - 4， 线程 - <NSThread: 0x600000431e80>{number = 8, name = (null)}
当前 - 2， 线程 - <NSThread: 0x600000425880>{number = 7, name = (null)}
当前 - 1， 线程 - <NSThread: 0x60000043e200>{number = 4, name = (null)}
当前 - 3， 线程 - <NSThread: 0x600000420f40>{number = 3, name = (null)}
当前 - 5， 线程 - <NSThread: 0x600000424380>{number = 5, name = (null)}
当前 - 6， 线程 - <NSThread: 0x600000410100>{number = 9, name = (null)}
当前 - 7， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 9， 线程 - <NSThread: 0x600000431e80>{number = 8, name = (null)}
当前 - 8， 线程 - <NSThread: 0x6000004714c0>{number = 11, name = (null)}
------------------
当前 - 0， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 1， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 2， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 3， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 4， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 5， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 6， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 7， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 8， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
当前 - 9， 线程 - <NSThread: 0x60000043e1c0>{number = 10, name = (null)}
```

### dispatch_source

应用场景：`GCDTimer`

#### 定义及使用

`dispatch_source`是一种基本的数据类型，可以用来监听一些底层的系统事件

- `Timer Dispatch Source`：定时器事件源，用来生成周期性的通知或回调
- `Signal Dispatch Source`：监听信号事件源，当有UNIX信号发生时会通知
- `Descriptor Dispatch Source`：监听文件或socket事件源，当文件或socket数据发生变化时会通知
- `Process Dispatch Source`：监听进程事件源，与进程相关的事件通知
- `Mach port Dispatch Source`：监听Mach端口事件源
- `Custom Dispatch Source`：监听自定义事件源

主要使用的API：

- `dispatch_source_create`: 创建事件源
- `dispatch_source_set_event_handler`: 设置数据源回调
- `dispatch_source_merge_data`: 设置事件源数据
- `dispatch_source_get_data`： 获取事件源数据
- `dispatch_resume`: 继续
- `dispatch_suspend`: 挂起
- `dispatch_cancle`: 取消

#### 自定义定时器

在iOS开发中一般使用`NSTimer`来处理定时逻辑，但`NSTimer`是依赖`Runloop`的，而`Runloop`可以运行在不同的模式下

如果`NSTimer`添加在一种模式下，当`Runloop`运行在其他模式下的时候，定时器就会不起作用

如果`Runloop`在阻塞状态，`NSTimer`触发时间就会推迟到下一个`Runloop`周期

因此`NSTimer`在计时上会有误差，并不是特别精确，而GCD定时器不依赖`Runloop`，计时精度要高很多

```objective-c
@property (nonatomic, strong) dispatch_source_t timer;
//1.创建队列
dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//2.创建timer
_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
//3.设置timer首次执行时间，间隔，精确度
dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
//4.设置timer事件回调
dispatch_source_set_event_handler(_timer, ^{
    NSLog(@"GCDTimer");
});
//5.默认是挂起状态，需要手动激活
dispatch_resume(_timer);
```

使用`dispatch_source`自定义定时器注意点：

- `GCDTimer`需要`强持有`，否则出了作用域立即释放，也就没有了事件回调

- `GCDTimer`默认是挂起状态，需要手动激活

- `GCDTimer`没有`repeat`，需要封装来增加标志位控制

- `GCDTimer`如果存在循环引用，使用`weak+strong`或者提前调用`dispatch_source_cancel`取消timer

- `dispatch_resume`和`dispatch_suspend`调用次数需要平衡

- `source`在`挂起状态`下，如果直接设置`source = nil`或者重新创建`source`都会造成`crash`

  正确的方式是在`激活状态`下调用`dispatch_source_cancel(source)`释放当前的`source`

### GCD实现多读单写

> 比如在内存中维护一份数据，有多处地方可能会同时操作这块数据，怎么保证数据安全？

想要达到上面的需求，要满足以下三点：

- 读写互斥
- 写写互斥
- 读读并发

先来看一下具体实现

```objective-c
@interface Person : NSObject

@property (nonatomic, strong) dispatch_queue_t concurrentQueue;

@property (nonatomic, copy) NSMutableDictionary *dict;

- (void)setSafeObject:(id)object forKey:(NSString *)key;

- (id)safeObjectForKey:(NSString *)key;

@end

@implementation Person

- (instancetype)init
{
    self = [super init];
    if (self) {
        _concurrentQueue = dispatch_queue_create("com.person.Queue", DISPATCH_QUEUE_CONCURRENT);
        
        _dict = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setSafeObject:(id)object forKey:(NSString *)key {
    key = [key copy];
    dispatch_barrier_async(_concurrentQueue, ^{
        [self->_dict setObject:object forKey:key];
    });
}

- (id)safeObjectForKey:(NSString *)key {
    __block NSString *temp;
    dispatch_async(_concurrentQueue, ^{
        temp = [self->_dict objectForKey:key];
    });
    return temp;
}

@end
```

- 首先，要维系一个 GCD 队列，尽量不要使用全局队列（在全局队列中使用栅栏函数有坑点）

- 考虑性能、死锁、堵塞的因素，这里不使用串行队列，选择用自定义并发队列

- 对于读操作`safeObjectForKey`，由于多线程影响，这里不能使用异步函数

  - 例如，线程 2 获取 `name`，线程 3 获取 `age`，如果异步并发，那么就会混乱
  - 允许多个任务同时加入，但是读操作需要同步返回，因此选择`同步函数`，**读读并发**

- 写操作`setSafeObject:forKey:`

  先对 key 进行 copy，关于为什么需要 copy，可以参考文献：

  > 函数调用者可以自由传递一个 `NSMutableString` 的 `key`，并且能够在函数返回后修改它。因此我们必须对传入的字符串使用 `copy` 操作以确保函数能够正确地工作。如果传入的字符串不是可变的（也就是正常的 `NSString`），调用 `copy` 基本上是空操作

  这里选择使用栅栏函数`dispatch_barrier_async`，分析如下

  - 栅栏函数：相当于同步锁，保证栅栏之前的任务执行在栅栏之后，确保**写写互斥**
  - 如果用异步函数，并发队列+异步函数，会产生混乱
  - 如果用同步函数，由于读操作已经使用了同步函数，那么就可能存在：在写的时候，需要等待读操作完成才能执行，无法保证**读写并发**

### 总结

GCD 的 API 是相对比较多的，本来梳理了常见的应用

下一篇将探索 GCD 的底层原理