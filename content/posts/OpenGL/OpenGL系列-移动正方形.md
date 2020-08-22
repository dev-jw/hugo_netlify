---
title: "OpenGL系列-正方形的移动"
date: 2020-07-03T22:35:42+08:00
draft: false
tags: ["OpenGL", "iOS"]
url:  "moveSquare"
---

在之前我们已经成功地显示出了三角形，这次我们来渲染显示正方形，同时通过键盘让正方形移动起来。

### OpenGL 渲染正方形

现在我们先来渲染显示一个正方形，正方形的显示和之前三角形显示的步骤基本上是一样的。

- 配置**OpenGL**工程
- 定义着色器
- 实现重要函数`SetupRc`、`ChangeSize`、`RenderScene`、`main`

这里不再过多叙述这几个函数的具体作用与实现。

`SetupRc` 函数修改图元连接方式

```c++
    batch.Begin(GL_TRIANGLE_FAN, 4);
```

**基本图元**

![image-20200705202701195](https://w-md.imzsy.design/image-20200705202701195.png)

渲染三角形时，我们采用的是 `GL_TRIANGLES` 方式来连接各个顶点；但是在渲染正方形时，我们则是使用 `GL_TRIANGLES_FAN`

这 2 种都是三角形的绘制方式：

**GL_TRIANGLES**是以每三个顶点绘制一个三角形。第一个三角形使用顶点v0,v1,v2,第二个使用v3,v4,v5,以此类推。如果顶点的个数n不是3的倍数，那么最后的1个或者2个顶点会被忽略。

**GL_TRIANGLE_FAN**绘制各三角形形成一个扇形序列，以v0为起始点，（v0，v1，v2）、（v0，v2，v3）、（v0，v3，v4）。

正方形可以看作是 2 个三角形组合而来，因此这里采用**GL_TRIANGLE_FAN**

**正方形和三角形的区别**

![image-20200705202018192](https://w-md.imzsy.design/image-20200705202018192.png)

三角形顶点数据

```c++
GLfloat vVerts[] = {
    -0.5f,0.0f,0.0f,
    0.5f,0.0f,0.0f,
    0.0f,0.5f,0.0f,
};
```

正方形顶点数据

```c++
// 定义顶点到坐标原点的距离
GLfloat blockSize = 0.1f;

// 四个顶点的坐标
GLfloat verts[] = {
    -blockSize, -blockSize, 0.0f,
    blockSize,  -blockSize, 0.0f,
    blockSize,  blockSize, 0.0f,
    -blockSize,  blockSize, 0.0f,
};
```

我们运行程序，就可以看到正方形了

![image-20200705210743617](https://w-md.imzsy.design/image-20200705210743617.png)

### 通过键盘移动正方形

添加监听键盘输入函数`SpecialKeys`，同时在 `main` 函数中注册该函数

```c++
glutSpecialFunc(SpecialKeys)
```

**`SpecialKeys`函数的具体实现**

**坐标更新**

通过更新每个顶点的坐标，重新绘制即可移动正方形。

- 定义一个步长，每次移动的距离（向量值）
- 计算一个相对顶点的 x 和 y 值

![image-20200705213517169](https://w-md.imzsy.design/image-20200705213517169.png)

这里以左上角的`顶点D`为例

- 当 D 向上移动时，y += stepSize
- 当 D 向下移动时，y -= stepSize
- 当 D 向左移动时，x -= stepSize
- 当 D 向右移动时，x += stepSize

重新更新每个点的坐标

- A 点 =（x, y - 2 * blockSize）
- B 点 =（x + blockSize * 2, y - 2 * blockSize）
- C 点 =（x + blockSize * 2, y）
- D 点 =（x, y）

代码实现为：

```C++
void SpecialKeys(int key, int x, int y) {
    GLfloat stepSize = 0.25f;
    
    GLfloat blockX = verts[0];
    GLfloat blockY = verts[10];
    
    if (key == GLUT_KEY_UP) {
        blockY += stepSize;
    }
    if (key == GLUT_KEY_DOWN) {
        blockY -= stepSize;
    }
    if (key == GLUT_KEY_LEFT) {
        blockX -= stepSize;
    }
    if (key == GLUT_KEY_RIGHT) {
        blockX += stepSize;
    }
    
    verts[0] = blockX;
    verts[1] = blockY - blockSize * 2;
    
    verts[3] = blockX + blockSize * 2;
    verts[4] = blockY - blockSize * 2;
    
    verts[6] = blockX + blockSize * 2;
    verts[7] = blockY;
    
    verts[9] = blockX;
    verts[10] = blockY;

  	// 更新顶点数据
    batch.CopyVertexData3f(verts);
  	// 重新提交渲染  
    glutPostRedisplay();
}
```



**变换矩阵**

在之前的文章中，有提到过在 OpenGL 中的缩放、位移、旋转等操作，实际上就是矩阵与向量的操作。

**位移**(Translation)是在原始向量的基础上加上另一个向量从而获得一个在不同位置的新向量的过程，从而在位移向量基础上**移动**了原始向量。

在 OpenGL 中，由于某一些原因我们通常使用 **4*4** 的变换矩阵，而其中最重要的原因就是大部分的向量都是 4 分量的。

因此，位移矩阵就是在 **4*4** 的矩阵上有几个特别的位置用来执行特定的操作，即第四列上面的 3 个值。如果我们把位移向量表示为$(T_x, T_y, T_z）$

那么位移矩阵定义为

<div>
$$
\left[
 \begin{matrix}
   1 & 0 & 0 & T_x \\
   0 & 1 & 0 & T_y \\
   0 & 0 & 1 & T_z \\
   0 & 0 & 0 & 1 
  \end{matrix} 
\right] *
\left(
	\begin{matrix}
		x\\
		y\\
		z\\
		1
	\end{matrix}
\right) = 
\left(
	\begin{matrix}
		x + T_x\\
		y + T_y\\
		z + T_z\\
		1
	\end{matrix}
\right)
$$
</div>

了解位移矩阵的定义后，我们来通过位移矩阵实现正方形的移动。

- 先定义 2 个全局变量，分别记录 x 轴和 y 轴的位移距离

```c++
  GLfloat xPos = 0.0f;
  GLfloat yPos = 0.0f;
```

修改 **SpecialKeys** 函数

根据输入键位，计算移动距离，再手动触发渲染

```c++
void SpecialKeys(int key, int x, int y){
    
    GLfloat stepSize = 0.025f;
    
    if (key == GLUT_KEY_UP) {
        
        yPos += stepSize;
    }
    
    if (key == GLUT_KEY_DOWN) {
        yPos -= stepSize;
    }
    
    if (key == GLUT_KEY_LEFT) {
        xPos -= stepSize;
    }
    
    if (key == GLUT_KEY_RIGHT) {
        xPos += stepSize;
    }	    
    glutPostRedisplay();
}
```

修改 **RenderScene** 函数

由于我们需要使用**位移矩阵**，那么就需要定义

```c++
//定义矩阵
M3DMatrix44f mTransformMatrix;

//平移矩阵
m3dTranslationMatrix44(mTransformMatrix, xPos, yPos, 0.0f);
```

`GLT_SHADER_IDENTITY`单元着色器就不够用了，需要使用`GLT_SHADER_FLAT`平面着色器。

```c++
//当单元着色器不够用时，使用平面着色器
//参数1：存储着色器类型
//参数2：使用什么矩阵变换
//参数3：颜色
shaderManager.UseStockShader(GLT_SHADER_FLAT, mTransformMatrix, colors);
```

至此，分别通过 2 种方式实现了正方形的移动。

现在还有一个问题：当移动正方形到边界时，我们会发现正方形会移到当前窗口外，这是因为我们没有做边缘检测

### 边缘检测

当正方形移动到边缘时，如果不进行边缘检测，则会移动到屏幕不可见的区域，如下图

![image-20200705230629248](https://w-md.imzsy.design/image-20200705230629248.png)

**坐标更新**

对于坐标更新的移动方式，我们需要检测 4 个顶点与边缘的距离

- 上边界：blockSize > 1, 则 blockSize = 1
- 下边界：blockSize < -1 + blockSize * 2, 则 blockSize = -1 + blockSize *2
- 左边界：blockSize < -1, 则 blockSize = -1
- 右边界：blockSize > 1 - blockSize * 2, 则 blockSize = 1 - blockSize * 2

**位移矩阵**

对于位移矩阵的移动方式，我们需要检测移动的距离是否超过边缘

- 上边界: yPos > 1 - blockSize，则 yPos = 1 - blockSize
- 下边界：yPos < -1 + blockSize，则 yPos = -1 + blockSize
- 左边界：xPos < -1 + blockSize，则 xPos = -1 + blockSize
- 右边界：xPos > 1 - blockSize，则 xPos = 1 - blockSize

### 总结

移动正方形的整个流程就是这样，主要需要注意边缘检测、以及对于变换矩阵的理解和应用。

[完整代码](https://github.com/dev-jw/Learning-OpenGL)