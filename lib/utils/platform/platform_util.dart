import 'package:flutter/foundation.dart' show kIsWeb;
import 'platform_util_impl.dart'
    if (dart.library.io) 'platform_util_io.dart'
    if (dart.library.html) 'platform_util_stub.dart';

/// 平台工具类 - 提供跨平台的平台检测
class PlatformUtil {
  /// 是否为 Web 平台
  static bool get isWeb => kIsWeb;

  /// 是否为移动端或桌面端（非 Web）
  static bool get isNative => !kIsWeb;

  /// 获取路径分隔符
  static String get pathSeparator {
    if (kIsWeb) {
      return '/';
    }
    return getPlatformPathSeparator();
  }

  /// 是否为 Windows 平台
  static bool get isWindows {
    if (kIsWeb) return false;
    return isWindowsPlatform();
  }

  /// 是否为 macOS 平台
  static bool get isMacOS {
    if (kIsWeb) return false;
    return isMacOSPlatform();
  }

  /// 是否为 Linux 平台
  static bool get isLinux {
    if (kIsWeb) return false;
    return isLinuxPlatform();
  }

  /// 是否为 Android 平台
  static bool get isAndroid {
    if (kIsWeb) return false;
    return isAndroidPlatform();
  }

  /// 是否为 iOS 平台
  static bool get isIOS {
    if (kIsWeb) return false;
    return isIOSPlatform();
  }
}
