import 'package:flutter/material.dart';

/// Material 3 风格的加载指示器
///
/// 提供多种样式的加载动画，适配不同场景
class LoadingIndicator extends StatelessWidget {
  /// 加载提示文字
  final String? message;

  /// 是否显示为卡片样式
  final bool asCard;

  /// 指示器大小
  final double size;

  const LoadingIndicator({
    super.key,
    this.message,
    this.asCard = false,
    this.size = 48.0,
  });

  /// 创建居中的加载指示器（用于整页加载）
  const LoadingIndicator.center({super.key, this.message, this.size = 48.0})
    : asCard = false;

  /// 创建卡片样式的加载指示器
  const LoadingIndicator.card({super.key, this.message, this.size = 48.0})
    : asCard = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final indicator = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 加载动画
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator.adaptive(
            strokeWidth: 3.5,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
        // 加载文字
        if (message != null) ...[
          const SizedBox(height: 20),
          Text(
            message!,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '请稍候...',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (asCard) {
      return Center(
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: indicator,
          ),
        ),
      );
    }

    return Center(child: indicator);
  }
}

/// Sliver 版本的加载指示器
///
/// 用于 CustomScrollView 中
class SliverLoadingIndicator extends StatelessWidget {
  /// 加载提示文字
  final String? message;

  /// 指示器大小
  final double size;

  const SliverLoadingIndicator({super.key, this.message, this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: LoadingIndicator(message: message, size: size),
    );
  }
}

/// 线性加载指示器
///
/// 用于顶部显示加载进度
class LinearLoadingIndicator extends StatelessWidget {
  /// 是否显示
  final bool visible;

  const LinearLoadingIndicator({super.key, this.visible = true});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
