---
title: "Flutter的混合开发"
date: 2020-06-20T16:46:21+08:00
draft: false
tags: ["Flutter"]
url:  "mixed"

---

> Flutter 开发非常的简便，声明式 UI 的编写风格十分的友好，但是在实际应用开发中，我们并不会去用 Flutter 开发，从 0 重新开发项目，更多的是基于原有的原生项目，将 Flutter 的页面嵌入

#### 混合开发的集成方式

目前项目集成方式有闲鱼技术和 `Flutter` 官方的两种方式。

1. 闲鱼技术的[Flutter混合工程改造实践](https://www.jianshu.com/p/64608e67af26)

   在这里，不得不说先入为主的重要性，Flutter 早期在混合开发这方面确实做的不足，闲鱼技术在这个上面踩了不少坑，但是真的很麻烦（毕竟在初期能解决问题的办法都是好办法）

2. Flutter 的[官方 Wiki 指南](https://flutter.dev/docs/development/add-to-app)

   开发者对于 Flutter 的混合开发呼声越来越高，为了满足开发者的要求，Flutter 也专门为了这个问题提供 **add to app** 的集成。官方的集成是特别的简单

#### 项目集成

这里采用了官方的集成： **add to app** 方式，且只是针对 iOS 平台集成。

**项目所需文件**

为了方便，将原生工程与 Flutter 工程放在同一个目录下。

* 创建 Flutter Module 工程

  可以通过命令行 `flutter create -t module flutter_module` 或 Android Studio 新建 flutter_module

* 创建 iOS 工程，使用 cocoapods 引用 Flutter

1. 通过 Xcode 新建原生工程
2. 初始化 Podfile
3. 执行 `pod install`

**Podfile** 中的内容：

```ruby
# Uncomment the next line to define a global platform for your project
flutter_application_path = '../flutter_module' # flutter_module 工程
load File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')

platform :ios, '9.0'

target 'NativeDemo' do
  install_all_flutter_pods(flutter_application_path)
  use_frameworks!

  # Pods for NativeDemo

end

```

至此，经过官方集成的步骤，我们可以得到如下的一个文件目录结构：

```
HybridApp
├── HybridiOSApp
│   ├── HybridiOSApp
│   ├── HybridiOSApp.xcodeproj
│   ├── HybridiOSAppTests
│   └── HybridiOSAppUITests
└── flutter_module
    ├── .android
    ├── .idea
    ├── .ios
    ├── lib
    └── test
```



#### Flutter 与原生 iOS 之间的通信

![Channel](https://w-md.imzsy.design//Channel.png)

Flutter 与 iOS 进行的交互是通过 Channel 的。

**常见的几种 Channel：**

* *FlutterMethodChannel*：用于传递方法调用（method invocation）通常用来调用native中某个方法
* *FlutterBasicMessageChannel*：用于传递字符串和半结构化的信息,这个用的比较少
* *FlutterEventChannel*：用于数据流（event streams）的通信。有监听功能，比如电量变化之后直接推送数据给flutter端

三种Channel之间互相独立，各有用途，但它们在设计上却非常相近。每种Channel均有三个重要成员变量：

* name: String类型，代表Channel的名字，也是其唯一标识符。

* messager：BinaryMessenger类型，代表消息信使，是消息的发送与接收的工具。

* codec: MessageCodec类型或MethodCodec类型，代表消息的编解码器。

*FlutterMethodChannel*是单次通信，其他的两种则是持续通信

**FlutterMethodChannel具体使用**

* Flutter 调用原生方法

```objective-c
    FlutterMethodChannel* methodChannel = [FlutterMethodChannel methodChannelWithName:@"MethodChannelName" binaryMessenger:flutterVC];
    [methodChannel setMethodCallHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        if ([@"foo" isEqualToString:call.method]) {
            result(some data);
        } else {
            result(FlutterMethodNotImplemented);
        }
    }];
```

channelName：channel唯一标识，Native侧和flutter侧保持名称一致
binaryMessenger：channel Context，数据通信时的上下文
handle：`typedef void (^FlutterMethodCallHandler)(FlutterMethodCall* call, FlutterResult result);`
FlutterMethodCall：包含`method`(方法名)和`arguments`(参数)的对象，管理方法对象
FlutterResult：`typedef void (^FlutterResult)(id _Nullable result);`

* 原生调用 Flutter 方法

```objective-c
    FlutterMethodChannel* methodChannel = [FlutterMethodChannel methodChannelWithName:@"MethodChannelName" binaryMessenger:flutterVC];

    [methodChannel invokeMethod:@"sayOK" arguments:nil];

```

同样，需要先定义一个管道，然后发生 invoke 消息，Method 对应是方法名，arguments是参数。

**在 Dart 中，MethodChannel 的使用**

```dart
  MethodChannel methodChannel = const MethodChannel('MethodChannelName');
  methodChannel.invokeMethod('foo', "你好");

  methodChannel.setMethodCallHandler((call) {
    if (call.method == 'sayOK') {
      print('sayOK');
    }
    return null;
  });
```

能够看到，其实和在 iOS 中使用有着非常的相似的，当然在 Dart 中尽可能的加上 Future、async异步操作去使用。

#### 小结

Flutter 虽然可以作为 module 被原生端去使用，但是频繁在 Flutter 与原生之间进行切换，是会造成内存的泄漏，本身官方的引擎就是存在这样的问题。所以尽量减少频繁切换、使用自定义的引擎、定义一个引擎单列等方法去避免内存泄漏的问题。

简单的 Flutter 混合工程 Demo，中间封装 engine 单列管理类，同时，这样避免了重新的声明，以及打开时内存的骤增。