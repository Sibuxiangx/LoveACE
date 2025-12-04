import 'package:dio/dio.dart';
import '../services/logger_service.dart';

/// VPN重定向检测回调函数类型
/// 返回 true 表示静默重登录成功，false 表示失败
typedef SimpleVpnRedirectCallback = Future<bool> Function();

/// 简单的 HTTP 客户端（使用 Dio 自动重定向，简单的 Cookie 管理）
/// 用于 AAC 等不需要复杂 Cookie 管理的服务
class SimpleHTTPClient {
  late Dio _dio;
  final Map<String, String> _cookies = {};

  /// VPN重定向检测回调
  SimpleVpnRedirectCallback? onVpnRedirect;

  /// 是否正在处理VPN重定向（防止递归调用）
  bool _isHandlingVpnRedirect = false;

  /// 客户端是否已关闭
  bool _isClosed = false;

  /// 保存初始化参数，用于重建连接
  final String? _baseUrl;
  final int _timeout;

  SimpleHTTPClient({String? baseUrl, int timeout = 30000})
      : _baseUrl = baseUrl,
        _timeout = timeout {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: Duration(milliseconds: timeout),
        receiveTimeout: Duration(milliseconds: timeout),
        sendTimeout: Duration(milliseconds: timeout),
        followRedirects: true, // 使用 Dio 自动重定向
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // 添加拦截器用于 Cookie 管理和日志
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 添加 Cookie 到请求头
          if (_cookies.isNotEmpty) {
            final cookieStr = _cookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
            options.headers['Cookie'] = cookieStr;
          }

          // 打印请求信息
          LoggerService.info('🌐 ${options.method} ${options.uri}');

          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // 从响应中提取 Cookie
          final setCookie = response.headers['set-cookie'];
          if (setCookie != null) {
            for (var cookie in setCookie) {
              _parseCookie(cookie);
            }
          }

          final statusCode = response.statusCode ?? 0;

          // 打印响应信息
          LoggerService.info('✅ $statusCode ${response.requestOptions.uri}');

          // 检测VPN重定向（检查响应内容）
          final vpnRedirectResult = await _checkVpnRedirect(response);
          if (vpnRedirectResult != null) {
            // VPN会话过期
            if (vpnRedirectResult) {
              // 静默重登录成功，重试原始请求
              LoggerService.info('✅ 静默重登录成功，重试原始请求');
              try {
                final retryResponse = await _dio.request(
                  response.requestOptions.path,
                  data: response.requestOptions.data,
                  queryParameters: response.requestOptions.queryParameters,
                  options: Options(
                    method: response.requestOptions.method,
                    headers: response.requestOptions.headers,
                    contentType: response.requestOptions.contentType,
                    responseType: response.requestOptions.responseType,
                  ),
                );
                return handler.resolve(retryResponse);
              } catch (e) {
                LoggerService.error('❌ 重试原始请求失败', error: e);
                return handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: '重试请求失败: $e',
                    type: DioExceptionType.unknown,
                  ),
                );
              }
            } else {
              // 静默重登录失败，返回错误
              LoggerService.warning('🚨 VPN会话已过期，静默重登录失败');
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  type: DioExceptionType.badResponse,
                  error: 'VPN会话已过期，需要重新登录',
                ),
              );
            }
          }

          return handler.next(response);
        },
        onError: (error, handler) {
          LoggerService.info('❌ HTTP Error: ${error.message}');
          LoggerService.info('❌ Error type: ${error.type}');
          LoggerService.info(
            '❌ Request: ${error.requestOptions.method} ${error.requestOptions.uri}',
          );

          if (error.response != null) {
            LoggerService.info('❌ Status code: ${error.response?.statusCode}');
          }

          return handler.next(error);
        },
      ),
    );
  }

  /// 解析 Cookie 字符串并存储
  void _parseCookie(String cookieStr) {
    final parts = cookieStr.split(';')[0].split('=');
    if (parts.length == 2) {
      _cookies[parts[0].trim()] = parts[1].trim();
    }
  }

  /// GET 请求
  Future<Response> get(
    String path, {
    Map<String, dynamic>? params,
    Options? options,
  }) async {
    _ensureNotClosed();
    return await _dio.get(path, queryParameters: params, options: options);
  }

  /// POST 请求
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _ensureNotClosed();
    return await _dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// 设置 Cookie
  void setCookie(String name, String value) {
    _cookies[name] = value;
  }

  /// 获取 Cookie
  String? getCookie(String name) {
    return _cookies[name];
  }

  /// 获取所有 Cookie
  Map<String, String> getAllCookies() {
    return Map.from(_cookies);
  }

  /// 清除所有 Cookie
  void clearCookies() {
    _cookies.clear();
  }

  /// 从另一个 SimpleHTTPClient 复制所有 Cookie
  void copyCookiesFrom(SimpleHTTPClient other) {
    _cookies.clear();
    _cookies.addAll(other.getAllCookies());
  }

  /// 从 HTTPClient 复制所有 Cookie
  void copyCookiesFromHTTPClient(Map<String, String> cookies) {
    _cookies.clear();
    _cookies.addAll(cookies);
  }

  /// 检测VPN重定向并触发回调
  /// 返回 null 表示正常响应（未检测到VPN重定向）
  /// 返回 true 表示检测到VPN重定向且静默重登录成功
  /// 返回 false 表示检测到VPN重定向但静默重登录失败
  Future<bool?> _checkVpnRedirect(Response response) async {
    // 防止递归调用
    if (_isHandlingVpnRedirect) {
      return null;
    }

    try {
      final statusCode = response.statusCode ?? 0;
      final responseUrl = response.realUri.toString();
      final responseData = response.data?.toString() ?? '';

      bool isVpnRedirect = false;

      // 方法1: 检查302状态码和Location头
      if (statusCode == 302) {
        final location = response.headers['location']?.first ?? '';
        if (location.contains('vpn2.aufe.edu.cn:443') &&
            location.contains('redirect_uri=')) {
          LoggerService.warning('🚨 检测到VPN重定向 (302): $location');
          isVpnRedirect = true;
        }
      }

      // 方法2: 检查响应URL是否包含VPN重定向特征
      if (!isVpnRedirect &&
          responseUrl.contains('vpn2.aufe.edu.cn:443') &&
          responseUrl.contains('redirect_uri=')) {
        LoggerService.warning('🚨 检测到VPN重定向 (URL): $responseUrl');
        isVpnRedirect = true;
      }

      // 方法3: 检查响应内容是否为VPN登录页面HTML
      if (!isVpnRedirect &&
          (responseData.contains('<title>302 Found</title>') ||
              responseData.contains('Sangine') ||
              (responseData.contains('<html>') &&
                  responseData.contains('302 Found')))) {
        LoggerService.warning('🚨 检测到VPN重定向 (HTML内容)');
        isVpnRedirect = true;
      }

      if (!isVpnRedirect && responseData.contains('class="sangfor-main"')) {
        LoggerService.warning('🚨 检测到 Sangfor (HTML内容)');
        isVpnRedirect = true;
      }

      if (isVpnRedirect) {
        // 触发VPN重定向回调，尝试静默重登录
        return await _triggerVpnRedirect();
      }

      return null;
    } catch (e) {
      LoggerService.error('❌ 检测VPN重定向时出错', error: e);
      return null;
    }
  }

  /// 触发VPN重定向回调
  /// 返回 true 表示静默重登录成功，false 表示失败
  Future<bool> _triggerVpnRedirect() async {
    if (onVpnRedirect == null) {
      LoggerService.warning('⚠️ 未设置VPN重定向回调');
      return false;
    }

    try {
      _isHandlingVpnRedirect = true;
      LoggerService.info('🔄 触发VPN重定向回调，尝试静默重登录...');
      final success = await onVpnRedirect!();
      LoggerService.info(success ? '✅ 静默重登录成功' : '❌ 静默重登录失败');
      return success;
    } catch (e) {
      LoggerService.error('❌ VPN重定向回调执行失败', error: e);
      return false;
    } finally {
      _isHandlingVpnRedirect = false;
    }
  }

  /// 关闭客户端
  void close() {
    _isClosed = true;
    _dio.close();
  }

  /// 检查并确保连接可用，如果已关闭则重建
  void _ensureNotClosed() {
    if (_isClosed) {
      LoggerService.info('🔄 SimpleHTTPClient 已关闭，正在重建连接...');
      _rebuildDio();
      _isClosed = false;
    }
  }

  /// 重建 Dio 实例
  void _rebuildDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl ?? '',
        connectTimeout: Duration(milliseconds: _timeout),
        receiveTimeout: Duration(milliseconds: _timeout),
        sendTimeout: Duration(milliseconds: _timeout),
        followRedirects: true,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    _setupInterceptors();
  }

  /// 设置拦截器（抽取为单独方法以便重建时复用）
  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_cookies.isNotEmpty) {
            final cookieStr = _cookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
            options.headers['Cookie'] = cookieStr;
          }
          LoggerService.info('🌐 ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          final setCookie = response.headers['set-cookie'];
          if (setCookie != null) {
            for (var cookie in setCookie) {
              _parseCookie(cookie);
            }
          }

          final statusCode = response.statusCode ?? 0;
          LoggerService.info('✅ $statusCode ${response.requestOptions.uri}');

          final vpnRedirectResult = await _checkVpnRedirect(response);
          if (vpnRedirectResult != null) {
            if (vpnRedirectResult) {
              LoggerService.info('✅ 静默重登录成功，重试原始请求');
              try {
                final retryResponse = await _dio.request(
                  response.requestOptions.path,
                  data: response.requestOptions.data,
                  queryParameters: response.requestOptions.queryParameters,
                  options: Options(
                    method: response.requestOptions.method,
                    headers: response.requestOptions.headers,
                    contentType: response.requestOptions.contentType,
                    responseType: response.requestOptions.responseType,
                  ),
                );
                return handler.resolve(retryResponse);
              } catch (e) {
                LoggerService.error('❌ 重试原始请求失败', error: e);
                return handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: '重试请求失败: $e',
                    type: DioExceptionType.unknown,
                  ),
                );
              }
            } else {
              LoggerService.warning('🚨 VPN会话已过期，静默重登录失败');
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  type: DioExceptionType.badResponse,
                  error: 'VPN会话已过期，需要重新登录',
                ),
              );
            }
          }

          return handler.next(response);
        },
        onError: (error, handler) {
          LoggerService.info('❌ HTTP Error: ${error.message}');
          LoggerService.info('❌ Error type: ${error.type}');
          LoggerService.info(
            '❌ Request: ${error.requestOptions.method} ${error.requestOptions.uri}',
          );

          if (error.response != null) {
            LoggerService.info('❌ Status code: ${error.response?.statusCode}');
          }

          return handler.next(error);
        },
      ),
    );
  }

  /// 获取 Dio 实例（用于高级操作）
  Dio get dio {
    _ensureNotClosed();
    return _dio;
  }
}
