---
title: "iOS底层原理探索-消息发送与转发"
date: 2020-09-18T22:07:29+08:00
draft: true
tags: [iOS]
url:  "message"
---

在`cache_t`中，介绍了方法的缓存，那么方法具体是什么？方法的调用过程又是怎么样的呢？本来将对方法进行分析

同样的，先提出几个问题：

- 什么是 Runtime

- 方法的本质
- 方法快速查找流程
- 方法慢速查找流程

### Runtime

### 方法的本质

### 方法查找流程

#### 快速查找流程

#### 慢速查找流程

### 总结







```c
#include <objc/objc-runtime.h>

id  c_objc_msgSend( struct objc_class /* ahem */ *self, SEL _cmd, ...)
{
   struct objc_class    *cls;
   struct objc_cache    *cache;
   unsigned int         hash;
   struct objc_method   *method;   
   unsigned int         index;
   
   if( self)
   {
      cls   = self->isa;
      cache = cls->cache;
      hash  = cache->mask;
      index = (unsigned int) _cmd & hash;
      
      do
      {
         method = cache->buckets[ index];
         if( ! method)
            goto recache;
         index = (index + 1) & cache->mask;
      }
      while( method->method_name != _cmd);
      return( (*method->method_imp)( (id) self, _cmd));
   }
   return( (id) self);

recache:
   /* ... */
   return( 0);
}
```




C版本的objc_msgSend源码，可以帮助理解，今天讲的方法快速查找