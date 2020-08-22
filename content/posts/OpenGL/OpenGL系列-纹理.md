---
title: "OpenGL系列-纹理"
date: 2020-07-17T21:08:57+08:00
draft: false
tags: ["OpenGL", "iOS"]
url:  "texture"

---

纹理是一个2D图片（甚至也有1D和3D的纹理），它可以用来添加物体的细节；你可以想象纹理是一张绘有砖块的纸，无缝折叠贴合到你的3D的房子上，这样你的房子看起来就像有砖墙外表了。

#### 纹理坐标

为了能够把纹理映射到三角形上，需要让每个顶点关联一个纹理坐标，用来标明从纹理图形的哪个部分采样。

纹理坐标在 x 轴和 y 轴上，范围为 0 到 1 之间（2D 纹理图形）。

使用纹理坐标获取纹理颜色叫做**采样**。

纹理坐标起始于（0，0），也就是纹理图片的左下角，终止于（1，1），即纹理图片的右上角。

![image-20200719170659180](https://w-md.imzsy.design/image-20200719170659180.png)

#### 环绕方式

纹理坐标的范围通常是从(0, 0)到(1, 1)。

当纹理坐标设置在范围之外，OpenGL 默认的行为是重复这个纹理图像。

但 OpenGL 提供了更多的选择：

| 环绕方式           | 描述                                                         |
| ------------------ | ------------------------------------------------------------ |
| GL_REPEAT          | 对纹理的默认行为。重复纹理图像。                             |
| GL_MIRRORED_REPEAT | 和GL_REPEAT一样，但每次重复图片是镜像放置的。                |
| GL_CLAMP_TO_EDGE   | 纹理坐标会被约束在0到1之间，超出的部分会重复纹理坐标的边缘，产生一种边缘被拉伸的效果。 |
| GL_CLAMP_TO_BORDER | 超出的坐标为用户指定的边缘颜色。                             |

当纹理坐标超出默认范围时，每个选项不同的视觉效果输出：
![image-20200719171113378](https://w-md.imzsy.design/image-20200719171113378.png)



#### 纹理过滤

纹理坐标不依赖于分辨率(Resolution)，它可以是任意浮点值。

当有一个很大的物体，但是纹理的分辨率很低的时候，纹理过滤就变得很重要了

- 邻近过滤 `GL_NEAREST`：是OpenGL默认的纹理过滤方式。当设置为`GL_NEAREST`的时候，OpenGL会选择中心点最接近纹理坐标的那个像素
- 线性过滤 `GL_LINEAR`：它会基于纹理坐标附近的纹理像素，计算出一个插值，近似出这些纹理像素之间的颜色

![image-20200719171435332](https://w-md.imzsy.design/image-20200719171435332.png)

在一个很大的物体上应用一张低分辨率的纹理：

![image-20200719171716270](https://w-md.imzsy.design/image-20200719171716270.png)

`GL_NEAREST`产生了颗粒状的图案，我们能够清晰看到组成纹理的像素，而`GL_LINEAR`能够产生更平滑的图案，很难看出单个的纹理像素。



#### 纹理常用 API

**生成纹理**

```c++
//使用函数分配纹理对象
//指定纹理对象的数量 和 指针（指针指向一个无符号整形数组，由纹理对象标识符填充）。
void glGenTextures(GLsizei n,GLuint * textTures);

//绑定纹理状态
//参数target:GL_TEXTURE_1D、GL_TEXTURE_2D、GL_TEXTURE_3D
//参数texture:需要绑定的纹理对象
void glBindTexture(GLenum target,GLunit texture);

//删除绑定纹理对象
//纹理对象 以及 纹理对象指针（指针指向一个无符号整形数组，由纹理对象标识符填充）。
void glDeleteTextures(GLsizei n,GLuint *textures);

//测试纹理对象是否有效
//如果texture是一个已经分配空间的纹理对象，那么这个函数会返回GL_TRUE,否则会返回GL_FALSE。
GLboolean glIsTexture(GLuint texture);
```

**读取纹理**

```c++
//参数1: 纹理文件名称
//参数2: 文件宽度地址
//参数3：文件高度地址
//参数4：文件组件地址
//参数5：文件格式地址
//返回值：pBits,指向图像数据的指针
GLbyte *gltReadTGABits(const char *szFileName, GLint *iWidth, GLint *iHeight, GLint *iComponents, GLenum *eFormat);

GLbyte* gltReadBMPBits(const char *szFileName, int *nWidth, int *nHeight);
```

**纹理参数**

```c++
// 参数1:target,指定这些参数将要应用在那个纹理模式上，比如GL_TEXTURE_1D、GL_TEXTURE_2D、GL_TEXTURE_3D。
// 参数2:pname,指定需要设置那个纹理参数
// 参数3:param,设定特定的纹理参数的值
glTexParameterf(GLenum target,GLenum pname,GLFloat param);
glTexParameteri(GLenum target,GLenum pname,GLint param);
glTexParameterfv(GLenum target,GLenum pname,GLFloat *param);
glTexParameteriv(GLenum target,GLenum pname,GLint *param);
```

**过滤方式**

```c++
glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);

glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
```

**S/T 轴环绕方式**

`s`、`t`（如果是使用3D纹理那么还有一个`r`）和`x`、`y`、`z`是等价的

```C++
glTextParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAR_S,GL_CLAMP_TO_EDGE);
glTextParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAR_T,GL_CLAMP_TO_EDGE);
```

如果选择`GL_CLAMP_TO_BORDER`，还需要指定一个边缘的颜色

```c++
float borderColor[] = { 1.0f, 1.0f, 0.0f, 1.0f };
glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, borderColor);
```

**载入纹理**

```c++
//target:GL_TEXTURE_1D、GL_TEXTURE_2D、GL_TEXTURE_3D 。 
//Level :指定所加载的mip贴图层次。一般我们都把这个参数设置为0。
//internalformat:每个纹理单元中存储多少颜色成分。
//width、height、depth 参数:指加载纹理的宽度、高度、深度。
//border参数:允许为纹理贴图指定一个边界宽度。
//format参数:gltReadTGABits函数中,通过 eFormat 参数返回图片的颜色格式
//type参数:OpenGL 数据存储方式,一般使用 GL_UNSIGNED_BYTE
//data参数:图片数据指针
void glTexImage1D(GLenum target,GLint level,GLint internalformat,GLsizei width,GLint border,GLenum format,GLenum type,void *data);

void glTexImage2D(GLenum target,GLint level,GLint internalformat,GLsizei width,GLsizei height,GLint border,GLenum format,GLenum type,void * data);

void glTexImage3D(GLenum target,GLint level,GLint internalformat,GLSizei width,GLsizei height,GLsizei depth,GLint border,GLenum format,GLenum type,void *data);
```



#### 加载 TGA 纹理

```c++
// load Texture TGA
bool LoadTGATexture(const char *szFileName, GLenum minFilter, GLenum magFilter, GLenum wrapMode)
{
    GLbyte *pBits;
    int nWidth, nHeight, nComponents;
    GLenum eFormat;
    
    // Read the texture bits
    pBits = gltReadTGABits(szFileName, &nWidth, &nHeight, &nComponents, &eFormat);
    if(pBits == NULL)
        return false;
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrapMode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrapMode);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter);
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_COMPRESSED_RGB, nWidth, nHeight, 0,
                 eFormat, GL_UNSIGNED_BYTE, pBits);
    
    free(pBits);
    
    if(minFilter == GL_LINEAR_MIPMAP_LINEAR ||
       minFilter == GL_LINEAR_MIPMAP_NEAREST ||
       minFilter == GL_NEAREST_MIPMAP_LINEAR ||
       minFilter == GL_NEAREST_MIPMAP_NEAREST)
        glGenerateMipmap(GL_TEXTURE_2D);
    
    return true;
}

void SetupRC() {
	  glGenTextures(1, textures);
    glBindTexture(GL_TEXTURE_2D, textures[0]);
    LoadTGATexture("图片.tga", GL_LINEAR_MIPMAP_LINEAR, GL_LINEAR, GL_CLAMP_TO_EDGE);
}
```

#### 加载 BMP 纹理

```c++
	// Load in a BMP file as a texture. Allows specification of the filters and the wrap mode
bool LoadBMPTexture(const char *szFileName, GLenum minFilter, GLenum magFilter, GLenum wrapMode)
{
    GLbyte *pBits;
    GLint iWidth, iHeight;
    
    pBits = gltReadBMPBits(szFileName, &iWidth, &iHeight);
    if(pBits == NULL)
        return false;
    
    // Set Wrap modes
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrapMode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrapMode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, iWidth, iHeight, 0, GL_BGR, GL_UNSIGNED_BYTE, pBits);
    
    // Do I need to generate mipmaps?
    if(minFilter == GL_LINEAR_MIPMAP_LINEAR || minFilter == GL_LINEAR_MIPMAP_NEAREST || minFilter == GL_NEAREST_MIPMAP_LINEAR || minFilter == GL_NEAREST_MIPMAP_NEAREST)
        glGenerateMipmap(GL_TEXTURE_2D);
    
    return true;
}

void SetupRC() {
	  glGenTextures(1, textures);
    glBindTexture(GL_TEXTURE_2D, textures[0]);
    LoadBMPTexture("图片.bmp", GL_LINEAR_MIPMAP_LINEAR, GL_LINEAR, GL_REPEAT);
}
```

