---
title: "Metal系列-认识Metal"
date: 2020-08-20T16:38:42+08:00
draft: false
tags: ["Metal", "iOS"]
url:  "Metal-1"
---

#### 什么是 Metal

Metal是一个和 OpenGL ES类似的面向底层的图形编程接口，通过使用相关的 api 可以直接操作 GPU，能最大的挖掘设备的 GPU 能力，进行复制的运算。

Metal 经过版本迭代，已经不再是 iOS 平台独有，现在同样支持在 macOS、watchOS 下。

**Metal具有特点**

- 和 CPU 并行处理数据（深度学习）
- 提供低功耗接口
- GPU 支持的 3D 渲染
- 和 CPU 共享资源内存

**层级关系**

**UIKit -> Core Graphics -> Metal/OpenGL ES -> GPU Driver -> GPU**

![image-20200821104303922](https://w-md.imzsy.design/image-20200821104303922.png)

#### Metal渲染

Metal 渲染流程和 OpenGL ES 是基本一致的。

- CPU 将顶点数据传递到顶点着色器
- 顶点着色器处理顶点，将处理的结果传送到几何着色器
- 几何着色器进行图元装配
- 图元装配完成后，进入光栅化阶段，将图元光栅化为像素点
- 光栅化后，进入片段着色器，处理每一个像素点的颜色值
- 片段着色器会将数据存储到帧缓冲，并由视频控制器显示到屏幕上

#### Metal核心类

**MTLDevice**

既然是操作 GPU，当然需要去获取 GPU 对象。

Metal 中提供了 `MTDevice` 协议，代表了 GPU 的接口。

```objective-c
//获取设备
id<MTLDevice> device = MTLCreateSystemDefaultDevice();
NSAssert(device, @"Don't support metal !");
```

`MTLDevice`提供了如下的能力：

- 查询设备状态
- 创建 buffer 和 texture
- 指令转换和队列化渲染进行指令的计算

**MTKView**

在 Metal 中直接绘制，需要用特殊的界面 `MTKView`，同时给它设置对应的 `device`，并把它添加到当前的界面上。

```objective-c
_mtkView = [[MTKView alloc] initWithFrame:self.view.frame device:_device];
[self.view addSubview:_mtkView];
```

> 在 `GLKit` 中直接绘制，我们会使用 `GLKView`

**MTLCommandQueue**

在获得 GPU 对象之后，我们需要一个渲染队列 `MTLCommandQueue`，通过 `MTLDevice` 获取队列

```objective-c
[_device newCommandQueue];
```

`MTLCommandQueue`具有以下特点：

- 队列是单一队列，确保了指令能够按顺序执行
- 里面的是将要渲染的指令 `MTLCommandBuffer`
- 这是个线程安全的队列
- 支持多个 CommandBuffer 同时编码

**渲染**

在绘制之前，我们需要先配置好 `MTLDevice`、`MTLCommandQueue` 和 `MTKView`，然后就是要塞进队列中的缓冲数据 `MTLCommandBuffer`

简单的流程：

- 构造`MTLCommandBuffer`
- 配置`MTLRenderCommandEncoder`，包括配置资源文件，设置渲染管线等
- 将`MTLRenderCommandEncoder`进行编码
- 最后将`MTLCommandBuffer`提交到队列中

**MTLCommandBuffer**

命令缓冲区 CommandBuffer 是包含了多种类型的命令编码。

`MTLCommandBuffer`是不支持重用的轻量级对象，需要每次都获取一个新的 Buffer。

> 通常情况下，app 的一帧就是渲染为一个单独的 Command Buffer

在创建了`MTLCommandQueue`之后，我们需要构建队列中的`MTLCommandBuffer`，一开始获取的 Buffer 对象是空的，要通过`MTLCommandEncoder`编码器来 Encode，一个 Buffer 可以被多个 Encoder进行编码

**创建 Command Buffer**

```objective-c
id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
```

**执行 Command Buffer**

Buffer在未提交之前，是不会开始执行的

提交方式：

- `enqueue` 顺序执行
- `commit`  插队尽快执行（如果前面有 commit 还是需要排队等着）

**MTLCommandEncoder**

指令编码器是将GPU命令写入命令缓冲区的编码器。

包括四种编码器：

- `MTLRenderCommandEncoder` 图形渲染编码器
- `MTLComputeCommandEncoder` 计算编码器
- `MTLBlitCommandEncoder` 内存管理编码器（比如复制buffer texture）
- `MTLParallelRenderCommandEncoder`并行编码的多个图形渲染任务

在创建 CommandEncoder 之前，需要先创建渲染过程描述符 `MTLRenderPassDescriptor`

```objective-c
MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
```

然后构造合适的指令编码器

```objective-c
id<MTLRenderCommandEncoder> renderCommandEncoder = 
  	[commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
```

最后结束编码

```objective-c
[renderCommandEncoder endEncoding];
```

#### 总结

**Metal的使用建议**

苹果对metal的使用有以下几点建议：

- `Separate Your Rendering Loop` 分开渲染循环：不希望将渲染的处理放到VC中，希望将渲染循环封装在一个单独的类中
- `Respond to View Events` 响应视图的事件，即`MTKViewDelegate`协议，也需要放在自定义的渲染循环中
- `Metal Command Objects` 创建一个命令对象，即创建执行命令的GPU、与GPU交互的`MTLCommandQueue`对象以及`MTCommandBuffer`渲染缓存区湘

**渲染流程**

1. 配置 Device 和 Queue
2. 配置 PipelineState
3. 构造 CommandBuffer
4. 配置 CommandEncoder
5. 将资源、渲染管线进行 Encode
6. 提交 buffer 到 Queue

![image-20200821151833114](https://w-md.imzsy.design/image-20200821151833114.png)

**Metal能做什么？**

- 图片处理、滤镜
- 视频处理
- 机器学习
- 大计算工作、分担 CPU 压力



> 参考资料：
>
> [Metal渲染案例](https://github.com/dev-jw/learning-metal)
>
> [Metal 的最佳实践](https://developer.apple.com/library/content/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/index.html#//apple_ref/doc/uid/TP40016642-CH27-SW1)
>
> [Metal Programming Guide](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Introduction/Introduction.html#//apple_ref/doc/uid/TP40014221-CH1-SW1)
>
> [Metal Shading Language](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf#//apple_ref/doc/uid/TP40014364)

