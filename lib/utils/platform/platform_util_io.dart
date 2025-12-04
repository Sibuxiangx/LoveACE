import 'dart:io' show Platform;

/// 获取平台路径分隔符 - IO 版本
String getPlatformPathSeparator() => Platform.pathSeparator;

/// 是否为 Windows 平台 - IO 版本
bool isWindowsPlatform() => Platform.isWindows;

/// 是否为 macOS 平台 - IO 版本
bool isMacOSPlatform() => Platform.isMacOS;

/// 是否为 Linux 平台 - IO 版本
bool isLinuxPlatform() => Platform.isLinux;

/// 是否为 Android 平台 - IO 版本
bool isAndroidPlatform() => Platform.isAndroid;

/// 是否为 iOS 平台 - IO 版本
bool isIOSPlatform() => Platform.isIOS;
