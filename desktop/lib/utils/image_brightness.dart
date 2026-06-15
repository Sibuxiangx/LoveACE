import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Utility for calculating image brightness
class ImageBrightness {
  /// Calculate average brightness of an image
  /// Returns a value between 0.0 (dark) and 1.0 (bright)
  static Future<double> calculateBrightness(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return 0.5; // Default to medium brightness
      }

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 100, // Sample at lower resolution for performance
        targetHeight: 100,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        return 0.5;
      }

      final pixels = byteData.buffer.asUint8List();
      double totalBrightness = 0;
      int pixelCount = 0;

      // Sample every 4th pixel for performance
      for (int i = 0; i < pixels.length; i += 16) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];

        // Calculate relative luminance using standard formula
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
        totalBrightness += brightness;
        pixelCount++;
      }

      return pixelCount > 0 ? totalBrightness / pixelCount : 0.5;
    } catch (e) {
      debugPrint('Failed to calculate image brightness: $e');
      return 0.5; // Default to medium brightness on error
    }
  }

  /// Determine if text should be light or dark based on background brightness
  /// Returns true if text should be light (for dark backgrounds)
  static bool shouldUseLightText(double brightness) {
    return brightness < 0.5;
  }

  /// Get appropriate text color based on background brightness, theme, and opacity
  static Color getTextColor(
    double brightness, {
    Color? themeColor,
    double opacity = 1.0,
  }) {
    // If we have theme color and opacity, consider their impact
    if (themeColor != null && opacity > 0.5) {
      // Calculate the effective brightness considering theme color overlay
      final themeBrightness = _calculateColorBrightness(themeColor);
      final effectiveBrightness = _blendBrightness(
        brightness,
        themeBrightness,
        opacity,
      );
      return shouldUseLightText(effectiveBrightness)
          ? Colors.white
          : Colors.black87;
    }

    return shouldUseLightText(brightness) ? Colors.white : Colors.black87;
  }

  /// Get appropriate icon color based on background brightness, theme, and opacity
  static Color getIconColor(
    double brightness, {
    Color? themeColor,
    double opacity = 1.0,
  }) {
    return getTextColor(brightness, themeColor: themeColor, opacity: opacity);
  }

  /// Calculate brightness of a color
  static double _calculateColorBrightness(Color color) {
    final r = (color.r * 255.0).round() & 0xff;
    final g = (color.g * 255.0).round() & 0xff;
    final b = (color.b * 255.0).round() & 0xff;
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  }

  /// Blend background brightness with theme color brightness based on opacity
  static double _blendBrightness(
    double bgBrightness,
    double themeBrightness,
    double opacity,
  ) {
    // Higher opacity means more theme color influence
    return bgBrightness * (1 - opacity) + themeBrightness * opacity;
  }

  /// Get appropriate shadow for text based on background brightness
  static List<Shadow> getTextShadow(double brightness) {
    if (shouldUseLightText(brightness)) {
      // Light text on dark background - use dark shadow
      return [
        Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 4),
      ];
    } else {
      // Dark text on light background - use light shadow
      return [
        Shadow(color: Colors.white.withValues(alpha: 0.7), blurRadius: 4),
      ];
    }
  }

  /// Calculate optimal card opacity based on background brightness and theme mode
  ///
  /// For dark mode:
  /// - Dark backgrounds (< 0.5): Higher opacity (0.85-0.95) for better contrast
  /// - Light backgrounds (>= 0.5): Lower opacity (0.70-0.80) to show background
  ///
  /// For light mode:
  /// - Dark backgrounds (< 0.5): Lower opacity (0.70-0.80) to show background
  /// - Light backgrounds (>= 0.5): Higher opacity (0.85-0.95) for better contrast
  static double calculateOptimalCardOpacity(
    double backgroundBrightness,
    bool isDarkMode,
  ) {
    if (isDarkMode) {
      // Dark mode: Need more opacity on dark backgrounds
      if (backgroundBrightness < 0.3) {
        return 0.95; // Very dark background - maximum opacity
      } else if (backgroundBrightness < 0.5) {
        return 0.85; // Dark background - high opacity
      } else if (backgroundBrightness < 0.7) {
        return 0.75; // Medium background - medium opacity
      } else {
        return 0.70; // Light background - lower opacity
      }
    } else {
      // Light mode: Need more opacity on light backgrounds
      if (backgroundBrightness >= 0.7) {
        return 0.95; // Very light background - maximum opacity
      } else if (backgroundBrightness >= 0.5) {
        return 0.85; // Light background - high opacity
      } else if (backgroundBrightness >= 0.3) {
        return 0.75; // Medium background - medium opacity
      } else {
        return 0.70; // Dark background - lower opacity
      }
    }
  }
}
