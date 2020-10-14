---
title: "Swift-链表结构"
date: 2020-05-01T10:14:32+08:00
draft: true
tags: ["LeetCode", "LinkedList"]
url:  "swift-Linked-List"
---

#### Swift - 链表结构

```swift
public class ListNode {
    var value: Int
    var next: ListNode?
    
    public init(_ value: Int) {
        self.value = value
    }
    
    // for debug
    func printNode() {
        var current: ListNode? = self
        while current != nil {
            print("\(current!.value) -> ", separator: "", terminator: "")
            current = current?.next
        }
        print(current as Any)
    }

    // 尾插法
    func appendNode(_ val: Int) {
        let node = ListNode(val)
        var head = self
        while let next = head.next {
            head = next
        }
        head.next = node
    }
}

let one   = ListNode(1)
let two   = ListNode(2)
let three = ListNode(3)

one.next  = two
two.next  = three

one.printNode()
two.printNode()

```



#### 黑苹果 - 新配置

CPU：3700X 

主板：华硕 ROG Strix B450i

电源：海盗船 sfx750

散热：恩杰x53

机箱：六水ghost s1复刻机箱+水冷帽 黑色

内存：海盗船 8G * 2

硬盘：三星 970 500G m.2 + 三星 860 500G Sata3

