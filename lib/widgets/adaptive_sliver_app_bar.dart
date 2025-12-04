import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// 自适应 SliverAppBar
///
/// 根据背景状态自动调整样式和文字颜色
/// 支持背景模糊效果和自适应文字颜色
class AdaptiveSliverAppBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final bool pinned;
  final bool floating;
  final double? expandedHeight;
  final Widget? flexibleSpace;

  const AdaptiveSliverAppBar({
    super.key,
    required this.title,
    this.actions,
    this.pinned = true,
    this.floating = false,
    this.expandedHeight,
    this.flexibleSpace,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final hasBackground = themeProvider.backgroundPath != null;
        final textColor = hasBackground ? themeProvider.appBarTextColor : null;
        final iconColor = hasBackground ? themeProvider.appBarIconColor : null;

        return SliverAppBar(
          title: Text(
            title,
            style: hasBackground && textColor != null
                ? TextStyle(color: textColor)
                : null,
          ),
          centerTitle: false,
          pinned: pinned,
          floating: floating,
          expandedHeight: expandedHeight,
          backgroundColor: hasBackground ? Colors.transparent : null,
          foregroundColor: hasBackground ? iconColor : null,
          flexibleSpace: hasBackground
              ? ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: themeProvider.appBarBlur,
                      sigmaY: themeProvider.appBarBlur,
                    ),
                    child: Container(
                      color: Theme.of(context).colorScheme.surface.withValues(
                        alpha: themeProvider.appBarOpacity,
                      ),
                    ),
                  ),
                )
              : flexibleSpace,
          actions: actions,
        );
      },
    );
  }
}
