---
title: "OpenGLES系列-GLSL小结"
date: 2020-07-28T09:49:46+08:00
draft: false
tags: ["iOS", "OpenGLES"]
url:  "GLSL"
---

#### EGL的主要作用

1. 和本地窗⼝口系统(native windowing system)通讯

2. 查询可⽤用的配置

3. 创建OpenGL ES可⽤用的“绘图表⾯面”(drawing surface)

4. 同步不不同类别的API之间的渲染，⽐比如在OpenGL ES和OpenVG之间同步，或者在

OpenGL和本地窗⼝口的绘图命令之间

5. 管理理“渲染资源”，⽐比如纹理理映射(rendering map)

### GLSL 基础

**OpenGL Shading Language GLSL**作为一种着色语言是纯粹的和GPU打交道的计算机语言。

因为 GPU 是多线程并行处理器，所以 GLSL 直接面向 SIMD 模型的多线程计算。

GLSL 编写的着色器函数是对每一个数据同时执行的。

- 每个顶点都会由顶点着色器中的算法处理

- 每个像素都会由片段着色器中的算法处理

**GLSL 注意**

- 支持函数重载
- 不存在数据类型的自动提升，必须严格保持类型一致
- 不支持指针、字符串、字符，它基本上是一种处理数字数据的语言
- 不支持联合、枚举类型、结构体位字段及按位运算符

**数据类型**

GLSL 有三种基本数据类型：float、int 和 bool，以及由这些数据类型组成的数字和结构体

GLSL 将向量和矩阵作为基本数据类型。

- 向量类型

  ```glsl
  vec2,  vec3,  vec4 // 包含2/3/4个浮点数的矢量
  ivec2, ivec3, ivec4 // 包含2/3/4个整数的矢量
  bvec2, bvec3, bvec4 // 包含2/3/4个布尔值的矢量
    
  // 声明
  vec3 vertex;     // 声明三维浮点型向量
  vertex[1] = 3.0; // 向向量的第二个元素赋值
  
  vec3 v = vec3(0.6);
  vec3 v = vec3(0.6, 0.6, 0.6);
  
  v.y = 2.0;		 // 通过选择运算符赋值
  ```

  > 注意：除了用索引的方式外，还可以用选择运算符的方式来使用向量
  >
  > 选择运算符是对于向量的各个元素（最多为4个）约定俗成的名称，用一个小写拉丁字母来表示

  - 表示顶点可以用`（x, y, z, w）`

  - 表示颜色可以用`（r, g, b, a）`
  - 表示纹理可以用`（s, t, r, q）`

- 矩阵类型

  ```glsl
  // 矩阵是按列顺序组织的，先列后行
  mat2 - 2x2
  mat3 - 3x3
  mat4 - 4x4
    
  // 声明
  mat4 matrix;
  matrix[2][0] = 2.0;
  ```

- 取样器（Sampler）

  纹理查找需要制定哪个纹理或者纹理单元将制定查找

  ```glsl
  sampler1D				// 访问一个一维纹理
  sampler2D  			// 访问一个二维纹理
  sampler3D  			// 访问一个三维纹理
  samplerCube			// 访问一个正方体维纹理
  sampler1DShadow	// 访问一个带对比的一维深度纹理
  sampler2DShadow	// 访问一个带对比的二维深度纹理
    
  // 声明
  uniform sampler2D grass;
  vec4 color = texture2D(grass, vec2(100, 100));
  
  // 一个着色器要在程序里结合多个纹理，可以使用取样器数组
  const int tex_nums = 4;
  uniform sampler2D textures[tex_nums];
  
  for(int i = 0; i < tex_nums; ++i) {
      sampler2D tex = textures[i];
      // todo ...
  }
  ```

- 结构体（这是唯一的用户定义类型）

  ```glsl
  struct light
  {
  	vec3 position;
    vec3 color;
  }
  light default_light;
  ```

- 数组

  数组索引是从 0 开始的，而且没有指针概念

- void - 只能用于声明函数返回值

**限定符**

GLSL 中有 4 个限定符，它们限定了被标记的变量不能被更改的「范围」

- const

  定义不可变常量，表示限定的变量在编译时不可被修改

- attribute： **应用程序传给顶点着色器用**

  不允许声明时初始化

- uniform：**一般是应用程序用于设定顶点着色器和片段着色器相关初始值**

  不允许声明时初始化

- varying：**用于传递顶点着色器的值给片段着色器**

  不允许声明时初始化

**限制**

- 不能再`if-else`中声明变量
- 用于判断的添加必须是 bool 类型
- 三目运算符的后连个参数必须类型相同
- 不支持 switch 语句

**discard 关键字**

discard关键字可以避免片段更新帧缓冲区

**函数**

- 函数名可以通过参数类型重载，但是和返回值类型无关
- 所有参数必须完全匹配，参数不会自动
- 函数不能被递归调用
- 函数返回值不能是数组

```glsl
函数参数标示符

in: 进复制到函数中，但不返回的参数(默认)

out: 不将参数复制到函数中，但返回参数

inout: 复制到函数中并返回
```

**混合操作**

通过在选择器`(.)`后列出各分量名，就可以选择这些分量

```glsl
vec4 v4;
v4.rgba;    // 得到vec4
v4.rgb;     // 得到vec3
v4.b;       // 得到float
v4.xy;      // 得到vec2

v4.xgba;    // 错误！分量名不是同一类
v4.wxyz;    // 打乱原有分量顺序
v4.xxyy;    // 重复分量
```
#### GLSL 完整示例

**顶点着色器**

- 4 分量的顶点坐标数据

- 2 分量的纹理坐标数据

gl_Position是顶点着色器的输出结果，即顶点坐标

注意：attribute 限定的变量，无法直接传递到片段着色器，只能通过顶点着色器进行桥接传递

```glsl
attribute vec4 position;
attribute vec2 textCoord;

varying lowp vec2 varyTextCoord;

void main(){
  varyTextCoord = textCoord;

  gl_Position = position;
}
```

**片段着色器**

- 2D纹理采样器

gl_FragColor是片段着色器的输出结果

通过 varying 限定符，将纹理坐标传入片段着色器，再通过 texture2D 函数去获取每一个像素点的颜色

```glsl
precision highp float;

varying lowp vec2 varyTextCoord;

uniform sampler2D colorMap;

void main(){
  gl_FragColor = texture2D(colorMap, varyTextCoord);
}
```

这里是一些基础语法，如果感兴趣，想要了解可以阅读这两篇文章：[GLSL详解(基础篇)](http://colin1994.github.io/2017/11/11/OpenGLES-Lesson04/) 、[GLSL详解(高级篇)](http://colin1994.github.io/2017/11/12/OpenGLES-Lesson05/#11-_%E8%87%AA%E6%B5%8B)

> **Visual Studio Code配置 glsl 语法提示**
>
> 1. 安装插件：[Shader languages support for VS Code](https://marketplace.visualstudio.com/items?itemName=slevesque.shader)
> 2. 设置 Code -> Preferences -> User snippets，搜索 glsl
> 3. 将该[链接](https://gist.github.com/lewislepton)中的 `glsl.json`复制过去，保存即可
> 4. 返回 shader 文件，已经有相应提示了

### shader 编译

> C语言编译流程：预编译、编译、汇编、链接

glsl 的编译过程类似 C语言。

**预编译**

以`#`开头的是预编译指令，通常有：

```glsl
#define #undef #if #ifdef #ifndef #else
#elif #endif #error #pragma #extension #version #line
```

比如 **#version 100** 他的意思是规定当前shader使用 GLSL ES 1.00标准进行编译，如果使用这条预编译指令，则他必须出现在程序的最开始位置。

除预编译指令外，还有内置的宏等

**创建 GLSL 着色器程序**

核心函数：`glCreateProgram`，

**编译着色器对象**

1. 创建着色器对象，并获得对象引用：`glCreateShader`
2. 为着色器对象注入 GLSL 源代码：`glShaderSource`
3. 编译着色器对象：`glCompileShader`
4. 挂载着色器对象：`glAttachShader`
5. 删除着色器对象：`glDeleteShader`，当着色器不再使用时，可以删除，减少内存开销

**链接 GLSL 着色器程序**

核心函数：`glLinkProgram`

**使用 GLSL 着色器程序**

核心函数：`glUseProgram`

#### 完整流程

```objective-c
- (GLuint)loadShaders:(NSString *)vertex frag:(NSString *)frag {
  
    GLuint verShader, fragShader;
    // 创建 GLSL 程序
  	GLuint program = glCreateProgram();
    
    [self compileShader:&verShader type:GL_VERTEX_SHADER file:vertex];
    [self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:frag];
    
  	// 挂载着色器对象 
    glAttachShader(program, verShader);
    glAttachShader(program, fragShader);
    
    // 删除着色器对象
    glDeleteShader(verShader);
    glDeleteShader(fragShader);
    
    // 链接
    glLinkProgram(self.myProgram);
    GLint linkRes;
  	// 获取链接的结果
    glGetProgramiv(self.myProgram, GL_LINK_STATUS, &linkRes);
    if (linkRes == GL_FALSE) {
      	// 当链接失败时，打印错误信息
        GLchar message[512];
        glGetProgramInfoLog(self.myProgram, sizeof(message), 0, &message[0]);
        NSString *messageInfo = [NSString stringWithUTF8String:message];
        NSLog(@"link error: %@", messageInfo);
        return;
    }else {
      	// 链接成功，使用 GLSL 着色器程序
        NSLog(@"link successed");
        glUseProgram(self.myProgram);
    }
    return program;
}

- (void)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file {
  	// 文件路径 - NSString 转 C 字符串
    NSString * filePath  = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    const GLchar *source = (GLchar *)[filePath UTF8String];
    
    // 创建着色器对象
    *shader = glCreateShader(type);
  	// 注入 GLSL 源代码
    glShaderSource(*shader, 1, &source, NULL);
  	// 编译着色器对象
    glCompileShader(*shader);
}
```

