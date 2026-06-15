import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';

/// Background manager service
///
/// Manages custom background images and generates color schemes
/// using Material You (Monet) color extraction algorithm
class BackgroundManager {
  static const String _backgroundPrefix = 'background-';
  static const String _backgroundExtension = '.jpg';

  final ImagePicker _picker = ImagePicker();

  /// Get background images directory
  Future<Directory> _getBackgroundDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final bgDir = Directory(path.join(appDir.path, 'backgrounds'));

    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
      LoggerService.info('Created backgrounds directory: ${bgDir.path}');
    }

    return bgDir;
  }

  /// Pick image from gallery
  Future<File?> pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) {
        LoggerService.info('User cancelled image selection');
        return null;
      }

      LoggerService.info('Image selected: ${image.path}');
      return File(image.path);
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to pick image',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Save background image to app directory
  Future<String?> saveBackground(File imageFile) async {
    try {
      // Remove old background first
      await removeCurrentBackground();

      final bgDir = await _getBackgroundDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$_backgroundPrefix$timestamp$_backgroundExtension';
      final targetPath = path.join(bgDir.path, fileName);

      // Copy image to app directory
      await imageFile.copy(targetPath);

      LoggerService.info('Background saved: $targetPath');
      return targetPath;
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to save background',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Get current background image path
  Future<String?> getCurrentBackground() async {
    try {
      final bgDir = await _getBackgroundDirectory();
      final files = await bgDir
          .list()
          .where(
            (entity) =>
                entity is File &&
                entity.path.contains(_backgroundPrefix) &&
                entity.path.endsWith(_backgroundExtension),
          )
          .cast<File>()
          .toList();

      if (files.isEmpty) {
        return null;
      }

      // Sort by timestamp (newest first)
      files.sort((a, b) => b.path.compareTo(a.path));

      return files.first.path;
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to get current background',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Remove current background image
  Future<void> removeCurrentBackground() async {
    try {
      final bgDir = await _getBackgroundDirectory();
      final files = await bgDir
          .list()
          .where(
            (entity) =>
                entity is File &&
                entity.path.contains(_backgroundPrefix) &&
                entity.path.endsWith(_backgroundExtension),
          )
          .cast<File>()
          .toList();

      for (final file in files) {
        await file.delete();
        LoggerService.info('Removed background: ${file.path}');
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to remove background',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Extract dominant color from image using Material You algorithm
  /// Uses compute to run in a separate isolate to avoid blocking UI
  Future<Color?> extractDominantColor(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        LoggerService.warning('Image file does not exist: $imagePath');
        return null;
      }

      // Run color extraction in a separate isolate to avoid blocking UI
      final dominantColor = await compute(_extractColorInIsolate, imagePath);

      if (dominantColor != null) {
        final colorValue =
            (dominantColor.a * 255).toInt() << 24 |
            (dominantColor.r * 255).toInt() << 16 |
            (dominantColor.g * 255).toInt() << 8 |
            (dominantColor.b * 255).toInt();
        LoggerService.info(
          'Extracted dominant color: #${colorValue.toRadixString(16)}',
        );
      }

      return dominantColor;
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to extract dominant color',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Static method to extract color in isolate
  static Future<Color?> _extractColorInIsolate(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        FileImage(imageFile),
        maximumColorCount: 16,
      );

      // Try to get vibrant color first (Material You style)
      return paletteGenerator.vibrantColor?.color ??
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.lightVibrantColor?.color ??
          paletteGenerator.darkVibrantColor?.color;
    } catch (e) {
      return null;
    }
  }

  /// Get all available colors from image (for preview)
  /// Uses compute to run in a separate isolate to avoid blocking UI
  Future<List<Color>> extractColorPalette(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        return [];
      }

      // Run color palette extraction in a separate isolate
      final colors = await compute(_extractPaletteInIsolate, imagePath);

      return colors;
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to extract color palette',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Static method to extract color palette in isolate
  static Future<List<Color>> _extractPaletteInIsolate(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        FileImage(imageFile),
        maximumColorCount: 8,
      );

      final colors = <Color>[];

      // Add colors in priority order
      if (paletteGenerator.vibrantColor != null) {
        colors.add(paletteGenerator.vibrantColor!.color);
      }
      if (paletteGenerator.lightVibrantColor != null) {
        colors.add(paletteGenerator.lightVibrantColor!.color);
      }
      if (paletteGenerator.darkVibrantColor != null) {
        colors.add(paletteGenerator.darkVibrantColor!.color);
      }
      if (paletteGenerator.mutedColor != null) {
        colors.add(paletteGenerator.mutedColor!.color);
      }
      if (paletteGenerator.lightMutedColor != null) {
        colors.add(paletteGenerator.lightMutedColor!.color);
      }
      if (paletteGenerator.darkMutedColor != null) {
        colors.add(paletteGenerator.darkMutedColor!.color);
      }

      return colors;
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to extract color palette',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }
}
