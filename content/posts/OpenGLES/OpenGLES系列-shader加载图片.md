---
title: "OpenGLES系列-Shader加载图片"
date: 2020-07-30T10:52:27+08:00
draft: false
tags: ["iOS", "OpenGLES"]
url:  "shader-image"
---

> Shader 着色器是通过 GLSL 编写，关于 GLSL 的基本概念可以参考『[GLSL小节](/glsl/)』



#### 着色器准备阶段

**顶点着色器：接收顶点坐标数据**

```glsl
attribute vec4 position;
attribute vec2 textCoord;

varying lowp vec2 varyTextCoord;

void main(){
  varyTextCoord = textCoord;

  gl_Position = position;
}
```

**片段着色器：接收纹理坐标数据**

```glsl
#ifdef GL_ES 
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#endif

varying lowp vec2 varyTextCoord;

uniform sampler2D colorMap;

void main(){
  gl_FragColor = texture2D(colorMap, varyTextCoord);
}

```

**编译、链接着色器**

1. 创建着色器程序
2. 创建着色器对象，并获得对象引用
3. 为着色器对象注入 GLSL 源代码
4. 编译着色器对象
5. 挂载着色器对象，删除着色器对象
6. 链接着色器程序
7. 使用着色器程序

```objective-c
#pragma mark - 编译、链接、使用 shader
- (GLuint)loadShaders:(NSString *)vertex frag:(NSString *)frag {
    GLuint verShader, fragShader;
    GLuint program = glCreateProgram();
    
    [self compileShader:&verShader type:GL_VERTEX_SHADER file:vertex];
    [self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:frag];
    
    glAttachShader(program, verShader);
    glAttachShader(program, fragShader);
    
    glDeleteShader(verShader);
    glDeleteShader(fragShader);
    
    return program;
}

- (BOOL)validate:(GLuint)programId {
    GLint logLength, status;
    
    glValidateProgram(programId);
    glGetProgramiv(programId, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(programId, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(programId, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    return YES;
}

- (void)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file {
    NSString * filePath  = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    const GLchar *source = (GLchar *)[filePath UTF8String];
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
}

- (void)linkProgrm(GLuint)programId {
    // 链接
    glLinkProgram(programId);
    GLint linkRes;
    glGetProgramiv(programId, GL_LINK_STATUS, &linkRes);
    if (linkRes == GL_FALSE) {
        GLchar message[512];
        glGetProgramInfoLog(programId, sizeof(message), 0, &message[0]);
        NSString *messageInfo = [NSString stringWithUTF8String:message];
        NSLog(@"link error: %@", messageInfo);
        return;
    }else {
        NSLog(@"link successed");
        glUseProgram(programId);
    }
}
```

#### 初始化配置

**设置 Layer**

 将自定义 View 的`layer`设置为`CAEAGLLayer`，并设置 layer 的绘制选项

> `CAEAGLLayer`主要是用于显示 Open ES 绘制内容的载体

```objective-c
- (void)setupLayer {
    
    self.mEAGLLayer = (CAEAGLLayer *)self.layer;
    
    self.mEAGLLayer.contentsScale = [UIScreen mainScreen].scale;
    
    self.mEAGLLayer.opaque = true;
    
    self.mEAGLLayer.drawableProperties = @{
        kEAGLDrawablePropertyRetainedBacking:@false,
        kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
    };
}
```

**设置 OpenGL ES 上下文**

创建`EAGLContext`对象，并设置为当前上下文

```objective-c
- (void)setupContext {
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!context) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }
    
    if (![EAGLContext setCurrentContext:context]) {
        NSLog(@"Failed to set current OpenGL context");
        exit(1);
    }
    self.mContext = context;
}
```

**清理RenderBuffer、FrameBuffer**

清除缓冲区是为了清除残留数据，防止残留数据对本次操作造成影响。类似初始化时赋初值：`let i = 0`

```objective-c
- (void)deleteRenderAndFrameBuffer {
    glDeleteRenderbuffers(1, &_myColorRenderBuffer);
    self.myColorRenderBuffer = 0;
    
    glDeleteFramebuffers(1, &_myColorFrameBuffer);
    self.myColorFrameBuffer = 0;
}
```

**申请RenderBuffer**

`RenderBuffer`是一个通过应用分配的**2D**图像缓冲区，需要附着在`FrameBuffer`上

```objective-c
- (void)setupRenderBuffer {
    GLuint buffer;
    glGenRenderbuffers(1, &buffer);
    self.myColorRenderBuffer = buffer;
    
    glBindRenderbuffer(GL_RENDERBUFFER, self.myColorRenderBuffer);
    // 为 颜色缓冲区 分配存储空间
    [self.mContext renderbufferStorage:GL_RENDERBUFFER
                          fromDrawable:self.mEAGLLayer];
}
```

**申请FrameBuffer**

是一个收集颜色、深度和模板缓存区的附着点，简称`FBO`，即是一个`管理者`，用来管理`RenderBuffer`，且`FrameBuffer`没有实际的存储功能，真正实现存储的是`RenderBuffer`

```objective-c
- (void)setupFrameBuffer {
    GLuint buffer;
    glGenFramebuffers(1, &buffer);
    self.myColorFrameBuffer = buffer;
    
    // 设置为当前 framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, self.myColorFrameBuffer);
    // 将 _colorRenderBuffer 装配到 GL_COLOR_ATTACHMENT0 这个装配点上
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, self.myColorRenderBuffer);
}

```

FrameBuffer 和 RenderBuffer 关系图

- FrameBuffer有3个附着点
  - 颜色附着点（Color Attachment）：管理纹理、颜色缓冲区
  - 深度附着点（depth Attachment）：会影响颜色缓冲区，管理深度缓冲区（Depth Buffer）
  - 模板附着点（Stencil Attachment）：管理模板缓冲区（Stencil Buffer）
- RenderBuffer有3种缓存区
  - 深度缓存区（Depth Buffer）：存储深度值等
  - 纹理缓存区：存储纹理坐标中对应的纹素、颜色值等
  - 模板缓存区（Stencil Buffer）：存储模板

![image-20200801211457662](https://w-md.imzsy.design/image-20200801211457662.png)

#### 渲染阶段

- 加载顶点数据及申请顶点缓冲

```objective-c
    GLfloat attrArr[] =
    {
        0.5f, -0.5f, -1.0f,     1.0f, 0.0f,
        -0.5f, 0.5f, -1.0f,     0.0f, 1.0f,
        -0.5f, -0.5f, -1.0f,    0.0f, 0.0f,
        
        0.5f, 0.5f, -1.0f,      1.0f, 1.0f,
        -0.5f, 0.5f, -1.0f,     0.0f, 1.0f,
        0.5f, -0.5f, -1.0f,     1.0f, 0.0f,
    };
    
    // 申请顶点缓冲
    GLuint attrBuffer;
    glGenBuffers(1, &attrBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, attrBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(attrArr), attrArr, GL_DYNAMIC_DRAW);
```

- 将顶点坐标和将纹理坐标数据传入 GLSL 中的声明的变量

```objective-c
    // 开启顶点坐标
    GLuint position = glGetAttribLocation(self.myProgram, "position");
    glVertexAttribPointer(position, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, NULL);
    glEnableVertexAttribArray(position);
    
    // 开启纹理
    GLuint textCoord = glGetAttribLocation(self.myProgram, "textCoord");
    glVertexAttribPointer(textCoord, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, (float *)NULL + 3);
    glEnableVertexAttribArray(textCoord);
```

#### 加载纹理

图片的解压缩在 iOS 中，通过使用 `CoreGraphic`。

整个纹理加载流程：

1. 图片解压缩：获取`UIImage`对象的 `CGImageRef`

2. 图片重绘：创建`CGContextRef`上下文，并调用其`CGContextDrawImage`函数进行绘制

3. 绑定纹理：使用 `GLBindTexture`函数绑定

   > 当只有一个纹理的时候，默认的纹理 ID 是 0，且纹理 ID 为 0是一直处于激活状态，因此可以省略 glGenTexture的

4. 设置纹理属性：通过`glTexParameteri`函数分别设置 `放大/缩小的过滤方式` 和 `S/T的环绕模式`

5. 载入纹理：通过`glTexImage2D`函数载入纹理，载入完成后，释放指向纹理数据的指针

```objective-c
- (GLuint)loadTexture:(NSString *)imageName {
    CGImageRef imageRef = [UIImage imageNamed:imageName].CGImage;
    if (!imageRef) {
        NSLog(@"Failed to load image");
        exit(1);
    }
    
    size_t width  = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    
    CGColorSpaceRef  colorSpace;
    void *           bitmapData;
    unsigned long    bitmapByteCount;
    unsigned long    bitmapBytesPerRow;
    
    bitmapBytesPerRow   = (width * 4);// 1
    bitmapByteCount     = (bitmapBytesPerRow * height);
    
    // CGImageGetColorSpace(imageRef);// 2
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    bitmapData = calloc( bitmapByteCount, sizeof(uint8_t) );// 3
    if (bitmapData == NULL)
    {
        fprintf (stderr, "Memory not allocated!");
        exit(1);
    }
    
    // 创建上下文
    CGContextRef contextRef = CGBitmapContextCreate(bitmapData, width, height, 8, bitmapBytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
    if (contextRef == NULL) {
        free(bitmapData);
        NSLog(@"Context not created!");
        exit(1);
    }
    // 绘图
    CGContextDrawImage(contextRef, CGRectMake(0, 0, width, height), imageRef);
    
    // 图片翻转
    CGContextTranslateCTM(contextRef, width, height);
    CGContextRotateCTM(contextRef, -M_PI);
  
  	// CGContextTranslateCTM(spriteContext, 0, height);//向x,平移0,向y平移height
    // CGContextScaleCTM(spriteContext, 1.0, -1.0); //x,缩放1.0，y,缩放-1.0
    CGContextDrawImage(contextRef, CGRectMake(0, 0, width, height), imageRef);
    
    // 释放上下文
    CGContextRelease(contextRef);
    
    // 读取纹理
    glBindTexture(GL_TEXTURE_2D, 0);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    float fw = width, fh = height;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, fw, fh, 0, GL_RGBA, GL_UNSIGNED_BYTE, bitmapData);
    glBindBuffer(GL_TEXTURE_2D, 0);
    
    free(bitmapData);
    return 0;
}

```

在加载完纹理后，需要将纹理传到片段着色器的采样器中

`glUniform1i(glGetUniformLocation(self.myProgram, "colorMap"), 0);`

##### 纹理坐标

**OpenGL ES**

![image-20200805180039060](https://w-md.imzsy.design/image-20200805180039060.png)

**iOS**

![image-20200805180104407](https://w-md.imzsy.design/image-20200805180104407.png)

**图片翻转处理**

![image-20200803113954183](https://w-md.imzsy.design/image-20200803113954183.png)

2. 通过 CGContext 将图片源文件进行翻转（推荐）

   > Quartz 2D 相关内容，请查阅[官方文档](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/Introduction/Introduction.html#//apple_ref/doc/uid/TP40007533-SW1)

   ```objective-c
       CGContextTranslateCTM(contextRef, width, height);
       CGContextRotateCTM(contextRef, -M_PI);
   ```

   

3. 旋转矩阵翻转图片

   ```objective-c
       GLuint rotate = glGetUniformLocation(self.myPrograme, "rotateMatrix");
       float radians = 180 * 3.14159f / 180.0f;
       float s = sin(radians);
       float c = cos(radians);
       
     
       GLfloat zRotation[16] = {
           c, -s, 0, 0,
           s, c, 0, 0,
           0, 0, 1.0, 0,
           0.0, 0, 0, 1.0
       };
       
      glUniformMatrix4fv(rotate, 1, GL_FALSE, (GLfloat *)&zRotation[0]);
   ```

   

4. 修改片元着色器，纹理坐标

   ```glsl
   varying lowp vec2 varyTextCoord;
   uniform sampler2D colorMap;
   void main()
   {
       gl_FragColor = texture2D(colorMap, vec2(varyTextCoord.x,1.0-varyTextCoord.y));
   }
   
   ```

   

5. 修改顶点着色器，纹理坐标

   ```glsl
   attribute vec4 position;
   attribute vec2 textCoordinate;
   varying lowp vec2 varyTextCoord;
   
   void main()
   {
       varyTextCoord = vec2(textCoordinate.x,1.0-textCoordinate.y);
       gl_Position = position;
   }
   
   ```

   

6. 修改源纹理坐标数据，使纹理映射与顶点对应

#### 绘制

- 调用`glDrawArrays`指定图元连接方式、顶点个数
- 将绘制好的图片渲染到屏幕上进行显示

```objective-c
    glDrawArrays(GL_TRIANGLES, 0, 6);
		// 从渲染缓存区显示到屏幕上
    [self.mContext presentRenderbuffer:GL_RENDERBUFFER];
```

[完整 Demo](https://github.com/dev-jw/Learning-OpenGL-ES)

