---
title: "Dart异步小结"
date: 2020-06-03T17:40:46+08:00
draft: false
tags: ["Flutter", "Dart", "异步"]
url:  "Promise"
---

> 关于单线程和异步之间的关系，经常容易让人产生迷惑。
>
> 如果你之前有学习过签到的 Promise、await、async，可能会让你觉得 Dart 中大量的异步操作方式（Future、await、async 等）与之相同，实则并非如此

### 耗时操作

首先，来了解一下什么是耗时操作

#### 程序中的耗时操作

在开发中，经常会遇到一些耗时的操作，比如网络请求、文件读写等。

如果在主线程中一直等待这些耗时操作的完成，就会造成阻塞，无法响应其他事件，比如用户点击交换



#### 如何处理耗时操作

* 多线程：在`Java、Objective-C`等高级语言中，普遍是开启一个新的线程「**Thread**」，在新的线程中完成这些异步的操作，再通过线程间通信的方式，将数据传递给主线程
* 单线程+事件循环：像`JavaScript、Dart`都是基于单线程+事件循环来完成耗时操作的处理



> 很多开发者对单线程的异步操作都是非常疑惑的，其实它们两者并不冲突：
>
> * 一个程序大部分时间都是出于空间的状态，并不是无限制的在和用户进行交互
> * 比如等待用户点击、网络请求、文件读写，这些等待的行为之所以不会阻塞我们的线程，是因为它们都可以基于非阻塞调用



**阻塞式调用和非阻塞式调用**

阻塞和非阻塞关注的是**程序在等待调用结果的状态**

* 阻塞式调用：调用结果返回之前，当前线程会被挂起，调用线程只有在得到调用结果之后才会继续执行
* 非阻塞式调用：调用执行后，当前线程不会停止执行，只需要过一段时间来检查一下有没有结果返回即可

举个例子：当你寄一个快递，**寄快递的动作**就是调用，**快递被签收**则是等待的结果

* 阻塞式调用：寄出快递，不再做任何时间，就一直等待，你的线程停止了任何其他的工作
* 非阻塞式调用：寄出快递，继续做其他的事情，工作、玩游戏等，你的线程继续执行其他的事务，只是偶尔检查一下快递有没有被签收

> 在开发中的很多耗时操作，都可以基于这样的非阻塞调用：
>
> 比如网络请求本身使用 Socket 通信，而 Socket 本身提高了 select 模型，可以进行非阻塞方式的调用；
>
> 文件读写的 IO 操作，可以使用操作系统提供的**基于事件的回调机制**



那么现在有个问题：单线程是如何来处理网络通信、IO 操作返回的结果的呢？答案就是事件循环



### Dart 的事件循环

事件循环就是将需要处理的一系列事件放在一个事件队列中，不断从事件队列中取出事件，并执行其对应的代码块

```c
// 伪代码
Queue eventQueue = []; // 事件队列

do {
  if eventQueue.length > 0 {
    // 出队
    event = eventQueue.removeAt(0)
  	// 执行事件
    event();
  }
}while(1)

```

在 Dart 中，实际上有两种队列：

1. 事件队列：包含所有的外来事件：`I/O`、`mouse events`、`drawing events`、`timers`、`isolate`之间的信息传递
2. 微任务队列：表示一个短时间内就会完成的异步任务。它的优先级最高，高于`event queue`，只要队列中还有任务，就可以一直霸占着事件循环。`microtask queue`添加的任务主要是由 `Dart`内部产生

![enevtQueue](https://w-md.imzsy.design/enevtQueue.png)

在每一次事件循环中，`Dart`总是先去第一个`microtask queue`中查询是否有可执行的任务，如果没有，才会处理后续的`event queue`的流程。

### Dart 的异步操作

#### Future

Future<T> 类，表示一个类型 T 的异步操作结构，内部实现定义如下：

```dart
abstract class Future<T> {
  /// A `Future<Null>` completed with `null`.
  static final _Future<Null> _nullFuture =
      new _Future<Null>.zoneValue(null, Zone.root);

  /// A `Future<bool>` completed with `false`.
  static final _Future<bool> _falseFuture =
      new _Future<bool>.zoneValue(false, Zone.root);

  /**
   * Creates a future containing the result of calling [computation]
   * asynchronously with [Timer.run].
   *
   * If the result of executing [computation] throws, the returned future is
   * completed with the error.
   *
   * If the returned value is itself a [Future], completion of
   * the created future will wait until the returned future completes,
   * and will then complete with the same result.
   *
   * If a non-future value is returned, the returned future is completed
   * with that value.
   */
  factory Future(FutureOr<T> computation()) {
    _Future<T> result = new _Future<T>();
    Timer.run(() {
      try {
        result._complete(computation());
      } catch (e, s) {
        _completeWithErrorCallback(result, e, s);
      }
    });
    return result;
  }

```

可以看出，Future 的工厂构造函数接受一个 Dart 函数作为参数，内部通过 `Timer.run` 执行异步操作，同时加入 `try-catch` 来返回正确的结果和捕获异常

**具体使用方式**

```dart

final future = Future(() {
  print('object');
});
future.then((value) => {}).catchError((e) {});

// 链式调用
Future(() {
  print('object');
}).then((value) => {}).catchError((e) {
  print(e.toString());
});
```

1. 创建一个 Future
2. 通过`then`的方式来监听 Future 内部执行完成时返回的结果
3. 通过`catchError`的方式来监听 Future 内部执行失败或者出现异常时的错误信息



> `(){}`与`()=>{}`的区别
>
> 语法糖`()=>{}`比`(){}`多了一个 `return`返回语句



#### 关键字await、async

Dart 中的关键字 await、async 可以让我们用**同步的代码格式，去实现异步的调用过程**

* async：用来表示函数是异步的，定义的函数会返回一个 Future 对象
* await：后面更正一个 Future，表示等待该异步任务完成，异步任务完成后才会继续往下执行。

> await 只能出现在异步函数内部



```dart
void testFuture() async {
    var future = await Future(() => 1);
    print("future value: $future.");
}
testFuture();
print("在testFuture()执行之后打印。");
```

执行结果：

```shell
在testFuture()执行之后打印。
future value: 1.
```



#### 微任务队列

上面提及的 Future、await、async 都是在事件队列中去进行异步执行任务的，那么微任务队列作为优先级高于事件队列又是怎么操作的呢

```dart
// 微任务创建
scheduleMicrotask(() => 1);
```



#### 判断异步执行的顺序

```dart

void textFuture() {
  Future x = Future(()=> null);
  x.then((value) {
    print('6');
    scheduleMicrotask(()=> print('7'));
  }).then((value) => print('8'));

  Future y = Future(()=> print('1'));
  y.then((value) {
    print('4');
    Future(() => print('9'));
  }).then((value) => print('10'));

  Future(() => print('2'));
  scheduleMicrotask(() => print('3'));

  print('5');
}

```

执行结果：

```shell
"5，3，6, 8, 7, 1, 4, 10, 2, 9"
```



> 在 Fullter 中：
>
> * 事件队列：所有的外部事件任务都在事件队列中，如：IO、计时器、点击、以及绘制事件等
> * 微任务队列：通常来源于 Dart 内部，并且微任务非常少，这是因为如果微任务非常多，就会造成事件队列排不上队，会阻塞事件队列的执行（例：用户点击无反应的情况）

### 多核 CPU 的利用

在 iOS 开发中，多线程开发是利用了多核 CPU 高性能，来提高资源的利用率

#### Isolate

在 Dart 中，有一个 Isolate 概念。

我们已经知道 Dart 是单线程的，这个线程有自己可以访问的内存空间以及需要运行的事件循环，而这个空间称为 Isolate

* 例如，Flutter 中就有一个 Root Isolate，负责运行 Flutter 代码，比如 UI 渲染，用户交互等

在Flutter中，资源隔离做得非常好，每个 Isolate 都有自己的 Event Loop 与 Queue

* Isolate 之间不共享任何资源，只能通过消息机制`ReceivePort`通信

对于多核CPU来说，可以自己创建 Isolate，在独立的 Isolate 中完成想要的计算操作等。

**Isolate 的创建**

```dart
void test() {
  Isolate.spawn(foo, "Hello Isolate");
}

void foo(info) {
  print("新的isolate：$info");
}
```



**Isolate 的通信**

```dart
void test() async {
  // 1.创建管道
  ReceivePort receivePort= ReceivePort();

  // 2.创建新的Isolate
  Isolate isolate = await Isolate.spawn<SendPort>(foo, receivePort.sendPort);

  // 3.监听管道消息
  receivePort.listen((data) {
    print('Data：$data');
    // 不再使用时，我们会关闭管道
    receivePort.close();
    // 需要将isolate杀死
    isolate?.kill(priority: Isolate.immediate);
  });
}

void foo(SendPort sendPort) {
  sendPort.send("Hello World");
}
```

上面的通信是单向通信，如果要改成双向通信，在代码实现上是比较麻烦。

Flutter 为我们提供了支持并发计算的 `compute` 函数，内部封装了 Isolate 的创建和双向通信

#### compute

```dart
void test() async {
  int result = await compute(powerNum, 5);
  print(result);
}

int powerNum(int num) {
  return num * num;
}
```

> 上面的代码不是dart的API，而是Flutter的API，所以只有在Flutter项目中才能运行

