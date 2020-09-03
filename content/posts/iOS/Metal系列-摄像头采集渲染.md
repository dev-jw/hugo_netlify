---
title: "Metal系列-摄像头采集渲染"
date: 2020-08-27T23:12:32+08:00
draft: false
tags: ["Metal", "iOS"]
url:  "Metal-6"
---

摄像头实时采集内容，并基于 Metal 实时渲染所需要的几个框架

- 摄像头采集内容：`AVFoundation`框架捕获视频
- 将视频帧转化为纹理对象：`CoreVideo`框架的`CMSampleBufferRef`对象
- 渲染纹理：`Metal` 框架中的`MetalPerformanceShaders`

#### Metal 相关设置

1. 创建和初始化 MTKView
2. 设置 MTKView 的 `drawable`，默认的帧缓存是**只读**，设为 NO 即**可读写**，但会牺牲性能
3. 创建`CVMetalTextureCacheRef`纹理缓存，这是`Core Video`的 Metal 纹理缓存

```objective-c
- (void)setupMetal {
    self.mtkView = [[MTKView alloc] initWithFrame:self.view.bounds device:MTLCreateSystemDefaultDevice()];
    [self.view insertSubview:self.mtkView atIndex:0];

    self.mtkView.delegate = self;
    
    // 设置MTKView的drawable纹理是可读写的；（默认是只读）
    self.mtkView.framebufferOnly = false;
    
    self.commandQueue = [self.mtkView.device newCommandQueue];

    /*
     CVMetalTextureCacheCreate(CFAllocatorRef  allocator,
     CFDictionaryRef cacheAttributes,
     id <MTLDevice>  metalDevice,
     CFDictionaryRef  textureAttributes,
     CVMetalTextureCacheRef * CV_NONNULL cacheOut )
     
     功能: 创建纹理缓存区
     参数1: allocator 内存分配器.默认即可.NULL
     参数2: cacheAttributes 缓存区行为字典.默认为NULL
     参数3: metalDevice
     参数4: textureAttributes 缓存创建纹理选项的字典. 使用默认选项NULL
     参数5: cacheOut 返回时，包含新创建的纹理缓存。
     */
    CVMetalTextureCacheCreate(NULL, NULL, self.mtkView.device, NULL, &_textureCache);
}
```



#### 采集

初始化视频采集的准备工作

1. 初始化`AVCaptureSession`对象，并设置视频采集的分辨率

2. 创建串行队列

   将与AVCaptureSession的任何交互（包括其输入和输出）委托给专用的串行调度队列（sessionQueue），以使该交互不会阻塞主队列。

   ![image-20200831150043568](https://w-md.imzsy.design/image-20200831150043568.png)

3. 设置输入设备`AVCaptureDeviceInput`

   1. 获取摄像头设备`AVCaptureDevice`
   2. 根据`AVCaptureDevice`对象创建`AVCaptureDeviceInput`输入设备
   3. 将输入设备添加到 `AVCaptureSession`，添加之前需要判断是否可以添加当前输入设备

4. 设置输出`AVCaptureVideoDataOutput`

   1. 创建`AVCaptureVideoDataOutput`对象，即输出设备
   2. 设置捕获输出的`alwaysDiscardsLateVideoFrames`属性（表示视频帧延时使是否丢弃数据）为`NO`
   3.  设置捕获输出的`videoSettings`属性，指定输出内容格式，这里将像素格式设置为 `BGRA` 的格式
   4. 设置捕获输出的代理以及串行调度队列

5. 创建`AVCaptureSession`会话中一对特定的输入和输出对象之间的连接`AVCaptureConnection`

[官方文档](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture?language=objc)

```objective-c
- (void)setupCaptureSession {
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPreset1920x1080;
    
    self.processQueue = dispatch_queue_create("captureProcess", DISPATCH_QUEUE_SERIAL);
    
    NSArray *devices;
    if (@available(iOS 10.0, *)) {

        AVCaptureDeviceDiscoverySession *devicesIOS10 = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
        devices = devicesIOS10.devices;
    }else {
        devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    }

    AVCaptureDevice *inputCamera = nil;
    for (AVCaptureDevice *device in devices) {
        if ([device position] == AVCaptureDevicePositionBack) {
            inputCamera = device;
        }
    }
    
    self.deviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:nil];
    
    if ([self.session canAddInput:self.deviceInput]) {
        [self.session addInput:self.deviceInput];
    }
    
    self.deviceOutput = [[AVCaptureVideoDataOutput alloc] init];
        /**< 视频帧延迟是否需要丢帧 */
    [self.deviceOutput setAlwaysDiscardsLateVideoFrames:false];
    [self.deviceOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [self.deviceOutput setSampleBufferDelegate:self queue:self.processQueue];
    
    if ([self.session canAddOutput:self.deviceOutput]) {
        [self.session addOutput:self.deviceOutput];
    }
    // 链接输入与输出
    AVCaptureConnection *connection = [self.deviceOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    [self.session startRunning];
}
```



#### 视频帧转化

这是案例的**核心内容**

从摄像头回传`CMSampleBufferRef`数据获取`CVPixelBufferRef`视频像素对象（即位图），

通过`CVMetalTextureCacheCreateTextureFromImage`创建 `CoreVideo` 的 Metal 纹理缓存`CVMetalTextureRef`，最后通过`CVMetalTextureGetTexture`得到 Metal 纹理

1. 获取`CVPixelBufferRef`视频像素对象
2. 创建 Metal 纹理缓存`CVMetalTextureRef`
3. 通过`CVMetalTextureGetTexture`得到 Metal 纹理

```
- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
		// 从 CMSampleBufferRef 获取视频像素缓存区对象，即获取位图
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // 获取捕获视频帧的 size
    size_t width  = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    // 将位图转化为 Metal 纹理
    
    CVMetalTextureRef tmpTexture = NULL;
  
    /* 根据视频像素缓存区 创建 Metal 纹理缓存区
    CVReturn CVMetalTextureCacheCreateTextureFromImage(CFAllocatorRef allocator,                         CVMetalTextureCacheRef textureCache,
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
    参数8: planeIndex 颜色通道.如果图像缓冲区是平面的，则为映射纹理数据的平面索引。对于非平面图像缓冲区忽略。
    参数9: textureOut,返回时，返回创建的Metal纹理缓冲区。
    */
    CVReturn res = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.textureCache, pixelBuffer, NULL, MTLPixelFormatRGBA8Unorm, width, height, 0, &tmpTexture);
    
    if (res == kCVReturnSuccess) {
        
        设置绘制大小
        self.mtkView.drawableSize = CGSizeMake(width, height);
        
        // 从纹理缓存中返回Metal纹理对象
        self.texture = CVMetalTextureGetTexture(tmpTexture);
        
        CFRelease(tmpTexture);
    }
}
```



#### 渲染

`MetalPerformanceShaders`是Metal的一个集成库，有一些滤镜处理的Metal实现

`MPSImageGaussianBlur`是用作高斯模糊处理的，等价于Metal中的`MTLRenderCommandEncoder`渲染命令编码器

`MPSImageGaussianBlur`以一个Metal纹理作为输入，以一个Metal纹理作为输出，在这里：

- 输入的纹理是从摄像头采集的视频帧，也就是上面创建的纹理对象

- 输出的纹理是 MTKView 的 `currentDrawable.texture`，即当前帧缓存的纹理对象

```objective-c
- (void)drawInMTKView:(nonnull MTKView *)view {
    if (self.texture) {
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

        id<MTLTexture> drawingTexture = view.currentDrawable.texture;
        
        MPSImageGaussianBlur *filter =
        [[MPSImageGaussianBlur alloc] initWithDevice:self.mtkView.device sigma:1];
        
        [filter encodeToCommandBuffer:commandBuffer sourceTexture:self.texture destinationTexture:drawingTexture];
        
        [commandBuffer presentDrawable:view.currentDrawable];
        
        [commandBuffer commit];
        
        self.texture = nil;
    }
}
```

#### 总结

摄像头采集渲染的两个核心点：

- 从 `CVPixelBufferRef` 创建 Metal 纹理
- 使用以及理解`MetalPerformanceShaders`

> 在实际的开发应用中，`AVFoundation`提供了一个`AVCaptureVideoPreviewLayer`预览 layer，直接预览视频采集后的即时渲染，[官方文档](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer?language=objc)

[完整代码获取](https://github.com/dev-jw/learning-metal)

