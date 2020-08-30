---
title: "Metal系列-大批量顶点数据的图形渲染"
date: 2020-08-25T10:43:20+08:00
draft: false
tags: ["Metal", "iOS"]
url:  "Metal-4"
---

在 Metal 中，当顶点数据比较少时，我们将顶点数据存储在 CPU 中，直接从内存中获取数据传递到 Metal 程序。

但当顶点数据量过大时(`大于 4KB`)，就不适合使用 CPU 来进行存储和传递了，而是需要通过 `MTLBuffer`，将顶点数据存储到顶点缓冲区，GPU 能够直接访问顶点缓冲区获取顶点数据，并且传递到 Metal 程序。

#### MTLBuffer

Metal框架不知道MTLBuffer的任何内容，只知道它的大小。

在缓冲区中定义数据的格式，并确保你的应用程序和你的着色器知道如何读取和写入数据。

例如，可以在着色器中创建一个结构，它定义了想要存储在缓冲区及其内存布局中的数据。

```objective-c
// 顶点数据结构体
typedef struct
{
//    像素空间的位置
    vector_float2 position;    
//    RGBA颜色
    vector_float4 color;
}Vertex;

// 创建 MTLBuffer 对象
_vertexBuffer = [_device newBufferWithBytes:vertexData.bytes length:vertexData.length options:MTLResourceStorageModeShared];
memcmp(_vertexBuffer.contents, vertexData.bytes, vertexData.length);

// 将 Buffer 中的数据传递到着色器
[commandEncoer setVertexBuffer:_vertexBuffer offset:0 atIndex:VertexInputIndexVertices];
```

#### 案例分析

**生成顶点数据**

- `generateVertexData`函数模拟生成大批量的顶点数据

- 创建 MTLBuffer 对象，并且将顶点数据复制到 MTLBuffer 的 `contens` 内容属性

  ```objective-c
  NSData *vertexData = [Renderer generateVertexData];
          
  _vertexBuffer = [_device newBufferWithBytes:vertexData.bytes length:vertexData.length options:MTLResourceStorageModeShared];
  
  memcmp(_vertexBuffer.contents, vertexData.bytes, vertexData.length);
  ```

- 计算顶点个数`_numberVertex = vertexData.length / sizeof(Vertex);`

**渲染前配置**

- 获取 `MTLDevice` 对象，即获取 GPU 的使用权限
- 创建Metal着色器函数的集合`MTLLibrary`对象
- 加载顶点函数、片段函数
- 根据渲染管线描述符创建渲染管线状态
- 创建命令提交队列

```objective-c
- (void)configWithMetalView:(MTKView *)mtkView {
    _device = mtkView.device;
    
    // 设置像素颜色格式
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
		
    // 着色器函数的集合
    id<MTLLibrary> defaultLibrary  = [_device newDefaultLibrary];
    id<MTLFunction> vertexShader   = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentShader = [defaultLibrary newFunctionWithName:@"fragmentShader"];
    
    // 渲染管线描述符
    MTLRenderPipelineDescriptor *pipelineDes    = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDes.vertexFunction                  = vertexShader;
    pipelineDes.fragmentFunction                = fragmentShader;
    pipelineDes.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

    // 渲染管线状态
    NSError *error;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDes error:&error];
    NSAssert(_pipelineState, @"Failed to created pipeline state, error %@", error);

    // 命令提交队列
    _commandQueue = [_device newCommandQueue];
}
```

**每一帧渲染**

实现`MTKViewDelegate`的代理方法`- (void)drawInMTKView:(nonnull MTKView *)view;`，完成每一帧的渲染

- 创建命令缓存`MTLCommandBuffer`对象
- 创建渲染过程描述符`MTLRenderPassDescriptor`对象
- 创建渲染命令编码器`MTLRenderCommandEncoder`对象
- 设置视口
- 设置渲染管线状态
- 传递顶点缓冲区中的顶点数据
- 传递窗口尺寸（坐标归一化使用）
- 设置图元装配方式
- 结束编码
- 渲染到屏幕
- 将命令缓存对象提交至命令提交队列

```objective-c
- (void)drawInMTKView:(nonnull MTKView *)view {
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Simple Command Buffer";
   
    MTLRenderPassDescriptor *renderPassDes = view.currentRenderPassDescriptor;
    
    if (renderPassDes) {
        id<MTLRenderCommandEncoder> commandEncoer = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDes];
        commandEncoer.label = @"Simple Command Encoer";
        
        [commandEncoer setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0}];
        
        [commandEncoer setRenderPipelineState:_pipelineState];
        
        [commandEncoer setVertexBuffer:_vertexBuffer offset:0 atIndex:VertexInputIndexVertices];
        
        [commandEncoer setVertexBytes:&_viewportSize length:sizeof(_viewportSize) atIndex:VertexInputIndexViewportSize];
        
        [commandEncoer drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_numberVertex];
        
        [commandEncoer endEncoding];
    
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
}
```

顶点数据传递方式对比：

- 通过 CPU

  ```objective-c
  /* 这个调用有3个参数
      1) 参数1-bytes：指向传递给着色器的内存指针
      2) 参数2-length：想要传递的数据的内存大小
      3) 参数3-Index：对应的索引
   */
  
  //将 _viewportSize 设置到顶点缓存区绑定点设置数据        
  [commandEncoer setVertexBytes:&_viewportSize length:sizeof(_viewportSize) atIndex:VertexInputIndexViewportSize];     
  ```

- 通过 顶点缓冲对象 MTLBuffer

  ```objective-c
  /* 这个调用有3个参数
      1) buffer - 包含需要传递数据的缓冲对象
      2) offset - 它们从缓冲器的开头字节偏移，指示“顶点指针”指向什么。在这种情况下，我们通过0，所以数据一开始就被传递下来.偏移量
      3) index - 一个整数索引，对应「vertexShader」函数中的缓冲区属性限定符的索引
   */
          
  //将_vertexBuffer 设置到顶点缓存区中，顶点数据很多时，存储到buffer
  [commandEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:CJLVertexInputIndexVertices];        
  ```

#### 总结

- 当顶点数据`小于 4KB`时，可以选择存储到 CPU，通过`setVertexBytes:length:atIndex:`将数据传递到着色器

- 当顶点数据`大于 4KB`时，需要将数据存储到 MTLBuffer 对象中，让 GPU 能够直接获取，并通过`setVertexBuffer: offset: atIndex:`将顶点数据传递到着色器

[完整代码获取](https://github.com/dev-jw/learning-metal)