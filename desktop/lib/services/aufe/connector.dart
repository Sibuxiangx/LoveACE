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

/// EC 验证码待提交上下文：取图时的认证页参数（仅内存保存，单次有效，不得记录日志）
class _EcAuthContext {
  final String twfId;
  final String csrfCode;
  final String rsaKey;
  final String rsaExp;
  /// 学校是否要求验证码（RndImg == 1）
  final bool rndImg;
  final DateTime createdAt;

  _EcAuthContext({
    required this.twfId,
    required this.csrfCode,
    required this.rsaKey,
    required this.rsaExp,
    required this.rndImg,
  }) : createdAt = DateTime.now();
}

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

  /// 验证码待提交上下文（取图时保存，提交后或过期即清除）
  _EcAuthContext? _pendingCaptcha;

  /// 验证码上下文有效期
  static const Duration _captchaContextTtl = Duration(seconds: 180);

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
  ///
  /// [captchaCode] 为空表示尚未输入验证码：学校要求验证码时返回 captchaRequired 并附带图片，不提交密码。
  /// 非空时使用最近一次取得图片时保存的认证上下文提交（单次有效）。
  Future<ECLoginStatus> ecLogin({String? captchaCode}) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performEcLogin(captchaCode),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      return ECLoginStatus(failUnknownError: true);
    }
  }

  Future<ECLoginStatus> _performEcLogin(String? captchaCode) async {
    try {
      if (captchaCode != null && captchaCode.isNotEmpty) {
        final pending = _takePendingCaptcha();
        if (pending == null) {
          // 无有效上下文：不提交，重新获取认证页与验证码
          return await _startCaptchaChallenge();
        }
        // 上下文取出即失效（单次有效），无论提交结果如何都不复用
        return await _finishEcLogin(await _submitEcLogin(pending, captchaCode));
      }

      // 无验证码：先取认证页
      _pendingCaptcha = null;
      final page = await _fetchEcAuth();
      if (page.failure != null) return page.failure!;
      final auth = page.auth!;
      if (auth.rndImg) {
        // 学校要求验证码：不提交密码，直接取图片
        return await _captchaChallenge(auth);
      }
      return await _finishEcLogin(await _submitEcLogin(auth, null));
    } on DioException {
      return ECLoginStatus(failNetworkError: true);
    } catch (e) {
      return ECLoginStatus(failUnknownError: true);
    }
  }

  /// 取新的认证页与验证码（不提交密码）
  Future<ECLoginStatus> _startCaptchaChallenge() async {
    final page = await _fetchEcAuth();
    if (page.failure != null) return page.failure!;
    final auth = page.auth!;
    if (!auth.rndImg) return ECLoginStatus(failUnknownError: true);
    return await _captchaChallenge(auth);
  }

  /// 拉取验证码图片，并保存待提交上下文（图片与上下文绑定同一 TWFID）
  Future<ECLoginStatus> _captchaChallenge(_EcAuthContext auth) async {
    final image = await _fetchCaptchaImage(auth.twfId);
    if (image.isEmpty) return ECLoginStatus(failUnknownError: true);
    _pendingCaptcha = auth;
    LoggerService.info('🖼️ 学校要求验证码，已获取验证码图片');
    return ECLoginStatus(captchaRequired: true, captchaImage: image);
  }

  /// 提交结果为需要验证码时，重新取认证页与图片，保证 captchaRequired 总是附带图片
  Future<ECLoginStatus> _finishEcLogin(ECLoginStatus status) async {
    if (status.captchaRequired) return await _startCaptchaChallenge();
    return status;
  }

  /// 取出待提交上下文：单次有效，过期视为不存在
  _EcAuthContext? _takePendingCaptcha() {
    final pending = _pendingCaptcha;
    _pendingCaptcha = null;
    if (pending == null) return null;
    if (DateTime.now().difference(pending.createdAt) > _captchaContextTtl) {
      return null;
    }
    return pending;
  }

  /// 获取验证码图片（GET /por/rand_code.csp，绑定认证页的 TWFID）
  Future<Uint8List> _fetchCaptchaImage(String twfId) async {
    final response = await _client.get(
      '$serverUrl/por/rand_code.csp',
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Cookie': 'TWFID=$twfId'},
      ),
    );
    return Uint8List.fromList(response.data as List<int>);
  }

  /// 获取认证页参数（TwfID / RSA / CSRF / RndImg）
  Future<({_EcAuthContext? auth, ECLoginStatus? failure})> _fetchEcAuth() async {
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
      return (auth: null, failure: ECLoginStatus(failNotFoundTwfid: true));
    }
    final twfId = twfIdMatch.group(1)!;
    _twfId = twfId;

    // 3. 提取RSA密钥
    final rsaKeyMatch = RegExp(
      r'<RSA_ENCRYPT_KEY>(.*?)</RSA_ENCRYPT_KEY>',
    ).firstMatch(responseText);
    if (rsaKeyMatch == null) {
      return (auth: null, failure: ECLoginStatus(failNotFoundRsaKey: true));
    }
    final rsaKey = rsaKeyMatch.group(1)!;

    // 4. 提取RSA指数
    final rsaExpMatch = RegExp(
      r'<RSA_ENCRYPT_EXP>(.*?)</RSA_ENCRYPT_EXP>',
    ).firstMatch(responseText);
    if (rsaExpMatch == null) {
      return (auth: null, failure: ECLoginStatus(failNotFoundRsaExp: true));
    }
    final rsaExp = rsaExpMatch.group(1)!;

    // 5. 提取CSRF代码
    final csrfMatch = RegExp(
      r'<CSRF_RAND_CODE>(.*?)</CSRF_RAND_CODE>',
    ).firstMatch(responseText);
    if (csrfMatch == null) {
      return (auth: null, failure: ECLoginStatus(failNotFoundCsrfCode: true));
    }
    final csrfCode = csrfMatch.group(1)!;

    // 6. 是否需要图形验证码（RndImg=1）
    final rndImgMatch = RegExp(r'<RndImg>(.*?)</RndImg>').firstMatch(responseText);
    final rndImg = rndImgMatch?.group(1)?.trim() == '1';

    return (
      auth: _EcAuthContext(
        twfId: twfId,
        csrfCode: csrfCode,
        rsaKey: rsaKey,
        rsaExp: rsaExp,
        rndImg: rndImg,
      ),
      failure: null,
    );
  }

  /// 提交 login_psw（可携带验证码），并按协议顺序判定结果
  Future<ECLoginStatus> _submitEcLogin(
    _EcAuthContext auth,
    String? captchaCode,
  ) async {
    final codeSubmitted = captchaCode != null && captchaCode.isNotEmpty;

    // RSA加密密码
    final passwordToEncrypt = '${ecPassword}_${auth.csrfCode}';
    final encryptedPassword = _rsaEncrypt(
      passwordToEncrypt,
      auth.rsaKey,
      auth.rsaExp,
    );

    // 执行登录（验证码仅在此处发送，且不记录日志）
    final loginResponse = await _client.post(
      '$serverUrl/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs',
      data: {
        'svpn_rand_code': captchaCode ?? '',
        'mitm': '',
        'svpn_req_randcode': auth.csrfCode,
        'svpn_name': userId,
        'svpn_password': encryptedPassword,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Cookie': 'TWFID=${auth.twfId}'},
      ),
    );

    final loginResponseText = loginResponse.data.toString();

    // 检查登录结果：成功 → 验证码 → 密码错误 → 未知
    if (loginResponseText.contains('<Result>1</Result>')) {
      _twfId = auth.twfId;
      _client.setCookie('TWFID', auth.twfId);
      _ecLogged = true;
      // 同步Cookie到无重定向客户端和简单客户端
      _clientNoRedirect.copyCookiesFrom(_client);
      _simpleClient.copyCookiesFromHTTPClient(_client.getAllCookies());
      return ECLoginStatus(success: true);
    }

    final captchaChallenge = loginResponseText.contains('20023') ||
        loginResponseText.contains('CAPTCHA required') ||
        loginResponseText.contains('characters are incorrect');
    final maybeAttacked = loginResponseText.contains('20041') ||
        loginResponseText.contains('maybe attacked') ||
        loginResponseText.contains('[CDATA[maybe attacked]]');
    if (captchaChallenge || maybeAttacked) {
      if (codeSubmitted && captchaChallenge) {
        return ECLoginStatus(captchaInvalid: true);
      }
      // 无图片：由调用方经 _finishEcLogin 重新取图
      return ECLoginStatus(captchaRequired: true);
    }

    if (loginResponseText.contains('Invalid username or password!') ||
        loginResponseText.contains('20004')) {
      return ECLoginStatus(failInvalidCredentials: true);
    }

    return ECLoginStatus(failUnknownError: true);
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
          loginResponseText.contains('密码输入错误') ||
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
    _pendingCaptcha = null;
    _client.close();
    _clientNoRedirect.close();
    _simpleClient.close();
  }
}
