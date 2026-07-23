import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/manifest_model.dart';

class DesktopUpdateService {
  DesktopUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<String?> chooseWindowsInstallerPath(ManifestRelease release) async {
    final downloadsDirectory = await getDownloadsDirectory();
    return FilePicker.saveFile(
      dialogTitle: '保存 LoveACE 安装程序',
      fileName: 'loveace-${release.version}-setup.exe',
      initialDirectory: downloadsDirectory?.path,
      type: FileType.custom,
      allowedExtensions: const ['exe'],
    );
  }

  Future<void> downloadWindowsInstaller(
    ReleaseArtifact artifact,
    String destinationPath, {
    required void Function(double progress) onProgress,
  }) async {
    final destination = destinationPath.toLowerCase().endsWith('.exe')
        ? destinationPath
        : '$destinationPath.exe';
    final file = File(destination);
    try {
      await _dio.download(
        artifact.url,
        destination,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress((received / total).clamp(0, 1));
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          followRedirects: true,
        ),
      );
      await verifyInstaller(file, artifact.checksums);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> launchWindowsInstaller(String destinationPath) async {
    final installerPath = destinationPath.toLowerCase().endsWith('.exe')
        ? destinationPath
        : '$destinationPath.exe';
    await Process.start(
      installerPath,
      const [],
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> verifyInstaller(File file, ArtifactChecksums checksums) async {
    final expectedSha256 = checksums.sha256;
    if (expectedSha256?.isNotEmpty == true) {
      final actual = await sha256.bind(file.openRead()).first;
      if (actual.toString().toLowerCase() != expectedSha256!.toLowerCase()) {
        throw const FormatException('安装程序 SHA-256 校验失败');
      }
      return;
    }

    final expectedMd5 = checksums.md5;
    if (expectedMd5?.isNotEmpty == true) {
      final actual = await md5.bind(file.openRead()).first;
      if (actual.toString().toLowerCase() != expectedMd5!.toLowerCase()) {
        throw const FormatException('安装程序 MD5 校验失败');
      }
      return;
    }

    throw const FormatException('Manifest 未提供安装程序校验值');
  }
}
