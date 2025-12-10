import 'package:fluent_ui/fluent_ui.dart';

/// WinUI 风格的空状态组件
///
/// 用于显示页面无数据、需要刷新或其他空白状态
/// 使用 fluent_ui 的组件和图标
class WinUIEmptyState extends StatelessWidget {
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

  const WinUIEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionText,
    this.onAction,
    this.iconSize = 64,
    this.iconColor,
  });

  /// 创建无数据状态
  factory WinUIEmptyState.noData({
    String title = '暂无数据',
    String? description,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return WinUIEmptyState(
      icon: FluentIcons.inbox,
      title: title,
      description: description,
      actionText: actionText,
      onAction: onAction,
    );
  }

  /// 创建需要刷新状态
  factory WinUIEmptyState.needRefresh({
    String title = '数据加载失败',
    String? description = '请点击刷新重新加载',
    VoidCallback? onAction,
  }) {
    return WinUIEmptyState(
      icon: FluentIcons.refresh,
      title: title,
      description: description,
      actionText: '刷新',
      onAction: onAction,
    );
  }

  /// 创建无考试状态
  factory WinUIEmptyState.noExams({
    String title = '最近没有考试',
    String? description = '暂时没有安排考试',
    VoidCallback? onAction,
  }) {
    return WinUIEmptyState(
      icon: FluentIcons.event_accepted,
      title: title,
      description: description,
      actionText: onAction != null ? '刷新' : null,
      onAction: onAction,
    );
  }

  /// 创建无课程状态
  factory WinUIEmptyState.noCourses({
    String title = '暂无课程',
    String? description,
    VoidCallback? onAction,
  }) {
    return WinUIEmptyState(
      icon: FluentIcons.education,
      title: title,
      description: description,
      actionText: onAction != null ? '刷新' : null,
      onAction: onAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final defaultIconColor = theme.inactiveColor;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? defaultIconColor,
            ),
            const SizedBox(height: 16),
            // 标题
            Text(
              title,
              style: theme.typography.subtitle?.copyWith(
                color: theme.inactiveColor,
              ),
              textAlign: TextAlign.center,
            ),
            // 描述
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: theme.typography.body?.copyWith(
                  color: theme.inactiveColor.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            // 操作按钮
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.refresh, size: 16),
                    const SizedBox(width: 8),
                    Text(actionText!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
