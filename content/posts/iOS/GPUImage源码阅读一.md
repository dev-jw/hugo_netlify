---
title: "GPUImage源码阅读(一)"
date: 2020-08-18T10:04:33+08:00
draft: false
tags: ["GPUImage", "iOS"]
url:  "GPUImage-1"
---

> [GPUImage](https://github.com/BradLarson/GPUImage)是一个著名的图像处理开源库，它让你能够在图片、视频、相机上使用GPU加速的滤镜和其它特效

本文主要对框架中的 `GLProgram` 和 `GPUImageContext`，两个重要类的源码阅读

**预习知识**

阅读 GPUImage 源码需要有一定的基础知识储备:

- OpenGL / OpenGL ES
- AVFoundation
- CoreGraphics

> 请确保熟悉以上的框架，阅读源码会起到事半功倍

#### `GLProgram`

`GLProgram` 实现的功能就专门处理 OpenGL ES 自定义着色器程序的创建、编译、链接等相关工作。

- 初始化

  ```objective-c
  // GLProgram.h
  // 声明的 3 个初始化方法
  // 传入顶点着色器和片段着色器
  - (id)initWithVertexShaderString:(NSString *)vShaderString 
              fragmentShaderString:(NSString *)fShaderString;
  // 传入顶点着色器和片段着色器文件名
  - (id)initWithVertexShaderString:(NSString *)vShaderString 
            fragmentShaderFilename:(NSString *)fShaderFilename;
  // 传入顶点着色器文件名和片段着色器文件名
  - (id)initWithVertexShaderFilename:(NSString *)vShaderFilename 
              fragmentShaderFilename:(NSString *)fShaderFilename;
  
  // GLProgram.m 
  // 初始化着色器
  - (id)initWithVertexShaderString:(NSString *)vShaderString 
              fragmentShaderString:(NSString *)fShaderString;
  {
      if ((self = [super init])) 
      {
          _initialized = NO;
          // 初始化attributes、uniforms数组
          attributes = [[NSMutableArray alloc] init];
          uniforms = [[NSMutableArray alloc] init];
        	// 创建着色器程序
          program = glCreateProgram();
          // 编译顶点着色器
          if (![self compileShader:&vertShader 
                              type:GL_VERTEX_SHADER 
                            string:vShaderString])
          {
              NSLog(@"Failed to compile vertex shader");
          }
          // 编译片段着色器
          // Create and compile fragment shader
          if (![self compileShader:&fragShader 
                              type:GL_FRAGMENT_SHADER 
                            string:fShaderString])
          {
              NSLog(@"Failed to compile fragment shader");
          }
          // 将顶点着色器和片段着色器附着到着色器程序
          glAttachShader(program, vertShader);
          glAttachShader(program, fragShader);
      }
      
      return self;
  }
  ```

  整个初始化过程中，包含了着色器程序的创建，顶点着色器和片段着色器的创建、编译，以及附着

- 编译顶点着色器和片段着色器

  ```objective-c
  - (BOOL)compileShader:(GLuint *)shader 
                   type:(GLenum)type 
                 string:(NSString *)shaderString
  {
  //    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
                   
  	  // 编译结果
      GLint status;
      // GLSL 源代码格式化
      const GLchar *source;
      source = (GLchar *)[shaderString UTF8String];
      if (!source)
      {
          NSLog(@"Failed to load vertex shader");
          return NO;
      }
      // 根据类型创建对应的着色器对象
      *shader = glCreateShader(type);
      // 为着色器对象注入 GLSL 源代码
      glShaderSource(*shader, 1, &source, NULL);
      // 编译着色器对象
      glCompileShader(*shader);
      // 获取编译结果
      glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
  
      if (status != GL_TRUE)
      {
        // 如果编译失败，打印失败原因
        GLint logLength;
        glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0)
        {
          GLchar *log = (GLchar *)malloc(logLength);
          glGetShaderInfoLog(*shader, logLength, &logLength, log);
                if (shader == &vertShader)
                {
                    self.vertexShaderLog = [NSString stringWithFormat:@"%s", log];
                }
                else
                {
                    self.fragmentShaderLog = [NSString stringWithFormat:@"%s", log];
                }
  
          free(log);
        }
      }	
  	
  //    CFAbsoluteTime linkTime = (CFAbsoluteTimeGetCurrent() - startTime);
  //    NSLog(@"Compiled in %f ms", linkTime * 1000.0);
  	
      return status == GL_TRUE;
  }
  ```

  

- 链接

  ```objective-c
  - (BOOL)link
  {
  //    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
  		// 链接结果
      GLint status;
      // 链接着色器程序
      glLinkProgram(program);
      // 获取链接结果
      glGetProgramiv(program, GL_LINK_STATUS, &status);
      if (status == GL_FALSE)
          return NO;
      // 链接成功，删除相关的 shader，释放资源
      if (vertShader)
      {
          glDeleteShader(vertShader);
          vertShader = 0;
      }
      if (fragShader)
      {
          glDeleteShader(fragShader);
          fragShader = 0;
      }
      // 初始化成功标识
      self.initialized = YES;
  
  //    CFAbsoluteTime linkTime = (CFAbsoluteTimeGetCurrent() - startTime);
  //    NSLog(@"Linked in %f ms", linkTime * 1000.0);
  
      return YES;
  }
  ```



- 使用着色器

  ```objective-c
  - (void)use
  {
      glUseProgram(program);
  }
  ```

- 向着色器传值

  ```objective-c
  - (void)addAttribute:(NSString *)attributeName
  {
      // 先判断当前的属性是否已存在
      if (![attributes containsObject:attributeName])
      {
          // 如果不存在先加入属性数组，然后绑定该属性的位置为在属性数组中的位置
          [attributes addObject:attributeName];
          glBindAttribLocation(program, 
                               (GLuint)[attributes indexOfObject:attributeName],
                               [attributeName UTF8String]);
      }
  }
  
  - (GLuint)attributeIndex:(NSString *)attributeName
  {
      // 获取着色器属性变量的位置，即在数组的位置（根据之前的绑定关系）
      return (GLuint)[attributes indexOfObject:attributeName];
  }
  
  - (GLuint)uniformIndex:(NSString *)uniformName
  {
      // 获取Uniform变量的位置
      return glGetUniformLocation(program, [uniformName UTF8String]);
  }
  ```

  

#### `GPUImageContext`

`GPUImageContext`类，提供 OpenGL ES 基本上下文，GPUImage 相关处理线程，GLProgram 缓存、帧缓存。

由于是上下文对象，因此该类提供的更多是存取、设置相关的方法。

- 属性

  ```objective-c
  // GPUImage处理OpenGL绘制的相关队列，串行队列
  @property(readonly, nonatomic) dispatch_queue_t contextQueue;
  // 当前使用的着色器程序
  @property(readwrite, retain, nonatomic) GLProgram *currentShaderProgram;
  // OpenGLES上下文对象
  @property(readonly, retain, nonatomic) EAGLContext *context;
  // CoreVideo中的纹理缓存
  @property(readonly) CVOpenGLESTextureCacheRef coreVideoTextureCache;
  // 帧缓存
  @property(readonly) GPUImageFramebufferCache *framebufferCache;
  ```

- 初始化，`dispatch_queue_set_specific`是为队列设置标识，其主要目的是为了避免死锁的产生

  ```objective-c
  - (id)init;
  {
      if (!(self = [super init]))
      {
          return nil;
      }
      
      // 创建OpenGL渲染队列
      openGLESContextQueueKey = &openGLESContextQueueKey;
      _contextQueue = dispatch_queue_create("com.sunsetlakesoftware.GPUImage.openGLESContextQueue", GPUImageDefaultQueueAttribute());
      
  #if OS_OBJECT_USE_OBJC
      // 设置队列标识
      dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void *)self, NULL);
  #endif
      // 初始化着色器缓存相关数组
      shaderProgramCache = [[NSMutableDictionary alloc] init];
      shaderProgramUsageHistory = [[NSMutableArray alloc] init];
      
      return self;
  }
  ```

- 方法

  ```objective-c
  // 获取队列标识
  + (void *)contextKey;
  // 单例对象
  + (GPUImageContext *)sharedImageProcessingContext;
  // 获取处理队列
  + (dispatch_queue_t)sharedContextQueue;
  // 帧缓存
  + (GPUImageFramebufferCache *)sharedFramebufferCache;
  // 设置当前上下文
  + (void)useImageProcessingContext;
  - (void)useAsCurrentContext;
  // 设置当前的GL程序
  + (void)setActiveShaderProgram:(GLProgram *)shaderProgram;
  - (void)setContextShaderProgram:(GLProgram *)shaderProgram;
  // 获取设备OpenGLES相关特性的支持情况
  + (GLint)maximumTextureSizeForThisDevice;
  + (GLint)maximumTextureUnitsForThisDevice;
  + (GLint)maximumVaryingVectorsForThisDevice;
  + (BOOL)deviceSupportsOpenGLESExtension:(NSString *)extension;
  + (BOOL)deviceSupportsRedTextures;
  + (BOOL)deviceSupportsFramebufferReads;
  // 纹理大小调整，保证纹理不超过OpenGLES支持最大的尺寸
  + (CGSize)sizeThatFitsWithinATextureForSize:(CGSize)inputSize;
  // 将渲染缓存呈现在设备上
  - (void)presentBufferForDisplay;
  // 创建GLProgram，首先在缓存中查找，如果没有则创建
  - (GLProgram *)programForVertexShaderString:(NSString *)vertexShaderString fragmentShaderString:(NSString *)fragmentShaderString;
  // 创建Sharegroup
  - (void)useSharegroup:(EAGLSharegroup *)sharegroup;
  // Manage fast texture upload
  + (BOOL)supportsFastTextureUpload;
  ```

`GPUImageContext`可以理解为一个上下文对象，是管理渲染的状态机。

简单介绍几个方法：

- 调整纹理大小，保证纹理不超过 OpenGL ES 支持最大的尺寸

  ```objective-c
  + (CGSize)sizeThatFitsWithinATextureForSize:(CGSize)inputSize;
  {
      GLint maxTextureSize = [self maximumTextureSizeForThisDevice]; 
      if ( (inputSize.width < maxTextureSize) && (inputSize.height < maxTextureSize) )
      {
          return inputSize;
      }
      
      CGSize adjustedSize;
      if (inputSize.width > inputSize.height)
      {
          adjustedSize.width = (CGFloat)maxTextureSize;
          adjustedSize.height = ((CGFloat)maxTextureSize / inputSize.width) * inputSize.height;
      }
      else
      {
          adjustedSize.height = (CGFloat)maxTextureSize;
          adjustedSize.width = ((CGFloat)maxTextureSize / inputSize.height) * inputSize.width;
      }
  
      return adjustedSize;
  }
  ```

- 获取 OpenGL ES 支持的最大纹理尺寸

  ```objective-c
  + (GLint)maximumTextureSizeForThisDevice;
  {
      static dispatch_once_t pred;
      static GLint maxTextureSize = 0;
      
      dispatch_once(&pred, ^{
          [self useImageProcessingContext];
          glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize);
      });
  
      return maxTextureSize;
  }
  ```

- 创建 `GLProgram`，首先在缓存中查找，如果没有则创建

  ```objective-c
  - (GLProgram *)programForVertexShaderString:(NSString *)vertexShaderString fragmentShaderString:(NSString *)fragmentShaderString;
  {
      NSString *lookupKeyForShaderProgram = [NSString stringWithFormat:@"V: %@ - F: %@", vertexShaderString, fragmentShaderString];
      GLProgram *programFromCache = [shaderProgramCache objectForKey:lookupKeyForShaderProgram];
  
      if (programFromCache == nil)
      {
          programFromCache = [[GLProgram alloc] initWithVertexShaderString:vertexShaderString fragmentShaderString:fragmentShaderString];
          [shaderProgramCache setObject:programFromCache forKey:lookupKeyForShaderProgram];
  //        [shaderProgramUsageHistory addObject:lookupKeyForShaderProgram];
  //        if ([shaderProgramUsageHistory count] >= MAXSHADERPROGRAMSALLOWEDINCACHE)
  //        {
  //            for (NSUInteger currentShaderProgramRemovedFromCache = 0; currentShaderProgramRemovedFromCache < 10; currentShaderProgramRemovedFromCache++)
  //            {
  //                NSString *shaderProgramToRemoveFromCache = [shaderProgramUsageHistory objectAtIndex:0];
  //                [shaderProgramUsageHistory removeObjectAtIndex:0];
  //                [shaderProgramCache removeObjectForKey:shaderProgramToRemoveFromCache];
  //            }
  //        }
      }
      
      return programFromCache;
  }
  ```

#### 总结

`GLProgram`是自定义着色器程序有着非常紧密的关系，其中包括着色器程序的创建、编译、链接、使用等过程。

`GPUImageContext`是 GPUImage 的上下文对象，管理着 OpenGL ES 上下文对象，管理着色器程序，帧缓存等操作。

