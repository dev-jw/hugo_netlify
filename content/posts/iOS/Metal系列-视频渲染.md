---
title: "Metal系列-视频渲染"
date: 2020-08-30T23:13:50+08:00
draft: true
tags: ["Metal", "iOS"]
url:  "Metal-7"
---

之前介绍了 Metal 如何渲染处理摄像头采集的视频，本文将介绍如何使用 Metal 渲染视频文件

> 关于 `YUV` 格式，请阅读「 [YUV格式](/yuv) 」

#### 原理

视频渲染其实和之前「[摄像头采集渲染](/metal-6)」是一样的，都是对 `CMSampleBuffer`的绘制。

利用 `AVFoundation` 框架，将视频解码，获取原始数据信息，读取可渲染的样本`CMSampleBuffer`。

由于视频采样是使用 `YUV 格式`，而渲染显示采样的 `RGB 格式`，这里需要通过 `CoreVideo`提供的方法得到 Y 和 UV 的纹理，再在 Metal 程序中，通过 YUV 转 RGB 矩阵，得到最终的 RGB 颜色值，显示到屏幕上。



> 如果从 CPU 传数据到 GPU，会阻塞等待 CPU 的数据传送完毕，比如之前在「[Metal系列-加载纹理](/metal-5)中的传递纹理逻辑」
>
> `replaceRegion` 如果用在需要频繁传递纹理的视频渲染场景，会产生很多等待的时间。

#### 思路

1. 封装 `AssetRender` 工具类，读取 mov/mp4 视频文件，提供返回`CMSampleBuffer`对象的方法
2. 初始化 Metal、顶点数据、转换矩阵
3. 实现 Metal 渲染回调方法，从`CMSampleBuffer`对象生成 Y 纹理、UV 纹理，并传递到 Metal 程序
4. 在 Metal 程序中，实现将 YUV 格式转换为 RGB 格式

整体的流程图，如下：

![image-20200903152026218](https://w-md.imzsy.design/image-20200903152026218.png)

#### 具体步骤

##### ShaderTypes.h

OC代码与 Metal 程序共用的数据

- 顶点数据结构体

  ```c
  typedef struct {
      // 顶点坐标
      vector_float4 position;
      // 纹理坐标
      vector_float2 textureCoordinate;
  }Vertex;
  ```

  

- 转换矩阵结构体

  ```c
  typedef struct {
      // 转换矩阵
      matrix_float3x3 matrix;
      
      // 偏移值
      vector_float3 offset;
  }ConvertMatrix;
  ```

  

- 顶点函数缓冲区索引

  ```c
  typedef enum VertexInputIndex {
      VertexInputIndexVertices = 0,
  }VertexInputIndex;
  ```

  

- 片段函数缓冲区索引

  ```c
  typedef enum FragmentBufferIndex {
      FragmentInputIndexMatrix = 0,
  }FragmentBufferIndex;
  ```

  

- 片段函数纹理索引

  ```c
  typedef enum FragmentTextureIndex {
      // Y
      FragmentTextureIndexTextureY = 0,
      // UV
      FragmentTextureIndexTextureUV = 1,
  }FragmentTextureIndex;
  ```

##### AssetReader 工具类

利用 `AVFoundation` 框架中的`AVAssetReader`，对视频进行解码，返回`CMSampleBuffer`对象

![image-20200903152643400](https://w-md.imzsy.design/image-20200903152643400.png)

其中，AVAssetReaderOutPut包含三种类型的输出

- AVAssetReaderTrackOutput：用于从`AVAssetReader`存储中读取单个轨道的媒体样本
- AVAssetReaderAudioMixOutput：用于读取音频样本
- AVAssetReaderVideoCompositionOutput：用于读取一个或多个轨道中的帧合成的视频帧

##### 初始化

**初始化 MTKView**

```objective-c
self.mtkView = [[MTKView alloc] initWithFrame:self.view.bounds device:MTLCreateSystemDefaultDevice()];

self.view = self.mtkView;

self.mtkView.delegate = self;

// 设置视口
self.viewPortSize =
(vector_uint2){self.mtkView.drawableSize.width, self.mtkView.drawableSize.height};
```

**初始化 AssetReader工具类**

```objective-c
NSURL *url = [[NSBundle mainBundle] URLForResource:@"abc" withExtension:@"mov"];

self.assetReader = [[AssetReader alloc] initWithUrl:url];

// _textureCacheRef的创建(通过CoreVideo提供给CPU/GPU高速缓存通道读取纹理数据)
CVMetalTextureCacheCreate(NULL, NULL, self.mtkView.device, NULL, &_textureCacheRef);
```

**初始化 渲染管道状态**

```objective-c
id<MTLLibrary> defaultLibrary = [self.mtkView.device newDefaultLibrary];
id<MTLFunction> vertexShader = [defaultLibrary newFunctionWithName:@"vertexShader"];
id<MTLFunction> fragmentShader = [defaultLibrary newFunctionWithName:@"fragmentShader"];

MTLRenderPipelineDescriptor * pipelineDes = [[MTLRenderPipelineDescriptor alloc] init];
pipelineDes.vertexFunction  = vertexShader;
pipelineDes.fragmentFunction = fragmentShader;
pipelineDes.colorAttachments[0].pixelFormat = self.mtkView.colorPixelFormat;

self.renderPipelineState = [self.mtkView.device newRenderPipelineStateWithDescriptor:pipelineDes error:nil];

self.commandQueue = [self.mtkView.device newCommandQueue];
```

**设置顶点数据**

```objective-c
//注意: 为了让视频全屏铺满,所以顶点大小均设置[-1,1]
static const Vertex squardVertices[] = {
  // 顶点坐标，分别是x、y、z、w；    纹理坐标，x、y；
  { {  1.0, -1.0, 0.0, 1.0 },  { 1.f, 1.f } },
  { { -1.0, -1.0, 0.0, 1.0 },  { 0.f, 1.f } },
  { { -1.0,  1.0, 0.0, 1.0 },  { 0.f, 0.f } },

  { {  1.0, -1.0, 0.0, 1.0 },  { 1.f, 1.f } },
  { { -1.0,  1.0, 0.0, 1.0 },  { 0.f, 0.f } },
  { {  1.0,  1.0, 0.0, 1.0 },  { 1.f, 0.f } },
};

// 创建顶点缓存区
self.vertices = [self.mtkView.device newBufferWithBytes:squardVertices
                                               length:sizeof(squardVertices)
                                              options:MTLResourceStorageModeShared];
// 计算顶点个数
self.numberVertices = sizeof(squardVertices) / sizeof(Vertex);
```

**设置转换矩阵**

```objective-c
// 设置YUV->RGB转换的矩阵
- (void)setupMatrix
{
    //1.转化矩阵
     // BT.601, which is the standard for SDTV.
     matrix_float3x3 kColorConversion601DefaultMatrix = (matrix_float3x3){
         (simd_float3){1.164,  1.164, 1.164},
         (simd_float3){0.0, -0.392, 2.017},
         (simd_float3){1.596, -0.813,   0.0},
     };
     
     // BT.601 full range
     matrix_float3x3 kColorConversion601FullRangeMatrix = (matrix_float3x3){
         (simd_float3){1.0,    1.0,    1.0},
         (simd_float3){0.0,    -0.343, 1.765},
         (simd_float3){1.4,    -0.711, 0.0},
     };
    
     // BT.709, which is the standard for HDTV.
     matrix_float3x3 kColorConversion709DefaultMatrix[] = {
         (simd_float3){1.164,  1.164, 1.164},
         (simd_float3){0.0, -0.213, 2.112},
         (simd_float3){1.793, -0.533,   0.0},
     };
    
    //2.偏移量
    vector_float3 kColorConversion601FullRangeOffset = (vector_float3){ -(16.0/255.0), -0.5, -0.5};
    
    //3.创建转化矩阵结构体.
    CJLConvertMatrix matrix;
    //设置转化矩阵
    /*
     kColorConversion601DefaultMatrix；
     kColorConversion601FullRangeMatrix；
     kColorConversion709DefaultMatrix；
     */
    matrix.matrix = kColorConversion601FullRangeMatrix;
    //设置offset偏移量
    matrix.offset = kColorConversion601FullRangeOffset;
    
    //4.创建转换矩阵缓存区.
    self.convertMatrix = [self.mtkView.device newBufferWithBytes:&matrix length:sizeof(CJLConvertMatrix) options:MTLResourceStorageModeShared];
}
```

##### 实现 MTKViewDelegate回调方法

这里和之前渲染的方式是一样的，主要说明一下

- 从工具类中读取`CMSampleBuffer`
- 根据`CMSampleBuffer`对象，获取 Y 纹理、UV 纹理，并传递 Metal 着色程序
- 片段函数中， YUV 格式转换为 RGB 格式

**读取`CMSampleBuffer`对象**

工具类暴露了方法`readBuffer`，可以获取`CMSampleBuffer``CMSampleBuffer`

```objective-c
CMSampleBufferRef sampleBuffer = [self.reader readBuffer];
```

**加载纹理**

通过 DMA 的方式提供更高效率的访问

![image-20200903152849276](https://w-md.imzsy.design/image-20200903152849276.png)

根据苹果的头文件：

`CVBufferRef = CVImageBufferRef = CVMetalTextureRef`

`CVBufferRef = CVImageBufferRef = CVPixelBufferRef`

当`CVPixelBufferRef`和`CVMetalTextureRef`绑定之后，就可以拿到 Metal 用的纹理，所有渲染到该纹理的数据，会通过高速通道返回给CPU

```objective-c
- (void)setupTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                         buffer:(CMSampleBufferRef)CMSampleBufferRef
{
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(CMSampleBufferRef);
    
    id<MTLTexture> textureY = nil;
    id<MTLTexture> textureUV = nil;
    
    {
        // 返回像素缓冲区中给定索引处的平面宽度和高度
        size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);

        // 像素格式:普通格式，包含一个8位规范化的无符号整数组件。并不是 RGBA
        MTLPixelFormat pixelFormat = MTLPixelFormatR8Unorm;

        CVMetalTextureRef texture = NULL;

        /* 根据视频像素缓存区 创建 Metal 纹理缓存区
        CVReturn CVMetalTextureCacheCreateTextureFromImage(CFAllocatorRef allocator,
        CVMetalTextureCacheRef textureCache,
        CVImageBufferRef sourceImage,
        CFDictionaryRef textureAttributes,
        MTLPixelFormat pixelFormat,
        size_t width,
        size_t height,
        size_t planeIndex,
        CVMetalTextureRef  *textureOut);
        
        功能: 从现有图像缓冲区创建核心视频Metal纹理缓冲区。
        参数1: allocator 内存分配器,默认kCFAllocatorDefault
        参数2: textureCache 纹理缓存区对象
        参数3: sourceImage 视频图像缓冲区
        参数4: textureAttributes 纹理参数字典.默认为NULL
        参数5: pixelFormat 图像缓存区数据的Metal 像素格式常量.注意如果MTLPixelFormatBGRA8Unorm和摄像头采集时设置的颜色格式不一致，则会出现图像异常的情况；
        参数6: width,纹理图像的宽度（像素）
        参数7: height,纹理图像的高度（像素）
        参数8: planeIndex.如果图像缓冲区是平面的，则为映射纹理数据的平面索引。对于非平面图像缓冲区忽略。
        参数9: textureOut,返回时，返回创建的Metal纹理缓冲区。
        */
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, self.textureCacheRef, pixelBuffer, NULL, pixelFormat, width, height, 0, &texture);

        if (status == kCVReturnSuccess) {
            textureY = CVMetalTextureGetTexture(texture);

            CFRelease(texture);
        }
    }

    {
        size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);

        // 具有两个8位归一化无符号整数成分的普通格式
        MTLPixelFormat pixelFormat = MTLPixelFormatRG8Unorm;

        CVMetalTextureRef texture = NULL;

        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, self.textureCacheRef, pixelBuffer, NULL, pixelFormat, width, height, 1, &texture);

        if (status == kCVReturnSuccess) {
            textureUV = CVMetalTextureGetTexture(texture);

            CFRelease(texture);
        }
    }
    
    if (textureY != nil && textureUV != nil) {
        [encoder setFragmentTexture:textureY atIndex:FragmentTextureIndexTextureY];
        
        [encoder setFragmentTexture:textureUV atIndex:FragmentTextureIndexTextureUV];
    }
 
    CFRelease(CMSampleBufferRef);
}
```

#### Metal着色程序

- 顶点函数：原样输出顶点坐标和纹理坐标
- 片段函数：将 YUV 格式转换为 RGB 格式

```c++
typedef struct {
    float4 clipSpacePosition [[position]];
    
    float2 textureCoordinate;
} RasterizerData;

vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant Vertex *vertexArray [[buffer(VertexInputIndexVertices)]])
{
    RasterizerData out;
    
    out.clipSpacePosition = vertexArray[vertexID].position;
    
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    
    return out;
}


fragment float4
fragmentShader(RasterizerData in [[stage_in]],
               texture2d<float> textureY [[texture(FragmentTextureIndexTextureY)]],
               texture2d<float> textureUV [[texture(FragmentTextureIndexTextureUV)]],
               constant ConvertMatrix *convertMatrix [[buffer(FragmentInputIndexMatrix)]])
{
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);

    /*
     读取YUV 纹理对应的像素点值，即颜色值
     textureY.sample(textureSampler, input.textureCoordinate).r
     从textureY中的纹理采集器中读取,纹理坐标对应上的R值.(Y)
     textureUV.sample(textureSampler, input.textureCoordinate).rg
     从textureUV中的纹理采集器中读取,纹理坐标对应上的RG值.(UV)
     */
    //r 表示 第一个分量，相当于 index 0
    //rg 表示 数组中前面两个值，相当于 index 的0 和 1，用xy也可以
    float3 yuv = float3(textureY.sample(textureSampler, in.textureCoordinate).r,
                        textureUV.sample(textureSampler, in.textureCoordinate).rg);
    
    // 将YUV 转化为 RGB值.convertMatrix->matrix * (YUV + convertMatrix->offset)
    float3 rgb = convertMatrix->matrix * (yuv + convertMatrix->offset);
    
    return float4(rgb, 1.0);
}
```

#### 总结

学习Metal的一个重点，如何使用API是其次，重点是学习苹果如何设计Metal这个语言，以及Metal 与 OpenGL ES 的对比，还有音视频编解码的基础知识等。

[完整代码获取](https://github.com/dev-jw/learning-metal)

