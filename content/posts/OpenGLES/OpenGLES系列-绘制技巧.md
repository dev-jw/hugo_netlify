---
title: "OpenGLES系列-绘制技巧"
date: 2020-08-01T15:45:37+08:00
draft: false
tags: ["iOS", "OpenGLES"]
url:  "draw-skill"
---

> 本文所介绍的OpenGL ES 优化技巧都是以减少CPU和GPU之间的数据传递，提高绘制速度

试想一下，顶点数据是通过 CPU 传递到 GPU，但是如果每次渲染都需要传递一次，如果数据量过多，可能会导致数据传递时间过长，从而严重地影响帧率

**例**

有一个三角锥

![image-20200802212048971](https://w-md.imzsy.design/image-20200802212048971.png)

实际应用到 5 个顶点数据为：

```objective-c
GLfloat vertexArr[] =
{
    -0.5f, 0.5f, 0.0f,      0.0f, 0.0f, 0.5f,       0.0f, 1.0f,//左上
    0.5f, 0.5f, 0.0f,       0.0f, 0.5f, 0.0f,       1.0f, 1.0f,//右上
    -0.5f, -0.5f, 0.0f,     0.5f, 0.0f, 1.0f,       0.0f, 0.0f,//左下
    0.5f, -0.5f, 0.0f,      0.0f, 0.0f, 0.5f,       1.0f, 0.0f,//右下
    0.0f, 0.0f, 1.0f,       1.0f, 1.0f, 1.0f,       0.5f, 0.5f,//顶点
};
```

### 使用VBO&VAO渲染

#### VBO

顶点缓冲对象(Vertex Buffer Objects, VBO)，它就是把系统内存中的顶点数据传递给GPU后返回的引用凭证。

我们可以提前将顶点数据传递到 GPU 内存中，CPU 每次绘制的时候只需要告诉 GPU 自己引用看显存里的那一块数据，从而就可以减少数据的传递。

**VBO** 的使用，我们在之前已经用过很多次了

**具体过程**

- `glGenBuffers`生成 Buffer
- 绑定缓存到 `GL_ARRAY_BUFFER`
- 向`GL_ARRAY_BUFFER`写入数据

```objective-c
GLuint buffer;
glGenBuffers(1, &buffer);
glBindBuffer(GL_ARRAY_BUFFER, buffer);
glBufferData(GL_ARRAY_BUFFER, sizeof(vertexArr), vertexArr, GL_STATIC_DRAW);
```

这样 VBO 所对应的 GPU 显存中就有 `vertexArr` 数据。

最后一个参数指定了希望 GPU 如何管理给定的数据

- `GL_STREAM_DRAW`：数据不会或几乎不会改变。

- `GL_DYNAMIC_DRAW`： 数据会被改变很多。

- `GL_STREAM_DRAW`：数据每次绘制时都会改变。

#### VAO

顶点数组对象(Vertex Array Object, VAO)，可以像顶点缓冲对象那样被绑定，任何随后的顶点属性调用都会储存在这个VAO中。

这样的好处就是，当配置顶点属性指针时，你只需要将那些调用执行一次，之后再绘制物体的时候只需要绑定相应的VAO就行了。

这使在不同顶点数据和属性配置之间切换变得非常简单，只需要绑定不同的VAO就行了。

VAO 的使用和 VBO 特别的相似。

**使用过程**

1.  `glGenVertexArraysOES`生成 VAO Buffer
2.  绑定VAO Buffer
3.  执行属性绑定操作
4.  解绑 VAO Buffer

```objective-c
GLuint vao;
glGenVertexArraysOES(1, &vao);
glBindVertexArrayOES(vao);
glBindBuffer(GL_ARRAY_BUFFER, buffer);
//    向顶点属性传递数据
//    GLuint positionAttribLocation = glGetAttribLocation(program, "position");
//    glEnableVertexAttribArray(positionAttribLocation);
//    glVertexAttribPointer(positionAttribLocation, 3, GL_FLOAT, GL_FALSE, sizeof(GL_FLOAT) * 8, (GLfloat *)NULL);
//    解绑
glBindVertexArrayOES(0);
```

`glGenVertexArraysOES`等 OES 结尾的方法是苹果自己扩展的，其他平台上也会有VAO相关的方法集合，但命名会有所不同

**总结**

顶点数据经过 VBO 和 VAO 的优化，就不需要每次绘制前进行数据传递和属性绑定了，大大提高绘制速度

> ```objective-c
> // 绘制
> glBindVertexArrayOES(vao);
> glDrawArrays(GL_TRIANGLES, 0, vertexCount);
> ```

### 使用EBO渲染

在 OpenGL 系列中有简单介绍过**顶点索引缓冲对象**(Element Buffer Object，EBO)。

以上面的三角锥例子来说，我们可以发现真正使用到的顶点坐标，只有 5 个点，如果我们不使用 EBO，需要使用到 18 个顶点坐标数据，这其实有几个顶点叠加了，比如：底面的矩阵，渲染需要用到 6 个点的，而不是 4 个顶点，这样就产生 **50%** 的额外开销。

**EBO 的工作方式**：存储真正使用的顶点数据，再给予指定的绘制顺序。

通过 EBO 渲染，大大减少了需要传递给 GPU 的数据量，提高了渲染的性能。

```objective-c
GLfloat vertexArr[] =
{
    -0.5f, 0.5f, 0.0f,      0.0f, 0.0f, 0.5f,       0.0f, 1.0f,//左上
    0.5f, 0.5f, 0.0f,       0.0f, 0.5f, 0.0f,       1.0f, 1.0f,//右上
    -0.5f, -0.5f, 0.0f,     0.5f, 0.0f, 1.0f,       0.0f, 0.0f,//左下
    0.5f, -0.5f, 0.0f,      0.0f, 0.0f, 0.5f,       1.0f, 0.0f,//右下
    0.0f, 0.0f, 1.0f,       1.0f, 1.0f, 1.0f,       0.5f, 0.5f,//顶点
};
// 顶点索引
GLuint indices[] =
{
    0, 3, 2,
    0, 1, 3,
    0, 2, 4,
    0, 4, 1,
    2, 3, 4,
    1, 4, 3,
};
```

**使用过程**

1. 为索引数据创建索引缓冲 (Index Buffer Object，IBO)
2. `glBindBuffer`绑定 IBO，需要传递`GL_ELEMENT_ARRAY_BUFFER`当作缓冲目标
3. `glBufferData`把索引复制到缓冲里
4. `glDrawElements`来替换`glDrawArrays`函数进行绘制

```objective-c
// 创建
GLuint index;
glGenBuffers(1, &index);
glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, index);
glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

// 绘制
glDrawElements(GL_TRIANGLES, sizeof(indices) / sizeof(GLuint), GL_UNSIGNED_INT, 0);
```

**glDrawElements函数文档**

![image-20200805105551467](https://w-md.imzsy.design/image-20200805105551467.png)

[完整 Demo](https://github.com/dev-jw/Learning-OpenGL-ES)

#### 注意点

当用 EBO 的方式去渲染一个立方体，并为之贴上 2D 纹理时，会出现一个奇怪的现象。

<img src="https://w-md.imzsy.design/Simulator" style="zoom:30%" />

这是因为这里的纹理方式采用的是2D 纹理贴图`GLKTextureTarget2D`，而给一个 3D 物体渲染一张 2D 纹理，显示是不合理的。

> 立方体具体该怎么正确的贴图？
>
> 使用立方体贴图`GLKTextureTargetCubeMap`，会在介绍天空盒的时候进行分析

