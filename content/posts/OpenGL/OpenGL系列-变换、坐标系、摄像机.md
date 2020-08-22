---
title: "OpenGL系列-变换和矩阵栈"
date: 2020-07-12T08:40:20+08:00
draft: false
tags: ["iOS", "OpenGL"]
url:  "Translation"
---

### 变换

在OpenGL 下，对一个物体进行位移、旋转、缩放等操作，我们一般使用**矩阵**(Matrix)对象去操作物体。

在深入了解变换矩阵之前，我们首先要了解一下向量。

#### 向量

向量最基本的定义就是一个方向。即向量有一个方向和大小。

向量可以在任意维度上，如果一个向量有 2 个维度，它表示一个平面的方向，当它有 3 个维度的时候，则可以表示一个 3D 世界的方向。

通常，向量表示为：

<div>
$$
	\vec v = 
	\left(
   \begin{matrix}
     x  \\
     y  \\
     z  \\
     w 
    \end{matrix} 
  \right)
$$
</div>

标量只是一个数字（或者说是仅有一个分量的向量）。

当向量与标量进行运算时，会像这样：

<div>
$$
	\left(
   \begin{matrix}
     1  \\
     2  \\
     3  \\
     w 
    \end{matrix} 
  \right) + x =
  \left(
   \begin{matrix}
     1 + x  \\
     2 + x \\
     3 + x \\
     w + x 
    \end{matrix} 
  \right)
$$
</div>


> 其中的 `+` 可以是加减乘除



**向量相乘**

普通的乘法在向量上是没有定义的，因为它在视觉上是没有意义的。但是在相乘的时候我们有两种特定情况可以选择：

- **点乘**，记作 $\vec v \cdot \vec k$
- **叉乘**，记作 $\vec v \times \vec k$

**向量点乘**

点乘的几何意义是可以用来计算两个向量之间的夹角，以及 b 向量在 a 向量方向上的投影

公式为：（具体的推导过程，不在这里展开）

<div>
$$
a \cdot b = |a||b|cos\theta
$$
</div>


**向量叉乘**

叉乘的结果是一个向量，更为熟知的叫法是**法向量**，该向量垂直于 a 和 b 向量构成的平面。

在 3D 图像学中，通过两个向量的叉乘，生成的是垂直于 a、b 的法向量，从而构建 x、y、z 坐标系

两个正交向量 A 和 B 叉积：

<div>
$$
	\left(
   \begin{matrix}
     A_x  \\
     A_y  \\
     A_z  \\
    \end{matrix} 
  \right) \times 
  \left(
   \begin{matrix}
     B_x  \\
     B_y  \\
     B_z  \\
    \end{matrix} 
  \right) = 
  \left(
   \begin{matrix}
     A_y \cdot B_z - A_z \cdot B_y  \\
     A_z \cdot B_x - A_x \cdot B_z  \\
     A_x \cdot B_y - A_y \cdot B_x  \\
    \end{matrix} 
  \right)
$$
</div>


#### 矩阵

矩阵就是一个矩形的数字、符号或表达式数组，就是一个矩形的数学表达式阵列。

**矩阵的数乘**

矩阵与标量之间的乘法

<div>
$$
	\left[
   \begin{matrix}
     1 & 2 \\
     3 & 4 \\
    \end{matrix} 
  \right] \cdot 2 =
  \left[
   \begin{matrix}
     1 \cdot 2 & 2 \cdot 2 \\
     3 \cdot 2 & 4 \cdot 2 \\
    \end{matrix} 
  \right] = 
  \left[
   \begin{matrix}
     2 & 4 \\
     6 & 8 \\
    \end{matrix} 
  \right]
$$
</div>


**矩阵相乘**

矩阵之间的相乘，有一些限制：

1. 只有当左侧矩阵的列数和右侧矩阵的行数相等，两个矩阵才能相乘
2. 矩阵相乘不遵守**交换律**

比如，下面两个 2*2 矩阵相乘的列子：

<div>
$$
	\left[
   \begin{matrix}
     1 & 2 \\
     3 & 4 \\
    \end{matrix} 
  \right] \cdot 
  \left[
   \begin{matrix}
     5 & 6 \\
     7 & 8 \\
    \end{matrix} 
  \right] =
  \left[
   \begin{matrix}
     1 \cdot 5 + 2 \cdot 7 & 1 \cdot 6 + 2 \cdot 8 \\
     3 \cdot 5 + 4 \cdot 7 & 3 \cdot 6 + 4 \cdot 8 \\
    \end{matrix} 
  \right] = 
  \left[
   \begin{matrix}
     19 & 22 \\
     43 & 50 \\
    \end{matrix} 
  \right]
$$
</div>


#### 矩阵与向量相乘

在 OpenGL 中，我们通常用向量来表示位置、颜色、纹理坐标。

我们可以把向量看作是 $N \times 1$ 矩阵，N 表示向量分量的个数。

这样便满足了，矩阵的列数等于向量的行数。


<div>
$$
\left[
 \begin{matrix}
   1 & 0 & 0 & 0 \\
   0 & 1 & 0 & 0 \\
   0 & 0 & 1 & 0 \\
   0 & 0 & 0 & 1 \\
  \end{matrix} 
\right]  \times
\left[
 \begin{matrix}
   x \\
   y \\
   z \\
   1 \\
  \end{matrix} 
\right] = 
\left[
 \begin{matrix}
   x \\
   y \\
   z \\
   1 \\
  \end{matrix} 
\right]
$$
</div>


**单位矩阵**

在 OpenGL 中，我们通常使用 $4 \times 4$ 的**变换矩阵**，这是因为大部分的向量都是 4分量的。

单位矩阵是一个除了对角线以外都是 0 的 $N \times N$ 矩阵。

<div>
$$
\left[
 \begin{matrix}
   1 & 0 & 0 & 0 \\
   0 & 1 & 0 & 0 \\
   0 & 0 & 1 & 0 \\
   0 & 0 & 0 & 1 \\
  \end{matrix} 
\right]
$$
</div>


> 单位矩阵是生成其他变换矩阵的起点

- 在数学中为了方便计算，矩阵是以**行矩阵**为标准，根据以下过程相乘：

  **顶点坐标 = 顶点坐标 · 模型矩阵 · 观察矩阵 · 投影矩阵**


$$
Vec = \vec V_{local} \cdot M_{model} \cdot M_{view} \cdot M_{projection}
$$

- 在 OpenGL 中，矩阵都是以**列矩阵**为标准的，为了满足矩阵相乘的规则，需要将数学中的相乘过程按右往左相乘，即：

  **顶点坐标 =  投影矩阵 · 观察矩阵 · 模型矩阵 · 顶点坐标**

$$
Vec = M_{projection} \cdot M_{view} \cdot M_{model} \cdot \vec V_{local}
$$

### 矩阵栈

OpenGL 中的变换一般包括**视图变换**、**模型变换**、**投影变换**等，在每次变换后，OpenGL 会记住新的状态。

但是，有时候在经过一些变换后，我们想回到原来的状态，便可以借助使用**矩阵栈**来回到原来的状态。

**过程分析**

首先，对于矩阵的操作都是对于矩阵栈的栈顶元素来操作的。

当前矩阵就是矩阵栈的栈顶元素。

整个过程如图：

![image-20200715184213793](https://w-md.imzsy.design/image-20200715184213793.png)

- 压栈 `PushMatrix()`
- 取出当前矩阵，进行矩阵相乘 `MultMatrix()`（变换、缩放、旋转）
- 将结果压入矩阵栈
- 出栈 `PopMatrix()`，恢复到原来的状态