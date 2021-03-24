## Core NFC

### NFC_Protocol_Stack

![NFC_Protocol_Stack](/Users/zsy/Documents/typora-img/NFC_Protocol_Stack.png)

### 几个方面

- 协议
  - NFCNDEFReaderSession —— 支持 NDEF 格式的标签
  - NFCTagReaderSession —— 支持 iso14443、iso15693、iso18092
    - iso14443，同时支持 A 和 B，兼容iso7816 和 miFare
    - iso15693，支持 iso15693
    - iso18092，支持 feliCa

- 优缺点

  - 优点：
    - 功耗低
    - 连接速度快
  - 缺点：
    - 必须打开 App，唤起 NFC 扫描才能去识别内容，仅通过系统的识别，无法根据 NFC 标签中的内容去执行后续的操作
    - 由于 NFC 标签不依赖于网络，外人轻易地获取 NFC 中的内容


### NDEF详解

NDEF 是一种能够在NFC设备或者标签之间进行信息交换的数据格式

分为两部分：

- NDEF Message：由负载记录数组组成的NDEF消息，对应为 `NFCNDEFMessage`
- NDEF Records：NDEF消息中的有效负载记录，对应为 `NFCNDEFPayload`

**NFCNDEFPayload解释**

一条有效负载记录，用以下结构来标识内容和记录大小

![image-20210323202233044](/Users/zsy/Documents/typora-img/image-20210323202233044.png)

#### TNF: typeNameFormat 字段

一条NDEF记录的类型名称是一个3个位的数值，用来描述这条记录的类型，并且可以用来设置对该记录中其它的结构和内容的期望

简单的说就是这3个位不仅可以表示该条记录的类型，也可以在一定程度上决定了该条记录接下来的数据结构。

可能的记录名称如下表：

```swift
public enum NFCTypeNameFormat : UInt8 {

    /// 记录没有类型、id或有效payload，一般用于新格式化的 NDEF 卡上
    @available(iOS 11.0, *)
    case empty = 0 
    /// Well-Known Record 表明记录类型字段使用RTD类型名称格式.这种类型名称用一个Record Type Definition (RTD)来存储任何指定的类型，例如：存储RTD文本、RTD URIs等等
    @available(iOS 11.0, *)
    case nfcWellKnown = 1
		/// 表明payload是这条NDEF记录分块的中间或者最后一块
    @available(iOS 11.0, *)
    case media = 2
		/// 表明这条记录的类型字段一定包含一个URI字段
    @available(iOS 11.0, *)
    case absoluteURI = 3
		/// 表明这条记录的类型字段包含一个RTD格式的外部字段
    @available(iOS 11.0, *)
    case nfcExternal = 4
		/// 表明payload的类型未知
    @available(iOS 11.0, *)
    case unknown = 5
		/// 未发生变化的记录类型，释同MIME Media Record
    @available(iOS 11.0, *)
    case unchanged = 6
}
```

### iOS-Demo

#### 基于 NDEF 格式的读写

- 初始化 `NFCNDEFReaderSession`

  ```swift
    guard NFCNDEFReaderSession.readingAvailable else {
        completion?(.failure(NFCError.unavailable))
        print("NFC is not available on this device")
        return
    }
  
    shared.session = NFCNDEFReaderSession(delegate: shared.self, queue: nil, invalidateAfterFirstRead: false)
    shared.session?.alertMessage = action.alertMessage
    shared.session?.begin()
  ```
  
- 实现`NFCNDEFReaderSessionDelegate`方法

  ```swift
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let error = error as? NFCReaderError,
           error.code != .readerSessionInvalidationErrorFirstNDEFTagRead &&
            error.code != .readerSessionInvalidationErrorUserCanceled {
            completion?(.failure(NFCError.invalidated(message: error.localizedDescription)))
        }
  
        self.session = nil
        completion = nil
    }
  
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first, tags.count == 1 else {
            session.alertMessage = "There are too many tags present. Remove all and then try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                session.restartPolling()
            }
            return
        }
  
        session.connect(to: tag) { error in
            if let error = error {
                self.handleError(error)
                return
            }
  
            tag.queryNDEFStatus { (status, _, error) in
                if let error = error {
                    self.handleError(error)
                    return
                }
                // Process Tag
            }
        }
    }
  
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
  
    }
  ```

- 读取

  ```swift
    private func read(
        tag: NFCNDEFTag,
        alertMessage: String = "Tag Read",
        readCompletion: NFCReadingCompletion? = nil
    ) {
        tag.readNDEF { message, error in
            if let error = error {
                self.handleError(error)
                return
            }
  
            if let readCompletion = readCompletion,
               let message = message {
                readCompletion(.success(message))
            } else if let message = message,
                      let record = message.records.first {
                let payload = record.payload
                printf("data: \(payload)")
                self.session?.alertMessage = "Read tag data."
                self.session?.invalidate()
            } else {
                self.session?.alertMessage = "Could not decode tag data."
                self.session?.invalidate()
            }
        }
    }
  ```
  
- 写入

  ```swift
    private func write(tag: NFCNDEFTag) {
      
        let payload = NFCNDEFPayload(format: .nfcWellKnown,
                                     type: String("U").data(using: .utf8)!,
                                     identifier: String("12345678").data(using: .utf8)!,
                                     payload: String("content").data(using: .utf8)!)
  
        let NDEFMessage = NFCNDEFMessage(records: [payload])
  	
        tag.writeNDEF(NDEFMessage) { error in
            if let error = error {
                self.handleError(error)
                return
            }
            self.session?.alertMessage = "Write Successed!"
            self.session?.invalidate()
        }
    }
  ```

#### 基于 iso14443 格式的读写

iso14443格式以及其他格式，读写过程与 NDEF 的过程大致相似，主要区别在于：

NDEF 使用的是 **NDEFReadSession**，而其他的标签格式，使用**NFCTagReaderSession**

**指令交互**







#### 唤醒 App

原理：扫描 NFC 标签打开对应的 App 实际上是读取 NFC 标签数据区的 URL，然后打开该 URL 绑定的 App，类似 **Universal Link**

数据格式为：

| iOS 唤醒 NDEF | 示例        | 描述                                                       |
| :------------ | :---------- | :--------------------------------------------------------- |
| TNF           | 0x01        | nfcWellKnown                                               |
| TYPE          | U           | RTD_URI                                                    |
| ID            | NULL        | 非必要不填减少存储占用                                     |
| PAYLOAD       | 0x04 + 域名 | 1字节url前缀「[https://」](https://xn--26j/) + url内容数据 |

这里以 NDEF 格式完成 Demo

**过程：**

1. 在关联的域名下添加`apple-app-site-association`文件，文件内容为：

   ```
   {
       "applinks": {
           "apps": [],
           "details": [
               {
                   "appID": "DevelopmentTeamID.BundleID",
                   "paths": [ "*" ]
               }
           ]
       }
   }
   ```

   `DevelopmentTeamID`可在Apple开发者中心的找到，`BundleID`为 App 的唯一标识

   > 如果 App 有对应的 App Clips，那么在`apple-app-site-association`文件可同时为其进行配置
   >
   > 如：
   >
   > ```
   >     "appclips": {
   >         "apps": ["DevelopmentTeamID.BundleID"]
   >     }
   > ```

2. 选中相应的 Target，在`Signing & Capabilities` 选项卡，添加`Associated Domains`，填入对应的域名

3. 添加回调方法，如果不存在 `SceneDelegate`，那么在 `AppDelegate` 中添加以下方法

   ```swift
       func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
           guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else {
               return false
           }
   
           // Confirm that the NSUserActivity object contains a valid NDEF message.
           let ndefMessage = userActivity.ndefMessagePayload
           guard ndefMessage.records.count > 0,
               ndefMessage.records[0].typeNameFormat != .empty else {
                   return false
           }
   
           // Send the message to `XXXX` for processing.
           print(ndefMessage)
           
           return true
       }
   ```

   如果使用 `SceneDelegate`，那么需要实现`func scene(_ scene: UIScene, continue userActivity: NSUserActivity)`方法

4. 创建 URL 的 NFC 标签，这里以 NDEF 格式为例

   ```swift
   private func write(tag: NFCNDEFTag) {
           
           let backgroudPayLoad = NFCNDEFPayload.wellKnownTypeURIPayload(string: String("域名"))
           
           let NDEFMessage = NFCNDEFMessage(records: [backgroudPayLoad!])
         
           tag .writeNDEF(NDEFMessage) { error in
               if let error = error {
                   self.handleError(error)
                   return
               }
               self.session?.alertMessage = "Write Successed!"
               self.session?.invalidate()
           }
       }
   ```

##### 测试效果

现在，载有 URL 的 NFC 标签已经准备好了，并且对应 URL 的 App 也已经准备完毕，可以进行测试

![image-20210304150620691](/Users/zsy/Documents/typora-img/image-20210304150620691.png)

当我们的 App 没有被启动，或在前台时，手机识别到 NFC 信息

1. 首先，会显示通知
2. 点击通知，会打开相应的 App
3. 在回调中，可以看到内容被输出

### 注意点

#### 支持系统扫描的标签

设备在后台标签读取模式下扫描NFC标签后，系统将通过查找具有以下属性值的`NFCNDEFPayLoad`对象来检查标签的NDEF消息中的URI记录：

- `ypeNameFormat`等于`NFCTypeNameFormatNFCWellKnown`

- `type`等于**U**

如果NDEF消息包含多个URI记录，系统将使用第一个记录。

URI记录必须包含通用链接或支持的URL方案。

#### URL Schemes

根据官方文档，我们并不能使用 `Custom URL Scheme`，而只支持以下的 `URL Schems`

| URL Scheme               | Example                                                      |
| :----------------------- | :----------------------------------------------------------- |
| Website URL (HTTP/HTTPS) | https://www.example.com                                      |
| Email                    | mailto:user@example.com                                      |
| SMS                      | sms:+14085551212                                             |
| Telephone                | tel:+14085551212                                             |
| FaceTime                 | facetime://user@example.com                                  |
| FaceTime Audio           | facetime-audio://user@example.com                            |
| Maps                     | http://maps.apple.com/?address=Apple%20Park,Cupertino,California |
| HomeKit Accessory Setup  | X-HM://12345                                                 |



### 其他

> 1. 苹果手机从iPhone6开始装有NFC硬件，但并未对第三方应用开放。因此iPhone6及iPhone6s不能识别NFC标签，但是可以使用系统NFC功能如：刷地铁。
> 2. 苹果从iOS11系统开始开放NFC读取功能，同时要求iPhone7及以上机型。不满足要求则无法读取NFC标签
> 3. 苹果在iOS13系统开放了标签写入功能，想要向标签内写入数据，需要升级系统到iOS13，同样只能写入DNEF格式数据
> 4. 另外苹果只开放DNEF数据格式的NFC标签读取，如果数据格式不满足则无法读取。身份证、地铁卡、银行卡、大部分的工卡都不是DNEF格式，因此无法读取。（空标签只能在iOS13系统下才可以读取到）（NFC标签可以去淘宝购买，价格很便宜 9.9六个还包邮）
> 5. 身份证、地铁卡虽然无法读取到数据，但是可以用苹果官方APP“快捷指令”进行标记，来实现一些新颖玩法（需要iPhoneXS以上机型）
> 6. 关于后台读取，iPhoneXS以上机型支持，屏幕点亮状态下（无需解锁），手机可以读取一些特定数据格式的NFC标签。识别到标签后，可以实现拨打电话，发送邮件等功能（需解锁）



### 竞品分析——小米碰碰贴

标签格式为 **NDEF**

测试场景：写入执行一个场景，读取标签数据

测试结果：标签内，包含  4 条记录，分别为：

第一条数据：无法解析出内容

```
type: com.xiaomi.smarthome:externaltype
identifier: ""
typeNameFormat: 4	
payload: 解析不出，应该涉及解密方式
```

第二条数据

```
type: android.com:pkg
identifier: ""
typeNameFormat: 4	
payload: com.xiaomi.smarthome
```

第三条数据

```
type: android.com:pkg
identifier: ""
typeNameFormat: 4	
payload: com.xiaomi.mi_connect_service
```

第四条数据

```
type: com.xiaomi.smarthome:externaltype
identifier: ""
typeNameFormat: 1
payload: \u{04}g.home.mi.com
```

小米碰碰贴是MIFARE Ultraalight®产品系列的标识符，即 mifareFamily = .ultralight

#### UID

小米

 <0435d862 716b81>

普通圆卡

<1d7264b1 680000>

<1ddf9fb1 680000>

复旦微

<1debee03 670000>

<1d191504 670000>

#### mifare 指令

读：0x30

写：0xA2

验证：0x1B



### 参考资料：

[CoreNFC](https://developer.apple.com/documentation/corenfc)

[iPhone NFC Compatibility](https://www.bluebite.com/nfc/iphone-nfc-compatibility)

 

