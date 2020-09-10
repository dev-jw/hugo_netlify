---
title: "iOS底层原理探索-isa结构&指向分析"
date: 2020-09-10T10:25:02+08:00
draft: true
tags: ["iOS"]
url:  "isa"
---

在分析 isa 之前，先补充位域和结构体的知识点

### 准备知识

**位域**

位段，C语言允许在一个结构体中以位为单位来指定其成员所占内存长度，这种以位为单位的成员称为「位段」或称「位域」( bit field) 。利用位段能够用较少的位数存储数据。

示例：

```c++
// 使用位域声明
struct Struct1 {
    char ch:   1;  //1位
    int  size: 3;  //3位
} Struct1;

struct Struct2 {
    char ch;    //1位
    int  size;  //4位
} Struct2;

sizeof(Struct1); // 返回 4
sizeof(Struct2); // 返回 8
```

**联合体**



### isa结构分析



![isa定义](https://w-md.imzsy.design/isa定义.png)

### isa走位



![isa流程图](https://w-md.imzsy.design/isa流程图.png)





















> 参考文章：
>
> [神经病院Objective-C Runtime 入院第一天—— isa 和Class](https://halfrost.com/objc_runtime_isa_class/)   