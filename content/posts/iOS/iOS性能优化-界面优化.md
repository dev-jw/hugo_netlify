---
title: "iOS性能优化-界面优化"
date: 2020-11-27T20:47:41+08:00
draft: true
tags: ["iOS"]
url:  "interface-optimization"
---



### 卡顿原理

在 「[iOS的渲染原理总结上](/iOSRenderPre)」

**双重缓存**

**垂直同步信号**

### 卡顿检测

**CADisplayLink 检测 FPS**

**RunLoop 检测事务执行间隔**

- 微信团队的解决方案
- 滴滴团队的解决方案

### 优化方案

**预排版**

**预解码&预渲染**

图片加载过程：Data Buffer -> Image Buffer -> Layout

**按需加载**

**异步渲染**

- Graver：CoreText & CoreGraphics —— 异步绘制，减少图层的层级

  ![image-20201127215556693](/Users/zsy/Desktop/Blog/%E9%85%8D%E5%9B%BE/image-20201127215556693.png)

- Texture：UIKit 的重绘，特别重，坑点太多

