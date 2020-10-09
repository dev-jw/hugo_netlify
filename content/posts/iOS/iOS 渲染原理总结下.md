---
title: "iOS渲染原理总结(下)"
date: 2020-06-17T14:04:48+08:00
draft: true
tags: ["iOS"]
url:  "iOSRenderNext"
---

接上一篇，继续带着问题去学习

1. CoreAnimation 的职责是什么？
2. UIView 和 CALayer 是什么关系？有什么区别？
3. 为什么会同时有 UIView 和 CALayer，能否合成一个？
4. 渲染流水线中，CPU 会负责哪些任务？
5. 离屏渲染为什么会有效率问题？
6. 什么时候应该使用离屏渲染？
7. shouldRasterize 光栅化是什么？
8. 有哪些常见的触发离屏渲染的情况？
9. cornerRadius 设置圆角会触发离屏渲染吗？
10. 圆角触发的离屏渲染有哪些解决方案？
11. 重写 drawRect 方法会触发离屏渲染吗？

