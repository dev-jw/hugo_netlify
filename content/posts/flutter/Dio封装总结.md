---
title: "Dio封装总结"
date: 2020-06-11T17:41:03+08:00
draft: false
tags: ["Flutter", "Dio"]
url:  "Dio"
---

> 网络请求在实际开发中，会频繁的被使用到，如何在 `Dio`的基础上封装一个更加易用、方便的请求库呢

### Dio 了解

在 **Flutter** 中，**[Dio](https://github.com/flutterchina/dio)** 是一个非常强大的第三方网络请求库，支持 Restful Api、FormData、拦截器、请求取消、Cookie 管理、文件上传/下载、超时等等很多功能。

在[官方文档](https://github.com/flutterchina/dio/blob/master/README-ZH.md)上，有很具体的示例，指导我们怎么去使用它。



### 在封装之前

在开始着手封装 **Dio** 之前，我们需要思考最为关键的问题：为什么要二次封装 **Dio**？

假设，你是直接使用 `Dio` 进行网络请求的发送，当 `Dio` 升级或替换请求库时，你需要将当前项目文件中，所有使用到 `Dio` 的地方进行修改，这个工作量是非常巨大的。

现在，当你基于 `Dio` 封装了一个专门的请求管理器，无论你是升级或是替换 `Dio`，你都只需要修改这个管理器就可以了，相对于这个请求管理器充当了中间件的角色。



### 设计网络请求管理类

![image-20200617180436709](https://w-md.imzsy.design/image-20200617180436709.png)

先来看一下 `index.dart` 文件，这个文件只是将其他的文件进行了导出操作。

```dart
export './abs_network_io.dart';
export './auth_interceptor.dart';
export './api_manager.dart';
export './connectivity_manager.dart';
```

接着来看一看 `abs_network_io`文件

```dart
AbsNetworkIo createAbsNetworkIo(BaseOptions _baseOptions) => AbsNetworkIo(options: _baseOptions);

abstract class AbsNetworkIo {
  factory AbsNetworkIo({BaseOptions options}) => createAbsNetworkIo(options);

  BaseOptions get options;

  void addInterceptor(Interceptor interceptor);
  void enableAuthTokenCheck(AuthTokenListener authTokenListener);
  void responseBodyWrapper(String attributeName);

  void enableLogging({
    bool request = true,
    bool requestHeader = true,
    bool requestBody = false,
    bool responseHeader = true,
    bool responseBody = false,
    bool error = true,
    Function(Object object) logPrint,
  });

  Future<MultipartFile> getMultipartFromFile(String filePath);

  Future<MultipartFile> getMultipartFromBytes(Uint8List bytes,
      [String fileName]);

  Future<ApiResponse<T>> request<T>({
    @required String route,
    @required RequestType requestType,
    Map<String, dynamic> requestParams,
    dynamic requestBody,
    CancelToken cancelToken,
    bool isAuthRequired = false,
    ResponseBodySerializer<T> responseBodySerializer,
    dynamic responseBodyWrapper,
    Options options,
    ProgressCallback onSendProgress,
    ProgressCallback onReceiveProgress,
  });
}

/// contains api status, body data, and error message
class ApiResponse<T> {
  ApiStatus status;
  T data;
  String errorMessage;

  ApiResponse.loading() : status = ApiStatus.LOADING;
  ApiResponse.completed(this.data) : status = ApiStatus.SUCCESS;
  ApiResponse.error(this.errorMessage) : status = ApiStatus.ERROR;

  @override
  String toString() {
    return "Status : $status \n Message : $errorMessage \n Data : $data";
  }
}

/// error body of http response
class ErrorBody {
  String message;
  ErrorBody({this.message});
  factory ErrorBody.fromJson(Map<String, dynamic> jsonMap) {
    return ErrorBody(message: jsonMap['message']);
  }
}

/// enable parsing http response using this [request]
typedef M ResponseBodySerializer<M>(dynamic jsonMap);

/// enable auth token checker by pass this to [enableAuthTokenCheck]
typedef Future<String> AuthTokenListener();

/// Http request type
enum RequestType { GET, POST, PUT, DELETE }

/// Api status state
enum ApiStatus { LOADING, SUCCESS, ERROR }

```

首先，将`AbsNetworkIo`设计为抽象类，定义了项目网络请求的相关配置以及统一的网络请求方式，同时还定义 `APIResponse` 和 `ErrorBody` 类，对返回的结果以及错误进行格式化，配置 `ResponseBodySerializer` 对成功返回数据进行自定义解析等。

再来，看一下`auth_interceptor`这个类的具体实现

```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._authTokenListener);

  AuthTokenListener _authTokenListener;

  @override
  Future onRequest(RequestOptions options) async {
    if (options != null &&
        options.headers.containsKey("isauthrequired") &&
        options.headers["isauthrequired"]) {
      if (_authTokenListener != null) {
        options.headers.remove("isauthrequired");
        String token = await _authTokenListener();
        options.headers.addAll({
          "Authorization": token,
        });
        return options;
      } else {
        print('Ignoring auth token for request');
        return options?.cancelToken?.cancel();
      }
    }
  }
}
```

`Dio`官方文档上，对于**拦截器**有具体的介绍，每个 `Dio` 实例都可以添加任意多个拦截器，他们组成一个队列，拦截器队列的执行顺序是**FIFO**。

通过拦截器你可以在请求之前或响应之后(但还没有被 `then` 或 `catchError`处理)做一些统一的预处理操作。

而在`auth_interceptor`的实现，就是通过继承 `Interceptor` 并重写 `onRequest` 方法，向 **header** 加入 **token**。

`connectivity_manager`文件，主要是通过第三方库`connectivity`监控当前网络环境。

```dart
class ConnectivityManager {
  static isConnected() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.mobile) {
      return true;
    } else if (connectivityResult == ConnectivityResult.wifi) {
      return true;
    }
    return false;
  }
}
```

最后，我们来看一下，最为关键的`api_manager`中具体做了些什么吧

```dart
class ApiManager implements AbsNetworkIo {
  Dio _dio;

  ApiManager({BaseOptions baseOptions}) {
    _dio = Dio(baseOptions);
    _dio.options.connectTimeout = 10000;
    _dio.options.receiveTimeout = 30000;
    _dio.options.headers['content-Type'] = 'application/json';
    _dio.options.headers['Accept'] = 'application/json';
  }

  static const _successCodeList = [200];

  String _responseBodyWrapper;

  @override
  BaseOptions get options {
    return _dio.options;
  }

  @override
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  @override
  void enableAuthTokenCheck(authTokenListener) {
    _dio.interceptors.add(
      AuthInterceptor(authTokenListener),
    );
  }

  @override
  void responseBodyWrapper(String attributeName) {
    _responseBodyWrapper = attributeName;
  }

  @override
  void enableLogging({
    bool request = true,
    bool requestHeader = true,
    bool requestBody = false,
    bool responseHeader = true,
    bool responseBody = false,
    bool error = true,
    Function(Object object) logPrint = print,
  }) {
    _dio.interceptors.add(
      LogInterceptor(
          request: request,
          requestHeader: requestHeader,
          requestBody: requestBody,
          responseHeader: responseHeader,
          responseBody: responseBody,
          error: error,
          logPrint: logPrint),
    );
  }

  @override
  Future<MultipartFile> getMultipartFromFile(String filePath) async {
    String fileName = filePath.split('/').last;
    return await MultipartFile.fromFile(filePath, filename: fileName);
  }

  @override
  Future<MultipartFile> getMultipartFromBytes(Uint8List bytes,
      [String fileName]) async {
    return MultipartFile.fromBytes(bytes, filename: fileName);
  }

  @override
  Future<ApiResponse<T>> request<T>({
    @required String route,
    @required RequestType requestType,
    Map<String, dynamic> requestParams,
    dynamic requestBody,
    CancelToken cancelToken,
    bool isAuthRequired = false,
    ResponseBodySerializer<T> responseBodySerializer,
    dynamic responseBodyWrapper,
    Options options,
    ProgressCallback onSendProgress,
    ProgressCallback onReceiveProgress,
  }) async {
    /// check internet connectivity & return an internet error message
    if (!await ConnectivityManager.isConnected()) {
      return _internetError<T>();
    }

    if (options == null) {
      options = Options();
    }
    options = Options(headers: {"isauthrequired": isAuthRequired});

    try {
      switch (requestType) {

        /// http get request method
        case RequestType.GET:
          final response = await _dio.get(
            route,
            queryParameters: requestParams,
            cancelToken: cancelToken,
            options: options,
            onReceiveProgress: onReceiveProgress,
          );
          return _returnResponse<T>(
            response,
            responseBodySerializer,
            responseBodyWrapper,
          );

        /// http post request method
        case RequestType.POST:
          final response = await _dio.post(
            route,
            data: requestBody,
            queryParameters: requestParams,
            cancelToken: cancelToken,
            options: options,
            onSendProgress: onSendProgress,
            onReceiveProgress: onReceiveProgress,
          );
          return _returnResponse<T>(
            response,
            responseBodySerializer,
            responseBodyWrapper,
          );

        /// http put request method
        case RequestType.PUT:
          final response = await _dio.put(
            route,
            data: requestBody,
            queryParameters: requestParams,
            cancelToken: cancelToken,
            options: options,
            onSendProgress: onSendProgress,
            onReceiveProgress: onReceiveProgress,
          );
          return _returnResponse<T>(
            response,
            responseBodySerializer,
            responseBodyWrapper,
          );

        /// http delete request method
        case RequestType.DELETE:
          final response = await _dio.delete(
            route,
            data: requestBody,
            queryParameters: requestParams,
            cancelToken: cancelToken,
            options: options,
          );
          return _returnResponse<T>(
            response,
            responseBodySerializer,
            responseBodyWrapper,
          );

        /// throw an exception when no http request method is passed
        default:
          throw Exception('No request type passed');
      }
    } on DioError catch (error) {
      print(error.toString());
      return ApiResponse.error(
        error.response == null ? error.message : error.response.toString(),
      );
    }
  }

  /// check the response success status
  /// then wrap the response with api call
  /// return {ApiResponse}
  ApiResponse<T> _returnResponse<T>(
    Response response,
    ResponseBodySerializer<T> responseBodySerializer,
    dynamic responseBodyWrapper,
  ) {
    if (_successCodeList.contains(response.statusCode)) {
      try {
        return ApiResponse.completed(
          responseBodyWrapper is String
              ? responseBodySerializer != null
                  ? responseBodySerializer(response.data[responseBodyWrapper])
                  : response.data[responseBodyWrapper]
              : responseBodyWrapper == false
                  ? responseBodySerializer != null
                      ? responseBodySerializer(response.data)
                      : response.data
                  : _responseBodyWrapper != null
                      ? responseBodySerializer != null
                          ? responseBodySerializer(
                              response.data[_responseBodyWrapper])
                          : response.data[_responseBodyWrapper]
                      : responseBodySerializer != null
                          ? responseBodySerializer(response.data)
                          : response.data,
        );
      } catch (e) {
        print(e);
        return ApiResponse.error("Data Serialization Error: $e");
      }
    } else {
      print('Dio Error: States Code ${response.statusCode}');
      return ApiResponse.error(response.statusMessage);
    }
  }

  ApiResponse<T> _internetError<T>() {
    return ApiResponse.error("Internet not connected");
  }
}

```

通过查看代码，我们可以发现 `ApiManager` 主要是将抽象类 `AbsNetworkIo` 中的方法进行了具体的实现，即 `AbsNetworkIo` 声明方法，`ApiManager` 负责实现。



### 具体使用

至此，基于 `Dio` 的基础封装已经完成，下面来看一下具体的使用示例。

首先定义一个 `ApiRepository` 类配置请求



```dart

const BASE_URL = 'baseUrl';
// 请求配置
class ApiRepository {
  
  static final ApiRepository _instance = ApiRepository._internal(); /// singleton api repository
  ApiManager _apiManager;
  
  factory ApiRepository() {
    return _instance;
  }

  /// base configuration for api manager
  ApiRepository._internal() {
    _apiManager = ApiManager();
    _apiManager.options.baseUrl = BASE_URL; 
    _apiManager.options.connectTimeout = 100000;
    _apiManager.options.receiveTimeout = 100000;
    _apiManager.responseBodyWrapper('data'); 
    _apiManager.enableLogging(responseBody: true, requestBody: false); 
  }

  ApiManager getManager() {
    return _apiManager;
  }
}
```



接着，在具体模型类中，实现具体请求方法，接口 api，返回 body，以及返回 body 的自定义解析。

```dart
class ChatApiResponse {
  ApiManager _apiManager = ApiRepository().getManager();
  Future<ApiResponse<List<ChatDataResponse>>> getRequestChatList() async =>
      await _apiManager.request<List<ChatDataResponse>>(
        requestType: RequestType.GET,
        route: 'chatlist',
        responseBodyWrapper: 'data',
        responseBodySerializer: (jsonMap) {
          return jsonMap.map<ChatDataResponse>((e) => ChatDataResponse.fromJson(e)).toList();
        },
      );
}

class ChatDataResponse {
  final String name;
  final String imgUrl;
  final String message;

  const ChatDataResponse({this.name, this.imgUrl, this.message});

  factory ChatDataResponse.fromJson(Map json) {
    return ChatDataResponse(
      name: json['name'],
      imgUrl: json['imgUrl'],
      message: json['message'],
    );
  }
}

```



最后，只需要调用 `ChatApiResponse().getRequestChatList().then((value) => value.data)`，就可以拿到请求返回并解析成对应模型的数据了。

### 总结

这里具体请求方法，自定义解析放在数据模型类中，是为了让数据模型可以更好的与使用的请求结合在一起，这样也方便去了解和管理，哪个请求返回的结果是对应哪个模型结构。

当然，这个封装的请求库肯定是有所欠缺的，不够完善的，这只是我对于项目的一些基本封装，在后续会根据具体的实际应用再进行优化。