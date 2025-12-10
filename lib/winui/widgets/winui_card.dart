import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

/// WinUI 风格的通用卡片组件
///
/// 使用 fluent_ui 的 Card 组件，支持自定义背景时的透明效果
class WinUICard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;

  const WinUICard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final hasBackground = themeProvider.backgroundPath != null;
        final cardOpacity = themeProvider.cardOpacity;
        final theme = FluentTheme.of(context);

        Widget cardContent = Card(
          padding: padding ?? const EdgeInsets.all(16),
          backgroundColor: hasBackground
              ? (backgroundColor ?? theme.cardColor).withValues(alpha: cardOpacity)
              : backgroundColor,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: child,
        );

        if (margin != null) {
          cardContent = Padding(
            padding: margin!,
            child: cardContent,
          );
        }

        return cardContent;
      },
    );
  }
}
