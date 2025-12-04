import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/manifest_model.dart';
import '../services/logger_service.dart';

/// Manifest 服务
///
/// 负责从远程服务器获取应用公告和 OTA 更新信息
class ManifestService {
  final Dio _dio;
  final String _manifestUrl;

  ManifestService({
    required Dio dio,
    required String manifestUrl,
  })  : _dio = dio,
        _manifestUrl = manifestUrl;

  /// 获取 Manifest
  ///
  /// 返回 LoveACEManifest 对象，包含公告和 OTA 信息
  /// 如果获取失败返回 null
  Future<LoveACEManifest?> getManifest() async {
    try {
      LoggerService.info('📦 正在获取 Manifest...');

      final response = await _dio.get(
        _manifestUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        // 处理响应数据，可能是字符串或 Map
        var data = response.data;
        
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (e) {
            LoggerService.error('❌ JSON 解析失败', error: e);
            return null;
          }
        }

        if (data is! Map<String, dynamic>) {
          LoggerService.error('❌ 响应数据格式错误: 期望 Map，得到 ${data.runtimeType}');
          return null;
        }

        final manifest = LoveACEManifest.fromJson(data);
        LoggerService.info('✅ Manifest 获取成功');
        return manifest;
      }

      LoggerService.warning('⚠️ Manifest 响应异常: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      LoggerService.error('❌ 获取 Manifest 失败', error: e);
      return null;
    } catch (e) {
      LoggerService.error('❌ 解析 Manifest 失败', error: e);
      return null;
    }
  }
}
