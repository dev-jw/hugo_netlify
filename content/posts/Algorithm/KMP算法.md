---
title: "KMP算法"
date: 2020-04-23T10:00:00+08:00
url:  "KMP"
draft: false
tags: [
  "数据结构与算法",
  "串"
]
---

### KMP算法是什么？

首先，我们先来看一下**BF算法**是怎么解决字符串匹配问题的。只有了解BF算法，才能知道KMP算法的优势。

> S = "bababaabd", T = "abaabd"

比如：在上面列子给到的2个字符串，

BF算法的原理是一位一位地比较，匹配失败的时候，将T串向后移动一位，S串回溯到下一个位置，再进行一位一位地重新匹配，如下图所示

![BF](https://w-md.imzsy.design/BF.gif)

当第5个字符匹配失败时，需要将T串的向右移动一位，重头开始进行逐个字符的比较。这种暴力求解的算法效率是很低的，上面的这个列子，就需要完全的遍历完S串和T串，才可以匹配成功。

假设，如果计算机可以知道，当你第5个字符匹配失败，不需要回溯S串的下标，直接去比较T串的第1个位置，从而省去S串中间的第3，第4个字符的比较，来降低循环的次数。这便是KMP算法。

> KMP算法是一种改进的字符串匹配算法，由D.E.Knuth，J.H.Morris和V.R.Pratt提出的，因此简称KMP算法。

### 如何理解KMP算法的核心思想？

![KMP](https://w-md.imzsy.design/KMP-7888806.gif)

通过图示，可以发现：

KMP算法的核心是利用匹配失败后的信息，尽量减少模式串与主串的匹配次数以达到快速匹配的目的。

**尽可能的利用已知的信息**，是KMP算法的思想所在。

**KMP算法流程**

* 假设主串S匹配到 i 位置，模式串T匹配到 j 位置
  * 如果 `j = -1`，或者当前字符匹配成功（`S[i] == T[j]`），则`i++`，`j++`继续下一个字符的匹配
  * 如果 `j != -1`，且当前字符匹配失败（`S[i] != T[j]`），则 i 不变，`j = next[j]`。这个操作就相当于将模式串T相对于主串S向右移动了 `j - next[j]` 位

> 当不匹配时，将模式串T的索引位置移动到，模式串T失配位置的next数组的值

现在的问题是**如何快速求解next数组**

**快速求解next数组**

现在我们来求解，上面列子中的模式串`T = abaabd`对应的next数组

首先，我们先来看模式串T的**前缀表**，去掉本身子串`abaabd`

| a    |      |      |      |      |
| ---- | ---- | ---- | ---- | ---- |
| a    | b    |      |      |      |
| a    | b    | a    |      |      |
| a    | b    | a    | a    |      |
| a    | b    | a    | a    | b    |

接着，我们分别计算每个子串的**最长公共前后缀**

> 这边以子串`abaab`为例，如图所示，最长公共前后缀的长度为2
>

![image-20200426165206371](https://w-md.imzsy.design/image-20200426165206371.png)

这样，求得模式串T的前缀表中每个子串的公共前后缀的**最大长度表**

| a   | b    | a    | a    | b    |   d   |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 0 | 0 | 1 | 1 | 2 | 0 |

现在我们根据**最大长度表**，来求**next数组**：

next数组，将最大长度表整体**向右移动一位**，将首位用-1补上

| 模式串T      | a    | b    | a    | a    | b    | d    |
| ------------ | ---- | ---- | ---- | ---- | ---- | ---- |
| Prefix table | 0    | 0    | 1    | 1    | 2    | 0    |
| next         | -1   | 0    | 0    | 1    | 1    | 2    |

这样我们就求得了模式串`T = abaabd`的next数组，next[] = [-1, 0, 0, 1, 1, 2]

### KMP算法的代码实现

模式串T的next数组

```c
void buildNext(char *T, int *next) {
    int prefix = 0; // 前缀
    int suffer = 1; // 后缀
    int len = (int)strlen(T); // 字符串长度
    next[0] = 0; // 初始首位置为0
    
    while (prefix < len) {
        if (T[prefix] == T[suffer]) {
            prefix++;
            next[suffer] = prefix;
            suffer++;
        }else {
            if (prefix > 0) {
                prefix = next[prefix - 1];
            }else {
                next[suffer] = 0;
                suffer++;
            }
        }
    }
    // 整体向右移动一位
    for (int i = len - 1; i > 0; i--) {
        next[i] = next[i - 1];
    }
    // 首位置为-1
    next[0] = -1;
}

```

KMP算法匹配实现

```c
int KMP(char *S, char *T) {
    int n = (int)strlen(S);
    int m = (int)strlen(T);
    int *next = malloc(sizeof(int) * m);
    buildNext(T, next);
    
    int i = 0;
    int j = 0;
    
    while (i < n && j < m) {
        if (j == 0 || S[i] == T[j]) {
            i++;
            j++;
        }else {
            j = next[j];
        }
    }
    
    if (j == m) {
        return i - m + 1 ;
    }
    return -1;
}
```



### KMP算法优化

当模式串`T= aaaaab`，我们可以得到next数组为

| 模式串       | a    | a    | a    | a    | a    | b    |
| ------------ | ---- | ---- | ---- | ---- | ---- | ---- |
| prefix table | 0    | 1    | 2    | 3    | 4    | 5    |
| next         | -1   | 0    | 1    | 2    | 3    | 4    |

我们可以发现，在next数组中，移动位置到1，2，3，4，其最后都会移动到首位，这样其实产生了对于重复比较的环节。

当知道T中的前5位字符都是相同的，当时匹配的下标移动缺少当前失配位置的前一位，是没有必要每次都向后移动一位，可以直接移动到第1位。

**实现方法**

我们在求前 i - 1 个元素前缀与后缀相等个数的时候，是不考虑第P[ i ]的，但是如果要是最大相等前缀的后一个字符和P[ i ]相等的话，不就表明即使你移动了之后，当前字符依然没变，也就依然不能匹配，所以也不必要再接着移

```c
void buildNext(char *T, int *next) {
    int prefix = 0; // 前缀
    int suffer = 1; // 后缀
    int len = (int)strlen(T); // 字符串长度
    next[0] = 0; // 初始首位置为0
    
    while (prefix < len) {
        if (T[prefix] == T[suffer]) {
            prefix++;
            suffer++;
            next[suffer] = T[suffer] != T[prefix] ? prefix : next[prefix];
        }else {
            if (prefix > 0) {
                prefix = next[prefix - 1];
            }else {
                next[suffer] = 0;
                suffer++;
            }
        }
    }
    // 整体向右移动一位
    for (int i = len - 1; i > 0; i--) {
        next[i] = next[i - 1];
    }
    // 首位置为-1
    next[0] = -1;
}
```

