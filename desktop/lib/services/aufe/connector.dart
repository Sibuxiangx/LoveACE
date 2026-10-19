import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';
import '../../models/aufe/login_status.dart';
import '../../services/http_client.dart';
import '../../services/simple_http_client.dart';
import '../../utils/retry_handler.dart';
import 'aufe_config.dart';
import '../../services/logger_service.dart';

/// AUFE教务系统连接类
class AUFEConnection {
  final String userId;
  final String ecPassword;
  final String password;

  late HTTPClient _client;
  late HTTPClient _clientNoRedirect;
  late SimpleHTTPClient _simpleClient; // 简单客户端，用于 AAC 等服务
  String? _twfId;
  bool _ecLogged = false;
  bool _uaapLogged = false;
  DateTime _lastCheck = DateTime.now();

  // 配置常量
  static const String serverUrl = AUFEConnectorConstants.serverUrl;
  static const String ecCheckUrl = AUFEConnectorConstants.ecCheckUrl;
  static const String uaapCheckUrl = AUFEConnectorConstants.uaapCheckUrl;
  static const String uaapLoginUrl = AUFEConnectorConstants.uaapLoginUrl;
  static const int timeout = AUFEConnectorConstants.defaultTimeout;

  AUFEConnection({
    required this.userId,
    required this.ecPassword,
    required this.password,
  });

  /// 获取TwfID
  String? get twfId => _twfId;

  /// 初始化HTTP客户端
  void startClient({Future<bool> Function()? onVpnRedirect}) {
    _client = HTTPClient(
      baseUrl: serverUrl,
      timeout: timeout,
      followRedirects: true,
    );
    _clientNoRedirect = HTTPClient(
      baseUrl: serverUrl,
      timeout: timeout,
      followRedirects: false,
    );
    _simpleClient = SimpleHTTPClient(baseUrl: serverUrl, timeout: timeout);

    // 设置VPN重定向回调
    if (onVpnRedirect != null) {
      _client.onVpnRedirect = onVpnRedirect;
      _clientNoRedirect.onVpnRedirect = onVpnRedirect;
      _simpleClient.onVpnRedirect = onVpnRedirect;
    }
  }

  /// EC系统登录（RSA加密）
  Future<ECLoginStatus> ecLogin() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performEcLogin(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      return ECLoginStatus(failUnknownError: true);
    }
  }

  Future<ECLoginStatus> _performEcLogin() async {
    try {
      // 1. 获取认证参数
      final response = await _client.get(
        '$serverUrl/por/login_auth.csp?apiversion=1',
      );
      final responseText = response.data.toString();

      // 2. 提取TwfID
      final twfIdMatch = RegExp(
        r'<TwfID>(.*?)</TwfID>',
      ).firstMatch(responseText);
      if (twfIdMatch == null) {
        return ECLoginStatus(failNotFoundTwfid: true);
      }
      _twfId = twfIdMatch.group(1);

      // 3. 提取RSA密钥
      final rsaKeyMatch = RegExp(
        r'<RSA_ENCRYPT_KEY>(.*?)</RSA_ENCRYPT_KEY>',
      ).firstMatch(responseText);
      if (rsaKeyMatch == null) {
        return ECLoginStatus(failNotFoundRsaKey: true);
      }
      final rsaKey = rsaKeyMatch.group(1)!;

      // 4. 提取RSA指数
      final rsaExpMatch = RegExp(
        r'<RSA_ENCRYPT_EXP>(.*?)</RSA_ENCRYPT_EXP>',
      ).firstMatch(responseText);
      if (rsaExpMatch == null) {
        return ECLoginStatus(failNotFoundRsaExp: true);
      }
      final rsaExp = rsaExpMatch.group(1)!;

      // 5. 提取CSRF代码
      final csrfMatch = RegExp(
        r'<CSRF_RAND_CODE>(.*?)</CSRF_RAND_CODE>',
      ).firstMatch(responseText);
      if (csrfMatch == null) {
        return ECLoginStatus(failNotFoundCsrfCode: true);
      }
      final csrfCode = csrfMatch.group(1)!;

      // 6. RSA加密密码
      final passwordToEncrypt = '${ecPassword}_$csrfCode';
      final encryptedPassword = _rsaEncrypt(passwordToEncrypt, rsaKey, rsaExp);

      // 7. 执行登录
      final loginResponse = await _client.post(
        '$serverUrl/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs',
        data: {
          'svpn_rand_code': '',
          'mitm': '',
          'svpn_req_randcode': csrfCode,
          'svpn_name': userId,
          'svpn_password': encryptedPassword,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Cookie': 'TWFID=$_twfId'},
        ),
      );

      final loginResponseText = loginResponse.data.toString();

      // 8. 检查登录结果
      if (loginResponseText.contains('<Result>1</Result>')) {
        _client.setCookie('TWFID', _twfId!);
        _ecLogged = true;
        // 同步Cookie到无重定向客户端和简单客户端
        _clientNoRedirect.copyCookiesFrom(_client);
        _simpleClient.copyCookiesFromHTTPClient(_client.getAllCookies());
        return ECLoginStatus(success: true);
      } else if (loginResponseText.contains('Invalid username or password!')) {
        return ECLoginStatus(failInvalidCredentials: true);
      } else if (loginResponseText.contains('[CDATA[maybe attacked]]') ||
          loginResponseText.contains('CAPTCHA required')) {
        return ECLoginStatus(failMaybeAttacked: true);
      } else {
        return ECLoginStatus(failUnknownError: true);
      }
    } on DioException {
      return ECLoginStatus(failNetworkError: true);
    } catch (e) {
      return ECLoginStatus(failUnknownError: true);
    }
  }

  /// RSA加密
  String _rsaEncrypt(String plaintext, String modulusHex, String exponentStr) {
    // 解析模数和指数
    final modulus = BigInt.parse(modulusHex, radix: 16);
    final exponent = BigInt.parse(exponentStr);

    // 创建RSA公钥
    final publicKey = RSAPublicKey(modulus, exponent);

    // 创建加密器
    final encryptor = PKCS1Encoding(RSAEngine());
    encryptor.init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    // 加密
    final plainBytes = utf8.encode(plaintext);
    final encrypted = encryptor.process(Uint8List.fromList(plainBytes));

    // 转换为十六进制字符串
    return encrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// UAAP系统登录（DES加密）
  Future<UAAPLoginStatus> uaapLogin() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performUaapLogin(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      return UAAPLoginStatus(failUnknownError: true);
    }
  }

  Future<UAAPLoginStatus> _performUaapLogin() async {
    try {
      // 1. 获取登录页面
      final response = await _client.get(uaapLoginUrl);
      final responseText = response.data.toString();

      // 2. 提取lt参数
      final ltMatch = RegExp(
        r'name="lt" value="(.*?)"',
      ).firstMatch(responseText);
      if (ltMatch == null) {
        return UAAPLoginStatus(failNotFoundLt: true);
      }
      final ltValue = ltMatch.group(1)!;

      // 3. 提取execution参数
      final executionMatch = RegExp(
        r'name="execution" value="(.*?)"',
      ).firstMatch(responseText);
      if (executionMatch == null) {
        return UAAPLoginStatus(failNotFoundExecution: true);
      }
      final executionValue = executionMatch.group(1)!;

      // 4. DES加密密码
      final encryptedPassword = _desEncrypt(password, ltValue);

      // 5. 提交登录表单
      // 注意：HTTPClient 会自动跟随重定向，所以最终会返回目标页面的内容
      final loginResponse = await _client.post(
        uaapLoginUrl,
        data: {
          'username': userId,
          'password': encryptedPassword,
          'lt': ltValue,
          'execution': executionValue,
          '_eventId': 'submit',
          'submit': 'LOGIN',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (status) => status! < 500,
        ),
      );

      // 6. 检查登录结果
      final statusCode = loginResponse.statusCode ?? 0;
      final loginResponseText = loginResponse.data.toString();
      final responseUrl = loginResponse.realUri.toString();

      LoggerService.info('🔐 UAAP login response status: $statusCode');
      LoggerService.info('🔐 UAAP login response URL: $responseUrl');

      // 学校强制改密：TGT 已铸出（密码正确）但 CAS 不签发票据，302 到改密页面。
      // 必须先于"密码错误"判定；正常返回状态值（不抛异常），避免 RetryHandler 自动重试。
      if (responseUrl.contains('/mng/acp/completeInfo/password')) {
        LoggerService.warning('🏫 UAAP login intercepted: password change required');
        return UAAPLoginStatus(failPasswordChangeRequired: true);
      }

      // 检查是否登录失败（用户名或密码错误）
      if (loginResponseText.contains('Invalid username or password') ||
          loginResponseText.contains('用户名或密码错误') ||
          loginResponseText.contains('errorMsg')) {
        return UAAPLoginStatus(failInvalidCredentials: true);
      }

      // 检查是否成功重定向到目标系统（JWC）
      // 成功的标志：
      // 1. 状态码为 200
      // 2. URL 包含目标系统域名（如 jwcxk2）
      // 3. 响应内容包含目标系统的特征（如 "URP综合教务系统"）
      if (statusCode == 200) {
        final isJwcPage = responseUrl.startsWith('http://jwcxk2');

        if (isJwcPage) {
          LoggerService.info('✅ UAAP login successful, redirected to JWC');
          _uaapLogged = true;
          // 同步Cookie到无重定向客户端
          _clientNoRedirect.copyCookiesFrom(_client);
          _simpleClient.copyCookiesFromHTTPClient(_client.getAllCookies());
          return UAAPLoginStatus(success: true);
        }
      }

      // 如果响应中包含 ticket 参数，说明登录成功但还需要完成 CAS 认证
      if (responseUrl.contains('ticket=')) {
        LoggerService.info('✅ UAAP login successful with ticket');
        _uaapLogged = true;
        // 同步Cookie到无重定向客户端
        _clientNoRedirect.copyCookiesFrom(_client);
        return UAAPLoginStatus(success: true);
      }

      // 其他情况视为登录失败
      LoggerService.warning(
        '⚠️ UAAP login result unclear, treating as failure',
      );
      return UAAPLoginStatus(failUnknownError: true);
    } on DioException {
      return UAAPLoginStatus(failNetworkError: true);
    } catch (e) {
      return UAAPLoginStatus(failUnknownError: true);
    }
  }

  /// DES加密（使用TripleDES ECB模式）
  String _desEncrypt(String plaintext, String key) {
    // 处理密钥 - 取前8字节
    var keyBytes = utf8.encode(key);
    if (keyBytes.length > 8) {
      keyBytes = keyBytes.sublist(0, 8);
    } else if (keyBytes.length < 8) {
      // 不足8字节用0填充
      keyBytes = Uint8List(8)..setRange(0, keyBytes.length, keyBytes);
    }

    // 创建DES密钥（TripleDES使用相同的8字节密钥重复3次）
    final desKey = KeyParameter(
      Uint8List(24)
        ..setRange(0, 8, keyBytes)
        ..setRange(8, 16, keyBytes)
        ..setRange(16, 24, keyBytes),
    );

    // 创建加密器
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), DESedeEngine());
    cipher.init(true, PaddedBlockCipherParameters(desKey, null));

    // 加密
    final plainBytes = utf8.encode(plaintext);
    final encrypted = cipher.process(Uint8List.fromList(plainBytes));

    // Base64编码
    return base64.encode(encrypted);
  }

  /// 检查EC登录状态
  Future<ECCheckStatus> checkEcLoginStatus() async {
    if (!_ecLogged) {
      return ECCheckStatus(loggedIn: false);
    }

    try {
      final response = await _client.get(ecCheckUrl);
      if (response.statusCode == 200) {
        return ECCheckStatus(loggedIn: true);
      } else {
        return ECCheckStatus(loggedIn: false);
      }
    } on DioException {
      return ECCheckStatus(failNetworkError: true);
    } catch (e) {
      return ECCheckStatus(failUnknownError: true);
    }
  }

  /// 检查UAAP登录状态
  Future<ECCheckStatus> checkUaapLoginStatus() async {
    return ECCheckStatus(loggedIn: _uaapLogged);
  }

  /// 健康检查
  Future<bool> healthCheck() async {
    final delta = DateTime.now().difference(_lastCheck);

    // 5分钟未检查则视为不健康
    if (delta.inSeconds > 300) {
      return false;
    }

    // 检查UAAP登录状态
    final uaapStatus = await checkUaapLoginStatus();
    if (!uaapStatus.isLoggedIn) {
      return false;
    }

    // 检查EC登录状态
    final ecStatus = await checkEcLoginStatus();
    if (!ecStatus.isLoggedIn) {
      return false;
    }

    return true;
  }

  /// 更新健康检查时间戳
  void healthCheckpoint() {
    _lastCheck = DateTime.now();
  }

  /// 获取HTTP客户端实例（带自动重定向）
  HTTPClient get client => _client;

  /// 获取HTTP客户端实例（不带自动重定向）
  HTTPClient get clientNoRedirect => _clientNoRedirect;

  /// 获取简单HTTP客户端实例（用于AAC等服务）
  SimpleHTTPClient get simpleClient => _simpleClient;

  /// 关闭连接
  Future<void> close() async {
    _client.close();
    _clientNoRedirect.close();
    _simpleClient.close();
  }
}
