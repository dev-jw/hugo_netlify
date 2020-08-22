---
title: "OpenGL ES系列-GLKit初探"
date: 2020-07-26T17:01:20+08:00
draft: false
tags: ["iOS", "OpenGLES"]
url:  "Start-GLKit"
---

### OpenGL ES 的 hello word

#### 准备

环境：**Xcode11.3.1 + OpenGL ES 2.0**

目标：熟悉 OpenGL ES 的 `hello word`

#### 思路

通过 GLKit，将屏幕颜色设置为红色。

**效果如下：**

![image-20200726171554137](https://w-md.imzsy.design/image-20200726171554137.png)

#### 具体细节

**新建 OpenGL ES 上下文**

```objective-c
- (void)setupContext {
    // 新建OpenGL ES上下文
    self.mContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    // 将 Storyboard 中的 view 改为 GLKitView
    GLKView *view = (GLKView*)self.view;
    view.context = self.mContext;
    
    // 设置颜色格式
    view.drawableColorFormat = GLKViewDrawableColorFormatRGBA8888;
    
    // 将mContext设置为当前上下文
    [EAGLContext setCurrentContext:self.mContext];
}
```

**实现GLKViewDelegate代理方法**

`- (**void**)glkView:(GLKView *)view drawInRect:(CGRect)rect;`相当于在 OpenGL 中的 `RenderScene`函数

```objective-c
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    // 清除颜色缓冲
    glClear(GL_COLOR_BUFFER_BIT);
    
    // 将背景色设置为红色 RGBA
    glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
}
```

至此，OpenGL ES 的`hello word`已经实现了。

#### 基本概念

**EGL(Embedded Graphics Library)**

- OpenGL ES 命令需要**渲染上下文**和**绘制表面**才能完成图像的绘制

  - 渲染上下文：存储相关 OpenGL ES 状态
  - 绘制表面：用于绘制图元的表面，指定渲染所需的缓冲区，例如：颜色缓冲区、深度缓冲区等

- OpenGL ES API 并没有提供如何创建渲染上下文或者上下文如何连接到原生窗口系统。**EGL**是**Khronos**渲染 API 和原生窗口系统之间的接口

  > 唯一支持 OpenGL ES 却不支持 EGL
  >
  > Apple 提供自己的 EGL API的 iOS 实现，称为 EAGL

### 实现一张图片绘制到屏幕

#### 具体过程

**新建 OpenGL ES上下文**与上面的操作一致，不再叙述

**配置顶点坐标数据和纹理坐标数据**

```objective-c
- (void)setupVertexData {
    // 顶点坐标数据（x, y, z） + 纹理坐标（s, t）
    GLfloat squareVertexData[] = {
        0.5, -0.5, 0.0f,      1.0, 0.0f,
        0.5, 0.5, 0.0f,       1.0, 1.0f,
        -0.5, 0.5, 0.0f,      0.0, 1.0f,
        
        0.5, -0.5, 0.0f,       1.0, 0.0f,
        -0.5, 0.5, 0.0f,      0.0, 1.0f,
        -0.5, -0.5, 0.0f,     0.0, 0.0f,
    };
}
```

顶点数组里包括顶点坐标和纹理坐标。

在 OpenGL ES 的世界坐标系是`[-1, 1]`，因此点（0，0）是在屏幕的**正中间**

- 顶点坐标：取值范围[-1, 1]，中心点为（0, 0）
- 纹理坐标：取值范围[0, 1]，原点是在**左下角**，因此（0, 0）在左下角，（1, 1）在右上角

**顶点数据缓存**

```objective-c
- (void)setupVertexData {
    // 顶点数据缓存
    GLuint buffer;
    // 创建顶点缓存区标识符
    glGenBuffers(1, &buffer);
    // 绑定顶点缓存区
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    // 将顶点数据 copy 到顶点缓存区
    glBufferData(GL_ARRAY_BUFFER, sizeof(squareVertexData), squareVertexData, GL_STATIC_DRAW);
    // 顶点坐标数据
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat), (GLfloat *)NULL + 0);
    // 纹理坐标数据
    glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat), (GLfloat *)NULL + 3);
}
```

这里是**核心重点**

- `glGenBuffers`申请一个标识符
- `glBindBuffer`把标识符绑定到`GL_ARRAY_BUFFER`上
- `glBufferData`把顶点数据从cpu内存复制到gpu内存
- `glEnableVertexAttribArray` 是开启对应的顶点属性
- `glVertexAttribPointer`设置合适的格式从buffer里面读取数据

顶点缓存区：提前分配一块显存，将顶点数据预先传入到显存中，是提高性能的一种做法

顶点属性：默认情况下，在 iOS 中所有顶点着色器的属性变量是关闭的，顶点着色器是无法读取传递过来的顶点数据的，所以必须通过`glEnableVertexAttribArray`来开启对应的顶点属性

**加载纹理**

```objective-c
- (void)setupTexture {
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"Farewell" ofType: @"jpg"];
    // GLKTextureLoaderOriginBottomLeft 纹理坐标系是相反的
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:@(1), GLKTextureLoaderOriginBottomLeft, nil];

    GLKTextureInfo *textureInfo = [GLKTextureLoader textureWithContentsOfFile:filePath options:options error:nil];
    
    self.mEffect = [[GLKBaseEffect alloc] init];
    self.mEffect.texture2d0.enabled = GL_TRUE;
    self.mEffect.texture2d0.name    = textureInfo.name;
}
```

- 设置纹理参数`GLKTextureLoaderOriginBottomLeft`，纹理坐标系是相反的
- `GLKTextureLoader`读取图片，创建纹理`GLKTextureInfo`
- 创建着色器`GLKBaseEffect`，把纹理赋值给着色器

**实现代理方法**

```objective-c
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    // 清除颜色缓冲
    glClear(GL_COLOR_BUFFER_BIT);
    
    // 设置背景色
    glClearColor(0.3f, 0.3f, 0.3f, 1.0f);
    
    [self.mEffect prepareToDraw];

    glDrawArrays(GL_TRIANGLES, 0, 6);
}
```

### 思考题

1. 代码中有6个顶点坐标，能否使用更少的顶点显示一个图像？
2. 顶点缓存数组可以不用glBufferData，要如何实现？
3. 如果把这个图变成左右两只对称的熊猫，该如何改？

[完整代码](https://github.com/dev-jw/Learning-OpenGL-ES)

