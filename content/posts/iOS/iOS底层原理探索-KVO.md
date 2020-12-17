---
title: "iOS底层原理探索-KVO"
date: 2020-10-28T14:35:29+08:00
draft: false
tags: ["iOS"]
url:  "kvo"
---

**KVO**，全称为 **Key-Value observing**（键值观察）本文将对其原理进行分析

同样的，几个问题：

- KVO 使用时的注意点
- KVO 原理

### KVO简述

KVO 是苹果提供的一套事件通知机制，这种机制允许将其他对象的特定属性的变化通知给对象

iOS开发者可以用 KVO 来监测对象属性的变化并作出响应，这使得我们在开发强交互、响应式应用以及实现视图和模型的双向绑定时提供大量的帮助

`KVO` 与 `NSNotificatioCenter` 都是观察者模式的一种实现，而区别在于：

- 相对于被观察者和观察者之间的关系，`KVO` 是一对一的，`NSNotificatioCenter` 是一对多的
- `KVO` 对被监听对象无侵入性，不需要修改其他内部代码即可实现监听

### KVO使用时的注意点

#### 基本使用

**注册观察者**

```objective-c
[self.person addObserver:self forKeyPath:@"name" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:NULL];
```

**实现回调**

```objective-c
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"name"]) NSLog(@"%@", change);
}
```

**移除观察者**

```objective-c
[self.person removeObserver:self forKeyPath:@"name"];
```

#### context的使用

关于 `context` 在官方文档是这样描述的

![image-20201217151140699](https://w-md.imzsy.design/image-20201217151140699.png)

大致含义就是：`addObserver：forKeyPath：options：context：`方法中的`上下文context`指针包含任意数据，这些数据将在相应的更改通知中传递回观察者。

可以通过`指定context为NULL`，从而`依靠keyPath`即`键路径字符串`传来确定更改通知的来源，但是这种方法可能会导致对象的父类由于不同的原因也观察到相同的键路径而导致问题。

所以可以为每个观察到的`keyPath`创建一个不同的`context`，从而`完全不需要进行字符串比较`，从而可以更有效地进行通知解析

通俗的讲，context上下文主要是用于`区分不同对象的同名属性`，从而在KVO回调方法中可以`直接使用context进行区分，可以大大提升性能，以及代码的可读性`

`context`使用总结

- 不使用`context`作为观察值

  ```objective-c
  [self.person addObserver:self forKeyPath:@"name" options:(NSKeyValueObservingOptionNew) context:NULL];
  ```

- 使用`context`传递信息

  ```objective-c
  static void *PersonNameContext = &PersonNameContext;
  static void *ChildNameContext = &ChildNameContext;
  
  [self.person addObserver:self forKeyPath:@"name" options:(NSKeyValueObservingOptionNew) context:PersonNameContext];
  [self.child addObserver:self forKeyPath:@"name" options:(NSKeyValueObservingOptionNew) context:ChildNameContext];
  
  - (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
      if (context == PersonNameContext) {
          NSLog(@"%@", change);
      } else if (context == ChildNameContext) {
          NSLog(@"%@", change);
      }
  }
  ```

#### 移除通知的必要性

在官方文档中，针对`KVO的移除`有以下几点说明

![image-20201217151202375](https://w-md.imzsy.design/image-20201217151202375.png)

删除观察者时，请记住以下几点：

- 要求被移除为观察者（如果尚未注册为观察者）会导致`NSRangeException`。您可以对`removeObserver：forKeyPath：context：`进行一次调用，以对应对`addObserver：forKeyPath：options：context：`的调用，或者，如果在您的应用中不可行，则将`removeObserver：forKeyPath：context：`调用在`try / catch块`内处理潜在的异常
- `释放后，观察者不会自动将其自身移除`。被观察对象继续发送通知，而忽略了观察者的状态。但是，与发送到已释放对象的任何其他消息一样，更改通知会触发内存访问异常。因此，您可以`确保观察者在从内存中消失之前将自己删除`
- 该协议无法询问对象是观察者还是被观察者。构造代码以避免发布相关的错误。一种典型的模式是在观察者初始化期间（例如，`在init或viewDidLoad中）注册为观察者`，并在释放过程中（通常`在dealloc中）注销`，以`确保成对和有序地添加和删除消息`，并确`保观察者在注册之前被取消注册，从内存中释放出来`

总得来说，KVO注册观察者和移除观察者必须是成对使用的，否则会出现类似野指针问题

例如：对单例对象添加观察者，由于单例对象是跟随应用常驻的，因为没有移除观察，就会出现重复注册观察，从而造成类似野指针的崩溃

> 苹果官方推荐的方式是——在`init`的时候进行`addObserver`，在`dealloc`时`removeObserver`，这样可以保证`add`和`remove`是成对出现的，这是一种比较理想的使用方式

#### KVO的自动触发与手动触发

`automaticallyNotifiesObserversForKey`返回结果表示 KVO 是自动触发还是手动触发

返回 YES，就是自动触发

```objective-c
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    return YES;
}
```

返回 NO，是手动触发，需要通过手动监听

```objective-c
- (void)setName:(NSString *)name{
    //手动开关
    [self willChangeValueForKey:@"name"];
    _name = name;
    [self didChangeValueForKey:@"name"];
}
```

#### 键值观察一对多

KVO观察中的`一对多`，意思是通过`注册一个KVO观察者，可以监听多个属性的变化`

比如有一个下载任务的需求，根据`总下载量Total`和`当前已下载量Current`来得到`当前下载进度Process`，这个需求就有两种实现：

- 分别观察`总下载量Total`和`当前已下载量Current`两个属性，其中一个属性发生变化时计算求值`当前下载进度Process`
- 实现`keyPathsForValuesAffectingValueForKey`方法，并观察`process`属性

只要`总下载量Total`或`当前已下载量Current`任意发生变化，`keyPaths=process`就能收到监听回调

```objective-c
+ (NSSet<NSString *> *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    NSSet *keyPaths = [super keyPathsForValuesAffectingValueForKey:key];
    if ([key isEqualToString:@"process"]) {
        NSArray *affectingKeys = @[@"total", @"current"];
        keyPaths = [keyPaths setByAddingObjectsFromArray:affectingKeys];
    }
    return keyPaths;
}
```

#### 可变数组

下面的代码，点击屏幕时并不会输出change

```objective-c
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.person = [Person new];
    [self.person addObserver:self forKeyPath:@"dataArray" options:(NSKeyValueObservingOptionNew) context:NULL];
  
    self.person.dateArray = [NSMutableArray arrayWithCapacity:1];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"dataArray"]) NSLog(@"%@", change);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.person.dataArray addObject:@"1"];
}
```

**分析**

由于 KVO 是建立在 KVC 的基础上的，而可变数组如果直接添加数据，是不会调用 `Setter` 方法

**解决**

在KVC官方文档中，针对`可变数组的集合`类型，有如下说明，即访问集合对象需要需要通过`mutableArrayValueForKey`方法，这样才能`将元素添加到可变数组`中

```objective-c
[[self.person mutableArrayValueForKey:@"dateArray"] addObject:@"1"];
```

一般属性与集合的 KVO 观察是有区别的，其回调参数 `change` 中的 `kind` 是不同的

- 属性一般是设值，即`NSKeyValueChangeSetting`
- 集合一把是插入，即`NSKeyValueChangeInsertion`

```objective-c
typedef NS_ENUM(NSUInteger, NSKeyValueChange) {
    NSKeyValueChangeSetting = 1,  //设值
    NSKeyValueChangeInsertion = 2,//插入
    NSKeyValueChangeRemoval = 3,  //移除
    NSKeyValueChangeReplacement = 4,//替换
};
```

### KVO原理

在官方文档中，对于 KVO 的实现有这样的描述

![image-20201217154018571](https://w-md.imzsy.design/image-20201217154018571.png)

- KVO是使用 `isa-swizzling` 技术实现的
- isa 指针指向维护分配表的对象的类，该分派表实质上包含该类实现的方法的指针及其他数据
- 当对象的属性注册观察时，将修改观察对象的 isa 指针，指向中间类而不是真实类。isa 指针的值不一定反应实例的实际类
- 你永远不应依靠 isa 指针来确定类成员身份。相反，你应该使用 class 方法来确定对象实例的类

#### 代码调式探索

**KVO 只对属性观察**

在类Person中有一个`成员变量name` 和 `属性nickName`，分别注册KVO观察，触发属性变化时，会有什么现象？

- 分别为`成员变量name` 和 `属性nickName`注册KVO观察

```objective-c
self.person = [[LGPerson alloc] init];
[self.person addObserver:self forKeyPath:@"nickName" options:(NSKeyValueObservingOptionNew) context:NULL];
[self.person addObserver:self forKeyPath:@"name" options:(NSKeyValueObservingOptionNew) context:NULL];

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"%@", object);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSLog(@"实际情况:%@-%@",self.person.nickName,self.person->name);
    self.person.nickName = @"Zsy";
    self.person->name    = @"dev";
}

// 输出
实际情况：(null)-(null)
{
   kind = 1;
   new = Zsy
}
```

结论：KVO 只对属性观察，而成员变量不观察，这也验证了 KVO 是建立在 KVC 的基础上的，因为成员变量没有 setter 方法

**中间类**

在注册 KVO 观察者后，观察对象的 isa 指针指向会改变

- 注册观察者之前：类对象为 Person，实例对象 isa 指向 Person

  ```objective-c
  // 调式输出
  po object_getClassName(self.person)
  "Person"
  ```

- 注册观察者之后：类对象为 Person，实例对象 isa 指向 NSKVONotifying_Person

  ```objective-c
  // 调式输出
  po object_getClassName(self.person)
  "NSKVONotifying_Person"
  ```

通过分别在注册 KVO 观察前后输出，可知：实例对象的 isa 指针指向由 `Person` 类变为 `NSKVONotifying_Person`中间类

那么`NSKVONotifying_Person`与`Person`有什么关系呢？

通过下面的方法，获取 `Person` 的相关类

```objective-c
#pragma mark - 遍历类以及子类
- (void)printClasses:(Class)cls{
    
    // 注册类的总数
    int count = objc_getClassList(NULL, 0);
    // 创建一个数组， 其中包含给定对象
    NSMutableArray *mArray = [NSMutableArray arrayWithObject:cls];
    // 获取所有已注册的类
    Class* classes = (Class*)malloc(sizeof(Class)*count);
    objc_getClassList(classes, count);
    for (int i = 0; i<count; i++) {
        if (cls == class_getSuperclass(classes[i])) {
            [mArray addObject:classes[i]];
        }
    }
    free(classes);
    NSLog(@"classes = %@", mArray);
}
```

打印结果：

```ruby
# 注册 KVO 前
class = (
	Person
)
# 注册 KVO 后
class = (
	Person,
	"NSKVONotifying_Person"
)
```

这就说明，`NSKVONotifying_Person`是`Person`的子类

#### 动态子类探索

获取`NSKVONotifying_Person`类中的所有方法

```objective-c
#pragma mark - 遍历方法-ivar-property
- (void)printClassAllMethod:(Class)cls{
    unsigned int count = 0;
    Method *methodList = class_copyMethodList(cls, &count);
    for (int i = 0; i<count; i++) {
        Method method = methodList[i];
        SEL sel = method_getName(method);
        IMP imp = class_getMethodImplementation(cls, sel);
        NSLog(@"%@-%p",NSStringFromSelector(sel),imp);
    }
    free(methodList);
}

//********调用********
[self printClassAllMethod:objc_getClass("NSKVONotifying_Person")];

//********输出********
// setName:-0x7fff207bab57
// class-0x7fff207b9662
// dealloc-0x7fff207b940b
// _isKVOA-0x7fff207b9403

//********调用********
[self printClassAllMethod:objc_getClass("Person")];
//********输出********
// name-0x10a6acd50
// .cxx_destruct-0x10a6acdb0
// setName:-0x10a6acd70
```

通过打印可以看出：

- `Person`类中的方法没有改变
- `NSKVONotifying_Person`类重写基类 `NSObject` 的 `class、dealloc、_isKVOA` 方法
  - `class` —— 重写 class 方法，将 isa 指向 `NSKVONotifying_Person`
  - `dealloc` —— 重写 dealloc 方法，将 isa 指回 `Person`
  - `_isKVOA` —— 用于判断当前是否是 KVO 类
- `NSKVONotifying_Person`类重写父类的 `setName` 方法
  - 子类只继承、不重写是不会有方法 IMP，且两个 setName 的地址不一样

**dealloc之后动态子类会销毁吗？**

答：不会销毁

中间类一旦生成，会一直存在在内存中 —— 主要是考虑重用的，避免重复多次注册动态子类到内存中

**automaticallyNotifiesObserversForKey是否会影响动态子类生成**

答：会

动态子类会根据观察属性的`automaticallyNotifiesObserversForKey`的布尔值来决定是否生成

总结：

1. `automaticallyNotifiesObserversForKey`为`YES`时注册观察属性会生成动态子类`NSKVONotifying_XXX`
2. 动态子类观察的是`setter`方法
3. 动态子类重写了观察属性的`setter`方法、`dealloc`、`class`、`_isKVOA`方法
   - `setter`方法用于观察键值
   - `dealloc`方法用于释放时对isa指向进行操作
   - `class`方法用于指回动态子类的父类
   - `_isKVOA`用来标识是否是在观察者状态的一个标志位
4. `dealloc` 之后 `isa` 指向原来的类 —— 父类
5. `dealloc` 之后动态子类不会销毁

### 自定义KVO

自定KVO的流程，跟系统一致，只是在系统的基础上针对其中的部分做了一些优化处理。

- 1、将`注册和响应`通过函数式编程，即`block`的方法结合在一起
- 2、去掉系统繁琐的三部曲，实现`KVO自动销毁机制`

**定义 block，注册观察方法，移除观察方法**

```objective-c
typedef void(^KVOBlock)(id observer,NSString *keyPath,id oldValue,id newValue);

- (void)kvo_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath handleBlock:(KVOBlock)block;

- (void)kvo_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;
```
整个过程为：

1. 判断当前观察值 `keyPath` 的 `setter` 方法是否存在

   ```objective-c
   - (BOOL)judgeSetterMethodFromKeyPath:(NSString *)keyPath {
       
       Class superClass = object_getClass(self);
       
       SEL setterSelector = NSSelectorFromString(setterForGetter(keyPath));
       
       Method setterMethod = class_getInstanceMethod(superClass, setterSelector);
       
       if (!setterMethod) {
           NSLog(@"没有找到该属性的setter方法--%@", keyPath);
           return NO;
       }
       return YES;
   }
   
   #pragma mark - 从get方法获取set方法的名称
   static NSString *setterForGetter(NSString *getter) {
       if (getter.length <= 0) { return nil; }
       NSString *firstString = [[getter substringToIndex:1] uppercaseString];
       NSString *leaveString = [getter substringFromIndex:1];
       return [NSString stringWithFormat:@"set%@%@:",firstString,leaveString];
   }
   ```

2. 判断观察属性的`automaticallyNotifiesObserversForKey`方法返回的布尔值

   ```objective-c
   - (BOOL)kvo_performSelectorWithMethodName:(NSString *)methodName keyPath:(id)keyPath {
       
       if ([[self class] respondsToSelector:NSSelectorFromString(methodName)]) {
           
   #pragma clang diagnostic push
   #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
           BOOL i = [[self class] performSelector:NSSelectorFromString(methodName) withObject:keyPath];
           return i;
   #pragma clang diagnostic pop
       }
       return NO;
   }
   ```

3. 动态生成子类，添加`class`方法指向原先的类

   ```objective-c
   - (Class)cretaChildClassWithKeyPath:(NSString *)keyPath {
       
       NSString *oldClassName = NSStringFromClass(self.class);
       NSString *newClassName = [NSString stringWithFormat:@"%@%@", kKVOPrefix, oldClassName];
       
       Class newClass = NSClassFromString(newClassName);
       
       if (newClass) return newClass;
       
       newClass = objc_allocateClassPair(self.class, newClassName.UTF8String, 0);
       objc_registerClassPair(newClass);
       
       //  class
       SEL classSel = NSSelectorFromString(@"class");
       Method classMethod = class_getInstanceMethod(self.class, classSel);
       const char *classType = method_getTypeEncoding(classMethod);
       class_addMethod(newClass, classSel, (IMP)kvo_class, classType);
       
       // setter
       SEL setterSel = NSSelectorFromString(setterForGetter(keyPath));
       Method setterMethod = class_getInstanceMethod(self.class, setterSel);
       const char *setterType = method_getTypeEncoding(setterMethod);
       class_addMethod(newClass, setterSel, (IMP)kvo_setter, setterType);
       
       // dealloc
       static dispatch_once_t onceToken;
       dispatch_once(&onceToken, ^{
           [self kvo_MethodSwizzlingWithClass:self.class
                                       oriSEL:NSSelectorFromString(@"dealloc")
                                  swizzledSEL:@selector(kvo_dealloc)];
       });
       
       return newClass;
   }
   ```

   - 重写 `class` 方法

     ```objective-c
     Class kvo_class(id self, SEL _cmd) {
         return class_getSuperclass(object_getClass(self));
     }
     ```

     

   - 重写 `setter` 方法

     ```objective-c
     static void kvo_setter(id self,SEL _cmd,id newValue) {
         NSString *keyPath = getterForSetter(NSStringFromSelector(_cmd));
         
         id oldValue = [self valueForKey:keyPath];
         //通过系统强制类型转换自定义objc_msgSendSuper
         void (*kvo_msgSenderSuper)(void *, SEL, id) = (void *)objc_msgSendSuper;
         //定义一个结构体
         struct objc_super superStruct = {
             .receiver = self,
             .super_class = class_getSuperclass(object_getClass(self)),
         };
       //调用自定义的发送消息函数
         kvo_msgSenderSuper(&superStruct, _cmd, newValue);
       
         /*---函数式编程---*/
         //让vc去响应
         NSMutableArray *mArray = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kKVOAssiociateKey));
         for (KVOInfo *info in mArray) {
             if ([info.keyPath isEqualToString:keyPath] && info.handleBlock) {
                 info.handleBlock(info.observer, keyPath, oldValue, newValue);
             }
         }
     }
     ```

   - 重写 `dealloc` 方法

     ```objective-c
     - (void)kvo_dealloc {
         Class superClass = [self class];
         object_setClass(self, superClass);
         [self kvo_dealloc];
     }
     ```

     

4. isa重指向——使对象的`isa`的值指向动态子类

   ```objective-c
   object_setClass(self, newClass);
   ```

5. 保存信息

   ```objective-c
   @interface KVOInfo : NSObject
   
   @property (nonatomic, weak) NSObject *observer;
   
   @property (nonatomic, copy) NSString *keyPath;
   
   @property (nonatomic, copy) KVOBlock handleBlock;
   
   @end
   
   @implementation KVOInfo
   
   - (instancetype)initWitObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath handleBlock:(KVOBlock)block {
       if (self=[super init]) {
           _observer = observer;
           _keyPath  = keyPath;
           _handleBlock = block;
       }
       return self;
   }
   @end
     
   KVOInfo *info = [[KVOInfo alloc] initWitObserver:observer forKeyPath:keyPath handleBlock:block];
   NSMutableArray *mArray = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kKVOAssiociateKey));
   if (!mArray) {
       mArray = [NSMutableArray arrayWithCapacity:1];
       objc_setAssociatedObject(self, (__bridge const void * _Nonnull)(kKVOAssiociateKey), mArray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   }
   [mArray addObject:info];
   ```

这样自定义 KVO 就将 KVO 三步操作用 block 形式合成一步

自定义KVO整个过程大致分为以下几步

- 注册观察者 & 响应
  - 1、验证是否存在setter方法
  - 2、保存信息
  - 3、动态生成子类，需要重写`class`、`setter`方法
  - 4、在子类的setter方法中向父类发消息，即自定义消息发送
  - 5、让观察者响应
- 移除观察者
  - 1、更改`isa指向`为原有类
  - 2、重写子类的`dealloc`方法

[完整 Demo](https://github.com/dev-jw/Custom_KVO)

> 参考资料：
>
> [苹果官方文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/KeyValueObserving/KeyValueObserving.html)
>
> [J_Knight_写的SJKVOController](https://github.com/knightsj/SJKVOController)[FBKVO](https://github.com/facebookarchive/KVOController)（强烈建议阅读成熟的自定义 KVO）