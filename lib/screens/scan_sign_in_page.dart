import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/labor_club_provider.dart';
import '../models/labor_club/sign_in_response.dart';
import '../services/logger_service.dart';
import '../utils/platform/platform_util.dart';
import '../widgets/adaptive_sliver_app_bar.dart';

/// 扫码签到页面
///
/// 提供二维码扫描功能，用于劳动俱乐部活动签到
/// 仅支持移动平台（Android/iOS）
class ScanSignInPage extends StatefulWidget {
  const ScanSignInPage({super.key});

  @override
  State<ScanSignInPage> createState() => _ScanSignInPageState();
}

class _ScanSignInPageState extends State<ScanSignInPage> {
  /// 扫码控制器
  MobileScannerController? _controller;

  /// 是否正在处理扫码结果
  bool _isProcessing = false;

  /// 是否已扫描成功
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  /// 初始化扫码器
  Future<void> _initializeScanner() async {
    // 检查平台支持
    if (!_isPlatformSupported()) {
      LoggerService.warning('⚠️ 当前平台不支持扫码功能');
      if (mounted) {
        _showUnsupportedPlatformDialog();
      }
      return;
    }

    // 请求摄像头权限
    final hasPermission = await _requestCameraPermission();
    if (!hasPermission) {
      LoggerService.warning('⚠️ 摄像头权限被拒绝');
      return;
    }

    // 初始化扫码控制器
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    if (mounted) {
      setState(() {});
    }
  }

  /// 检查平台是否支持扫码
  bool _isPlatformSupported() {
    // 仅支持 Android 和 iOS
    return PlatformUtil.isAndroid || PlatformUtil.isIOS || PlatformUtil.isMacOS || PlatformUtil.isWeb;
  }

  /// 请求摄像头权限
  Future<bool> _requestCameraPermission() async {
    try {
      LoggerService.info('📷 请求摄像头权限');

      final status = await Permission.camera.status;

      if (status.isGranted) {
        LoggerService.info('✅ 摄像头权限已授予');
        return true;
      }

      if (status.isDenied) {
        // 请求权限
        final result = await Permission.camera.request();

        if (result.isGranted) {
          LoggerService.info('✅ 摄像头权限已授予');
          return true;
        } else if (result.isPermanentlyDenied) {
          // 权限被永久拒绝，引导用户到设置页面
          if (mounted) {
            _showPermissionDeniedDialog(isPermanent: true);
          }
          return false;
        } else {
          // 权限被拒绝
          if (mounted) {
            _showPermissionDeniedDialog(isPermanent: false);
          }
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        // 权限被永久拒绝
        if (mounted) {
          _showPermissionDeniedDialog(isPermanent: true);
        }
        return false;
      }

      return false;
    } catch (e) {
      LoggerService.error('❌ 请求摄像头权限失败', error: e);
      return false;
    }
  }

  /// 显示权限被拒绝对话框
  void _showPermissionDeniedDialog({required bool isPermanent}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要摄像头权限'),
        content: Text(
          isPermanent
              ? '扫码签到需要使用摄像头。请在系统设置中授予摄像头权限。'
              : '扫码签到需要使用摄像头。请授予摄像头权限以继续。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // 返回上一页
            },
            child: const Text('取消'),
          ),
          if (isPermanent)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text('去设置'),
            )
          else
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _requestCameraPermission();
              },
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  /// 显示不支持的平台对话框
  void _showUnsupportedPlatformDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('不支持的平台'),
        content: const Text('扫码签到功能仅支持 Android 和 iOS 平台。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // 返回上一页
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 处理扫码结果
  Future<void> _handleScan(BarcodeCapture capture) async {
    // 防止重复处理
    if (_isProcessing || _hasScanned) {
      return;
    }

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      return;
    }

    final barcode = barcodes.first;
    final qrContent = barcode.rawValue;

    if (qrContent == null || qrContent.isEmpty) {
      LoggerService.warning('⚠️ 二维码内容为空');
      return;
    }

    setState(() {
      _isProcessing = true;
      _hasScanned = true;
    });

    try {
      LoggerService.info('📷 扫描到二维码: $qrContent');

      // 生成带抖动的地理位置
      final location = _generateLocation();

      // 调用 provider 进行签到
      final provider = Provider.of<LaborClubProvider>(context, listen: false);
      final response = await provider.scanSignIn(qrContent, location);

      if (mounted) {
        if (response != null) {
          _showSignInResult(response);
        } else {
          _showErrorDialog('签到失败，请稍后重试');
        }
      }
    } catch (e) {
      LoggerService.error('❌ 处理扫码结果失败', error: e);
      if (mounted) {
        _showErrorDialog('签到失败: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// 生成带抖动的地理位置
  ///
  /// 基础坐标：117.424733, 32.905237
  /// 添加 ±0.0001 度的随机偏移
  String _generateLocation() {
    const baseLongitude = 117.424733;
    const baseLatitude = 32.905237;
    const jitterRange = 0.0001;

    final random = Random();

    // 生成 -jitterRange 到 +jitterRange 的随机偏移
    final longitudeOffset = (random.nextDouble() * 2 - 1) * jitterRange;
    final latitudeOffset = (random.nextDouble() * 2 - 1) * jitterRange;

    final longitude = baseLongitude + longitudeOffset;
    final latitude = baseLatitude + latitudeOffset;

    final location = '$longitude,$latitude';
    LoggerService.info('📍 生成地理位置: $location');

    return location;
  }

  /// 显示签到结果对话框
  void _showSignInResult(SignInResponse response) {
    final isSuccess = response.isSuccess;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.shade300
                        : Colors.green)
                  : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.red.shade300
                        : Colors.red),
            ),
            const SizedBox(width: 8),
            Text(isSuccess ? '签到成功' : '签到失败'),
          ],
        ),
        content: Text(response.msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // 关闭对话框
              Navigator.of(context).pop(); // 返回上一页
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.error,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.red.shade300
                  : Colors.red,
            ),
            const SizedBox(width: 8),
            const Text('错误'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // 重置状态，允许重新扫描
              setState(() {
                _hasScanned = false;
              });
            },
            child: const Text('重试'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // 返回上一页
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          AdaptiveSliverAppBar(
            title: '扫码签到',
            actions: [
              if (_controller != null)
                IconButton(
                  icon: const Icon(Icons.flash_on),
                  onPressed: () => _controller?.toggleTorch(),
                  tooltip: '手电筒',
                ),
            ],
          ),
          SliverFillRemaining(child: _buildScannerBody()),
        ],
      ),
    );
  }

  /// 构建扫码器主体
  Widget _buildScannerBody() {
    if (!_isPlatformSupported()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_android_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('不支持的平台', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '扫码签到功能仅支持 Android 和 iOS 平台',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // 扫码器
        MobileScanner(controller: _controller, onDetect: _handleScan),

        // 扫描框叠加层
        _buildScanOverlay(),

        // 提示文字
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isProcessing ? '正在签到...' : '请将二维码放入框内',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建扫描框叠加层
  Widget _buildScanOverlay() {
    return CustomPaint(painter: _ScanOverlayPainter(), child: Container());
  }
}

/// 扫描框绘制器
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    // 扫描框大小
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    final scanRect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    // 绘制半透明背景（除了扫描框区域）
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(scanRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // 绘制扫描框边角
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final cornerLength = 30.0;

    // 左上角
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerLength, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + cornerLength),
      cornerPaint,
    );

    // 右上角
    canvas.drawLine(
      Offset(left + scanAreaSize, top),
      Offset(left + scanAreaSize - cornerLength, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + scanAreaSize, top),
      Offset(left + scanAreaSize, top + cornerLength),
      cornerPaint,
    );

    // 左下角
    canvas.drawLine(
      Offset(left, top + scanAreaSize),
      Offset(left + cornerLength, top + scanAreaSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + scanAreaSize),
      Offset(left, top + scanAreaSize - cornerLength),
      cornerPaint,
    );

    // 右下角
    canvas.drawLine(
      Offset(left + scanAreaSize, top + scanAreaSize),
      Offset(left + scanAreaSize - cornerLength, top + scanAreaSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + scanAreaSize, top + scanAreaSize),
      Offset(left + scanAreaSize, top + scanAreaSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
