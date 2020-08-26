---
title: "Metal系列-Metal Shader Language"
date: 2020-08-22T14:50:17+08:00
draft: false
tags: ["Metal", "iOS"]
url:  "Metal-3"
---

本文会简单梳理**Metal着色语言**的特性，从而更好地了解与使用。

#### 简述

Metal Shader Language的使用场景有两个：**图形渲染、通用技术**

- Metal 着色语言是用来编写 **3D 图形渲染逻辑**、**并行Metal计算核心逻辑**的一门编程语言，当你使用Metal框架来完成 App 的实现时，则需要使用 Metal 着色语言
- Metal 语言使用 **Clang** 和 **LLVM** 进行编译处理，编译器对于 GPU 上的代码执行效率有更好的控制
- Metal 基于 `C++11.0` 语言设计的，在 C++基础上多了一些扩展和限制
- Metal 像素坐标系统：Metal 中**纹理或者帧缓冲 attachment** 的像素使用的坐标系统原点是在**左上角**

#### 限制

Metal 中不支持 `C++11.0` 的如下特性：

- Lambda 表达式
- 递归函数调用
- 动态转换操作符
- 类型识别
- 对象创建 new 和销毁 delete 操作符
- 操作符 noexcept
- go 跳转
- 变量存储修饰符 register 和 thread_local
- 虚函数修饰符
- 派生类
- 异常处理

> C++标准库在 Metal 着色语言中也是不可使用的

Metal 着色语言对指针使用的限制：

- Metal 图形和并行计算函数用到的入参（比如**指针/引用**），如果是**指针/引用**必须使用地址空间修饰符（`device`/`threadgroup`/`constant`）
- 不支持函数指针
- 函数名不能出现 main

#### 基本数据类型

**标量**

Metal 中的标量类型，如下表

| 类型                  | 描述                                                         |
| --------------------- | ------------------------------------------------------------ |
| bool                  | 布尔类型，取值范围 true、false;true 可拓展为整数常量 1，false 为 0 |
| char                  | 有符号 8-bit 整数                                            |
| unsigned char uchar   | 无符号 8-bit 整数                                            |
| short                 | 有符号 16-bit 整数                                           |
| unsigned short ushort | 无符号 16-bit 整数                                           |
| int                   | 有符号 32-bit 整数                                           |
| unsigned int uint     | 无符号 32-bit 整数                                           |
| half                  | 16-bit 浮点数                                                |
| float                 | 32-bit 浮点数                                                |
| size-t                | 64-bit 无符号整数，表示 sizeof 操作符的结果                  |
| ptrdiff_t             | 64-bit 有符号整数，表示 2 个指针的差                         |
| void                  | 空值集合                                                     |

- 常用的主要有 bool、int、uint、half
- undigned char可以简写为 uchar
- unsigned short 可以简写为 ushort
- unsigned int 可以简写为 uint
- `half` 相当于OC中的`float`，`float` 相当于OC中的`double`
- `size_t`用来表示内存空间， 相当于 OC中 `sizeof`

```c++
bool a = true;
char b = 5;
int  d = 15;
//用于表示内存空间
size_t c = 1;
ptrdiff_t f = 2;
```

> **字节对齐**
>
> char3、uchar3 的 size 是 4 Bytes，而不是 3 Bytes
>
> 类似的，int是 4  Bytes, 但 int3是 16 Bytes 而不是 12 Bytes
>
> **隐式类型转换**
>
> 向量到向量或是标量的隐式转换会导致编译错误，
>
> 比如`int4 i; float4 f = i; // compile error`，
>
> 无法将一个4维的整形向量转换为4维的浮点向量。
>
> 标量到向量的隐式转换，是标量被赋值给向量的每一个分量，
>
> `float4 f = 2.0f; // f = (2.0f, 2.0f, 2.0f, 2.0f)`
>
> 标量到矩阵、向量到矩阵的隐式转换，矩阵到矩阵和向量及标量的隐式转换会导致编译错误。

**向量**

Metal中用`类型`加`n`来表示一个 n 维向量，其中 n 表示向量的维度，最多不超过4维向量

`booln、charn、shortn、intn、ucharn、ushortn、uintn、halfn、floatn`

```c++
//直接赋值初始化
bool2 A= {1,2};
//通过内建函数float4初始化
float4 pos = float4(1.0,2.0,3.0,4.0);

//通过下标从向量中获取某个值
float x = pos[0];
float y = pos[1];

//通过for循环对一个向量进行运算
float4 VB;
for(int i = 0; i < 4 ; i++)
{
    VB[i] = pos[i] * 2.0f;
}
```

> 在 OpenGL ES 的 GLSL 语言中，例如 `2.0f`，在着色器是不能被识别到的，必须是`2.0`，
>
> 而在 Metal 中则可以保留，其中 `f` 可以是大写，也可以是小写

Metal 中向量的选择器访问和 OpenGL ES 类似，但多了一些特性

- 通过向量字母获取，`xyzw`、`rgba`这 2 种组合选择器不能同时使用

  ```c++
  int4 test = int4(0,1,2,3);
  int a = test.x; //获取的向量元素0
  int b = test.y; //获取的向量元素1
  int c = test.z; //获取的向量元素2
  int d = test.w; //获取的向量元素3
  
  int e = test.r; //获取的向量元素0
  int f = test.g; //获取的向量元素1
  int g = test.b; //获取的向量元素2
  int h = test.a; //获取的向量元素3
  ```

- 多个分量同时访问

  ```c++
  float4 c;
  c.xyzw = float4(1.0f,2.0f,3.0f,4.0f);
  c.z = 1.0f;
  c.xy = float2(3.0f,4.0f);
  c.xyz = float3(3.0f,4.0f,5.0f);
  ```

- 多分量访问可以乱序、重复

  - 赋值时，分量不可重复

  ```c++
  float4 pos = float4(1.0f,2.0f,3.0f,4.0f);
  //向量分量逆序访问
  float4 swiz = pos.wxyz;  //swiz = (4.0,1.0,2.0,3.0);
  //向量分量重复访问
  float4 dup = pos.xxyy;  //dup = (1.0f,1.0f,2.0f,2.0f);
  
  //可以仅对 xw / wx 修改
  //pos = (5.0f,2.0,3.0,6.0)
  pos.xw = float2(5.0f,6.0f);
  
  //pos = (8.0f,2.0f,3.0f,7.0f)
  pos.wx = float2(7.0f,8.0f);
  
  //可以仅对 xyz 进行修改
  //pos = (3.0f,5.0f,9.0f,7.0f);
  pos.xyz = float3(3.0f,5.0f,9.0f);
  
  float2 pos;
  pos.x = 1.0f; //合法
  pos.z = 1.0f; //非法，pos是二维向量，没有z这个索引
  
  float3 pos2;
  pos2.z = 1.0f; //合法
  pos2.w = 1.0f; //非法
  
  // 赋值 时 分量不可重复，取值 时 分量可重复
  //非法,x出现2次
  pos.xx = float2(3.0,4.0f);
  pos.xy = swiz.xx;
  
  //向量中xyzw与rgba两组分量不能混合使用
  float4 pos4 = float4(1.0f,2.0f,3.0f,4.0f);
  pos4.x = 1.0f;
  pos4.y = 2.0f;
  //非法,.rgba与.xyzw 混合使用
  pos4.xg = float2(2.0f,3.0f);
  ////非法,.rgba与.xyzw 混合使用
  float3 coord = pos4.ryz;
  ```

**矩阵**

Metal中用`类型half/float`加`nxm`来表示一个`n行m列`的矩阵，最多 4 行 4 列

```c++
float4x4 m;
//将第二行的所有值都设置为2.0
m[1] = float4(2.0f);

//设置第一行/第一列为1.0f
m[0][0] = 1.0f;

//设置第三行第四列的元素为3.0f
m[2][3] = 3.0f;
```

`float4` 类型向量构造方式

```c++
//1个一维向量，表示一行都是x
float4(float x);/
//4个一维向量 --> 4维向量
float4(float x,float y,float z,float w);
//2个二维向量 --> 4维向量
float4(float2 a,float2 b);
//1个二维向量+2个一维向量 --> 4维向量
float4(float2 a,float b,float c);
float4(float a,float2 b,float c);
float4(float a,float b,float2 c);
//1个三维向量+1个一维向量 --> 4维向量
float4(float3 a,float b);
float4(float a,float3 b);
//1个四维向量 --> 4维向量
float4(float4 x);
```

`float3` 类型向量构造方式

```c++
//1个一维向量
float3(float x);
//3个一维向量
float3(float x,float y,float z);
//1个一维向量 + 1个二维向量
float3(float a,float2 b);
//1个二维向量 + 1个一维向量
float3(float2 a,float b);
//1个三维向量
float3(float3 x);
```

`float2` 类型向量构造方式

```c++
//1个一维向量
float2(float x);
//2个一维向量
float2(float x,float y);
//1个二维向量
float2(float2 x);
```

#### 纹理、采样器

**纹理类型**

纹理类型是一个句柄，指向一维/二维/三维纹理数据，而纹理数据对应一个纹理的某个 level 的 mipmap 的全部或者一部分

**access描述符**

描述纹理如何被访问，分别为：

- `smaple`，纹理对象可以被采样（`可读可写可采样`），默认的 access描述符就是 sample
- `read`，不使用采样器，只可以读取纹理对象（`只读`）
- `write`，表示可以向纹理对象写入数据（`可读可写`）

**定义纹理对象**

纹理对象 = 类型 + 变量名 + 修饰符，

`texture2d<half, access::read>  sourceTexture  [[texture(0)]]`

- `texture2d<half, access::read>`表示纹理类型为只读的二维half
- `sourceTexture`变量名
- `[[texture(0)]]`对应纹理0

```css
kernel void
sobelKernel(texture2d<half, access::read>  sourceTexture  [[texture(0)]])
```

**采样器**

Sampler是采样器，决定如何对一个纹理对象进行采样操作

![img](https://w-md.imzsy.design/2251862-eb3e325c95cd480d.png)

在 Metal 中，初始化的采样器必须使用 `constexpr` 修饰声明

> 采样器指针和引用是不支持的，会编译出错

```c++
/*
constexpr：修饰符（必须写）
sampler：类型
s：采样器变量名称
参数
    - coord: 是否需要归一化，不需要归一化，用的是像素pixel
    - address: 地址环绕方式
    - filter: 过滤方式
*/
constexpr sampler s(coord::pixel, address::clamp_to_zero, filter::linear);

constexpr sampler a(coord::normalized);

constexpr sampler b(address::repeat);
```

#### 函数类型

在 Metal 中有三个基本函数：

- 顶点函数(`vertex`)，对每一个顶点进行处理，生成数据并输出到绘制管线
- 片段函数(`fragment`)，对光栅化后的每个像素点进行处理，生成数据并输出到绘制管线
- 通用计算函数(`kernel`)，并行计算的函数，其返回值类型必须为 `void`

顶点函数相关的修饰符：

- `[[vertex_id]]`，vertex_id是顶点shader每次处理的index，用于定位当前的顶点
- `[[instance_id]]`，instance_id是单个实例多次渲染时，用于表明当前索引；
- `[[clip_distance]]`，float 或者 float[n]， n必须是编译时常量；
- `[[point_size]]`，float；
- `[[position]]`，float4；

> 如果一个顶点函数的返回值不是void，那么返回值必须包含顶点位置；
>
> 如果返回值是float4，默认表示位置，可以不带[[ position ]]修饰符；
>
> 如果一个顶点函数的返回值是结构体，那么结构体必须包含“[[ position ]]”修饰的变量。

片段函数相关的修饰符：

- `[[color(m)]]`，float或half等，m必须是编译时常量，表示输入值从一个颜色attachment中读取，m用于指定从哪个颜色attachment中读取；
- `[[front_facing]]`，bool，如果像素所属片段是正面则为true；
- `[[point_coord]]`，float2，表示点图元的位置，取值范围是0.0到1.0；
- `[[position]]`，float4，表示像素对应的窗口相对坐标(x, y, z, 1/w)；
- `[[sample_id]]`，uint，表示正在处理的采样对象的 index.
- `[[sample_mask]]`，uint，The set of samples covered by the primitive generating the fragmentduring multisample rasterization.

> 以上都是输入相关的描述符。**片段函数的返回值是单个像素的输出，包括一个或是多个渲染结果颜色值，一个深度值，还有一个sample遮罩**，对应的输出描述符是
>
> [[color(m)]] floatn、[[depth(depth_qualifier)]] float、[[sample_mask]] uint

```C++
struct FragmFntOutput {
    // color attachment 0
    float4 color_float [[color(0)]];// color attachment 1
    int4 color_int4 [[color(1)]];// color attachment 2
    uint4 color_uint4 [[color(2)]];};
fragment FragmFntOutput fragment_shader( ... ) { ... };
```

需要注意，颜色attachment的参数设置要和片段函数的输入和输出的数据类型匹配。

> Metal支持一个功能，叫做前置深度测试（early depth testing），允许在像素着色器运行之前运行深度测试。如果一个像素被覆盖，则会放弃渲染。使用方式是在fragment关键字前面加上[[early_fragment_tests]]：
> `[[early_fragment_tests]] fragment float4 samplingShader(..)`
> 使用前置深度测试的要求是不能在fragment shader对深度进行写操作。

#### 变量、参数的地址空间修饰符

Metal中使用**地址空间修饰符**表示一个函数变量或参数变量被分配于哪一片内存区域

- `device`：设备地址空间

  设备地址空间指向`设备内存池分配出来的缓存对象`（设备指显存，即GPU），即GPU空间分配的缓存对象，它是`可读可写`的，一个缓存对象可以被声明成一个`标量、向量或是用户自定义结构体`的`指针/引用`

  除了可以修饰 `图形着色器函数 / 并行计算函数`参数，还可以修饰指针变量 和 结构体指针变量

  ```c++
  // 设备地址空间: device 用来修饰指针.引用
  //1.修饰指针变量
  device float4 *color;
  
  struct Struct{
      float a[3];
      int b[2];
  };
  //2.修饰结构体类的指针变量
  device Struct *my_Struct;
  ```

  > 1、纹理对象总是在`设备地址空间分配内存`，即纹理对象默认在GPU分配内存
  > 2、device地址空间修饰符`不必出现`在纹理类型定义中
  > 3、一个纹理对象的内容`无法直接访问`，Metal提供读写纹理的内建函数，通过`内建函数访问`纹理对象

- `constant`：常量地址空间

  - 常量地址空间指向的缓存对象也是从设备内存池分配存储，`仅可读`

  - 在程序域的变量必须定义在常量地址空间并且声明时初始化，用来初始化的值必须是编译时的常量
  - 在程序域的变量的生命周期和程序一样，在程序中的`并行计算着色函数` 或者 `图形绘制着色函数`调用，但是constant的值会保持不变

  > 常量地址空间的指针/引用可以作为函数的参数，向声明为`常量`的变量`赋值会产生编译错误`
  >
  > 声明常量但是`没有赋予初值`也会产生`编译错误`

  ```c++
  constant float samples[] = { 1.0f, 2.0f, 3.0f, 4.0f };
  
  //对一个常量地址空间的变量进行修改也会失败,因为它只读的
  sampler[4] = {3,3,3,3}; //编译失败; 
  
  //定义为常量地址空间声明时不赋初值也会编译失败
  constant float a;
  ```

- `threadgroup`：线程组地址空间

  - 线程组地址空间用于为`并行计算着色器函数`分配内存变量，这些变量被一个`线程组的所有线程共享`，在线程组地址空间分配的变量不能用于图形绘制着色函数（即顶点着色函数 / 片元着色函数），即`在图形绘制着色函数中不能使用线程组`
  - 在并行计算着色函数中，在线程组地址空间分配的变量为一个线程组使用，生命周期和线程组相同

  ```c++
  /*
   1. threadgroup 被并行计算计算分配内存变量, 这些变量被一个线程组的所有线程共享. 在线程组分配变量不能被用于图像绘制.
   2. thread 指向每个线程准备的地址空间. 在其他线程是不可见切不可用的
   */
  kernel void TestFouncitionF(threadgroup float *a)
  {
      //在线程组地址空间分配一个浮点类型变量x
      threadgroup float x;
      
      //在线程组地址空间分配一个10个浮点类型数的数组y;
      threadgroup float y[10];
      
  }
  ```

  

- `thread`：线程地址空间

  - 线程地址空间指向每个线程准备的地址空间，也是在GPU中，该线程的地址空间定义的变量`在其他线程不可见`（即变量不共享）
  - 在图形绘制着色函数 或者 并行计算着色函数中声明的变量，`在线程地址空间分配存储`

  ```c++
  kernel void TestFouncitionG(void)
  {
      //在线程空间分配空间给x,p
      float x;
      thread float p = &x;
  }
  ```

> 1、所有的着色函数（vertex、fragment、kernel）的参数，如果是指针/引用，都`必须带有地址空间修饰符号`
> 2、对于`图形着色器函数`（即vertex/fragment修饰的函数），其`指针/引用类型`的参数必须定义为 `device、constant`地址空间
> 3、对于`并行计算函数`（即kernel修饰的函数），其`指针/引用类型`的参数必须定义为 `device、threadgroup、constant`
> 4、并不是所有的变量都需要修饰符，也可以定义普通变量（即无修饰符的变量）

####  属性修饰符

图形绘制 或者 并行计算着色器函数的输入输出都是通过参数传递，除了常量地址空间变量和程序域定义的采样器之外, 其他参数修饰的可以是如下之一，有以下5种属性修饰符：

- `device buffer` 设备缓存：一个指向设备地址空间的任意数据类型的指针/引用
- `constant buffer` 常量缓存：一个指向常量地址空间的任意数据类型的指针/引用
- `texture` 纹理对象
- `sampler` 采样器对象
- `threadGroup` 在线程组中供线程共享的缓存

**为什么需要属性修饰符？**

- 参数表示资源的定位，可以理解为端口，相当于OpenGl ES中的`location`
- 在固定管线和可编程管线进行内建变量的传递
- 将数据沿着渲染管线从顶点函数传递到片元函数

**传递修饰符在代码中的体现**
对于每个着色函数来说，一个修饰符是必须指定的，它用来设置一个缓存、纹理、采样器的位置，传递修饰符对应的写法如下：

- `device buffer` ---> `[[buffer(index)]]`
- `constant buffer` ---> `[[buffer(index)]]`
- `texture` ---> `[[texture(index)]]`
- `sampler` ---> `[[sampler(index)]]`
- `threadGroup` ---> `[[threadGroup(index)]]`

在代码中的表现如下：

```ruby
在代码中如何表现:
 1.已知条件:device buffer(设备缓存)/constant buffer(常量缓存)
 代码表现:[[buffer(index)]]
 解读:不变的buffer ,index 可以由开发者来指定.
 
 2.已知条件:texture Object(纹理对象)
 代码表现: [[texture(index)]]
 解读:不变的texture ,index 可以由开发者来指定.
 
 3.已知条件:sampler Object(采样器对象)
 代码表示: [[sampler(index)]]
 解读:不变的sampler ,index 可以由开发者来指定.
 
 4.已知条件:threadgroup Object(线程组对象)
 代码表示: [[threadgroup(index)]]
 解读:不变的threadgroup ,index 可以由开发者来指定.
```

> 1、index是一个unsigned interger类型的值，表示了一个`缓存、纹理、采样器参数的位置`（即在函数参数索引表中的位置，相当于OpenGl ES中的`location`）
> 2、从语法上来说，属性修饰符的声明位置应该`位于参数变量名之后`

```C++
//并行计算着色器函数add_vectros ,实现2个设备地址空间中的缓存A与缓存B相加.然后将结果写入到缓存out.
//属性修饰符"(buffer(index))" 为着色函数参数设定了缓存的位置
//thread_position_in_grid：用于表示当前节点在多线程网格中的位置,并不需要开发者传递，是Metal自带的。
/*
 kernel：并行计算函数修饰符
 void：函数返回值类型
 add_vectros：函数名
 const device float4 *inA [[buffer(0)]]：定义了一个float4类型的指针，指向一个4维向量空间，放在设备内存空间（即显存GPU中）
    - const device：只决定放在哪里
    - inA：变量名
    - [[buffer(0)]] 对应 buffer中0这个id
 */
kernel void add_vectros(
                const device float4 *inA [[buffer(0)]],
                const device float4 *inB [[buffer(1)]],
                device float4 *out [[buffer(2)]],
                uint id[[thread_position_in_grid]])
{
    out[id] = inA[id] + inB[id];
}

//着色函数的多个参数使用不同类型的属性修饰符的情况
//纹理读取的方式的sampler，即采样器，[[sampler(0)]]表示采样器的缓存id
kernel void my_kernel(device float4 *p [[buffer(0)]],
                      texture2d<float> img [[texture(0)]],
                      sampler sam [[sampler(0)]])
{
    //.....
    
```