---
title: "iOS底层原理探索-GCD应用"
date: 2020-11-03T20:47:18+08:00
draft: true
tags: ["iOS"]
url:  "gcd-project"
---

在iOS多线程开发中，GCD是最为常用的一种方案，本文将对其的使用进行介绍

同样的，提几个问题：

- 什么是 GCD
- 什么是函数
- 什么是队列

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

#### 队列

