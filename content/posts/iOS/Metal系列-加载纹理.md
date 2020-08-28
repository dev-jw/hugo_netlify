---
title: "Metal系列-加载纹理"
date: 2020-08-25T14:51:40+08:00
draft: true
tags: ["Metal", "iOS"]
url:  "Metal-5"
---

> 之前我们已经对顶点缓冲对象 `MTLBuffer` 有了简单的了解和使用。
>
> 加载纹理对象，我们需要借助 `MTLTexture`

在 Metal 中，`MTLBuffer` 可以用来传递一些未格式化的信息，例如顶点坐标、纹理坐标等；`MTLTexture`可以用来传递图像信息。

#### MTLTexture

`MTLTexture`对象是保存格式化后的图片数据的对象，用于向 Metal 程序传递图像信息。

**创建**

根据`MTLTextureDescriptor`纹理描述符对象，创建`MTLTexture`纹理对象

```objective-c
// 创建纹理描述符
MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
// 设置像素颜色格式
textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
// 设置纹理的像素尺寸
textureDescriptor.width = image.size.width;
textureDescriptor.height = image.size.height;
// 使用纹理描述符创建纹理
_texture = [_device newTextureWithDescriptor:textureDescriptor];
```

**加载图像数据**

- 加载 `TGA` 图片

```objective-c
	- (void)setupTexture{
    
//    1、获取TGA文件路径 --- TGA文件解压
    NSURL *imageFileLocation = [[NSBundle mainBundle] URLForResource:@"circle" withExtension:@"tga"];
    //将tag文件->CJLImage对象
    CJLImage *image = [[CJLImage alloc] initWithTGAFileAtLocation:imageFileLocation];
    //判断图片是否转换成功
    if (!image) {
        NSLog(@"Failed to create the image from:%@",imageFileLocation.absoluteString);
        return;
    }
    
//    2、创建纹理描述对象 & 设置属性 --- CJLImage --> 纹理（即位图变成纹理对象）
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    //表示每个像素有蓝色,绿色,红色和alpha通道.其中每个通道都是8位无符号归一化的值.(即0映射成0,255映射成1);
    //位图信息
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    //设置纹理的像素尺寸，即纹理的分辨率
    textureDescriptor.width = image.width;
    textureDescriptor.height = image.height;
    
//    3、创建纹理对象：使用描述符从设备中创建纹理
    _texture = [_device newTextureWithDescriptor:textureDescriptor];
    //计算图像每行的字节数
    NSUInteger bytesPerRow = 4 * image.width;
    
//    4、创建MTLRegion结构体
    /*
     typedef struct
     {
     MTLOrigin origin; //开始位置x,y,z
     MTLSize   size; //尺寸width,height,depth
     } MTLRegion;
     */
    //MLRegion结构用于标识纹理的特定区域。 demo使用图像数据填充整个纹理；因此，覆盖整个纹理的像素区域等于纹理的尺寸。
    MTLRegion region = {
        {0,0,0},
        {image.width, image.height, 1},
    };
    
//    5、复制图片数据到texture
    /*
     将图片复制到纹理0中（即用纹理替换region表示的区域）
     - (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow;
     参数1-region：像素区域在纹理中的位置
     参数2-level：从零开始的值，指定哪个mipmap级别是目标。如果纹理没有mipmap，请使用0。
     参数3-pixelBytes：指向要复制图片的字节数
     参数4-bytesPerRow：对于普通或压缩像素格式，源数据行之间的跨度（以字节为单位）。对于压缩像素格式，跨度是从一排块的开头到下一行的开始的字节数。
     */
   [_texture replaceRegion:region mipmapLevel:0 withBytes:image.data.bytes bytesPerRow:bytesPerRow];
}

- (nullable instancetype) initWithTGAFileAtLocation:(nonnull NSURL *)location
{
    self = [super init];
    if(self)
    {
        NSString *fileExtension = location.pathExtension;
        
        //判断文件后缀是否为tga
        if(!([fileExtension caseInsensitiveCompare:@"TGA"] == NSOrderedSame))
        {
            NSLog(@"此CCImage只加载TGA文件");
            return nil;
            
        }
        
        //定义一个TGA文件的头.
        typedef struct __attribute__ ((packed)) TGAHeader
        {
            uint8_t  IDSize;         // ID信息
            uint8_t  colorMapType;   // 颜色类型
            uint8_t  imageType;      // 图片类型 0=none, 1=indexed, 2=rgb, 3=grey, +8=rle packed
            
            int16_t  colorMapStart;  // 调色板中颜色映射的偏移量
            int16_t  colorMapLength; // 在调色板的颜色数
            uint8_t  colorMapBpp;    // 每个调色板条目的位数
            
            uint16_t xOffset;        // 图像开始右方的像素数
            uint16_t yOffset;        // 图像开始向下的像素数
            uint16_t width;          // 像素宽度
            uint16_t height;         // 像素高度
            uint8_t  bitsPerPixel;   // 每像素的位数 8,16,24,32
            uint8_t  descriptor;     // bits描述 (flipping, etc)
            
        }TGAHeader;
        
        NSError *error;
        
        //将TGA文件中整个复制到此变量中
        NSData *fileData = [[NSData alloc]initWithContentsOfURL:location options:0x0 error:&error];
        
        if(fileData == nil)
        {
            NSLog(@"打开TGA文件失败:%@",error.localizedDescription);
            return nil;
        }
        
        //定义TGAHeader对象
        TGAHeader *tgaInfo = (TGAHeader *)fileData.bytes;
        _width = tgaInfo->width;
        _height = tgaInfo->height;
        
        //计算图像数据的字节大小,因为我们把图像数据存储为/每像素32位BGRA数据.
        NSUInteger dataSize = _width * _height * 4;
        
        if(tgaInfo->bitsPerPixel == 24)
        {
            //Metal是不能理解一个24-BPP格式的图像.所以我们必须转化成TGA数据.从24比特BGA格式到32比特BGRA格式.(类似MTLPixelFormatBGRA8Unorm)
            NSMutableData *mutableData = [[NSMutableData alloc] initWithLength:dataSize];
            
            //TGA规范,图像数据是在标题和ID之后立即设置指针到文件的开头+头的大小+ID的大小.初始化源指针,源代码数据为BGR格式
            uint8_t *srcImageData = ((uint8_t*)fileData.bytes +
                                     sizeof(TGAHeader) +
                                     tgaInfo->IDSize);
            
            //初始化将存储转换后的BGRA图像数据的目标指针
            uint8_t *dstImageData = mutableData.mutableBytes;
            
            
            //图像的每一行
            for(NSUInteger y = 0; y < _height; y++)
            {
                //对于当前行的每一列
                for(NSUInteger x = 0; x < _width; x++)
                {
                    //计算源和目标图像中正在转换的像素的第一个字节的索引.
                    NSUInteger srcPixelIndex = 3 * (y * _width + x);
                    NSUInteger dstPixelIndex = 4 * (y * _width + x);
                    
                    //将BGR信道从源复制到目的地,将目标像素的alpha通道设置为255
                    dstImageData[dstPixelIndex + 0] = srcImageData[srcPixelIndex + 0];
                    dstImageData[dstPixelIndex + 1] = srcImageData[srcPixelIndex + 1];
                    dstImageData[dstPixelIndex + 2] = srcImageData[srcPixelIndex + 2];
                    dstImageData[dstPixelIndex + 3] = 255;
                }
            }
            _data = mutableData;
            
        }else
        {
        
            uint8_t *srcImageData = ((uint8_t*)fileData.bytes +
                                     sizeof(TGAHeader) +
                                     tgaInfo->IDSize);

            _data = [[NSData alloc] initWithBytes:srcImageData
                                           length:dataSize];
            
        }
        
    }
    return self;
    
}
```

- 加载 `PNG/JPG` 图片

```objective-c
- (void)setupTexture {
    UIImage *image = [UIImage imageNamed:@"wlop.png"];
    
    MTLTextureDescriptor *textureDes = [[MTLTextureDescriptor alloc] init];
    textureDes.pixelFormat = MTLPixelFormatRGBA8Unorm;
    textureDes.width    = image.size.width;
    textureDes.height   = image.size.height;
    
    _texture = [_device newTextureWithDescriptor:textureDes];
   
    MTLRegion region = {
        {0, 0, 0},
        {image.size.width, image.size.height, 1},
    };
    
    Byte *imageBytes = [self loadImage:image];
    NSAssert(imageBytes, @"imageBytes load failed");

    [_texture replaceRegion:region
                mipmapLevel:0
                  withBytes:imageBytes
                bytesPerRow:4 * image.size.width];
    
    free(imageBytes);
    imageBytes = NULL;
}

- (Byte *)loadImage:(UIImage *)image {
    CGImageRef imageRef = image.CGImage;
    NSAssert(imageRef, @"Image load failed");
    
    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    
    Byte *spriteData = (Byte*)calloc(width * height * 4, sizeof(Byte));
    
    CGContextRef contextRef = CGBitmapContextCreate(spriteData, width, height, 8, width * 4, CGImageGetColorSpace(imageRef), kCGImageAlphaPremultipliedLast);
    
    CGRect rect = CGRectMake(0, 0, width, height);
    CGContextDrawImage(contextRef, rect, imageRef);
    CGContextTranslateCTM(contextRef, 0, rect.size.height);
    CGContextScaleCTM(contextRef, 1.0, -1.0);
    CGContextDrawImage(contextRef, rect, imageRef);

    CGContextRelease(contextRef);
    CGImageRelease(imageRef);
    
    return spriteData;
}
```

**传递图像数据**

通过命令编码器，将当前纹理对象传递到 Metal 程序的片段函数中

`[commandEncoder setFragmentTexture:_texture atIndex:TextureIndexBaseColor]`