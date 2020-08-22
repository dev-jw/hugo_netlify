---
title: "OpenGL系列-图元的连接、面剔除"
date: 2020-07-08T20:17:39+08:00
draft: false
tags: ["OpenGL", "iOS"]
url:  "primitive"
---

> 之前我们在画三角形与正方形时，分别使用了`GL_TRIANGLE`和`GL_TRIANGLE_FAN`，两者的区别是怎么样的呢？以及 OpenGL 中还有哪些图元连接方式呢？

### 图元

图元是由一组表示**顶点位置**的顶点描述。其他如颜色、纹理坐标和几何法线等信息也作为属性与每个顶点关联。

### 图元连接方式

#### 点

![image-20200709153931681](https://w-md.imzsy.design//image-20200709153931681.png)

#### 直线

![image-20200709153954515](https://w-md.imzsy.design//image-20200709153954515.png)

- GL_LINES：用于连接一系列**不相连**的线段，可以绘制 `n/2` 条
- GL_LINE_STRIP：用于连接相连的线段，可以绘制 `n-1` 条
- GL_LINE_LOOP：用于连接首尾相连的线段，可以绘制 `n` 条

#### 三角形

![image-20200709154003390](https://w-md.imzsy.design//image-20200709154003390.png)

- GL_TRIANGLES：绘制一系列**单独**的三角形，可以绘制 `n/3` 个
- GL_TRIANGLE_STRIP：绘制一系列相互连接的三角形，可以绘制 `n-2` 个
- GL_TRIANGLE_FAN：绘制一系列相连的三角形，可以绘制 `n-2` 个

> n 代表顶点个数

#### 具体使用

我们一般会通过工具类 `GLBatch` 的 Begin 函数去传入图元连接方式

```c++
GLBatch pointBatch;
pointBatch.Begin(GL_POINTS, 3);
```

`GLBatch`的 Begin 函数

```c++
参数1:图元
参数2:顶点数 
参数3:⼀组或者2组纹理理坐标(可选)
void GLBatch::Begain(GLeunm primitive,GLuint nVerts,GLuint nTexttureUnints = 0);

```

### 环绕顺序

任何一个闭合形状，它的每一个面都有两则，每一则要么面向用户，要么背对用户。

OpenGL 会依据顶点特定的环绕顺序来定义图形的正反面，可能是**顺时针**(Clockwise)的，也可能是**逆时针**(Counter-clockwise)的。

比如，当我们定义一组三角形顶点时，我们会从三角形中间来看，为这 3 个顶点设定一个环绕顺序。

![image-20200710154656618](https://w-md.imzsy.design//image-20200710154656618.png)

可以看到，我们首先定义了顶点 1，之后我们可以选择定义顶点 2 或者顶点 3，这个选择将定义这个三角形的环绕顺序。

OpenGL 在渲染图元的时候将使用这个信息来决定一个三角形是一个正向三角形还是背向三角形。

默认情况下，逆时针顶点所定义的三角形将会被处理为正向三角形。

**观察者**视角所面向的所有三角形顶点就是我们所指定的正确环绕顺序。

比如，在立方体中，观察者所面向的三角形将会是正向三角形，而背面的三角形则是背向三角形。

![image-20200710155339442](https://w-md.imzsy.design//image-20200710155339442.png)

#### 面剔除

OpenGL 能够丢弃那些渲染为背向三角形的三角形图元，这样能省下超过 50% 的片段着色器执行数。

要想启用面剔除，只需要启用 OpenGL 的 `GL_CULL_FACE` 选项：

```c++
glEnable(GL_CULL_FACE);
```

当然，OpenGL 允许我们改变需要剔除的面的类型。

```c++
glCullFace(CL_FRONT);
```

- GL_BACK：只剔除背向面，是默认值
- GL_FRONT：只剔除正向面
- GL_FRONT_AND_BACK：剔除正向面和背向面

除了需要剔除的面之外，我们也可以通过调研 `glFrontFace`，告诉 OpenGL 我们希望将正向面定义为哪种环绕方式。

默认值是 `GL_CCW`，即逆时针的环绕顺序；`GL_CW` 代表是顺时针的环绕顺序

```c++
glFrontFace(GL_CCW);
```

> **面剔除**是一个提高 OpenGL 程序性能的工具。我们需要记住哪些物体能够从面剔除中获益，而哪些物体不应该被剔除

