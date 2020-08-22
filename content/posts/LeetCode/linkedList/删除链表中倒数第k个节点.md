---
title: "删除链表中倒数第k个节点"
date: 2020-05-07T10:38:30+08:00
draft: false
tags: ["LeetCode", "LinkedList"]
url:  "remove-nth-node-from-end-of-list"
---

#### 题目 - 删除链表中倒数第k个节点

[LeetCode 19](https://leetcode-cn.com/problems/remove-nth-node-from-end-of-list/)

**难度：简单**

#### 分析

**双指针法**

1. 先让快指针走 k 步
2. 快慢指针同时走，每次走一步
3. 当快指针到达链表尾端时，慢指针就指向当倒数第 k 个节点

#### 代码

```swift
  func removeNthFromEnd(_ head: ListNode?, _ n: Int) -> ListNode? {
      var dummy = head
      var fast = head, slow = head
      for i in 0..<n {
          fast = fast?.next
          if fast == nil {
              return head?.next
          }
      }
      while fast?.next != nil {
          slow = slow?.next
          fast = fast?.next
      }
      slow?.next = slow?.next?.next
      return dummy
  }
```

