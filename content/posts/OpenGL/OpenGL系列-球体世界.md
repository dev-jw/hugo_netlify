---
title: "OpenGL系列-球体世界"
date: 2020-07-16T15:50:12+08:00
draft: false
tags: ["OpenGL", "iOS"]
url:  "EarthWorld"
---

#### 基础概念

**三角形批次类**

`GLTriangleBatch`是专门为了绘制三角形的批次类，它以索引顶点数组进行组织，并使用定点缓冲区对象，从而达到高效的绘制

**角色帧**

为了在 3D 场景中表示物体的位置和方向，`GLTools`为我们提供了 `GLFrame`角色帧

```c++
class GLFrame {
    M3DVector3f vOrigin;    // Where am I?
    M3DVector3f vForward;   // Where am I going?
    M3DVector3f vUp;        // Which way is up?
    ...
}
```

**渲染球体**

```cpp
// 初始化球体的三角形批次，后面参数依次是，球半径，片段数，堆叠数
gltMakeSphere(sphereBatch, 3.0, 10, 20);
```

**渲染圆环**

```cpp
// 初始化圆环的三角形批次，后面参数依次是，外半径，内半径，片段数，堆叠数
gltMakeTorus(torusBatch, 3.0f, 0.75f, 150, 15);
```

**渲染圆柱**

```cpp
// 初始化圆柱的三角形批次，后面参数依次是，底部半径，顶部半径，高度，片段数，堆叠数
gltMakeCylinder(cylinderBatch, 2.0f, 2.0f, 3.0f, 13, 2);
```

**渲染圆盘**

```cpp
// 初始化圆盘的三角形批次，后面参数依次是，内半径，外半径，片段数，堆叠数
gltMakeDisk(diskBatch, 1.5f, 3.0f, 13, 3);
```

#### 球体世界搭建流程

**绘制地板**

地板是一个矩形，我们可以通过 2 个三角形来进行渲染

```c++
GLBatch                floorBatch;          //地板
void SetupRC() {
    floorBatch.Begin(GL_LINES, 324);
    for(GLfloat x = -20.0; x <= 20.0f; x+= 0.5) {
        floorBatch.Vertex3f(x, -0.55f, 20.0f);
        floorBatch.Vertex3f(x, -0.55f, -20.0f);
        
        floorBatch.Vertex3f(20.0f, -0.55f, x);
        floorBatch.Vertex3f(-20.0f, -0.55f, x);
    }
    floorBatch.End();
}

void RenderScene() {
    //1.颜色值(地板,大球,小球颜色)
    static GLfloat vFloorColor[] = { 0.0f, 1.0f, 0.0f, 1.0f};

    //2.清除颜色缓存区和深度缓冲区
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    //3.绘制地面
    shaderManager.UseStockShader(GLT_SHADER_FLAT,
                                 transformPipeline.GetModelViewProjectionMatrix(),
                                 vFloorColor);
    floorBatch.Draw();
    
    
    //4.执行缓存区交换
    glutSwapBuffers();
}
```


**绘制随机小球**

使用批次类`sphereBatch`的`gltMakeSphere`来渲染随机小球

```c++
GLTriangleBatch     sphereBatch; 
void SetupRC() {
    //1. 设置小球球模型
    gltMakeSphere(sphereBatch, 0.1f, 26, 13);
    //2. 随机位置放置小球球
    for (int i = 0; i < NUM_SPHERES; i++) {
        
        //y轴不变，X,Z产生随机值
        GLfloat x = ((GLfloat)((rand() % 400) - 200 ) * 0.1f);
        GLfloat z = ((GLfloat)((rand() % 400) - 200 ) * 0.1f);
        
        //在y方向，将球体设置为0.0的位置，这使得它们看起来是飘浮在眼睛的高度
        //对spheres数组中的每一个顶点，设置顶点数据
        spheres[i].SetOrigin(x, 0.0f, z);
    }
}

void RenderScene() {
  	
    static GLfloat vWhite[] = { 1.0f, 1.0f, 1.0f, 1.0f };
    static GLfloat vLightPos[] = {0.0f, 3.0f, 0.0f, 1.0f};
  	...
    // 画小球
    for (int i = 0; i < NUM_SPHERES; i++) {
        modelViewMatrix.PushMatrix();
        modelViewMatrix.MultMatrix(spheres[i]);
        shaderManager.UseStockShader(GLT_SHADER_POINT_LIGHT_DIFF, 
                                     transformPipeline.GetModelViewMatrix(),
                                     transformPipeline.GetProjectionMatrix(), 
                                     vLightPos, 
                                     vWhite);
        sphereBatch.Draw();
        modelViewMatrix.PopMatrix();
        
    }
  	...
}
```

**绘制自转大球**

使用批次类`torusBatch`的`gltMakeSphere`来渲染中心大球

```c++
GLTriangleBatch		torusBatch;             //大球
void SetupRC() {
    gltMakeTorus(torusBatch, 0.4f, 0.15f, 40, 20);
}

void RenderScene() {
    static CStopWatch    rotTimer;
    GLfloat yRot = rotTimer.GetElapsedSeconds() * 60.0f;
  
    static GLfloat vWhite[] = { 1.0f, 1.0f, 1.0f, 1.0f };
    static GLfloat vLightPos[] = {0.0f, 3.0f, 0.0f, 1.0f};
    
    // 自转球
    M3DVector4f vLightPos = {0.0f,10.0f,5.0f,1.0f};
   
    //1.使得大球位置平移(3.0)向屏幕里面
    modelViewMatrix.Translate(0.0f, 0.0f, -3.0f);
    //2.压栈(复制栈顶)
    modelViewMatrix.PushMatrix();
    //3.大球自转
    modelViewMatrix.Rotate(yRot, 0.0f, 1.0f, 0.0f);
    //4.指定合适的着色器(点光源着色器)
    shaderManager.UseStockShader(GLT_SHADER_POINT_LIGHT_DIFF, 
                                 transformPipeline.GetModelViewMatrix(),
                                 transformPipeline.GetProjectionMatrix(), 
                                 vLightPos, 
                                 vWhite);
    torusBatch.Draw();
    //5.绘制完毕则Pop
    modelViewMatrix.PopMatrix();
    
    //6.执行缓存区交换
    glutSwapBuffers();
}
```

**绘制公转小球**

使用批次类`sphereBatch`的`gltMakeSphere`来渲染绕中心大球的小球

```c++
GLTriangleBatch     sphereBatch;
void RenderScene() {
  	...
    modelViewMatrix.Rotate(yRot * -2.0f, 0.0f, 1.0f, 0.0f);
    modelViewMatrix.Translate(0.8f, 0.0f, 0.0f);
    shaderManager.UseStockShader(GLT_SHADER_FLAT,
                                 transformPipeline.GetModelViewProjectionMatrix(),
                                 vSphereColor);
    sphereBatch.Draw();
    modelViewMatrix.PopMatrix();
	 ...
}
```


