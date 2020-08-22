---
title: "链表中倒数第k个节点"
date: 2020-05-05T10:38:30+08:00
draft: false
tags: ["LeetCode", "LinkedList"]
url:  "kth-element"
---

#### 题目 - 链表中倒数第k个节点

[面试题 02.02](https://leetcode-cn.com/problems/kth-node-from-end-of-list-lcci/)

[剑指 Offer 22. 链表中倒数第k个节点](https://leetcode-cn.com/problems/lian-biao-zhong-dao-shu-di-kge-jie-dian-lcof/)

**难度：简单**

#### 分析

**双指针法**

1. 先让快指针走 k 步
2. 快慢指针同时走，每次走一步
3. 当快指针到达链表尾端时，慢指针就指向当倒数第 k 个节点

#### 代码

```swift
func getKthFromEnd(_ head: ListNode?, _ k: Int) -> ListNode? {
      var fast = head, slow = head
    var step = k
    while step > 0 {
        fast = fast!.next
        step -= 1
    }

    while fast != nil {
        fast = fast!.next
        slow = slow!.next
    }

    return slow
  }
```

