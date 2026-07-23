import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/manifest_model.dart';
import '../services/logger_service.dart';

/// Manifest 服务
///
/// 负责从远程服务器获取应用公告和 OTA 更新信息
class ManifestService {
  final Dio _dio;
  final List<String> _manifestUrls;

  factory ManifestService({
    required Dio dio,
    required List<String> manifestUrls,
  }) => ManifestService._(dio, List.unmodifiable(manifestUrls));

  ManifestService._(this._dio, this._manifestUrls);

  /// 获取 Manifest
  ///
  /// 返回 ManifestV2 对象，包含公告和各平台发布信息
  /// 如果获取失败返回 null
  Future<ManifestV2?> getManifest() async {
    for (final manifestUrl in _manifestUrls) {
      try {
        LoggerService.info('📦 正在获取 Manifest v2: $manifestUrl');

        final response = await _dio.get(
          manifestUrl,
          options: Options(
            receiveTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
          ),
        );

        if (response.statusCode != 200 || response.data == null) {
          throw StateError('Manifest 响应异常: ${response.statusCode}');
        }
        var data = response.data;

        if (data is String) {
          data = jsonDecode(data);
        }

        if (data is! Map<String, dynamic>) {
          throw FormatException('期望 Map，得到 ${data.runtimeType}');
        }

        final manifest = ManifestV2.fromJson(data);
        if (manifest.schemaVersion != 2) {
          throw FormatException('不支持的 Manifest 版本: ${manifest.schemaVersion}');
        }
        LoggerService.info('✅ Manifest v2 获取成功');
        return manifest;
      } on DioException catch (error) {
        LoggerService.warning('⚠️ Manifest 地址不可用: $manifestUrl', error: error);
      } catch (error) {
        LoggerService.warning('⚠️ Manifest 解析失败: $manifestUrl', error: error);
      }
    }
    LoggerService.error('❌ 所有 Manifest v2 地址均不可用');
    return null;
  }
}
