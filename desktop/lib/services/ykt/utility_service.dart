import 'package:dio/dio.dart';

import '../../models/backend/uni_response.dart';
import '../../models/ykt/utility_models.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'ykt_config.dart';

/// 电费充值服务
///
/// 提供电费充值相关功能，包括获取校区/楼栋/楼层/房间列表和充值
class UtilityService {
  final AUFEConnection connection;
  final YKTConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'getOptions': '/utilitBindXiaoQuData.action',
    'payment': '/utilityUnBindUserPowerPay.action',
    'pageInit': '/utilityUnBindUserPowerPayInit.action',
    'purchaseHistory': '/utilityQueryRunningAccountInfo.action',
  };

  UtilityService(this.connection, this.config);

  /// 获取电费充值页面初始化信息（包含学生信息和校区列表）
  Future<UniResponse<StudentInfo>> getPageInfo() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetPageInfo(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('⚡ 获取页面信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('⚡ 获取页面信息失败', error: e);
      return ErrorHandler.handleError(e, '获取页面信息失败');
    }
  }

  Future<UniResponse<StudentInfo>> _performGetPageInfo() async {
    try {
      final url = config.toFullUrl(endpoints['pageInit']!);
      LoggerService.info('⚡ 正在获取电费充值页面: $url');

      final response = await connection.client.get(url);

      final data = response.data;
      if (data == null || data is! String) {
        throw Exception('响应数据格式错误');
      }

      final studentInfo = StudentInfo.fromHtml(data);
      LoggerService.info('⚡ 获取学生信息成功: ${studentInfo.name}');

      return UniResponse.success(studentInfo, message: '获取学生信息成功');
    } on DioException catch (e) {
      LoggerService.error('⚡ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('⚡ 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取校区列表（初始化）
  Future<UniResponse<List<SelectOption>>> getDormList() async {
    return _getOptions(dormId: '', buildingId: '', floorId: '', dormName: '');
  }

  /// 获取楼栋列表
  Future<UniResponse<List<SelectOption>>> getBuildingList({
    required String dormId,
    required String dormName,
  }) async {
    return _getOptions(
      dormId: dormId,
      buildingId: '',
      floorId: '',
      dormName: dormName,
    );
  }

  /// 获取楼层列表
  Future<UniResponse<List<SelectOption>>> getFloorList({
    required String dormId,
    required String buildingId,
    required String dormName,
  }) async {
    return _getOptions(
      dormId: dormId,
      buildingId: buildingId,
      floorId: '',
      dormName: dormName,
    );
  }

  /// 获取房间列表
  Future<UniResponse<List<SelectOption>>> getRoomList({
    required String dormId,
    required String buildingId,
    required String floorId,
    required String dormName,
  }) async {
    return _getOptions(
      dormId: dormId,
      buildingId: buildingId,
      floorId: floorId,
      dormName: dormName,
    );
  }

  /// 通用获取选项方法
  Future<UniResponse<List<SelectOption>>> _getOptions({
    required String dormId,
    required String buildingId,
    required String floorId,
    required String dormName,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetOptions(
          dormId: dormId,
          buildingId: buildingId,
          floorId: floorId,
          dormName: dormName,
        ),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('⚡ 获取选项失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('⚡ 获取选项失败', error: e);
      return ErrorHandler.handleError(e, '获取选项失败');
    }
  }

  Future<UniResponse<List<SelectOption>>> _performGetOptions({
    required String dormId,
    required String buildingId,
    required String floorId,
    required String dormName,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['getOptions']!);
      LoggerService.info('⚡ 正在获取选项: $url');

      final response = await connection.client.post(
        url,
        data: {
          'dormId': dormId,
          'buildingId': buildingId,
          'floorId': floorId,
          'dormName': dormName,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      final responseStr = data.toString().trim();
      final options = SelectOption.parseList(responseStr);

      LoggerService.info('⚡ 获取选项成功: ${options.length}个选项');
      return UniResponse.success(options, message: '获取选项成功');
    } on DioException catch (e) {
      LoggerService.error('⚡ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('⚡ 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 执行电费充值
  ///
  /// [request] 充值请求参数
  Future<UniResponse<UtilityPaymentResult>> pay(
    UtilityPaymentRequest request,
  ) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performPay(request),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 1, // 充值只尝试一次
        onRetry: (attempt, error) {
          LoggerService.warning('⚡ 充值失败，正在重试 (尝试 $attempt/1): $error');
        },
      );
    } catch (e) {
      LoggerService.error('⚡ 充值失败', error: e);
      return ErrorHandler.handleError(e, '充值失败');
    }
  }

  Future<UniResponse<UtilityPaymentResult>> _performPay(
    UtilityPaymentRequest request,
  ) async {
    try {
      final url = config.toFullUrl(endpoints['payment']!);
      LoggerService.info('⚡ 正在执行电费充值: $url');
      LoggerService.info('⚡ 充值金额: ${request.money}元');
      LoggerService.info('⚡ 房间: ${request.dormName} ${request.buildName} '
          '${request.floorName} ${request.roomName}');

      final response = await connection.client.post(
        url,
        data: request.toFormData(),
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final data = response.data;
      if (data == null || data is! String) {
        throw Exception('响应数据格式错误');
      }

      final result = UtilityPaymentResult.fromHtml(data);

      if (result.success) {
        LoggerService.info('⚡ 电费充值成功');
      } else {
        LoggerService.warning('⚡ 电费充值失败: ${result.message}');
      }

      return UniResponse.success(result, message: result.message);
    } on DioException catch (e) {
      LoggerService.error('⚡ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('⚡ 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 查询购电明细（最近7天）
  Future<UniResponse<ElectricPurchaseQueryResult>> getRecentPurchaseHistory() async {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 7));
    final endDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    return getPurchaseHistory(startDate: startDateStr, endDate: endDateStr);
  }

  /// 查询购电明细
  ///
  /// [startDate] 起始日期，格式：yyyy-MM-dd
  /// [endDate] 结束日期，格式：yyyy-MM-dd
  Future<UniResponse<ElectricPurchaseQueryResult>> getPurchaseHistory({
    required String startDate,
    required String endDate,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetPurchaseHistory(startDate, endDate),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('⚡ 获取购电明细失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('⚡ 获取购电明细失败', error: e);
      return ErrorHandler.handleError(e, '获取购电明细失败');
    }
  }

  Future<UniResponse<ElectricPurchaseQueryResult>> _performGetPurchaseHistory(
    String startDate,
    String endDate,
  ) async {
    try {
      final url = config.toFullUrl(endpoints['purchaseHistory']!);
      LoggerService.info('⚡ 正在获取购电明细: $url');
      LoggerService.info('⚡ 查询日期范围: $startDate ~ $endDate');

      // 日期格式需要加上时间
      final startDateTime = '$startDate 00:00:00';
      final endDateTime = '$endDate 23:59:59';

      final response = await connection.client.post(
        url,
        data: {
          'startDate': startDateTime,
          'endDate': endDateTime,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final data = response.data;
      if (data == null || data is! String) {
        throw Exception('响应数据格式错误');
      }

      final result = ElectricPurchaseQueryResult.fromHtml(data, startDate, endDate);
      LoggerService.info('⚡ 获取购电明细成功: ${result.count}条记录, 总金额${result.totalAmount}元');

      return UniResponse.success(result, message: '获取购电明细成功');
    } on DioException catch (e) {
      LoggerService.error('⚡ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('⚡ 解析响应数据失败', error: e);
      rethrow;
    }
  }
}
