import 'package:fluent_ui/fluent_ui.dart';

/// WinUI 风格的加载指示器组件
///
/// 使用 fluent_ui 的 ProgressRing 实现加载动画
class WinUILoading extends StatelessWidget {
  /// 加载提示文字
  final String? message;

  /// 指示器大小
  final double size;

  const WinUILoading({
    super.key,
    this.message,
    this.size = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: const ProgressRing(),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.typography.body?.copyWith(
                color: theme.inactiveColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '请稍候...',
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// WinUI 风格的线性加载指示器
///
/// 用于顶部显示加载进度
class WinUILinearLoading extends StatelessWidget {
  /// 是否显示
  final bool visible;

  const WinUILinearLoading({
    super.key,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return const ProgressBar();
  }
}
