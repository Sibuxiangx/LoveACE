import 'package:dio/dio.dart';
import '../services/logger_service.dart';

/// VPN重定向检测回调函数类型
/// 返回 true 表示静默重登录成功，false 表示失败
typedef VpnRedirectCallback = Future<bool> Function();

/// 重定向回调函数类型（用于捕获重定向URL）
typedef RedirectCallback = void Function(String url);

/// Cookie 存储类，支持域名和路径匹配
class CookieInfo {
  final String name;
  final String value;
  final String? domain;
  final String? path;
  final DateTime? expires;
  final bool httpOnly;
  final bool secure;

  CookieInfo({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.expires,
    this.httpOnly = false,
    this.secure = false,
  });

  /// 检查 Cookie 是否已过期
  bool get isExpired {
    if (expires == null) return false;
    return DateTime.now().isAfter(expires!);
  }

  /// 检查 Cookie 是否匹配指定的域名和路径
  bool matches(String requestDomain, String requestPath) {
    // 检查过期
    if (isExpired) return false;

    // 检查域名匹配
    if (domain != null) {
      // 支持子域名匹配（如 .example.com 匹配 www.example.com）
      if (domain!.startsWith('.')) {
        if (!requestDomain.endsWith(domain!) &&
            requestDomain != domain!.substring(1)) {
          return false;
        }
      } else {
        if (requestDomain != domain) return false;
      }
    }

    // 检查路径匹配
    if (path != null && !requestPath.startsWith(path!)) {
      return false;
    }

    return true;
  }

  @override
  String toString() => '$name=$value';
}

/// HTTP客户端封装类，提供统一的网络请求接口和智能 Cookie 管理
class HTTPClient {
  late Dio _dio;
  final Map<String, List<CookieInfo>> _cookieJar = {};

  /// VPN重定向检测回调
  /// 返回 true 表示静默重登录成功，false 表示失败
  VpnRedirectCallback? onVpnRedirect;

  /// 重定向回调（用于捕获重定向URL，如AAC ticket获取）
  RedirectCallback? onRedirect;

  /// 是否正在处理VPN重定向（防止递归调用）
  bool _isHandlingVpnRedirect = false;

  /// 客户端是否已关闭
  bool _isClosed = false;

  /// 保存初始化参数，用于重建连接
  final String? _baseUrl;
  final int _timeout;

  HTTPClient({
    String? baseUrl,
    int timeout = 30000,
    bool followRedirects = true,
  }) : _baseUrl = baseUrl, _timeout = timeout {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: Duration(milliseconds: timeout),
        receiveTimeout: Duration(milliseconds: timeout),
        sendTimeout: Duration(milliseconds: timeout),
        // 禁用自动重定向，我们手动处理以确保 Cookie 正确传递
        followRedirects: false,
        maxRedirects: 0,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // 添加拦截器用于Cookie管理和日志
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 检查是否已经手动设置了 Cookie 头
          final existingCookie = options.headers['Cookie'];
          final hasManualCookie =
              existingCookie != null && existingCookie.toString().isNotEmpty;

          // 如果没有手动设置 Cookie，才自动添加
          if (!hasManualCookie) {
            // 智能添加匹配的 Cookie 到请求头
            final uri = options.uri;
            final domain = uri.host;
            final path = uri.path;
            final cookies = _getCookiesForRequest(domain, path);

            if (cookies.isNotEmpty) {
              final cookieStr = cookies.join('; ');
              options.headers['Cookie'] = cookieStr;
              LoggerService.info('🍪 发送 Cookies: $cookieStr');
            }
          } else {
            LoggerService.info('🍪 使用手动设置的 Cookie（已隐藏）');
          }

          // 打印请求信息
          LoggerService.info('🌐 ${options.method} ${options.uri}');

          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // 智能提取和存储 Cookie
          final setCookieHeaders = response.headers['set-cookie'];
          if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
            final uri = response.requestOptions.uri;
            final domain = uri.host;
            final path = uri.path;

            for (var cookieStr in setCookieHeaders) {
              _storeCookie(cookieStr, domain, path);
            }
          }

          final statusCode = response.statusCode ?? 0;

          // 打印响应信息
          LoggerService.info('✅ $statusCode ${response.requestOptions.uri}');
          LoggerService.info('📥 Response Headers: ${response.headers}');

          // 打印响应数据（限制长度避免日志过大）
          // 二进制响应（如验证码图片）不打印内容，避免日志泄露
          final responseData = response.requestOptions.responseType == ResponseType.bytes
              ? '<binary>'
              : response.data.toString();
          if (responseData.length > 1000) {
            LoggerService.info(
              '📥 Response Data (truncated): ${responseData.substring(0, 1000)}...',
            );
          } else {
            LoggerService.info('📥 Response Data: $responseData');
          }

          // 处理重定向（302、301、303、307、308）
          if (statusCode >= 301 && statusCode <= 308) {
            final location = response.headers['location']?.first;
            if (location != null && location.isNotEmpty) {
              LoggerService.info('🔄 检测到重定向 ($statusCode): $location');

              // 检查是否是 VPN 会话过期的重定向
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

              // 手动跟随重定向，确保 Cookie 正确传递
              try {
                final redirectResponse = await _followRedirect(
                  location,
                  response.requestOptions,
                  maxRedirects: 8,
                );
                return handler.resolve(redirectResponse);
              } catch (e) {
                LoggerService.error('❌ 跟随重定向失败', error: e);
                return handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: '跟随重定向失败: $e',
                    type: DioExceptionType.unknown,
                  ),
                );
              }
            }
          }

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
            LoggerService.info(
              '❌ Response Headers: ${error.response?.headers}',
            );
            LoggerService.info('❌ Response Data: ${error.response?.data}');
          }

          return handler.next(error);
        },
      ),
    );
  }

  /// 解析 Set-Cookie 头并存储到 Cookie Jar
  void _storeCookie(
    String setCookieStr,
    String defaultDomain,
    String defaultPath,
  ) {
    try {
      // 分割 Cookie 字符串
      final parts = setCookieStr.split(';').map((s) => s.trim()).toList();
      if (parts.isEmpty) return;

      // 解析 name=value
      final nameValue = parts[0].split('=');
      if (nameValue.length != 2) return;

      final name = nameValue[0].trim();
      final value = nameValue[1].trim();

      // 解析 Cookie 属性
      String? domain;
      String? path = defaultPath;
      DateTime? expires;
      bool httpOnly = false;
      bool secure = false;

      for (var i = 1; i < parts.length; i++) {
        final attr = parts[i].toLowerCase();

        if (attr.startsWith('domain=')) {
          domain = attr.substring(7).trim();
        } else if (attr.startsWith('path=')) {
          path = attr.substring(5).trim();
        } else if (attr.startsWith('expires=')) {
          try {
            final dateStr = attr.substring(8).trim();
            expires = DateTime.parse(dateStr);
          } catch (e) {
            // 忽略解析错误
          }
        } else if (attr.startsWith('max-age=')) {
          try {
            final maxAge = int.parse(attr.substring(8).trim());
            expires = DateTime.now().add(Duration(seconds: maxAge));
          } catch (e) {
            // 忽略解析错误
          }
        } else if (attr == 'httponly') {
          httpOnly = true;
        } else if (attr == 'secure') {
          secure = true;
        }
      }

      // 如果没有指定 domain，使用默认域名
      // 对于 VPN 场景，我们需要让 Cookie 在所有 vpn2.aufe.edu.cn 的子域名下共享
      if (domain == null) {
        // 提取主域名（例如从 uaap-aufe-edu-cn.vpn2.aufe.edu.cn 提取 .vpn2.aufe.edu.cn）
        if (defaultDomain.contains('.vpn2.aufe.edu.cn')) {
          domain = '.vpn2.aufe.edu.cn';
        } else {
          domain = defaultDomain;
        }
      } else {
        // 如果域名不以 . 开头，添加 . 以支持子域名
        if (!domain.startsWith('.')) {
          domain = '.$domain';
        }
      }

      // 创建 CookieInfo 对象
      final cookie = CookieInfo(
        name: name,
        value: value,
        domain: domain,
        path: path,
        expires: expires,
        httpOnly: httpOnly,
        secure: secure,
      );

      // 存储到 Cookie Jar（按域名分组）
      final key = domain;
      if (!_cookieJar.containsKey(key)) {
        _cookieJar[key] = [];
      }

      // 移除同名的旧 Cookie
      _cookieJar[key]!.removeWhere((c) => c.name == name && c.path == path);

      // 添加新 Cookie
      _cookieJar[key]!.add(cookie);

      LoggerService.info(
        '🍪 存储 Cookie: $name=$value (domain=$domain, path=$path)',
      );
    } catch (e) {
      LoggerService.error('❌ 解析 Cookie 失败: $setCookieStr', error: e);
    }
  }

  /// 获取匹配请求的所有 Cookie
  List<String> _getCookiesForRequest(String domain, String path) {
    final matchedCookies = <CookieInfo>[];

    // 遍历所有域名的 Cookie
    for (var entry in _cookieJar.entries) {
      final cookieDomain = entry.key;
      final cookies = entry.value;

      // 检查域名是否匹配
      bool domainMatches = false;
      if (cookieDomain.startsWith('.')) {
        // 支持子域名匹配
        domainMatches =
            domain.endsWith(cookieDomain) ||
            domain == cookieDomain.substring(1);
      } else {
        domainMatches = domain == cookieDomain;
      }

      if (domainMatches) {
        // 添加所有匹配的 Cookie
        for (var cookie in cookies) {
          if (cookie.matches(domain, path)) {
            matchedCookies.add(cookie);
          }
        }
      }
    }

    // 清理过期的 Cookie
    _cleanExpiredCookies();

    return matchedCookies.map((c) => c.toString()).toList();
  }

  /// 清理所有过期的 Cookie
  void _cleanExpiredCookies() {
    for (var entry in _cookieJar.entries) {
      entry.value.removeWhere((cookie) => cookie.isExpired);
    }
    // 移除空的域名条目
    _cookieJar.removeWhere((key, value) => value.isEmpty);
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

  /// 手动跟随重定向，确保 Cookie 正确传递到新域名
  Future<Response> _followRedirect(
    String location,
    RequestOptions originalOptions, {
    int maxRedirects = 5,
    int currentRedirect = 0,
  }) async {
    if (currentRedirect >= maxRedirects) {
      throw Exception('重定向次数过多（超过 $maxRedirects 次）');
    }

    // 解析重定向 URL
    Uri redirectUri;
    if (location.startsWith('http://') || location.startsWith('https://')) {
      redirectUri = Uri.parse(location);
    } else {
      // 相对路径，基于原始请求的 URI
      final originalUri = originalOptions.uri;
      if (location.startsWith('/')) {
        // 绝对路径
        redirectUri = Uri(
          scheme: originalUri.scheme,
          host: originalUri.host,
          port: originalUri.port,
          path: location,
        );
      } else {
        // 相对路径
        final basePath = originalUri.path.substring(
          0,
          originalUri.path.lastIndexOf('/') + 1,
        );
        redirectUri = Uri(
          scheme: originalUri.scheme,
          host: originalUri.host,
          port: originalUri.port,
          path: basePath + location,
        );
      }
    }

    LoggerService.info(
      '🔄 跟随重定向 [${currentRedirect + 1}/$maxRedirects]: $redirectUri',
    );

    // 触发重定向回调（用于捕获重定向URL，如AAC ticket）
    if (onRedirect != null) {
      onRedirect!(redirectUri.toString());
    }

    // 获取适用于新域名的 Cookie
    final domain = redirectUri.host;
    final path = redirectUri.path;
    final cookies = _getCookiesForRequest(domain, path);

    // 构建新的请求选项
    final newOptions = Options(
      method: originalOptions.method,
      headers: {
        ...originalOptions.headers,
        if (cookies.isNotEmpty) 'Cookie': cookies.join('; '),
      },
      contentType: originalOptions.contentType,
      responseType: originalOptions.responseType,
      followRedirects: false,
      maxRedirects: 0,
    );

    if (cookies.isNotEmpty) {
      LoggerService.info('🍪 重定向请求携带 Cookies: ${cookies.join('; ')}');
    }

    // 发送重定向请求
    // 注意：不要同时传递完整 URL 和 queryParameters，会导致参数重复
    final response = await _dio.request(
      redirectUri.toString(),
      data: originalOptions.data,
      options: newOptions,
    );

    // 提取新的 Cookie
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
      for (var cookieStr in setCookieHeaders) {
        _storeCookie(cookieStr, domain, path);
      }
    }

    final statusCode = response.statusCode ?? 0;

    // 首先检查当前响应是否为 VPN 会话过期（无论是否继续重定向）
    final vpnRedirectResult = await _checkVpnRedirect(response);
    if (vpnRedirectResult != null) {
      if (vpnRedirectResult) {
        // 静默重登录成功，重试原始请求
        LoggerService.info('✅ 静默重登录成功，重试原始请求');
        try {
          final retryResponse = await _dio.request(
            originalOptions.path,
            data: originalOptions.data,
            queryParameters: originalOptions.queryParameters,
            options: Options(
              method: originalOptions.method,
              headers: originalOptions.headers,
              contentType: originalOptions.contentType,
              responseType: originalOptions.responseType,
              followRedirects: false,
              maxRedirects: 0,
            ),
          );
          // 如果重试后还是重定向，继续跟随
          if ((retryResponse.statusCode ?? 0) >= 301 &&
              (retryResponse.statusCode ?? 0) <= 308) {
            final retryLocation = retryResponse.headers['location']?.first;
            if (retryLocation != null && retryLocation.isNotEmpty) {
              return await _followRedirect(
                retryLocation,
                originalOptions,
                maxRedirects: maxRedirects,
                currentRedirect: 0, // 重置重定向计数
              );
            }
          }
          return retryResponse;
        } catch (e) {
          LoggerService.error('❌ 重试原始请求失败', error: e);
          throw DioException(
            requestOptions: originalOptions,
            error: '重试请求失败: $e',
            type: DioExceptionType.unknown,
          );
        }
      } else {
        // 静默重登录失败
        throw DioException(
          requestOptions: originalOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'VPN会话已过期，需要重新登录',
        );
      }
    }

    // 如果还是重定向，继续跟随
    if (statusCode >= 301 && statusCode <= 308) {
      final newLocation = response.headers['location']?.first;
      if (newLocation != null && newLocation.isNotEmpty) {
        return await _followRedirect(
          newLocation,
          originalOptions,
          maxRedirects: maxRedirects,
          currentRedirect: currentRedirect + 1,
        );
      }
    }

    return response;
  }

  /// GET请求
  Future<Response> get(
    String path, {
    Map<String, dynamic>? params,
    Options? options,
  }) async {
    _ensureNotClosed();
    return await _dio.get(path, queryParameters: params, options: options);
  }

  /// POST请求
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

  /// 手动设置 Cookie（简化版，用于兼容旧代码）
  void setCookie(String name, String value, {String? domain, String? path}) {
    final cookie = CookieInfo(
      name: name,
      value: value,
      domain: domain,
      path: path ?? '/',
    );

    final key = domain ?? 'default';
    if (!_cookieJar.containsKey(key)) {
      _cookieJar[key] = [];
    }

    // 移除同名的旧 Cookie
    _cookieJar[key]!.removeWhere(
      (c) => c.name == name && c.path == (path ?? '/'),
    );

    // 添加新 Cookie
    _cookieJar[key]!.add(cookie);

    LoggerService.info(
      '🍪 手动设置 Cookie: $name=$value (domain=$domain, path=$path)',
    );
  }

  /// 获取指定名称的 Cookie 值（从所有域名中查找）
  String? getCookie(String name) {
    for (var cookies in _cookieJar.values) {
      for (var cookie in cookies) {
        if (cookie.name == name && !cookie.isExpired) {
          return cookie.value;
        }
      }
    }
    return null;
  }

  /// 获取指定域名和路径的 Cookie
  String? getCookieForDomain(String name, String domain, {String path = '/'}) {
    final cookies = _cookieJar[domain];
    if (cookies == null) return null;

    for (var cookie in cookies) {
      if (cookie.name == name && cookie.matches(domain, path)) {
        return cookie.value;
      }
    }
    return null;
  }

  /// 获取所有 Cookie（简化格式，用于兼容旧代码）
  Map<String, String> getAllCookies() {
    final result = <String, String>{};
    for (var cookies in _cookieJar.values) {
      for (var cookie in cookies) {
        if (!cookie.isExpired) {
          result[cookie.name] = cookie.value;
        }
      }
    }
    return result;
  }

  /// 获取所有 Cookie 的详细信息
  Map<String, List<CookieInfo>> getAllCookiesDetailed() {
    _cleanExpiredCookies();
    return Map.from(_cookieJar);
  }

  /// 清除所有 Cookie
  void clearCookies() {
    _cookieJar.clear();
    LoggerService.info('🍪 已清除所有 Cookies');
  }

  /// 清除指定域名的 Cookie
  void clearCookiesForDomain(String domain) {
    _cookieJar.remove(domain);
    LoggerService.info('🍪 已清除域名 $domain 的 Cookies');
  }

  /// 清除指定名称的 Cookie（从所有域名中删除）
  void clearCookie(String name) {
    for (var cookies in _cookieJar.values) {
      cookies.removeWhere((cookie) => cookie.name == name);
    }
    LoggerService.info('🍪 已清除 Cookie: $name');
  }

  /// 从另一个 HTTPClient 复制所有 Cookie
  void copyCookiesFrom(HTTPClient other) {
    _cookieJar.clear();
    final otherCookies = other.getAllCookiesDetailed();
    for (var entry in otherCookies.entries) {
      _cookieJar[entry.key] = List.from(entry.value);
    }
    LoggerService.info('🍪 已从另一个客户端复制 Cookies');
  }

  /// 导出 Cookie 为 JSON 格式（用于持久化）
  Map<String, dynamic> exportCookies() {
    final result = <String, dynamic>{};
    for (var entry in _cookieJar.entries) {
      result[entry.key] = entry.value
          .map(
            (cookie) => {
              'name': cookie.name,
              'value': cookie.value,
              'domain': cookie.domain,
              'path': cookie.path,
              'expires': cookie.expires?.toIso8601String(),
              'httpOnly': cookie.httpOnly,
              'secure': cookie.secure,
            },
          )
          .toList();
    }
    return result;
  }

  /// 从 JSON 格式导入 Cookie（用于恢复持久化数据）
  void importCookies(Map<String, dynamic> data) {
    _cookieJar.clear();
    for (var entry in data.entries) {
      final domain = entry.key;
      final cookiesList = entry.value as List;

      _cookieJar[domain] = cookiesList.map((cookieData) {
        return CookieInfo(
          name: cookieData['name'] as String,
          value: cookieData['value'] as String,
          domain: cookieData['domain'] as String?,
          path: cookieData['path'] as String?,
          expires: cookieData['expires'] != null
              ? DateTime.parse(cookieData['expires'] as String)
              : null,
          httpOnly: cookieData['httpOnly'] as bool? ?? false,
          secure: cookieData['secure'] as bool? ?? false,
        );
      }).toList();
    }
    LoggerService.info('🍪 已导入 Cookies');
  }

  /// 获取 Cookie 统计信息
  Map<String, int> getCookieStats() {
    _cleanExpiredCookies();
    return {
      'totalDomains': _cookieJar.length,
      'totalCookies': _cookieJar.values.fold(
        0,
        (sum, list) => sum + list.length,
      ),
    };
  }

  /// 关闭客户端
  void close() {
    _isClosed = true;
    _dio.close();
  }

  /// 检查并确保连接可用，如果已关闭则重建
  void _ensureNotClosed() {
    if (_isClosed) {
      LoggerService.info('🔄 HTTPClient 已关闭，正在重建连接...');
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
        followRedirects: false,
        maxRedirects: 0,
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
          final existingCookie = options.headers['Cookie'];
          final hasManualCookie =
              existingCookie != null && existingCookie.toString().isNotEmpty;

          if (!hasManualCookie) {
            final uri = options.uri;
            final domain = uri.host;
            final path = uri.path;
            final cookies = _getCookiesForRequest(domain, path);

            if (cookies.isNotEmpty) {
              final cookieStr = cookies.join('; ');
              options.headers['Cookie'] = cookieStr;
              LoggerService.info('🍪 发送 Cookies: $cookieStr');
            }
          } else {
            LoggerService.info('🍪 使用手动设置的 Cookie（已隐藏）');
          }

          LoggerService.info('🌐 ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          final setCookieHeaders = response.headers['set-cookie'];
          if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
            final uri = response.requestOptions.uri;
            final domain = uri.host;
            final path = uri.path;

            for (var cookieStr in setCookieHeaders) {
              _storeCookie(cookieStr, domain, path);
            }
          }

          final statusCode = response.statusCode ?? 0;
          LoggerService.info('✅ $statusCode ${response.requestOptions.uri}');

          if (statusCode >= 301 && statusCode <= 308) {
            final location = response.headers['location']?.first;
            if (location != null && location.isNotEmpty) {
              LoggerService.info('🔄 检测到重定向 ($statusCode): $location');

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

              try {
                final redirectResponse = await _followRedirect(
                  location,
                  response.requestOptions,
                  maxRedirects: 8,
                );
                return handler.resolve(redirectResponse);
              } catch (e) {
                LoggerService.error('❌ 跟随重定向失败', error: e);
                return handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: '跟随重定向失败: $e',
                    type: DioExceptionType.unknown,
                  ),
                );
              }
            }
          }

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

  /// 获取Dio实例（用于高级操作）
  Dio get dio {
    _ensureNotClosed();
    return _dio;
  }
}
