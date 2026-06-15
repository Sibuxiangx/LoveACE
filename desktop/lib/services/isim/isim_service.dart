import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../models/backend/uni_response.dart';
import '../../models/isim/electricity_balance.dart';
import '../../models/isim/electricity_usage_record.dart';
import '../../models/isim/payment_record.dart';
import '../../models/isim/electricity_info.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../../services/http_client.dart';
import '../logger_service.dart';
import 'isim_config.dart';

/// ISIM (Integrated Student Information Management) 服务
///
/// 提供宿舍电费查询功能
/// 包括余额查询、用电记录和充值记录
class ISIMService {
  final AUFEConnection connection;
  final ISIMConfig config;

  /// ISIM 专用的 HTTPClient，避免 cookie 冲突
  late final HTTPClient _isimClient;

  /// JSESSION ID，用于维持会话
  String? _jsessionid;

  /// 会话是否已初始化
  bool _sessionInitialized = false;

  /// 会话初始化锁，防止并发初始化
  bool _initializingSession = false;

  /// API 端点常量
  static const Map<String, String> endpoints = {
    'init': '/go',
    'rebinding': '/about/rebinding',
    'usageRecord': '/use/record',
    'paymentRecord': '/pay/record',
    'about': '/about',
    'floors': '/about/floors',
    'rooms': '/about/rooms',
  };

  ISIMService(this.connection, this.config) {
    // 创建 ISIM 专用的 HTTPClient
    _isimClient = HTTPClient(
      baseUrl: ISIMConfig.defaultBaseUrl,
      timeout: 30000,
      followRedirects: true,
    );
    _isimClient.copyCookiesFrom(connection.client);
  }

  /// 确保 JSESSION 已初始化
  ///
  /// 使用异步锁防止并发初始化
  /// 如果会话已初始化，直接返回
  /// 否则调用 _initJsession() 进行初始化
  Future<void> _ensureJsession() async {
    // 如果已经初始化，直接返回
    if (_sessionInitialized && _jsessionid != null) {
      LoggerService.info('⚡ JSESSION 已存在，跳过初始化');
      return;
    }

    // 如果正在初始化，等待初始化完成
    while (_initializingSession) {
      LoggerService.info('⚡ 等待 JSESSION 初始化完成...');
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 再次检查是否已初始化（可能在等待期间完成）
    if (_sessionInitialized && _jsessionid != null) {
      LoggerService.info('⚡ JSESSION 初始化已完成');
      return;
    }

    // 开始初始化
    _initializingSession = true;
    try {
      await _initJsession();
    } finally {
      _initializingSession = false;
    }
  }

  /// 初始化 JSESSION
  ///
  /// 调用 /go 端点，让 HTTPClient 自动存储 JSESSIONID cookie
  /// 然后从 HTTPClient 的 cookie jar 中提取 JSESSIONID
  Future<void> _initJsession() async {
    try {
      LoggerService.info('⚡ 开始初始化 ISIM JSESSION');

      // 构建初始化 URL
      // openid 使用用户ID，sn 使用 EC 系统的 TwfID
      final url = config.toFullUrl(endpoints['init']!);
      final openid = connection.userId;
      final sn = connection.twfId ?? '';

      LoggerService.info('⚡ 初始化参数 - openid: $openid, sn: $sn');

      // 使用 ISIM 专用的 HTTPClient 发送请求
      // HTTPClient 会自动存储 JSESSIONID cookie
      final fullUrl = '$url?openid=$openid&sn=sn';
      await _isimClient.get(fullUrl);

      LoggerService.info('⚡ 请求完成，尝试获取 JSESSIONID');

      // 从 ISIM HTTPClient 中获取 JSESSIONID
      // 使用 getCookieForDomain 指定域名，避免获取到其他域名的 JSESSIONID
      _jsessionid = _isimClient.getCookieForDomain(
        'JSESSIONID',
        '.vpn2.aufe.edu.cn',
      );

      if (_jsessionid != null && _jsessionid!.isNotEmpty) {
        _sessionInitialized = true;
        LoggerService.info('✅ JSESSIONID 提取成功: $_jsessionid');
        return;
      }

      throw Exception('无法获取 JSESSIONID');
    } on DioException catch (e) {
      LoggerService.error('❌ JSESSION 初始化网络请求失败', error: e);
      _sessionInitialized = false;
      _jsessionid = null;
      rethrow;
    } catch (e) {
      LoggerService.error('❌ JSESSION 初始化失败', error: e);
      _sessionInitialized = false;
      _jsessionid = null;
      rethrow;
    }
  }

  /// 获取楼栋列表
  ///
  /// 从 /about 页面的 HTML 中解析楼栋信息
  /// 返回可用的楼栋列表，每个楼栋包含 code 和 name
  Future<UniResponse<List<Map<String, String>>>> getBuildings() async {
    try {
      LoggerService.info('🏢 开始获取楼栋列表');

      // 确保 JSESSION 已初始化
      await _ensureJsession();

      if (_jsessionid == null) {
        throw Exception('JSESSION 未初始化');
      }

      final url = config.toFullUrl(endpoints['about']!);
      final twfId = connection.twfId ?? '';

      final response = await _isimClient.get(
        url,
        options: Options(
          headers: {
            'Cookie': 'JSESSIONID=$_jsessionid; TWFID=$twfId',
            'Referer': '${ISIMConfig.defaultBaseUrl}/home',
          },
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('获取楼栋列表失败，状态码: ${response.statusCode}');
      }

      // 解析 HTML 页面
      final htmlContent = response.data.toString();
      final document = html_parser.parse(htmlContent);

      final buildings = <Map<String, String>>[];

      // 查找包含 pickerBuilding 的 script 标签
      final scripts = document.querySelectorAll('script');
      for (final script in scripts) {
        final scriptContent = script.text;
        if (scriptContent.contains('pickerBuilding')) {
          // 提取 values 数组
          final valuesMatch = RegExp(
            r'values:\s*\[(.*?)\]',
          ).firstMatch(scriptContent);
          // 提取 displayValues 数组
          final displayValuesMatch = RegExp(
            r'displayValues:\s*\[(.*?)\]',
          ).firstMatch(scriptContent);

          if (valuesMatch != null && displayValuesMatch != null) {
            final valuesStr = valuesMatch.group(1)!;
            final displayValuesStr = displayValuesMatch.group(1)!;

            // 解析数组内容
            final values = valuesStr
                .split(',')
                .map((v) => v.trim().replaceAll('"', '').replaceAll("'", ''))
                .where((v) => v.isNotEmpty && v != '""')
                .toList();

            final displayValues = displayValuesStr
                .split(',')
                .map((v) => v.trim().replaceAll('"', '').replaceAll("'", ''))
                .where((v) => v.isNotEmpty && v != '请选择')
                .toList();

            // 组合成楼栋列表
            for (
              int i = 0;
              i < values.length && i < displayValues.length;
              i++
            ) {
              if (values[i].isNotEmpty && displayValues[i] != '请选择') {
                buildings.add({'code': values[i], 'name': displayValues[i]});
              }
            }
            break;
          }
        }
      }

      LoggerService.info('✅ 获取楼栋列表成功，共 ${buildings.length} 个楼栋');
      return UniResponse.success(buildings);
    } catch (e) {
      LoggerService.error('❌ 获取楼栋列表失败', error: e);
      return ErrorHandler.handleError(e, '获取楼栋列表失败');
    }
  }

  /// 获取楼层列表
  ///
  /// [buildingCode] 楼栋代码
  ///
  /// 返回指定楼栋的楼层列表
  Future<UniResponse<List<Map<String, String>>>> getFloors(
    String buildingCode,
  ) async {
    try {
      LoggerService.info('🏢 开始获取楼层列表: $buildingCode');

      // 确保 JSESSION 已初始化
      await _ensureJsession();

      if (_jsessionid == null) {
        throw Exception('JSESSION 未初始化');
      }

      final url = config.toFullUrl('${endpoints['floors']!}/$buildingCode');
      final twfId = connection.twfId ?? '';

      final response = await _isimClient.get(
        url,
        options: Options(
          headers: {
            'Cookie': 'JSESSIONID=$_jsessionid; TWFID=$twfId',
            'Referer':
                '${ISIMConfig.defaultBaseUrl}/about;jsessionid=$_jsessionid',
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
          },
          responseType: ResponseType.plain, // 获取原始字符串，不自动解析 JSON
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('获取楼层列表失败，状态码: ${response.statusCode}');
      }

      // 解析响应数据
      var data = response.data;

      LoggerService.info('⚡ 楼层响应数据类型: ${data.runtimeType}');
      if (data is String) {
        LoggerService.info(
          '⚡ 楼层响应内容: ${data.length > 200 ? data.substring(0, 200) : data}',
        );
      }

      // 如果是字符串，尝试解析为 JSON
      if (data is String) {
        try {
          // 先尝试直接解析
          data = jsonDecode(data);
          LoggerService.info('⚡ 直接 JSON 解析成功');
        } catch (e) {
          LoggerService.info('⚡ 直接 JSON 解析失败，尝试处理 JavaScript 对象字面量格式');
          // 处理 JavaScript 对象字面量格式
          // 将 key: 转换为 "key":
          var jsonStr = data.replaceAllMapped(
            RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*:'),
            (match) => '"${match.group(1)}":',
          );
          LoggerService.info(
            '⚡ 转换后: ${jsonStr.length > 200 ? jsonStr.substring(0, 200) : jsonStr}',
          );
          data = jsonDecode(jsonStr);
          LoggerService.info('⚡ JavaScript 对象字面量解析成功');
        }
      }

      final floors = <Map<String, String>>[];

      if (data is List && data.isNotEmpty) {
        final floorData = data[0] as Map<String, dynamic>;
        final floorCodes = floorData['floordm'] as List?;
        final floorNames = floorData['floorname'] as List?;

        if (floorCodes != null && floorNames != null) {
          // 跳过第一个空值（"请选择"）
          for (int i = 1; i < floorCodes.length && i < floorNames.length; i++) {
            final code = floorCodes[i]?.toString() ?? '';
            final name = floorNames[i]?.toString() ?? '';

            if (code.isNotEmpty && name.isNotEmpty && name != '请选择') {
              floors.add({'code': code, 'name': name});
            }
          }
        }
      }

      LoggerService.info('✅ 获取楼层列表成功，共 ${floors.length} 个楼层');
      return UniResponse.success(floors);
    } catch (e) {
      LoggerService.error('❌ 获取楼层列表失败', error: e);
      return ErrorHandler.handleError(e, '获取楼层列表失败');
    }
  }

  /// 获取房间列表
  ///
  /// [floorCode] 楼层代码
  ///
  /// 返回指定楼层的房间列表
  Future<UniResponse<List<Map<String, String>>>> getRooms(
    String floorCode,
  ) async {
    try {
      LoggerService.info('🏢 开始获取房间列表: $floorCode');

      // 确保 JSESSION 已初始化
      await _ensureJsession();

      if (_jsessionid == null) {
        throw Exception('JSESSION 未初始化');
      }

      final url = config.toFullUrl('${endpoints['rooms']!}/$floorCode');
      final twfId = connection.twfId ?? '';

      final response = await _isimClient.get(
        url,
        options: Options(
          headers: {
            'Cookie': 'JSESSIONID=$_jsessionid; TWFID=$twfId',
            'Referer':
                '${ISIMConfig.defaultBaseUrl}/about;jsessionid=$_jsessionid',
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
          },
          responseType: ResponseType.plain, // 获取原始字符串，不自动解析 JSON
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('获取房间列表失败，状态码: ${response.statusCode}');
      }

      // 解析响应数据
      var data = response.data;

      // 如果是字符串，尝试解析为 JSON
      if (data is String) {
        // 处理 JavaScript 对象字面量格式
        final jsonStr = data.replaceAllMapped(
          RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*:'),
          (match) => '"${match.group(1)}":',
        );
        data = jsonDecode(jsonStr);
      }

      final rooms = <Map<String, String>>[];

      if (data is List && data.isNotEmpty) {
        final roomData = data[0] as Map<String, dynamic>;
        final roomCodes = roomData['roomdm'] as List?;
        final roomNames = roomData['roomname'] as List?;

        if (roomCodes != null && roomNames != null) {
          // 跳过第一个空值（"请选择"）
          for (int i = 1; i < roomCodes.length && i < roomNames.length; i++) {
            final code = roomCodes[i]?.toString() ?? '';
            final name = roomNames[i]?.toString() ?? '';

            if (code.isNotEmpty && name.isNotEmpty && name != '请选择') {
              rooms.add({'code': code, 'name': name});
            }
          }
        }
      }

      LoggerService.info('✅ 获取房间列表成功，共 ${rooms.length} 个房间');
      return UniResponse.success(rooms);
    } catch (e) {
      LoggerService.error('❌ 获取房间列表失败', error: e);
      return ErrorHandler.handleError(e, '获取房间列表失败');
    }
  }

  /// 绑定房间到当前 JSESSION
  ///
  /// 将指定的房间代码绑定到当前会话
  /// 绑定后才能查询该房间的电费信息
  ///
  /// [roomCode] 房间代码（如 "1-101"）
  /// [displayText] 房间显示文本（可选，如 "1号楼101室"）
  ///
  /// 返回 true 表示绑定成功，false 表示绑定失败
  Future<bool> bindRoom(String roomCode, {String? displayText}) async {
    try {
      LoggerService.info('🔌 开始绑定房间: $roomCode');

      // 确保 JSESSION 已初始化
      await _ensureJsession();

      if (_jsessionid == null) {
        LoggerService.error('❌ JSESSION 未初始化，无法绑定房间');
        return false;
      }

      // 构建绑定 URL
      final url = config.toFullUrl(endpoints['rebinding']!);
      final twfId = connection.twfId ?? '';
      // 发送 POST 请求绑定房间
      final response = await _isimClient.post(
        url,
        data: {
          'roomdm': roomCode,
          'room': displayText ?? roomCode,
          'openid': connection.userId,
          'sn': 'sn',
          'mode': 'u',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Cookie': 'JSESSIONID=$_jsessionid;TWFID=$twfId'},
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      LoggerService.info('🔌 房间绑定响应状态: ${response.statusCode}');

      // 检查响应状态
      if (response.statusCode == 200) {
        LoggerService.info('✅ 房间绑定成功: $roomCode');
        return true;
      } else {
        LoggerService.warning('⚠️ 房间绑定失败，状态码: ${response.statusCode}');
        return false;
      }
    } on DioException catch (e) {
      LoggerService.error('❌ 房间绑定网络请求失败', error: e);
      return false;
    } catch (e) {
      LoggerService.error('❌ 房间绑定失败', error: e);
      return false;
    }
  }

  /// 解析电费余额信息
  ///
  /// 从 HTML 内容中提取剩余购电和剩余补助
  ///
  /// [htmlContent] HTML 响应内容
  ///
  /// 返回 ElectricityBalance 对象
  ElectricityBalance _parseBalance(String htmlContent) {
    try {
      LoggerService.info('⚡ 开始解析电费余额');

      final document = html_parser.parse(htmlContent);

      double remainingPurchased = 0.0;
      double remainingSubsidy = 0.0;

      // 查找所有包含余额信息的列表项
      // ISIM 系统通常使用 li.item-content 或类似的结构
      final items = document.querySelectorAll(
        'li.item-content, li.item, .item-content, .balance-item',
      );

      for (final item in items) {
        // 获取标题和值
        final titleElement = item.querySelector(
          '.item-title, .title, dt, .label',
        );
        final valueElement = item.querySelector(
          '.item-after, .value, dd, .amount',
        );

        if (titleElement == null || valueElement == null) continue;

        final title = titleElement.text.trim();
        final valueText = valueElement.text.trim();

        // 使用正则表达式提取数字
        final match = RegExp(r'([\d.]+)').firstMatch(valueText);
        if (match != null) {
          final amount = double.tryParse(match.group(1)!) ?? 0.0;

          // 根据标题判断是购电还是补助
          if (title.contains('剩余购电') || title.contains('购电余额')) {
            remainingPurchased = amount;
            LoggerService.info('⚡ 剩余购电: $remainingPurchased 度');
          } else if (title.contains('剩余补助') || title.contains('补助余额')) {
            remainingSubsidy = amount;
            LoggerService.info('⚡ 剩余补助: $remainingSubsidy 度');
          }
        }
      }

      // 如果没有找到标准格式，尝试其他可能的格式
      if (remainingPurchased == 0.0 && remainingSubsidy == 0.0) {
        // 尝试查找包含"度"的文本节点
        final allText = document.body?.text ?? '';
        final purchasedMatch = RegExp(
          r'购电[：:]\s*([\d.]+)\s*度',
        ).firstMatch(allText);
        final subsidyMatch = RegExp(
          r'补助[：:]\s*([\d.]+)\s*度',
        ).firstMatch(allText);

        if (purchasedMatch != null) {
          remainingPurchased = double.tryParse(purchasedMatch.group(1)!) ?? 0.0;
        }
        if (subsidyMatch != null) {
          remainingSubsidy = double.tryParse(subsidyMatch.group(1)!) ?? 0.0;
        }
      }

      LoggerService.info(
        '✅ 电费余额解析完成 - 购电: $remainingPurchased, 补助: $remainingSubsidy',
      );

      return ElectricityBalance(
        remainingPurchased: remainingPurchased,
        remainingSubsidy: remainingSubsidy,
      );
    } catch (e) {
      LoggerService.error('❌ 解析电费余额失败', error: e);
      // 返回零值余额而不是抛出异常
      return ElectricityBalance(remainingPurchased: 0.0, remainingSubsidy: 0.0);
    }
  }

  /// 解析用电记录
  ///
  /// 从 HTML 内容中提取用电记录列表
  ///
  /// [htmlContent] HTML 响应内容
  ///
  /// 返回 ElectricityUsageRecord 列表
  List<ElectricityUsageRecord> _parseUsageRecords(String htmlContent) {
    try {
      LoggerService.info('⚡ 开始解析用电记录');

      final document = html_parser.parse(htmlContent);
      final records = <ElectricityUsageRecord>[];

      // 根据 Python 代码：#divRecord ul li
      final recordItems = document.querySelectorAll('#divRecord ul li');
      LoggerService.info('⚡ 找到 ${recordItems.length} 条用电记录项');

      for (final item in recordItems) {
        try {
          // 提取时间 (item-title)
          final titleDiv = item.querySelector('.item-title');
          // 提取用电量 (item-after)
          final afterDiv = item.querySelector('.item-after');
          // 提取电表名称 (item-subtitle)
          final subtitleDiv = item.querySelector('.item-subtitle');

          if (titleDiv != null && afterDiv != null && subtitleDiv != null) {
            final recordTime = titleDiv.text.trim();
            final usageText = afterDiv.text.trim();
            final meterText = subtitleDiv.text.trim();

            // 提取用电量：匹配 "X.XX度"
            final usageMatch = RegExp(r'([\d.]+)度').firstMatch(usageText);
            if (usageMatch != null) {
              final usageAmount = double.tryParse(usageMatch.group(1)!) ?? 0.0;

              // 提取电表名称：匹配 "电表: XXX"
              final meterMatch = RegExp(r'电表:\s*(.+)').firstMatch(meterText);
              final meterName = meterMatch != null
                  ? meterMatch.group(1)!.trim()
                  : meterText;

              records.add(
                ElectricityUsageRecord(
                  recordTime: recordTime,
                  usageAmount: usageAmount,
                  meterName: meterName,
                ),
              );

              LoggerService.info(
                '⚡ 解析用电记录: $recordTime, $usageAmount度, $meterName',
              );
            }
          }
        } catch (e) {
          LoggerService.warning('⚠️ 跳过无法解析的用电记录行: $e');
          continue;
        }
      }

      LoggerService.info('✅ 用电记录解析完成，共 ${records.length} 条');
      return records;
    } catch (e) {
      LoggerService.error('❌ 解析用电记录失败', error: e);
      return [];
    }
  }

  /// 解析充值记录
  ///
  /// 从 HTML 内容中提取充值记录列表
  ///
  /// [htmlContent] HTML 响应内容
  ///
  /// 返回 PaymentRecord 列表
  List<PaymentRecord> _parsePaymentRecords(String htmlContent) {
    try {
      LoggerService.info('⚡ 开始解析充值记录');

      final document = html_parser.parse(htmlContent);
      final records = <PaymentRecord>[];

      // 根据 Python 代码：#divRecord ul li
      final recordItems = document.querySelectorAll('#divRecord ul li');
      LoggerService.info('⚡ 找到 ${recordItems.length} 条充值记录项');

      for (final item in recordItems) {
        try {
          // 提取时间 (item-title)
          final titleDiv = item.querySelector('.item-title');
          // 提取金额 (item-after)
          final afterDiv = item.querySelector('.item-after');
          // 提取类型 (item-subtitle)
          final subtitleDiv = item.querySelector('.item-subtitle');

          if (titleDiv != null && afterDiv != null && subtitleDiv != null) {
            final paymentTime = titleDiv.text.trim();
            final amountText = afterDiv.text.trim();
            final typeText = subtitleDiv.text.trim();

            // 提取金额：匹配 "-X.XX元" 或 "X.XX元"
            final amountMatch = RegExp(r'(-?[\d.]+)元').firstMatch(amountText);
            if (amountMatch != null) {
              final amount = double.tryParse(amountMatch.group(1)!) ?? 0.0;

              // 提取充值类型：匹配 "类型: XXX"
              final typeMatch = RegExp(r'类型:\s*(.+)').firstMatch(typeText);
              final paymentType = typeMatch != null
                  ? typeMatch.group(1)!.trim()
                  : typeText;

              records.add(
                PaymentRecord(
                  paymentTime: paymentTime,
                  amount: amount,
                  paymentType: paymentType,
                ),
              );

              LoggerService.info(
                '⚡ 解析充值记录: $paymentTime, $amount元, $paymentType',
              );
            }
          }
        } catch (e) {
          LoggerService.warning('⚠️ 跳过无法解析的充值记录行: $e');
          continue;
        }
      }

      LoggerService.info('✅ 充值记录解析完成，共 ${records.length} 条');
      return records;
    } catch (e) {
      LoggerService.error('❌ 解析充值记录失败', error: e);
      return [];
    }
  }

  /// 获取电费信息
  ///
  /// 查询指定房间的电费余额、用电记录和充值记录
  ///
  /// [roomCode] 房间代码（如 "1-101"）
  /// [displayText] 房间显示文本（可选）
  ///
  /// 返回包含电费信息的 UniResponse
  /// 成功时返回 UniResponse.success，包含 ElectricityInfo 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<ElectricityInfo>> getElectricityInfo(
    String roomCode, {
    String? displayText,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async =>
            await _performGetElectricityInfo(roomCode, displayText),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('⚡ 获取电费信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('⚡ 获取电费信息失败', error: e);
      return ErrorHandler.handleError(e, '获取电费信息失败');
    }
  }

  /// 执行获取电费信息的实际操作
  Future<UniResponse<ElectricityInfo>> _performGetElectricityInfo(
    String roomCode,
    String? displayText,
  ) async {
    try {
      LoggerService.info('⚡ 开始获取电费信息: $roomCode');

      // 1. 确保 JSESSION 已初始化
      await _ensureJsession();

      if (_jsessionid == null) {
        throw Exception('JSESSION 初始化失败');
      }

      // 2. 绑定房间
      LoggerService.info('⚡ 绑定房间到会话');
      final bindSuccess = await bindRoom(roomCode, displayText: displayText);
      if (!bindSuccess) {
        throw Exception('房间绑定失败');
      }
      final twfId = connection.twfId ?? '';

      // 3. 并发获取用电记录和充值记录 HTML
      LoggerService.info('⚡ 并发获取用电记录和充值记录');
      final usageUrl = config.toFullUrl(endpoints['usageRecord']!);
      final paymentUrl = config.toFullUrl(endpoints['paymentRecord']!);

      final headers = {'Cookie': 'JSESSIONID=$_jsessionid;TWFID=$twfId'};
      final options = Options(
        headers: headers,
        followRedirects: true,
        validateStatus: (status) => status! < 500,
      );

      // 并发请求
      final results = await Future.wait([
        _isimClient.get(usageUrl, options: options),
        _isimClient.get(paymentUrl, options: options),
      ]);

      final usageResponse = results[0];
      final paymentResponse = results[1];

      if (usageResponse.statusCode != 200) {
        throw Exception('获取用电记录失败，状态码: ${usageResponse.statusCode}');
      }

      if (paymentResponse.statusCode != 200) {
        throw Exception('获取充值记录失败，状态码: ${paymentResponse.statusCode}');
      }

      final usageHtml = usageResponse.data.toString();
      final paymentHtml = paymentResponse.data.toString();

      // 4. 解析 HTML 数据（从用电记录页面解析余额、用电记录，从充值记录页面解析充值记录）
      LoggerService.info('⚡ 解析电费数据');

      final balance = _parseBalance(usageHtml);
      final usageRecords = _parseUsageRecords(usageHtml);
      final paymentRecords = _parsePaymentRecords(paymentHtml);

      // 5. 构建 ElectricityInfo 对象
      final electricityInfo = ElectricityInfo(
        balance: balance,
        usageRecords: usageRecords,
        payments: paymentRecords,
      );

      LoggerService.info('✅ 电费信息获取成功');
      LoggerService.info(
        '⚡ 余额: ${balance.total} 度 (购电: ${balance.remainingPurchased}, 补助: ${balance.remainingSubsidy})',
      );
      LoggerService.info('⚡ 用电记录: ${usageRecords.length} 条');
      LoggerService.info('⚡ 充值记录: ${paymentRecords.length} 条');

      return UniResponse.success(electricityInfo, message: '电费信息获取成功');
    } on DioException catch (e) {
      LoggerService.error('⚡ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('⚡ 获取电费信息失败', error: e);
      rethrow;
    }
  }
}
