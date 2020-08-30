---
title: "Metal系列-绘制三角形"
date: 2020-08-20T20:43:15+08:00
draft: false
tags: ["Metal", "iOS"]
url:  "Metal-2"
---

使用 MetalKit 渲染 2D 图形-三角形

**渲染关键点**

![image-20200825160100888](https://w-md.imzsy.design/image-20200825160100888.png)

#### MTKShaderTypes.h

这个头文件中包含了结构体，枚举等数据，这些数据可以被 OC 和 Metal Shader 同时共享，起到桥接的作用。

```objective-c
#ifndef MTKShaderTypes_h
#define MTKShaderTypes_h

#include <simd/simd.h>

// 定义缓存区索引值
typedef enum VertexInputIndex
{
    // 顶点
    VertexInputIndexVertices = 0,
    // 视图大小
  	VertexInputIndexViewportSize = 1
} VertexInputIndex;

// 图形数据的结构体
typedef struct
{
  	// 顶点
    vector_float4 position;
    // RGBA 颜色
  	vector_float4 color;
} Vertex;

#endif /* MTKShaderTypes_h */
```

#### MTKShaders.metal

Metal文件，由 Metal Shader Language 编写，这里主要实现顶点函数和片段函数

```c++
#include <metal_stdlib>
#include "MTKShaderTypes.h"

using namespace metal;

// 顶点着色器输出和片元着色器输入（相当于OpenGL ES中的varying修饰的变量，即桥接）
typedef struct
{
  	//    处理空间的顶点信息，相当于OpenGL ES中的gl_Position
  	//    float4 修饰符，是一个4维向量
    float4 position [[position]];
    //    颜色，相当于OpenGL ES中的gl_FragColor
    float4 color;
} RasterizerData;

//顶点着色器函数
/*
 vertex：修饰符，表示是顶点着色器
 RasterizerData：返回值
 vertexShader：函数名称，可自定义
 
 vertexID：metal自己反馈的id
 vertices：1）告诉存储的位置buffer 2）告诉传递数据的入口是CJLVertexInputIndexVertices
 vertices 和 viewportSizePointer 都是通过CJLRenderer 传递进来的
 */
vertex RasterizerData
vertexShader(uint vertexID [[vertex_id]],
             constant Vertex *vertices [[buffer(VertexInputIndexVertices)]],
             constant vector_float2 *viewportSizePointer [[buffer(VertexInputIndexViewportSize)]])
{
    RasterizerData out;
    
    out.position = vertices[vertexID].position;
    out.color  = vertices[vertexID].color;
    
    return out;
}

/*
 fragment：修饰符，表示是片元着色器
 float4：返回值，即颜色值RGBA
 fragmentShader：函数名称，可自定义
 
 RasterizerData：参数类型（可修改）
 in：形参变量（可修改）
 [[stage_in]]：属性修饰符，表示单个片元输入（由定点函数输出）(不可修改)，相当于OpenGL ES中的varying
 */
fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    return in.color;
}
```

#### MTKRender

该类主要负责 **Metal** 的渲染设置，以及每一帧的渲染回调实现

**初始化**

1. 创建`MTLDevice`
2. 创建`MTLLibrary`，并加载 `.metal` 文件中的顶点函数与片段函数
3. 配置用于创建管道状态的管道描述符`MTLRenderPipelineState`，加载顶点函数、片段函数、设置颜色数据的格式
4. 创建`MTLCommandQueue`

```objective-c
- (instancetype)initWithMetalKitView:(MTKView *)mtkView {
    self = [super init];
    if (self) {
        _device = mtkView.device;
        
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        // 加载顶点函数
        id<MTLFunction> vertexFunc = [defaultLibrary newFunctionWithName:@"vertexShader"];
        // 加载片段函数
        id<MTLFunction> fragmentFunc = [defaultLibrary newFunctionWithName:@"fragmentShader"];
        // 配置用于创建管道状态的管道描述符
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.label = @"pipelineDescriptor";
        // 设置顶点函数
        pipelineDescriptor.vertexFunction = vertexFunc;
        // 设置片段函数
        pipelineDescriptor.fragmentFunction = fragmentFunc;
        // 设置存储颜色数据的格式
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        
        NSError *error = NULL;
        // 根据渲染管线描述符创建管道状态
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        
        NSAssert(_pipelineState, @"Failed to created pipeline state, error:%@", error);
        
        // 创建命令队列
        _commandQueue = [_device newCommandQueue];
    }
    return self;
}
```

**每一帧渲染**

实现**MTKViewDelegate**的代理回调，即渲染三角形。

三角形的渲染和 OpenGL ES 渲染的流程非常相似，只是形式有一些不同。

在 Metal 中，我们需要使用命令缓存 `MTLCommandBuffer` 对象存储命令，同时配合`MTLRenderCommandEncoder`渲染命令描述符将顶点数据、渲染管线、图元连接方式进行编码

```objective-c
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

- (void)drawInMTKView:(MTKView *)view {
    // 顶点数据 NDC 坐标系
    static const Vertex triangleVertices[] = {
        {{0.5, -0.25, 0.0, 1.0}, {1, 0, 0, 1}},
        {{-0.5, -0.25, 0.0, 1.0}, {0, 1, 0, 1}},
        {{-0.0, 0.25, 0.0, 1.0}, {0, 0, 1, 1}},
    };
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"CommandBuffer";
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if (renderPassDescriptor != nil) {
        id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderCommandEncoder.label = @"RenderCommandEncoder";
        // 设置视口
        MTLViewport viewportSize = {
            0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0
        };
        [renderCommandEncoder setViewport:viewportSize];
        
        // 渲染管线
        [renderCommandEncoder setRenderPipelineState:_pipelineState];
        // 传递顶点数据
        [renderCommandEncoder setVertexBytes:triangleVertices
                                      length:sizeof(triangleVertices)
                                     atIndex:VertexInputIndexVertices];
      	// 传递视口大小
        [renderCommandEncoder setVertexBytes:&_viewportSize
                                      length:sizeof(_viewportSize)
                                     atIndex:VertexInputIndexViewportSize];
        
        // 图元连接方式
        [renderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        // 结束编码
        [renderCommandEncoder endEncoding];
        // 绘制
        [commandBuffer presentDrawable:view.currentDrawable];
    }
  	// 插队尽快执行
    [commandBuffer commit];
}
```

#### 总结

Metal 的图形渲染管线的流程：

顶点数据传入顶点着色器，顶点着色器处理顶点，接着 Metal 会完成图元装配和光栅化，将处理后的数据传入片段着色器进行处理

![image-20200826112351169](https://w-md.imzsy.design/image-20200826112351169.png)

[完整代码获取](https://github.com/dev-jw/learning-metal)