---
title: "什么是Widgets,Elements和RenderObjects"
date: 2020-06-16T10:09:46+08:00
draft: false
tags: ["Flutter", "Dio"]
url:  "Widgets"
---

> 有没有想过 **Flutter** 如何获取这些小部件并将其实际转换为屏幕上的像素？

理解基础技术的工资原理将使优秀的开发人员与开发人员脱颖而出。

当你知道有效的方法和无效的方法时，可以更轻松地创建自定义布局和特殊效果；并且知道这些将节省你在键盘上待几个晚上的时间。

这篇文章的目的是向你介绍 **Flutter** 之外的世界。我们将研究 **Flutter** 的不同方面，并了解其实际工作原理。



### 让我们开始吧

你可能已经知道如何使用 **StatelessWidget** 和 **StatefulWidget**。但是这些小部件仅仅构成其他小部件，布置小部件并渲染他们发生在其他位置。

打开你喜欢的 IDE，然后再进行操作，查看实际代码中的结构通常会造成这些『aha』时刻。



#### 不透明度 

为了熟悉 **Flutter** 原理的基本概念，我们将看一下 `Opacity` 小部件并进行检查。由于它是一个非常基本的小部件，因此是一个很好的例子。

它只接受一个 child 参数，因此，你可以将任何 **Widget** 包裹在 `Opacity` 中，并更改其显示方式。除了 child，它还接受一个名为 opacity 的参数，其值为 `0.0-1.0` 之间，用于控制不透明度。



#### Opacity 小部件

`Opacity` 是继承 `SingleChildRenderObjectWidget`

类的继承关系如下：

**Opacity -> SingleChildRenderObjectWidget -> RenderObjectWidget -> Widget**

相反的，StatelessWidget 和 StatefulWidget 如下

**StatelessWidget/StatefulWidget -> Widget**

区别在于，**StatelessWidget/StatefulWidget**仅仅构成小部件，而 `Opacity` 部件实际上会更改部件的绘制方式。

但是，如果你查看这些类中的任何一个，将找不到实际绘制不透明度相关的任何代码。

这是因为部件仅仅保存表面配置信息。

在这个列子中，`Opacity` 部件仅仅保存了不透明度的值。

> 这就是为什么每次调用 **build** 函数时都可以创建新的小部件的原因。因为小部件的构造并不昂贵，它们仅仅是信息的容器。



#### 渲染 - Rendering

但是渲染是在哪里发生？

**它在 RenderObjects 内部**

正如你可能从单词中猜到的那样，`RenderObject` 是负责一些事情，包括渲染

`Opacity` 小部件创建了一个 `RenderObject` 并通过这些方法去更新

```dart
  @override
  RenderOpacity createRenderObject(BuildContext context) {
    return RenderOpacity(
      opacity: opacity,
      alwaysIncludeSemantics: alwaysIncludeSemantics,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderOpacity renderObject) {
    renderObject
      ..opacity = opacity
      ..alwaysIncludeSemantics = alwaysIncludeSemantics;
  }
```

[源码](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/basic.dart#L188)

**RenderOpacity**

Opacity 部件的大小与其子部件 child 的大小完全相同。

它基本上模仿了 child 的各个方面，除了绘制。在绘制其子部件之前，会先为其添加不透明度。

在这种情况下，`RenderOpacity`需要去实现所有方法（例如执行布局、命中测试、计算大小），并要求其子部件执行实际工作

`RenderOpacity`继承`RenderProxyBox`（`RenderProxyBox`混合在其他几个类中，这些类恰好实现了这些方法，并将实际计算推迟到了唯一的子部件中）

```dart
double get opacity => _opacity;
double _opacity;
set opacity(double value) {
  _opacity = value;
  markNeedsPaint();
}
```

删除了一些 assert 断言和优化判断。[源码](https://medium.com/flutter-community/flutter-what-are-widgets-renderobjects-and-elements-630a57d05208)

字段通常将 getter 暴露给私有变量，而 setter 除了设置字段外，还调用 `markNeedsPaint（）` 或 `markNeedsLayout（）`。顾名思义，它在告诉系统『我发生了改变，请重新绘制/重新布局』

在 `RenderOpacity` 中，可以找到以下方法：

```dart
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      if (_alpha == 0) {
        // No need to keep the layer. We'll create a new one if necessary.
        layer = null;
        return;
      }
      if (_alpha == 255) {
        // No need to keep the layer. We'll create a new one if necessary.
        layer = null;
        context.paintChild(child, offset);
        return;
      }
      assert(needsCompositing);
      layer = context.pushOpacity(offset, _alpha, super.paint, oldLayer: layer as OpacityLayer);
    }
  }
```

`PaintingContext` 基本上是一块精美的画布，在这个画布上，有一个方法 `pushOpacity`，这才是实际的不透明度实现。

#### 现在来回顾一下

* **Opacity**小部件不是一个 `StatelessWidget` 或 `StatefulWidget`，而是 `SingleChildRenderObjectWidget`
* **Widget**仅能保存渲染器可以使用的信息
* 在本例中，**Opacity** 布局持有一个代表不透明度的 **double** 类型的值
* `RenderOpacity` 继承于 `RenderProxyBox`进行实际的 **layouting/rendering** 等操作
* 因为不透明度的行为几乎与它的子部件完全一样，所以她将美国方法调用委托给了子部件
* 重写 `paint` 方法并调用了 `pushOpacity`，后者将所需的不透明度添加到小部件中



### 当然，还不止这些

首先，我们知道了**Widget**只是一个配置，**RenderObject**只管理布局和渲染等。

在 **Flutter** 中，基本上一直在重新创建小部件。调用 `build()` 方法时，会创建一堆小部件。每次发生变化的时候都会调用这个 `build()` 方法。例如，当动画发生时，会经常调用 `build()` 方法。

这意味着你不能每次都重建整个子树，相反，你想要更新它。

> 你不能在屏幕上获得小部件的大小或位置，因为小部件就像蓝图，它实际上并不在屏幕上。
>
> 它只是对底层呈现对象应该使用哪些变量的描述。



#### 引入 Element

`Element` 是整个树中的一个具体的小部件。

**基本上是这样的：**

第一次创建小部件的时候，它会在内部创建一个 `Element`。然后将这个 `Element` 插入到树中。如果 **widget** 稍后发生更改，则将它与旧的 **widget** 进行对比，并相应地更新 **element**。

最重要的是，`Element`不会被重新构建，它只会被更新。

Element 是核心框架的中心部分，显然还有更多内容，但是现在这些信息以及足够了。



**在这个Opacity 小部件中的`Element`又是在哪里创建的呢？**

> 对于那些充满好奇心的人来说，这只是一小段插曲

在 `SingleChildRenderObjectWidget` 中，可以找到下面这样的代码:

```dart
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  
  const SingleChildRenderObjectWidget({ Key key, this.child }) : super(key: key);
  
  final Widget child;

  @override
  SingleChildRenderObjectElement createElement() => SingleChildRenderObjectElement(this);
}
```

如我们所见，`SingleChildRenderObjectElement` 是在 `SingleChildRenderObjectWidget` 中被创建的，这里的 **this**，即`SingleChildRenderObjectWidget`，所以`SingleChildRenderObjectElement`中的**widget**即当前的传入的 **this**。

类的继承关系如下：

**SingleChildRenderObjectElement -> RenderObjectElement -> Element**

`Element` 会创建 **RenderObject**，但是在我们的示例中，`Opacity` 小部件为什么是自己创建的 **RenderObject**？

```dart
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget widget) : super(widget);
```

通常更常见的情况是，`Widget` 需要一个 **RenderObject**，但不需要定制 `Element`。

**RenderObject** 实际上是由 `Element` 创建的。

`SingleChildRenderObjectElement` 获得对象 `RenderObjectWidget` (`RenderObjectWidget` 有创建 RenderObject的方法)。

在 `mount` 方法中，将 `Element` 插入到 Element 树中，这些都是在 `RenderObjectElement` 中发生的

```dart
@override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);

    _renderObject = widget.createRenderObject(this);
    
    attachRenderObject(newSlot);
    _dirty = false;
  }
```

紧接在 `super.mount(parent, newSlot)` 之后。

只有一次(当它被挂载时)它会问小部件：请给我你想要使用的renderobject，这样我可以保存它。



### 最后

这就是 `Opacity` 小部件内部工作的方式。

这篇文章的目的是向你介绍 widget 之外的世界。仍然有许多主题要去涉及，但希望能给你一个关于内部工作原理的很好的介绍。

