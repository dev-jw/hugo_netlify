---
title: "iOS编译流程-LLVM & Clang小结"
date: 2020-11-13T20:00:39+08:00
draft: true
tags: ["iOS"]
url:  "llvm"
---

本文主要是理解LLVM的编译流程以及clang插件的开发

## LLVM

LLVM是`架构编译器的框架系统`，以C++编写而成，用于`优化`任意程序语言编写的程序的`编译时间`（compile-time）、`链接时间`（link-time）、`运行时间`（run-time）以及`空闲时间`（idle-time）。对开发者保持开放，并兼容已有脚本

#### 传统编译器设计

源码 Source Code + 前端 Frontend + 优化器 Optimizer + 后端 Backend（代码生成器 CodeGenerator）+ 机器码 Machine Code，如下图所示



#### ios的编译器架构

`OC、C、C++`使用的编译器前端是`Clang`，`Swift`是`swift`，后端都是`LLVM`，如下图所示



**模块说明**

- **前端 Frontend**：编译器前端的`任务`是`解析源代码`（编译阶段），它会进行 `词法分析、语法分析、语义分析、检查源代码是否存在错误`，然后构建`抽象语法树`（Abstract Syntax Tree `AST`），`LLVM`的前端还会生成`中间代码`（intermediate representation，简称`IR`），可以理解为`llvm`是`编译器 + 优化器`， 接收的是`IR`中间代码，输出的还是`IR`，给后端，经过后端翻译成目标指令集
- **优化器 Optimizer**：优化器负责进行各种优化，改善代码的运行时间，例如消除冗余计算等
- **后端 Backend（代码生成器 Code Generator）**：将`代码映射到目标指令集，生成机器代码`，并且进行机器代码相关的代码优化

#### LLVM的设计

LLVM设计的最重要方面是，`使用通用的代码表示形式（IR）`，它是用来在编译器中表示代码的形式，所有LLVM可以为任何编程语言独立编写前端，并且可以为任意硬件架构独立编写后端，如下所示



通俗的一句话理解就是：LLVM的设计是`前后端分离`的，无论前端还是后端发生变化，都不会影响另一个

#### Clang简介

`clang`是LLVM项目中的一个`子项目`，它是基于LLVM架构图的`轻量级编译器`，诞生之初是`为了替代GCC`，提供更快的编译速度，它是`负责C、C++、OC语言的编译器`，属于整个LLVM架构中的 `编译器前端`，对于开发者来说，研究Clang可以给我们带来很多好处

### LLVM编译流程

 