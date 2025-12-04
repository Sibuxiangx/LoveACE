/// CSV导出器 - 平台适配层
///
/// 根据编译目标平台自动选择合适的实现
/// - Web平台：使用浏览器下载
/// - 桌面平台：保存到 Documents/loveace_export 目录
/// - 移动平台：使用文件选择器让用户选择保存位置
library;

// 条件导出 - 根据平台选择实现
export 'csv_exporter_io.dart' if (dart.library.html) 'csv_exporter_web.dart';
