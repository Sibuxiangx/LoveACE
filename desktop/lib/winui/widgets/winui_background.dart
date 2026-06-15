import 'package:fluent_ui/fluent_ui.dart';

/// WinUI 风格的背景组件
///
/// 注意：fluent_ui 的 NavigationView 和 ScaffoldPage 有不透明背景，
/// 自定义背景图片功能暂不支持。此组件保留用于未来扩展。
class WinUIBackground extends StatelessWidget {
  final Widget child;

  const WinUIBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 直接返回子组件，背景功能暂不支持
    return child;
  }
}

/// WinUI 风格的 Acrylic 容器
///
/// 提供毛玻璃效果的容器，用于卡片或面板
class WinUIAcrylicContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? tintAlpha;
  final double? blurAmount;
  final BorderRadiusGeometry? borderRadius;

  const WinUIAcrylicContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.tintAlpha,
    this.blurAmount,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    Widget content = Acrylic(
      tint: theme.acrylicBackgroundColor,
      tintAlpha: tintAlpha ?? 0.8,
      luminosityAlpha: 0.9,
      blurAmount: blurAmount ?? 20,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
      child: padding != null
          ? Padding(padding: padding!, child: child)
          : child,
    );

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}
