---
title: "OpenGL系列-深度测试、混合"
date: 2020-07-10T20:52:45+08:00
draft: false
tags: ["OpenGL", "iOS"]
url:  "DepthBuffer"
---

![image-20200713095528533](https://w-md.imzsy.design//image-20200713095528533.png)

> 我们渲染了一个圆环，但是发现圆环的一部分被挖空了，这个现象是怎么去解决的

### 深度测试

**问题背景**

在绘制 3D 场景的时候，我们需要决定哪些部分对观察者是可见的，而对于不可见的部分，应该及早地丢弃，不被渲染，这种问题也就是**隐藏面消除**。

解决这个问题比较简单的方法是**画家算法**。

画家算法的基本思路是：先绘制场景中离观察者较远的物体，再绘制较近的物体。

![image-20200713100739709](https://w-md.imzsy.design//image-20200713100739709.png)

使用画家算法时，只要将场景中物体安卓离观察者的距离远近排序，由远及近的绘制即可。

画家算法很简单，但是另一个方面也存在缺陷。例如下图中，三个三角形相互重叠的情况，画家算法将无法处理。

![image-20200713100946219](https://w-md.imzsy.design//image-20200713100946219.png)

使用**深度测试**，可以防止被其他面遮挡的面渲染到前面。

**解决方案**

窗口系统自动创建一块缓冲区称为深度缓冲，存储绘制对象的深度值（Z 值）。

当深度测试开启的时候，OpenGL 测试深度缓冲区内的深度值。

- 测试通过，深度缓冲区内的值将被设为新的深度值
- 测试失败，丢弃该片段

**启用深度测试**

深度测试默认是关闭的，要启用深度测试的话，我们需要用 `GL_DEPTH_TEST` 选项来启用

```c++
glEnable(GL_DEPTH_TEST);
```

一旦启用深度测试，我们还需要在开始的时候，申请一个深度缓冲区

```c++
glutInitDisplayMode(GLUT_DEPTH);

```

以及在每一次绘制前还应该清除深度缓冲区

```c++
glClear(GL_DEPTH_BUFFER_BIT);

```

**深度测试函数**

我们可以通过调用 `glDepthFunc` 来设置比较运算符，这样我们能够控制 OpenGL 通过或丢弃片段和如何更新深度缓冲区。

```c++
glDepthFunc(GL_LESS);
```

**比较运算符**

默认使用 `GL_LESS`

| 运算符      | 描述                                       |
| ----------- | ------------------------------------------ |
| GL_ALWAYS   | 永远通过测试                               |
| GL_NEVER    | 永远不通过测试                             |
| GL_LESS     | 在片段深度值小于缓冲区的深度时通过测试     |
| GL_EQUAL    | 在片段深度值等于缓冲区的深度时通过测试     |
| GL_LEQUAL   | 在片段深度值小于等于缓冲区的深度时通过测试 |
| GL_GREATER  | 在片段深度值大于缓冲区的深度时通过测试     |
| GL_NOTEQUAL | 在片段深度值不等于缓冲区的深度时通过测试   |
| GL_GEQUAL   | 在片段深度值大于等于缓冲区的深度时通过测试 |

**深度值精度**

在深度缓冲区中，存储的深度值在`[0,1]`范围内，且为 16、24 或 32 位浮点数。大多数系统中为 24 位

#### 深度冲突

两个平面或三角形相互紧密平行，深度缓冲区不具有足够的精度去区分哪个靠前。结果是，这两个形状不断切换顺序导致出问题。这种现象被称为**深度冲突**(Z-fighting)

**防止深度冲突**

- 让物体之间不要离得太近，使用多边形偏移
- 尽可能把近平面设置得远一些
- 放弃一些性能来得到更高的深度值的精度

### 混合

在 OpenGL 中，物体透明技术通常被叫做**混合**。

透明是物体非纯色而是混合色，这种颜色来自不同浓度的自身颜色和它后面的物体颜色。

![image-20200713150949560](https://w-md.imzsy.design//image-20200713150949560.png)

比如，一个有色玻璃窗就是一种透明物体，玻璃有自身的颜色，但是最终的颜色包含了玻璃后面的颜色。

透明物体可以是完全透明或者半透明的。一个物体的透明度，被定义为它的颜色的 alpha 值。alpha 值是一个颜色向量的第四个元素。

**启用混合**

当我们需要启用混合功能时，可以像大多数 OpenGL 功能一样，开启`GL_BLEND`选项

```c++
glEnable(GL_BLEND);
```

**混合方程式**

在开启混合后，我们还需要告诉 OpenGL 它该如何混合。

OpenGL 以下面的方程进行混合：

<div>
$$
	\vec C_{result} = \vec C_{source} * F_{source} + \vec C_{desination} * F_{desination} 
$$
</div>

- $\vec C_{source}$ ：源颜色向量，本来的颜色向量
- $\vec C_{desination}$ ：目标颜色向量，这是储存在颜色缓冲中当前位置的颜色向量
- $F_{source}$ ：源因子
- $F_{desination}$ ：目标因子

**举例**

一个简单列子：

![image-20200713154127101](https://w-md.imzsy.design/image-20200713154127101.png)

我们有两个方块，现在希望在红色方块上绘制绿色方块。那么红色方块就会变成目标颜色（它会先进入颜色缓冲）。

所以，我们会将$\vec F_{source}$设置为源颜色向量的`alpha`值，即将绿色方块的`alpha`设置为 0.6，那么目标方块（即红色方块）的`alpha`值，就等于剩下的浓度(1 - 0.6)= 0.4

方程式将变成：

<div>
$$
	\vec C_{result} = 
	\left(
   \begin{matrix}
     0.0  \\
     1.0  \\
     0.0  \\
     0.6 
    \end{matrix} 
  \right) * 0.6 +
  \left(
   \begin{matrix}
     1.0  \\
     0.0  \\
     0.0  \\
     1.0 
    \end{matrix} 
  \right) * (1 - 0.6)
$$
</div>
最终方块结合部分包含了**60%的绿色**和**40%的红色**

![image-20200713155744906](https://w-md.imzsy.design/image-20200713155744906.png)

**glBlendFuc函数**

我们可以通过**glBlendFuc**函数来告诉 OpenGL 使用哪种混合因子

`void glBlendFunc(GLenum sfactor, GLenum dfactor)`接收两个参数，来设置源（source）和目标（destination）因子。

**常用的混合因子选项**

颜色常数向量$\vec C_{constant}$可以用`glBlendColor`函数分开来设置。

| 选项                        | 值                                   |
| --------------------------- | ------------------------------------ |
| GL_ZERO                     | 00                                   |
| GL_ONE                      | 1                                    |
| GL_SRC_COLOR                | 源颜色向量$\vec C_{source}$          |
| GL_ONE_MINUS_SRC_COLOR      | 1 - $\vec C_source$                  |
| GL_DST_COLOR                | 目标颜色向量 $\vec C_{desination}$   |
| GL_ONE_MINUS_DST_COLOR      | 1 - $\vec C_{desination}$            |
| GL_SRC_ALPHA                | $\vec C_{source}$的 alpha 值         |
| GL_ONE_MINUS_SRC_ALPHA      | 1 - $\vec C_{source}$的 alpha 值     |
| GL_DST_ALPHA                | $\vec C_{desination}$的 alpha 值     |
| GL_ONE_MINUS_DST_ALPHA      | 1 - $\vec C_{desination}$的 alpha 值 |
| GL_CONSTANT_COLOR           | 常颜色向量 $\vec C_{constant}$       |
| GL_ONE_MINUS_CONSTANT_COLOR | 1 - $\vec C_{constant}$              |
| GL_CONSTANT_ALPHA           | $\vec C_{constant}$的 alpha 值       |
| GL_ONE_MINUS_CONSTANT_ALPHA | 1 - $\vec C_{constant}$的 alpha 值   |

我们还可以使用`glBlendFuncSeperate`为 RGB 和 alpha 通道各自设置不同的选项

```c++
void glBlendFuncSeperate(GLenum strRGB, GLenum dstRGB, GLenum strAlpha,  GLenum dstAlpha);
```

- strRGB: 源颜色的混合因子
- dstRGB：目标颜色的混合因子
- strAlpha：源颜色的 alpha 因子
- dstAlpha：目标颜色的 alpha 因子

**注意点**

要让混合在多物体上有效，我们必须先绘制最远的物体，然后绘制最近的物体。

普通的无混合物体仍然可以使用深度缓冲正常绘制，所以不必给它们排序。

当**无透明物体**和**透明物体**一起绘制的时候，通常要遵循以下原则：

1. 先绘制所有不透明物体
2. 为所有透明物体排序
3. 按顺序绘制透明物体