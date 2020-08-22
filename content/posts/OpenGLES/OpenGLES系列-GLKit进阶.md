---
title: "OpenGLES系列-GLKit进阶"
date: 2020-07-26T19:23:33+08:00
draft: false																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																				
tags: ["iOS", "OpenGLES"]
url:  "advanced-GLKit"
---

> 在上一篇中，渲染图片的时候，我们使用了 2 个三角形来绘制一个矩形，并且留下思考：能否用更少的顶点来渲染一个矩形

**2 个三角形渲染一个矩形**

```objective-c
GLfloat vertices[] = {
    // 第一个三角形
    0.5f, 0.5f, 0.0f,   // 右上角
    0.5f, -0.5f, 0.0f,  // 右下角
    -0.5f, 0.5f, 0.0f,  // 左上角
    // 第二个三角形
    0.5f, -0.5f, 0.0f,  // 右下角
    -0.5f, -0.5f, 0.0f, // 左下角
    -0.5f, 0.5f, 0.0f   // 左上角
};
```

观察顶点数组，我们可以发现，有两个顶点坐标是重复的，那么我们可以通过**索引数组**使用 4 个顶点来绘制一个矩形

#### 索引绘制

索引数组是顶点数组的索引，把 `squareVertexData` 数组看成 4 个顶点，每个顶点会有 3 个 `GLfloat` 数据，索引从 0 开始。

索引缓冲对象（EBO）的工作方式正是这样的。和顶点缓冲对象一样，EBO 也是一个缓冲，它专门存储索引，OpenGL ES调用这些顶点的索引来决定该绘制哪个顶点。

**具体操作**

顶点定义

```objective-c
GLfloat vertices[] = {
    0.5f, 0.5f, 0.0f,   // 右上角
    0.5f, -0.5f, 0.0f,  // 右下角
    -0.5f, -0.5f, 0.0f, // 左下角
    -0.5f, 0.5f, 0.0f   // 左上角
};

GLubyte indices[] = { // 注意索引从0开始! 
    0, 1, 3, // 第一个三角形
    1, 2, 3  // 第二个三角形
};
```

**调用`glDrawElements()`渲染**

```objective-c
// 6表示有6个索引数据，可以使用sizeof(indices)/sizeof(GLubyte)来确定

// glDrawElements 函数的原型为：glDrawElements(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices);

// 第一个参数 mode 为描绘图元的模式，其有效值为：GL_POINTS, GL_LINES, GL_LINE_STRIP,  GL_LINE_LOOP,  GL_TRIANGLES,  GL_TRIANGLE_STRIP, GL_TRIANGLE_FAN。

// 第二个参数 count 为顶点索引的个数也就是，type 是指顶点索引的数据类型，因为索引始终是正值，索引这里必须是无符号型的非浮点类型，因此只能是 GL_UNSIGNED_BYTE, GL_UNSIGNED_SHORT, GL_UNSIGNED_INT 之一，为了减少内存的消耗，尽量使用最小规格的类型如 GL_UNSIGNED_BYTE。

// 第三个参数 indices 是存放顶点索引的数组。（indices 是 index 的复数形式，3D 里面很多单词的复数都挺特别的。）
glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_BYTE, indices);  

```

### 渲染正方体

通过 GLKit 渲染一个正方体，并使其旋转

效果如下：

![正方体旋转](https://w-md.imzsy.design/正方体旋转.gif)

#### 思路

![image-20200727145412401](https://w-md.imzsy.design/image-20200727145412401.png)

使用 GLKit 进行图形变换、纹理贴图加载、深度测试，用GLKBaseEffect来管理纹理贴图和矩阵操作

#### 具体实现

**渲染正方体**

之前，我们已经知道如何渲染一个面的矩形了，现在只需要将添加其余 6 个面的顶点坐标和纹理坐标，[获取顶点数据](https://w-md.imzsy.design/vertices.txt)

**顶点缓存**

将顶点数据 copy 到显存中，并开启顶点属性变量

```objective-c
    GLuint buffer;
    glGenBuffers(1, &buffer);
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, (GLfloat *)NULL);
    
    glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, (GLfloat *)NULL + 3);
```

**设置变换矩阵**

设置着色器的投影矩阵和模型视图矩阵

```objective-c
    CGSize size = self.view.bounds.size;
    float aspect = fabs(size.width / size.height);
		// 投影矩阵
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(90.0), aspect, 0.1f, 100.f);
    projectionMatrix = GLKMatrix4Scale(projectionMatrix, 1.0f, 1.0f, 1.0f);
    self.mEffect.transform.projectionMatrix = projectionMatrix;
		// 平移矩阵
    GLKMatrix4 modelViewMatrix = GLKMatrix4Translate(GLKMatrix4Identity, 0.0f, 0.0f, -2.0f);
    self.mEffect.transform.modelviewMatrix = modelViewMatrix;
```

`GLKMatrix4MakePerspective`是透视投影变换
`GLKMatrix4Translate`是平移变换

```objective-c
- (void)update {
    GLKMatrix4 modelViewMatrix = GLKMatrix4Translate(GLKMatrix4Identity, 0.0f, 0.0f, -2.0f);
    
//    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, self.mDegreeX, 1.0, 1.0, 1.0);
    
    modelViewMatrix = GLKMatrix4RotateX(modelViewMatrix, self.mDegreeX);
    modelViewMatrix = GLKMatrix4RotateY(modelViewMatrix, self.mDegreeX);
    modelViewMatrix = GLKMatrix4RotateZ(modelViewMatrix, self.mDegreeX);

    self.mEffect.transform.modelviewMatrix = modelViewMatrix;
}
```

在场景变换函数里面，更新着色器的**模型视图矩阵**

`GLKMatrix4RotateX`是绕 X 轴旋转

**深度测试**

在配置上下文时，需要设置深度测试的格式`view.drawableDepthFormat = GLKViewDrawableDepthFormat24;`，同时开启深度测试`glEnable(GL_DEPTH_TEST);`，

在渲染场景的回调中，需要增加清除深度测试的缓冲区`GL_DEPTH_BUFFER_BIT`

### 通过 Core Animation 实现正方体旋转

**CALayer** 有一个用来做 3D 变换的属性：`transform`，类型是`CATransform3D`

CATransform3D是一个矩阵，和 OpenGL ES 中的矩阵一样，都是 4*4 的矩阵。

例：旋转子视图-45度：

```objective-c
CATransform3D transform = CATransform3DIdentity;
transform = CATransform3DRotate(transform, -(45.0f/180.0f*M_PI), 0.0f, 1.0f, 0.0f);
layerView.layer.transform = transform;
```

#### 具体实现

为正方体创建一个固态的 3D 对象，这里用独立的 `UIImageView` 来加载纹理

```objective-c
- (void)addCubeWithCATransform3D:(CATransform3D)transform {
    NSString *filePath = [[NSBundle mainBundle]pathForResource:@"cover" ofType:@"jpg"];
    UIImageView *face = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
    face.image = [UIImage imageWithContentsOfFile:filePath];
    [self.container addSubview:face];

    CGSize containerSize = self.container.bounds.size;
    face.center = CGPointMake(containerSize.width / 2.0, containerSize.height / 2.0);

    face.layer.transform = transform;
}
```

#### 平移矩阵

通过`CATransform3DMakeTranslation`和`CATransform3DRotate`实现 6 个面的矩阵

```objective-c
    CATransform3D transform = CATransform3DIdentity;
    
    transform = CATransform3DMakeTranslation(0, 0, 100);
    [self addCubeWithCATransform3D:transform];
    
    transform = CATransform3DMakeTranslation(100, 0, 0);
    transform = CATransform3DRotate(transform, M_PI_2, 0, 1, 0);
    [self addCubeWithCATransform3D:transform];
    
    transform = CATransform3DMakeTranslation(0, -100, 0);
    transform = CATransform3DRotate(transform, M_PI_2, 1, 0, 0);
    [self addCubeWithCATransform3D:transform];

    transform = CATransform3DMakeTranslation(0, 100, 0);
    transform = CATransform3DRotate(transform, -M_PI_2, 1, 0, 0);
    [self addCubeWithCATransform3D:transform];

    transform = CATransform3DMakeTranslation(-100, 0, 0);
    transform = CATransform3DRotate(transform, -M_PI_2, 0, 1, 0);
    [self addCubeWithCATransform3D:transform];

    transform = CATransform3DMakeTranslation(0, 0, -100);
    transform = CATransform3DRotate(transform, M_PI, 0, 1, 0);
    [self addCubeWithCATransform3D:transform];
```

#### 旋转矩阵

设置定时器，执行事件：更新`sublayerTransform`的旋转矩阵

```objective-c
    static CGFloat angle = 1.0f;
    double delayInSeconds = 0.1;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC, 0.0);
    dispatch_source_set_event_handler(timer, ^{
        CATransform3D transform3d = self.container.layer.sublayerTransform;
        transform3d = CATransform3DRotate(transform3d, angle/180.0f*M_PI, 1.0f, 1.0f, 1.0f);
        self.container.layer.sublayerTransform = transform3d;
    });
    dispatch_resume(timer);
```

在这里我们需要使用`sublayerTransform`而不是直接把`superLayer`进行旋转

> 尽管 Core Animation 图层存在于 3D 空间内，但他们并不都是存在同一个 3D 空间。
>
> 每个图层的 3D 场景其实是扁平化的，当你从正面观察一个图层，看到的实际上由子图层创建的想象出来的 3D 场景，但当你倾斜这个图层，你会发现实际上这个 3D 场景仅仅是被绘制在图层的表面

[完整代码](https://github.com/dev-jw/Learning-OpenGL-ES)

