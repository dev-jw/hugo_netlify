---
title: "iOS底层原理探索-GCD底层分析"
date: 2020-11-06T14:35:29+08:00
draft: true
tags: ["iOS"]
url:  "gcd"

---

在上一篇文章中，已经了解 GCD 常用的应用场景，且对函数与队列有了一定的认知。那么，本文将对 GCD 底层实现进行探索分析，同样地，先看一下问题：

- 底层队列如何创建
- `dispatch_block`任务的执行
- 同步函数原理
- 异步函数原理
- 信号量的原理
- 调度组的原理
- `dispatch_source`的原理
- 单例的原理

> GCD源码位于`libdispatch.dylib`

### 底层队列如何创建



### `dispatch_block`任务的执行



### 同步函数原理



### 异步函数原理



### 信号量的原理



### 调度组的原理



### `dispatch_source`的原理



### 单例的原理