---
title: "Flutter环境的安装"
date: 2020-05-27T19:09:48+08:00
draft: false
tags: ["Flutter"]
---

## Mac下搭建Flutter环境注意点

> Flutter 的配置其实特别简单，跟着[官方文档](https://flutterchina.club/get-started/install/)一步一步的执行就可以了，在这里主要讲几个注意点
>

### 一、安装路径

如果你将 Flutter 安装在`~`加目录(即登录用户目录)下时，在你切换登录用户后，你的 Flutter 环境将不会被共享，需要**重新安装**。

因此，如果你的 Mac 有多个账号用户，你可以尝试将 Flutter 安装到`/opt`根目录下的 opt 文件夹中，这样当你切换账号后，Flutter 环境依然存在。

> 对于根目录，首先需要对其进行设置权限
>
> 默认权限：`drwxr-xr-x   2 root  wheel    64  8 25  2019 opt`
>
> * d：第1位表示文件类型，d 是目录文件，l 是链接文件，- 是普通文件，p 是管道
>   * rwx：第2-4位表示文件的属主拥有的权限，r 是读，w 是写，x 是执行
> * r-x：第5-7位表示文件的属主同一个组的用户所具有的权限
> * r-x：第8-10位表示其他用户拥有的权限
>
> 比如我们常用的`chmod 777` 即`rwxrwxrwx`、`chmod 755` 即`rwxr-xr-x`



### 二、配置环境变量

首先，Mac 终端在新系统下默认使用的是 `zsh`（可以通过 chsh 查看），我们只需要将 FLutter 国内镜像配置到 `~/.zshrc`，之后 `source ~/.zshrc`

如果你的 Shell 使用的是 `bash`，将环境配置到 `~/.bash_profile` 之后 `source ~/.bash_profile`



### 三、Flutter 的编辑器

推荐使用 **Android Studio**，其次是 **Visual Studio Code**

安装相应的 Flutter 插件，设置 Flutter 和 Dart 的 SDK 地址即可；

> 当然，你可以选择去安装一些常用的缩写代码块插件



### 四、常见报错问题

1. 如果执行`flutter doctor`，输出的 `[!] Proxy Configuration` 时，建议将终端代理取消。如果不取消，会对 flutter 创建项目、 热重载、调式等产生官方暂时还未解决的问题。
2. 当你的 flutter 项目的路径发生变化时，只需要用 **Android Studio** 重新打开项目编译运行， **Android Studio**会自动为我们更新路径
3. 当引入新的 package 时，注意需要去执行 `flutter pub get`，如果失败了，可以尝试用 `flutter pub cache repair` 修复，再重新执行 `flutter pub get`

