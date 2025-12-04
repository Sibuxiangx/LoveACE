import 'package:universal_io/io.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/platform/platform_util.dart';

/// 统一的日志服务
/// 提供 debug、info、warning、error 四个级别的日志记录
/// 支持控制台输出和文件输出
class LoggerService {
  static Logger? _consoleLogger;
  static Logger? _fileLogger;
  static bool _isProduction = false;
  static bool _initialized = false;

  /// 初始化日志服务
  /// [isProduction] 是否为生产环境，生产环境只输出 WARNING 及以上级别
  static Future<void> init({required bool isProduction}) async {
    if (_initialized) return;

    _isProduction = isProduction;

    // 控制台日志配置
    _consoleLogger = Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      level: _isProduction ? Level.warning : Level.debug,
    );

    // 文件日志配置（仅原生平台）
    if (!PlatformUtil.isWeb) {
      _fileLogger = Logger(
        printer: SimplePrinter(colors: false, printTime: true),
        output: await _FileOutput.create(),
        level: Level.info,
      );
    }

    _initialized = true;
  }

  /// 确保日志服务已初始化
  static void _ensureInitialized() {
    if (!_initialized) {
      // 如果未初始化，使用默认配置
      _consoleLogger = Logger(
        printer: PrettyPrinter(
          methodCount: 2,
          errorMethodCount: 8,
          lineLength: 120,
          colors: true,
          printEmojis: true,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        ),
      );
      _initialized = true;
    }
  }

  /// 调试日志 - 仅在非生产环境输出
  static void debug(String message, {dynamic error, StackTrace? stackTrace}) {
    _ensureInitialized();
    if (!_isProduction) {
      _consoleLogger?.d(message, error: error, stackTrace: stackTrace);
    }
  }

  /// 信息日志 - 输出到控制台和文件
  static void info(String message, {dynamic error, StackTrace? stackTrace}) {
    _ensureInitialized();
    _consoleLogger?.i(message, error: error, stackTrace: stackTrace);
    _fileLogger?.i(message, error: error, stackTrace: stackTrace);
  }

  /// 警告日志 - 输出到控制台和文件
  static void warning(String message, {dynamic error, StackTrace? stackTrace}) {
    _ensureInitialized();
    _consoleLogger?.w(message, error: error, stackTrace: stackTrace);
    _fileLogger?.w(message, error: error, stackTrace: stackTrace);
  }

  /// 错误日志 - 输出到控制台和文件
  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    _ensureInitialized();
    _consoleLogger?.e(message, error: error, stackTrace: stackTrace);
    _fileLogger?.e(message, error: error, stackTrace: stackTrace);
  }

  /// 获取所有日志文件列表（仅原生平台）
  static Future<List<String>> getLogFiles() async {
    if (PlatformUtil.isWeb) {
      return [];
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/logs');

      if (!await logDir.exists()) {
        return [];
      }

      final files = await logDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .map((entity) => entity.path.split('/').last)
          .toList();

      files.sort((a, b) => b.compareTo(a)); // 按文件名降序排列
      return files;
    } catch (e) {
      stderr.writeln('获取日志文件列表失败: $e');
      return [];
    }
  }

  /// 读取指定日志文件内容（仅原生平台）
  static Future<String> readLogFile(String fileName) async {
    if (PlatformUtil.isWeb) {
      throw UnsupportedError('Web 平台不支持日志文件读取');
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/logs/$fileName');

      if (!await file.exists()) {
        throw Exception('日志文件不存在: $fileName');
      }

      return await file.readAsString();
    } catch (e) {
      stderr.writeln('读取日志文件失败: $e');
      rethrow;
    }
  }

  /// 清理过期日志（仅原生平台）
  static Future<void> cleanOldLogs() async {
    if (PlatformUtil.isWeb) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/logs');

      if (!await logDir.exists()) return;

      final files = await logDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // 按文件名排序（文件名包含时间戳）
      files.sort((a, b) => b.path.compareTo(a.path));

      // 删除超出数量限制的旧文件（保留最近3个）
      if (files.length > _FileOutput.maxFiles) {
        for (var i = _FileOutput.maxFiles; i < files.length; i++) {
          try {
            await files[i].delete();
          } catch (e) {
            stderr.writeln('删除旧日志文件失败: $e');
          }
        }
      }
    } catch (e) {
      stderr.writeln('清理过期日志失败: $e');
    }
  }

  /// 关闭日志服务
  static Future<void> close() async {
    await _consoleLogger?.close();
    await _fileLogger?.close();
  }
}

/// 文件输出类
/// 实现日志文件输出和轮转机制
class _FileOutput extends LogOutput {
  static const int maxFileSize = 5 * 1024 * 1024; // 5MB
  static const int maxFiles = 3; // 最多保留3个日志文件

  File? _currentFile;
  final String _logDirectory;

  _FileOutput._(this._logDirectory);

  /// 创建 FileOutput 实例
  static Future<_FileOutput> create() async {
    // Web 平台不支持文件系统，返回一个空实现
    if (PlatformUtil.isWeb) {
      return _FileOutput._('');
    }

    final directory = await getApplicationSupportDirectory();
    final logDir = '${directory.path}/logs';

    // 确保日志目录存在
    final dir = Directory(logDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final output = _FileOutput._(logDir);
    await output._ensureFileExists();
    return output;
  }

  @override
  void output(OutputEvent event) {
    // Web 平台不支持文件操作，直接返回
    if (PlatformUtil.isWeb || _currentFile == null) return;

    try {
      for (var line in event.lines) {
        _currentFile?.writeAsStringSync(
          '${DateTime.now().toIso8601String()} $line\n',
          mode: FileMode.append,
        );
      }

      // 检查文件大小，必要时轮转
      _checkFileSize();
    } catch (e) {
      // 文件写入失败时静默处理，避免影响应用运行
      stderr.writeln('日志文件写入失败: $e');
    }
  }

  /// 确保日志文件存在
  Future<void> _ensureFileExists() async {
    if (_currentFile != null && await _currentFile!.exists()) {
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFile = File('$_logDirectory/app_$timestamp.log');

    try {
      await _currentFile!.create(recursive: true);
    } catch (e) {
      stderr.writeln('创建日志文件失败: $e');
      _currentFile = null;
    }
  }

  /// 检查文件大小，超过限制时轮转
  void _checkFileSize() {
    if (_currentFile == null) return;

    try {
      final size = _currentFile!.lengthSync();
      if (size > maxFileSize) {
        _rotateLogFiles();
      }
    } catch (e) {
      stderr.writeln('检查日志文件大小失败: $e');
    }
  }

  /// 轮转日志文件
  /// 删除最旧的文件，创建新文件
  Future<void> _rotateLogFiles() async {
    try {
      final logDir = Directory(_logDirectory);

      // 获取所有日志文件
      final files = await logDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // 按文件名排序（文件名包含时间戳）
      files.sort((a, b) => b.path.compareTo(a.path));

      // 删除超出数量限制的旧文件
      if (files.length >= maxFiles) {
        for (var i = maxFiles - 1; i < files.length; i++) {
          try {
            await files[i].delete();
          } catch (e) {
            stderr.writeln('删除旧日志文件失败: $e');
          }
        }
      }

      // 创建新文件
      _currentFile = null;
      await _ensureFileExists();
    } catch (e) {
      stderr.writeln('轮转日志文件失败: $e');
    }
  }
}
