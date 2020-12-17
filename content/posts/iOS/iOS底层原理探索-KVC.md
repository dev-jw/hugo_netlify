---
title: "iOS底层原理探索-KVC"
date: 2020-10-24T14:35:29+08:00
draft: false
tags: ["iOS"]
url:  "kvc"
---

开发中经常使用的**KVC**，本来将对其底层原理进行探索分析

同样的，几个问题：

- KVC 的取值过程
- KVC 的赋值过程
- KVC 的常见使用场景

### KVC简介

`KVC(Key-Value Coding)`——键值编码，是由`NSKeyValueCoding`非正式协议启用的一种机制，对象采用该机制来间接访问属性

在日常开发中，经常用到的

```objective-c
// 通过 key 设值
- (void)setValue:(nullable id)value forKey:(NSString *)key;

// 通过 key 取值
- (nullable id)valueForKey:(NSString *)key;

// 通过 keyPath 设值
- (void)setValue:(nullable id)value forKeyPath:(NSString *)keyPath;

// 通过 keyPath 取值
- (nullable id)valueForKeyPath:(NSString *)keyPath;
```

`NSKeyValueCoding`的其它方法

```objective-c
// 默认为YES。 如果返回为YES,如果没有找到 set<Key> 方法的话, 会按照_key, _isKey, key, isKey的顺序搜索成员变量, 返回NO则不会搜索
+ (BOOL)accessInstanceVariablesDirectly;

// 键值验证, 可以通过该方法检验键值的正确性, 然后做出相应的处理
- (BOOL)validateValue:(inout id _Nullable * _Nonnull)ioValue forKey:(NSString *)inKey error:(out NSError **)outError;

// 如果key不存在, 并且没有搜索到和key有关的字段, 会调用此方法, 默认抛出异常。两个方法分别对应 get 和 set 的情况
- (nullable id)valueForUndefinedKey:(NSString *)key;
- (void)setValue:(nullable id)value forUndefinedKey:(NSString *)key;

// setValue方法传 nil 时调用的方法
// 注意文档说明: 当且仅当 NSNumber 和 NSValue 类型时才会调用此方法 
- (void)setNilValueForKey:(NSString *)key;

// 一组 key对应的value, 将其转成字典返回, 可用于将 Model 转成字典
- (NSDictionary<NSString *, id> *)dictionaryWithValuesForKeys:(NSArray<NSString *> *)keys;
```

### KVC使用

用例定义

```objective-c
typedef struct {
    float x, y, z;
} ThreeFloats;

@interface Person : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger age;
@property (nonatomic, copy) NSArray  *family;
@property (nonatomic) ThreeFloats threeFloats;
@property (nonatomic, strong) FXFriend *friends;
@end

@interface Friend : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger age;
@end
```

#### 基本使用

> 注意一下`NSInteger`这类的属性赋值时要转成`NSNumber`或`NSString`

```objective-c
[person setValue:@"Zsy" forKey:@"name"];

[person setValue:@(18) forKey:@"age"];

NSLog(@"名字%@ 年龄%@", [person valueForKey:@"name"], [person valueForKey:@"age"]);
```

#### 集合类型

两种方法对数组进行赋值，更推荐使用第二种方法

```objective-c
person.family = @[@"Person", @"Father"];

// 直接用新的数组赋值
NSArray *temp = @[@"Person", @"Father", @"Mother"];
[person setValue:temp forKey:@"family"];
NSLog(@"第一次改变%@", [person valueForKey:@"family"]);

// 取出数组以可变数组形式保存，再修改
NSMutableArray *mTemp = [person mutableArrayValueForKeyPath:@"family"];
[mTemp addObject:@"Child"];
NSLog(@"第二次改变%@", [person valueForKey:@"family"]);
```

#### 访问非对象类型——结构体

- 对于非对象类型的赋值总是把它先转成NSValue类型再进行存储
- 取值时转成对应类型后再使用

```objective-c
// 赋值
ThreeFloats floats = {180.0, 180.0, 18.0};
NSValue *value = [NSValue valueWithBytes:&floats objCType:@encode(ThreeFloats)];
[person setValue:value forKey:@"threeFloats"];
NSLog(@"非对象类型%@", [person valueForKey:@"threeFloats"]);

// 取值
ThreeFloats th;
NSValue *currentValue = [person valueForKey:@"threeFloats"];
[currentValue getValue:&th];
NSLog(@"非对象类型的值%f-%f-%f", th.x, th.y, th.z);
```

#### 集合操作符

- 聚合操作符
  - `@avg`: 返回操作对象指定属性的平均值
  - `@count`: 返回操作对象指定属性的个数
  - `@max`: 返回操作对象指定属性的最大值
  - `@min`: 返回操作对象指定属性的最小值
  - `@sum`: 返回操作对象指定属性值之和
- 数组操作符
  - `@distinctUnionOfObjects`: 返回操作对象指定属性的集合--去重
  - `@unionOfObjects`: 返回操作对象指定属性的集合
- 嵌套操作符
  - `@distinctUnionOfArrays`: 返回操作对象(嵌套集合)指定属性的集合--去重，返回的是 NSArray
  - `@unionOfArrays`: 返回操作对象(集合)指定属性的集合
  - `@distinctUnionOfSets`: 返回操作对象(嵌套集合)指定属性的集合--去重，返回的是 NSSet

> 集合操作符用得少之又少

```objective-c
Person *person = [Person new];

NSMutableArray *friendArray = [NSMutableArray array];
for (int i = 0; i < 6; i++) {
    Friend *f = [Friend new];
    NSDictionary* dict = @{
                           @"name":@"Zsy",
                           @"age":@(18+i),
                           };
    [f setValuesForKeysWithDictionary:dict];
    [friendArray addObject:f];
}
NSLog(@"%@", [friendArray valueForKey:@"age"]);

float avg = [[friendArray valueForKeyPath:@"@avg.age"] floatValue];
NSLog(@"平均年龄%f", avg);

int count = [[friendArray valueForKeyPath:@"@count.age"] intValue];
NSLog(@"调查人口%d", count);

int sum = [[friendArray valueForKeyPath:@"@sum.age"] intValue];
NSLog(@"年龄总和%d", sum);

int max = [[friendArray valueForKeyPath:@"@max.age"] intValue];
NSLog(@"最大年龄%d", max);

int min = [[friendArray valueForKeyPath:@"@min.age"] intValue];
NSLog(@"最小年龄%d", min);
```

#### 层层嵌套

通过`forKeyPath`对实例变量`friends`进行取值赋值

```objective-c
Person *person = [Person new];

Friend *f = [[Friend alloc] init];
f.name = @"Zsy----";
f.age = 18;
person.friends = f;
[person setValue:@"dev" forKeyPath:@"friends.name"];
NSLog(@"%@", [person valueForKeyPath:@"friends.name"]);
```

### KVC底层原理

由于`NSKeyValueCoding`的实现在`Foundation`框架，但它又不开源，但是通过[KVO官方文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/KeyValueCoding/index.html#//apple_ref/doc/uid/10000107-SW1)可以了解它

#### 取值过程

根据官方文档，「Set」过程为：

- 按 `set<Key>: -> _set<Key>: -> setIs<Key>:` 顺序查找对象中是否有对应的方法

  - 存在，调用赋值
  - 不存在，跳转到下一步

- 判断`accessInstanceVariablesDirectly`返回结果

  - 为 `true`，按照`_<key> -> _is<Key> -> <key> -> is<Key>`的顺序查找成员变量，如果找到，则赋值，否则跳转到下一步
  - 为 `false`，跳转到下一步

- 调用`setValue：forUndefinedKey:`，默认抛出`NSUndefinedKeyException`异常

  > 继承于`NSObject`的子类可以重写该方法就可以避免崩溃并做出相应措施

![image-20201214213728658](https://w-md.imzsy.design/image-20201214213728658.png)

#### 赋值过程

同样的，根据官方文档，KVC取值的过程为：

- **①** 首先查找getter方法，按照`get<Key> -> <key> -> is<Key> -> _<key>`的方法顺序查找

  - 如果`找到`，则进入 **⑤**
  - 如果`没有找到`，则进入而 **②**

- **②** 查找`countOf<Key>`和`objectIn<Key>AtIndex:`以及`<key>AtIndexes:`方法

  - 如果找到`countOf <Key>`和其他两个中的一个，则会创建一个响应所有`NSArray`方法的`集合代理对象`，并返回该对象，即`NSKeyValueArray`，是`NSArray`的`子类`

    代理对象随后将接收到的所有NSArray消息转换为`countOf<Key>，objectIn<Key> AtIndex：和<key>AtIndexes：`消息的某种组合，用来创建键值编码对象

    如果原始对象还实现了一个名为`get<Key>：range：`之类的可选方法，则代理对象也将在适当时使用该方法（注意：方法名的命名规则要符合KVC的标准命名方法，包括方法签名）

  - 如果没有找到这三个访问数组的，请继续进入 **③**

- **③** 查找`countOf <Key>，enumeratorOf<Key>`和`memberOf<Key>`

  - 如果这三个方法都找到，则会创建一个响应`所有NSSet方法的集合代理对象`，并返回该对象

    此代理对象随后将其收到的所有`NSSet`消息转换为`countOf<Key>，enumeratorOf<Key>和memberOf<Key>：`消息的某种组合，用于创建它的对象

  - 如果还是没有找到，则进入 **④**

- **④** 判断`accessInstanceVariablesDirectly`返回值

  - 如果为`true`，按照`_<key> -> _is<Key> -> <key> -> is<Key>`的顺序查找成员变量
  - 如果为`false`，跳转至入 **⑥**

- **⑤** 判断取出的属性值

  - 如果是**对象指针**，则直接返回
  - 如果是`NSNumber`支持的标量类型，则将属性值转化为 `NSNumber`类型
  - 如果不是对象，也不支持`NSNumber`类型，则将其转为 `NSValue` 类型返回

- **⑥** 调用`valueForUndefinedKey:`，默认抛出异常`NSUndefinedKeyException`

> 继承于`NSObject`的子类可以重写该方法就可以避免崩溃并做出相应措施

![image-20201214192847068](https://w-md.imzsy.design/image-20201214192847068.png)

### 自定义 KVC

#### 自定义设值

自定义KVC设置流程，主要分为以下几个步骤：

- 1、判断`key非空`
- 2、查找`setter`方法，顺序是：`setXXX、_setXXX、 setIsXXX`
- 3、判断是否响应`accessInstanceVariablesDirectly`方法，即间接访问实例变量
  - 返回`YES`，继续下一步设值，
  - 如果是`NO`，则崩溃
- 4、间接访问变量赋值（只会走一次），顺序是：`_key、_isKey、key、isKey`
  - 4.1 定义一个收集实例变量的可变数组
  - 4.2 通过`class_getInstanceVariable`方法，获取相应的 ivar
  - 4.3 通过`object_setIvar`方法，对相应的 ivar 设置值
- 5、如果找不到相关实例变量，则抛出异常

```objective-c
- (void)custom_setValue:(id)value forKey:(NSString *)key {
    // 判断 key 是否存在
    if (key == nil || key.length == 0) return;
    
    // set<Key>、_set<Key> setIsKey顺序调用
    NSString *Key = key.capitalizedString; // key 格式化
    NSString *setKey   = [NSString stringWithFormat:@"set%@:", Key];
    NSString *_setKey  = [NSString stringWithFormat:@"_set%@:", Key];
    NSString *setIsKey = [NSString stringWithFormat:@"setIs%@:", Key];
    
    if ([self kvc_performSelectorWithMethod:setKey value:value]) {
        NSLog(@"调用了 %@", setKey);
        return;
    }
    
    if ([self kvc_performSelectorWithMethod:_setKey value:value]) {
        NSLog(@"调用了 %@", _setKey);
        return;
    }
    
    if ([self kvc_performSelectorWithMethod:setIsKey value:value]) {
        NSLog(@"调用了 %@", setIsKey);
        return;
    }
    
    NSString *undefinedMethodName = @"setValue:forUndefinedKey:";
    IMP undefinedIMP = class_getMethodImplementation(self.class, NSSelectorFromString(undefinedMethodName));
    
    // 判断 accessInstanceVariablesDirectly
    if (![self.class accessInstanceVariablesDirectly]) {
        if (undefinedIMP) {
            [self kvc_performSelectorWithMethodName:undefinedMethodName value:value key:key];
        }else {
            @throw [NSException exceptionWithName:@"KVC_UnKnownKeyException"
                                           reason:[NSString stringWithFormat:@"****[%@ %@]: this class is not key value coding-compliant for the key %@.", self, NSStringFromSelector(_cmd), key]
                                         userInfo:nil];
        }
    }
    
    // 访问变量赋值，顺序为：_key、_isKey、key、isKey
    NSArray *mArray = [self getIvarListName];
    
    NSString *_key   = [NSString stringWithFormat:@"_%@", key];
    NSString *_isKey  = [NSString stringWithFormat:@"_is%@", Key];
    NSString *isKey = [NSString stringWithFormat:@"is%@", Key];
    
    if ([mArray containsObject:_key]) {
        Ivar ivar = class_getInstanceVariable(self.class, _key.UTF8String);
        object_setIvar(self, ivar, value);
        return;
    }else if ([mArray containsObject:_isKey]) {
        Ivar ivar = class_getInstanceVariable(self.class, _isKey.UTF8String);
        object_setIvar(self, ivar, value);
        return;
    }else if ([mArray containsObject:key]) {
        Ivar ivar = class_getInstanceVariable(self.class, key.UTF8String);
        object_setIvar(self, ivar, value);
        return;
    }else if ([mArray containsObject:isKey]) {
        Ivar ivar = class_getInstanceVariable(self.class, isKey.UTF8String);
        object_setIvar(self, ivar, value);
        return;
    }
    
    if (undefinedIMP) {
        [self kvc_performSelectorWithMethodName:undefinedMethodName value:value key:key];
    }else {
        // 异常
        @throw [NSException exceptionWithName:@"KVC_UnKnownKeyException"
                                       reason:[NSString stringWithFormat:@"****[%@ %@]: this class is not key value coding-compliant for the key %@.", self, NSStringFromSelector(_cmd), key]
                                     userInfo:nil];
    }
}
```



#### 自定义取值

取值的自定义代码如下，分为以下几步

- 1、判断`key非空`
- 2、查找相应方法，顺序是：`get<Key>、 <key>、 countOf<Key>、 objectIn<Key>AtIndex`
- 3、判断是否能够直接赋值实例变量，即判断是否响应`accessInstanceVariablesDirectly`方法，间接访问实例变量
  - 返回`YES`，继续下一步取值
  - 如果是`NO`，则崩溃
- 4、间接访问实例变量，顺序是`：_<key> _is<Key> <key> is<Key>`
  - 4.1 定义一个收集实例变量的`可变数组`
  - 4.2 通过`class_getInstanceVariable`方法，获取相应的 ivar
  - 4.3 通过`object_getIvar`方法，返回相应的 ivar 的值

```objective-c
- (id)custom_valueForKey:(NSString *)key {
    
    if (key == nil || key.length == 0) return nil;
    
    // get<Key> <key> countOf<Key> objectIn<Key>AtIndex
    NSString *Key                = key.capitalizedString;
    NSString *getKey             = [NSString stringWithFormat:@"get%@", Key];
    NSString *countOfKey         = [NSString stringWithFormat:@"countOf%@", Key];
    NSString *objectInKeyAtIndex = [NSString stringWithFormat:@"objectIn%@AtIndex:", Key];
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([self respondsToSelector:NSSelectorFromString(getKey)]) {
        return [self performSelector:NSSelectorFromString(getKey)];
    }else if ([self respondsToSelector:NSSelectorFromString(key)]) {
        return [self performSelector:NSSelectorFromString(key)];
    }else if ([self respondsToSelector:NSSelectorFromString(countOfKey)]) {
        // 集合类型
        if ([self respondsToSelector:NSSelectorFromString(objectInKeyAtIndex)]) {
            
            int num = (int)[self performSelector:NSSelectorFromString(countOfKey)];
        
            NSMutableArray *mArray = [NSMutableArray arrayWithCapacity:1];

            for (int i = 0; i < num - 1; i++) {
                num = (int)[self performSelector:NSSelectorFromString(countOfKey)];
            }
            
            for (int i = 0; i < num; i++) {
                id obj = [self performSelector:NSSelectorFromString(objectInKeyAtIndex) withObject:@(num)];
                [mArray addObject:obj];
            }
            
            return mArray;
        }
    }
#pragma clang diagnostic pop

    NSString *undefineMethodName = @"valueForUndefinedKey:";
    IMP undefineIMP = class_getMethodImplementation(self.class, NSSelectorFromString(undefineMethodName));
    
    if (![self.class accessInstanceVariablesDirectly]) {
        if (undefineIMP) {
            [self kvc_performSelectorWithMethod:undefineMethodName value:key];
        }else {
            @throw [NSException exceptionWithName:@"KVC_UnKnownKeyException"
                                           reason:[NSString stringWithFormat:@"****[%@ %@]: this class is not key value coding-compliant for the key %@.", self, NSStringFromSelector(_cmd), key]
                                         userInfo:nil];
        }
    }
    
    NSArray *mArr = [self getIvarListName];
    NSString *_key = [NSString stringWithFormat:@"_%@", key];
    NSString *_isKey = [NSString stringWithFormat:@"_is%@", Key];
    NSString *isKey = [NSString stringWithFormat:@"is%@", Key];
    
    if ([mArr containsObject:_key]) {
        Ivar ivar = class_getInstanceVariable(self.class, _key.UTF8String);
        return object_getIvar(self, ivar);
    }else if ([mArr containsObject:_isKey]) {
        Ivar ivar = class_getInstanceVariable(self.class, _isKey.UTF8String);
        return object_getIvar(self, ivar);
    }else if ([mArr containsObject:Key]) {
        Ivar ivar = class_getInstanceVariable(self.class, Key.UTF8String);
        return object_getIvar(self, ivar);
    }else if ([mArr containsObject:isKey]) {
        Ivar ivar = class_getInstanceVariable(self.class, isKey.UTF8String);
        return object_getIvar(self, ivar);
    }
    
    if (undefineIMP) {
        [self kvc_performSelectorWithMethod:undefineMethodName value:key];
    }else {
        @throw [NSException exceptionWithName:@"KVC_UnKnownKeyException"
                                       reason:[NSString stringWithFormat:@"****[%@ %@]: this class is not key value coding-compliant for the key %@.", self, NSStringFromSelector(_cmd), key]
                                     userInfo:nil];
    }
    
    return nil;
}
```

[完整 Demo](https://github.com/dev-jw/Custom_KVO) 

### KVC 使用场景

#### 动态设值和取值

- 常用的可以通过`setValue:forKey:` 和 `valueForKey:`
- 也可以通过`keyPath`的方式`setValue:forKeyPath:` 和 `valueForKeyPath:`

#### 通过 KVC 访问和修改私有变量

对系统内部控件，没有提供访问的 API，可以通过 KVC 去访问并修改，例如：`UITextField`中的 `placeHolderTextColor`

#### 多值操作

常见于字典与模型相互转化