---
title: "iOS性能优化-内存管理"
date: 2020-11-23T20:07:01+08:00
draft: true
tags: ["iOS"]
url:  "memory"
---



### 内存布局



### 内存管理方案

#### TaggedPointer

#### nonpointer_isa

#### SideTable

### ARC&MRC

#### alloc

#### retain

#### relase

#### retainCount

#### autorealse

#### dealloc



### 弱引用

#### weak 原理

### 自动释放池



objc-os.h

objc-sel-table.s





\#include "DenseMapExtras.h"

\#include "objc-private.h"

\#include "objc-runtime-new.h"

\#include "objc-file.h"

\#include "objc-cache.h"

\#include "objc-zalloc.h"

\#include <Block.h>

\#include <objc/message.h>

\#include <mach/shared_region.h>