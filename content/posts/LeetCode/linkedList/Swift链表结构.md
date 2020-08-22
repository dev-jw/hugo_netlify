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

