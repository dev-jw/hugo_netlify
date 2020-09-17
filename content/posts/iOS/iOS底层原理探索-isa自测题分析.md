---
title: "iOS底层原理探索-isa自测题分析"
date: 2020-09-15T10:45:30+08:00
draft: true
tags: ['iOS']
url:  "isa-question-analysis"
---

首先，我们再来回顾一下题目

### 代码一

```objc
@interface Cat : Animal
@end

@implementation Cat
- (id)init
{
    self = [super init];
    if (self)
    {
        NSLog(@"%@", NSStringFromClass([self class]));
        NSLog(@"%@", NSStringFromClass([super class]));
      
        NSLog(@"%@", NSStringFromClass([self superclass]));
        NSLog(@"%@", NSStringFromClass([super superclass]));
    }
return self;
}
@end
```



### 代码二

```objc
@interface Person : NSObject
@end

@implementation Person
@end

int main(int argc, const char * argv[]) {
  @autoreleasepool {
      BOOL res1 = [(id)[NSObject class] isKindOfClass:[NSObject class]];
      BOOL res2 = [(id)[NSObject class] isMemberOfClass:[NSObject class]];
      BOOL res3 = [(id)[Person class] isKindOfClass:[Person class]];
      BOOL res4 = [(id)[Person class] isMemberOfClass:[Person class]];

      NSLog(@"%d %d %d %d", res1, res2, res3, res4);
    
      BOOL res5 = [(id)[NSObject alloc] isKindOfClass:[NSObject class]];
      BOOL res6 = [(id)[NSObject alloc] isMemberOfClass:[NSObject class]];
      BOOL res7 = [(id)[Person alloc] isKindOfClass:[Person class]];
      BOOL res8 = [(id)[Person alloc] isMemberOfClass:[Person class]];
    
      NSLog(@"%d %d %d %d", res5, res6, res7, res8);
  }
  return 0;
}
```

在打印结果之前，我们先来看一下这两个函数的源码

```objective-c
+ (BOOL)isMemberOfClass:(Class)cls {
    return self->ISA() == cls;
}

- (BOOL)isMemberOfClass:(Class)cls {
    return [self class] == cls;
}

+ (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = self->ISA(); tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

- (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = [self class]; tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}
```

`+ (BOOL)isKindOfClass:(Class)cls`方法内部，会调用 `self->ISA()`, 去获取objct

```objective-c
// Calls [obj isKindOfClass]
BOOL
objc_opt_isKindOfClass(id obj, Class otherClass)
{
#if __OBJC2__
    if (slowpath(!obj)) return NO;
    Class cls = obj->getIsa();
    if (fastpath(!cls->hasCustomCore())) {
        for (Class tcls = cls; tcls; tcls = tcls->superclass) {
            if (tcls == otherClass) return YES;
        }
        return NO;
    }
#endif
    return ((BOOL(*)(id, SEL, Class))objc_msgSend)(obj, @selector(isKindOfClass:), otherClass);
}
```



### 代码三



```objc
@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
- (void)speak;
@end
@implementation Sark
- (void)speak {                            
   NSLog(@"my name's %@", self.name);
}
@end
  
@implementation ViewController
- (void)viewDidLoad {  
   [super viewDidLoad];
  
   id cls = [Sark class];
   void *obj = &cls;
   [(__bridge id)obj speak];
}
@end
```



> 参考资料：
>
> [从源代码看 ObjC 中消息的发送](https://github.com/draveness/analyze/blob/master/contents/objc/%E4%BB%8E%E6%BA%90%E4%BB%A3%E7%A0%81%E7%9C%8B%20ObjC%20%E4%B8%AD%E6%B6%88%E6%81%AF%E7%9A%84%E5%8F%91%E9%80%81.md)