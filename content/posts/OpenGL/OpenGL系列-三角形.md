---
title: "OpenGL系列-三角形"
date: 2020-07-02T09:34:18+08:00
draft: false
tags: ["OpenGL", "iOS"]
url: "Hello_Triangle"
---

在[《OpenGL系列-基本概念》](/openglnoun/)中，我们已经对 OpenGL 的概念有了一个初步的认识，现在让我们开始第一个案例吧。

### 你好，三角形

想在屏幕上新建窗口并输出一个三角形之前，我们先得配置一下 OpenGL 的环境

#### OpenGL在Mac环境下的配置

**通过 Xcode 创建工程**

`Command+shift+N`创建一个新的工程，选择 `macOS` 下的 `App`

![image-20200703143300745](https://w-md.imzsy.design//image-20200703143300745.png)

OpenGL 的集成有 2 种方式：

- [手动导入](#手动导入)

- [通过Cocoapods导入](#通过CocoaPods导入)

#### 手动导入

打开之前的工程，选择当前的 `target`，找到 `Build Phases` 下的 `Link Binary With Libraies`，添加 `OpenGL.framework` 和 `GLUT.framework`

![image-20200703144035645](https://w-md.imzsy.design//image-20200703144035645.png)

将 OpenGL 环境资料包解压，并将解压后的文件移动到目录下

![image-20200703145155853](https://w-md.imzsy.design//image-20200703145155853.png)

将文件添加到工程中，通过 `Add files to "XXX"`。

接着，需要切换到 `Build Setting` 下，输入 `Header Search Path`，将 `include` 文件夹拖入到 `Path` 中

![image-20200703145137411](https://w-md.imzsy.design//image-20200703145137411.png)

将 `libGLTools.a` 拖入到 **Frameworks** 文件夹下

![image-20200703145520747](https://w-md.imzsy.design//image-20200703145520747.png)

接着删除`AppDelegate.h  AppDelegate.m  main.m ViewController.h  ViewController.m`文件。

`Command + N` 选择 `C++` 文件并创建 `main.cpp` 文件，注意：不要勾选 `Also create a header file`

![image-20200703145817029](https://w-md.imzsy.design//image-20200703145817029.png)

现在，只需要到 `main.cpp` 去实现显示一个三角形就可以了

#### 通过CocoaPods导入

这里有一份配置好的本地的 Pod 资料，首先将其下载，并放到工程目录下

![image-20200703150054748](https://w-md.imzsy.design//image-20200703150054748.png)

打开终端，切换到工程目录，初始化 pod 工程

```sh
pod init
```

配置 Podfile

```ruby
# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'Hello_Triangle' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for Hello_Triangle
  pod 'GLTools', :path => 'libs/GLTools'
  pod 'GL', :path => 'libs/GL'

  target 'Hello_TriangleTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'Hello_TriangleUITests' do
    # Pods for testing
  end

end

```

执行 `pod install`

安装完成之后，打开 xcworkspace，接下来的步骤就是**手动导入**中的删除`AppDelegate.h  AppDelegate.m  main.m ViewController.h  ViewController.m`文件以及创建 `main.cpp` 文件。

完成之后，同样的就可以在 `main.cpp` 中去编写代码了

### 编写显示三角形代码

**我们来分析下三角形是如何被渲染到屏幕上的**？

对于 OpenGL 的渲染流程，在之前的文章中已经有所介绍，这里就不过多展开了。

整个流程分为：

输入顶点数据 -> 顶点着色器读取顶点数据 -> 装配图元 -> 几何着色器构成新的图元 -> 光栅化图元 -> 片段着色器计算一个像素的最终颜色 -> Alpha 测试和混合 -> 写入帧缓冲区 -> 显示到屏幕上

按照上面的流程，我们一直期待的三角形就可以被显示到屏幕上了。



**导入依赖头文件**

```c++
#include "GLTools.h"
#include "GLShaderManager.h"

#ifdef __APPLE__
#include <glut/glut.h>
#else
#define FREEGLUT_STATIC
#include <GL/glut.h>
#endif
```

`GLShaderManager.h`移入了 GLTool 着色器管理器类

`GLTools.h`头文件中包含了大部分 GLTool 中类似 C语言的独立函数

**定义着色器**

`GLShaderManager shaderManager`定义着色器管理对象

`GLBatch triangleBatch`定义三角形批次容器

```c++
GLShaderManager shaderManager;

GLBatch triangleBatch;
```

**重要的函数**

```c++
void ChangeSize(int w,int h){}
void SetupRC(){}
void RenderScene(void){}
int main(int argc,char* argv[]){}
```

分别的作用：

`void ChangeSize(int w,int h){}`是自定义函数，当视口大小发生变化或第一个创建视口时，会调用该函数调整视口大小

`void SetupRC(){}`是自定义函数，设置你需要渲染的图形的相关顶点数据、颜色数据等数据装备工作

`void RenderScene(void){}`是自定义函数，用来将数据渲染到屏幕的

`int main(int argc,char* argv[]){}`是程序入口函数。

**ChangeSize**

 ChangeSize 触发条件:

- 新建窗⼝
- 窗⼝尺⼨发生调整

处理业务:

- 设置OpenGL 视⼝
- 设置OpenGL 投影方式等.

```c++
//窗口大小改变时接受新的宽度和高度，其中0,0代表窗口中视口的左下角坐标，w，h代表像素
void ChangeSize(int w,int h)
{
    glViewport(0,0, w, h);
}
 
```

**SetupRC**

setupRC 触发条件:

- 手动main函数触发

处理业务:

- 设置窗⼝背景颜⾊

- 初始化存储着色器shaderManager

- 设置图形顶点数据

- 利用 GLBatch 三角形批次类,将数据传递到着⾊器

```c++
void SetupRC()
{
    //设置背影颜色
    glClearColor(0.0f,0.0f,0.0f,1.0f);
    //初始化着色管理器 - 固定渲染管线
    shaderManager.InitializeStockShaders();
    //设置三角形，其中数组vVert包含所有3个顶点的x,y,笛卡尔坐标对。
    GLfloat vVerts[] = {
        -0.5f,0.0f,0.0f,
        0.5f,0.0f,0.0f,
        0.0f,0.5f,0.0f,
    };
    //批次处理
    triangleBatch.Begin(GL_TRIANGLES,3);
    triangleBatch.CopyVertexData3f(vVerts);
    triangleBatch.End();
}
```

**RenderScene**

RenderScene 触发条件:

- 系统⾃动触发
- 开发者手动调用函数触发

处理业务:

- 清理缓存区(颜⾊,深度,模板缓存区等)

- 使⽤存储着⾊器

- 绘制图形

```C++
    //清除一个或一组特定的缓冲区
    glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
    //设置一组浮点数来表示红色
    GLfloat vRed[] = {1.0f,0.0f,0.0f,1.0f};
    //传递到存储着色器，即GLT_SHADER_IDENTITY着色器，这个着色器只是使用指定颜色以默认笛卡尔坐标第在屏幕上渲染几何图形
    shaderManager.UseStockShader(GLT_SHADER_IDENTITY,vRed);
    //提交着色器
    triangleBatch.Draw();
    //将在后台缓冲区进行渲染，然后在结束时交换到前台
    glutSwapBuffers();
```

**main**

主要是 GLUT 相关的初始化以及注册回调函数

```c++
    //设置当前工作目录，针对MAC OS X
    gltSetWorkingDirectory(argv[0]);
    //初始化GLUT库
    glutInit(&argc, argv);
    /*初始化双缓冲窗口，其中标志GLUT_DOUBLE、GLUT_RGBA、GLUT_DEPTH、GLUT_STENCIL分别指
     双缓冲窗口、RGBA颜色模式、深度测试、模板缓冲区*/
    glutInitDisplayMode(GLUT_DOUBLE|GLUT_RGBA|GLUT_DEPTH|GLUT_STENCIL);
    //GLUT窗口大小，标题窗口
    glutInitWindowSize(800,600);
    glutCreateWindow("Triangle");
    //注册回调函数
    glutReshapeFunc(ChangeSize);
    glutDisplayFunc(RenderScene);
    //驱动程序的初始化中没有出现任何问题。
    GLenum err = glewInit();
    if(GLEW_OK != err) {
        fprintf(stderr,"glew error:%s\n",glewGetErrorString(err));
        return 1;
    }
    //调用SetupRC
    SetupRC();
    glutMainLoop();
    return 0;
```

整个流程：

![image-20200705205634882](https://w-md.imzsy.design/image-20200705205634882.png)

在运行循环时

- 收到重塑消息，会回调 `ChangeSize` 触发渲染
- 收到渲染消息，会回调 `RenderScene` 触发绘制

完整代码如下：

```c++
#include "GLTools.h"
#include "GLShaderManager.h"

#ifdef __APPLE__
#include <glut/glut.h>
#else
#define FREEGLUT_STATIC
#include <GL/glut.h>
#endif

GLBatch triangleBatch;

GLShaderManager shaderManager;

//窗口大小改变时接受新的宽度和高度，其中0,0代表窗口中视口的左下角坐标，w，h代表像素
void ChangeSize(int w,int h)
{
    glViewport(0,0, w, h);
}

//为程序作一次性的设置
void SetupRC()
{
    //设置背影颜色
    glClearColor(0.0f,0.0f,0.0f,1.0f);
    //初始化着色管理器 - 固定渲染管线
    shaderManager.InitializeStockShaders();
    //设置三角形，其中数组vVert包含所有3个顶点的x,y,笛卡尔坐标对。
    GLfloat vVerts[] = {
        -0.5f,0.0f,0.0f,
        0.5f,0.0f,0.0f,
        0.0f,0.5f,0.0f,
    };
    //批次处理
    triangleBatch.Begin(GL_TRIANGLES,3);
    triangleBatch.CopyVertexData3f(vVerts);
    triangleBatch.End();
}

//开始渲染
void RenderScene(void)
{
    //清除一个或一组特定的缓冲区
    glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
    //设置一组浮点数来表示红色
    GLfloat vRed[] = {1.0f,0.0f,0.0f,1.0f};
    //传递到存储着色器，即GLT_SHADER_IDENTITY着色器，这个着色器只是使用指定颜色以默认笛卡尔坐标第在屏幕上渲染几何图形
    shaderManager.UseStockShader(GLT_SHADER_IDENTITY,vRed);
    //提交着色器
    triangleBatch.Draw();
    //将在后台缓冲区进行渲染，然后在结束时交换到前台
    glutSwapBuffers();
}

int main(int argc,char* argv[])
{
    //设置当前工作目录，针对MAC OS X
    gltSetWorkingDirectory(argv[0]);
    //初始化GLUT库
    glutInit(&argc, argv);
    /*初始化双缓冲窗口，其中标志GLUT_DOUBLE、GLUT_RGBA、GLUT_DEPTH、GLUT_STENCIL分别指
     双缓冲窗口、RGBA颜色模式、深度测试、模板缓冲区*/
    glutInitDisplayMode(GLUT_DOUBLE|GLUT_RGBA|GLUT_DEPTH|GLUT_STENCIL);
    //GLUT窗口大小，标题窗口
    glutInitWindowSize(800,600);
    glutCreateWindow("Triangle");
    //注册回调函数
    glutReshapeFunc(ChangeSize);
    glutDisplayFunc(RenderScene);
    //驱动程序的初始化中没有出现任何问题。
    GLenum err = glewInit();
    if(GLEW_OK != err) {
        fprintf(stderr,"glew error:%s\n",glewGetErrorString(err));
        return 1;
    }
    //调用SetupRC
    SetupRC();
    glutMainLoop();
    return 0;
}
```

效果：

![image-20200703151309611](https://w-md.imzsy.design//image-20200703151309611.png)

最后，如果你觉得 `xcode` 警告太烦人，可以将 `Build Setting`下 的 `Deprecated Functions` 设置为 **NO**