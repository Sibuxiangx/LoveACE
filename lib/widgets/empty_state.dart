import 'package:flutter/material.dart';

/// 空数据状态组件
///
/// 用于显示页面无数据、需要刷新或其他空白状态
/// 支持自定义图标、标题、描述和操作按钮
class EmptyState extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 标题
  final String title;

  /// 描述文本（可选）
  final String? description;

  /// 操作按钮文本（可选）
  final String? actionText;

  /// 操作按钮回调（可选）
  final VoidCallback? onAction;

  /// 图标大小
  final double iconSize;

  /// 图标颜色
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionText,
    this.onAction,
    this.iconSize = 80,
    this.iconColor,
  });

  /// 创建无数据状态
  factory EmptyState.noData({
    String title = '暂无数据',
    String? description,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: title,
      description: description,
      actionText: actionText,
      onAction: onAction,
    );
  }

  /// 创建需要刷新状态
  factory EmptyState.needRefresh({
    String title = '数据加载失败',
    String? description = '请点击刷新重新加载',
    VoidCallback? onAction,
  }) {
    return EmptyState(
      icon: Icons.refresh,
      title: title,
      description: description,
      actionText: '刷新',
      onAction: onAction,
    );
  }

  /// 创建无考试状态
  factory EmptyState.noExams({
    String title = '最近没有考试',
    String? description = '暂时没有安排考试',
    VoidCallback? onAction,
  }) {
    return EmptyState(
      icon: Icons.event_available_outlined,
      title: title,
      description: description,
      actionText: onAction != null ? '刷新' : null,
      onAction: onAction,
    );
  }

  /// 创建无课程状态
  factory EmptyState.noCourses({
    String title = '暂无课程',
    String? description,
    VoidCallback? onAction,
  }) {
    return EmptyState(
      icon: Icons.school_outlined,
      title: title,
      description: description,
      actionText: onAction != null ? '刷新' : null,
      onAction: onAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultIconColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标
            Icon(icon, size: iconSize, color: iconColor ?? defaultIconColor),
            const SizedBox(height: 24),
            // 标题
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            // 描述
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            // 操作按钮
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
