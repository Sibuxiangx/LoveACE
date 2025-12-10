import 'package:fluent_ui/fluent_ui.dart';

/// 通知类型枚举
enum WinUINotificationType {
  /// 成功通知
  success,

  /// 错误通知
  error,

  /// 警告通知
  warning,

  /// 信息通知
  info,
}

/// WinUI 风格的通知组件
///
/// 使用 fluent_ui 的 InfoBar 实现轻量级通知提示
/// 支持成功、错误、警告、信息等类型
class WinUINotification extends StatelessWidget {
  /// 通知标题
  final String title;

  /// 通知内容（可选）
  final String? content;

  /// 通知类型
  final WinUINotificationType type;

  /// 是否显示关闭按钮
  final bool isClosable;

  /// 关闭回调
  final VoidCallback? onClose;

  /// 操作按钮文本（可选）
  final String? actionText;

  /// 操作按钮回调（可选）
  final VoidCallback? onAction;

  /// 是否为长内容模式
  final bool isLong;

  const WinUINotification({
    super.key,
    required this.title,
    this.content,
    this.type = WinUINotificationType.info,
    this.isClosable = true,
    this.onClose,
    this.actionText,
    this.onAction,
    this.isLong = false,
  });

  /// 创建成功通知
  factory WinUINotification.success({
    required String title,
    String? content,
    bool isClosable = true,
    VoidCallback? onClose,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return WinUINotification(
      title: title,
      content: content,
      type: WinUINotificationType.success,
      isClosable: isClosable,
      onClose: onClose,
      actionText: actionText,
      onAction: onAction,
    );
  }

  /// 创建错误通知
  factory WinUINotification.error({
    required String title,
    String? content,
    bool isClosable = true,
    VoidCallback? onClose,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return WinUINotification(
      title: title,
      content: content,
      type: WinUINotificationType.error,
      isClosable: isClosable,
      onClose: onClose,
      actionText: actionText,
      onAction: onAction,
    );
  }

  /// 创建警告通知
  factory WinUINotification.warning({
    required String title,
    String? content,
    bool isClosable = true,
    VoidCallback? onClose,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return WinUINotification(
      title: title,
      content: content,
      type: WinUINotificationType.warning,
      isClosable: isClosable,
      onClose: onClose,
      actionText: actionText,
      onAction: onAction,
    );
  }

  /// 创建信息通知
  factory WinUINotification.info({
    required String title,
    String? content,
    bool isClosable = true,
    VoidCallback? onClose,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return WinUINotification(
      title: title,
      content: content,
      type: WinUINotificationType.info,
      isClosable: isClosable,
      onClose: onClose,
      actionText: actionText,
      onAction: onAction,
    );
  }

  InfoBarSeverity get _severity {
    switch (type) {
      case WinUINotificationType.success:
        return InfoBarSeverity.success;
      case WinUINotificationType.error:
        return InfoBarSeverity.error;
      case WinUINotificationType.warning:
        return InfoBarSeverity.warning;
      case WinUINotificationType.info:
        return InfoBarSeverity.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      title: Text(title),
      content: content != null ? Text(content!) : null,
      severity: _severity,
      isLong: isLong,
      onClose: isClosable ? onClose : null,
      action: actionText != null && onAction != null
          ? Button(
              onPressed: onAction,
              child: Text(actionText!),
            )
          : null,
    );
  }
}

/// WinUI 通知管理器
///
/// 提供便捷的方法在页面顶部显示通知
class WinUINotificationManager {
  /// 显示通知（使用 displayInfoBar）
  static void show(
    BuildContext context, {
    required String title,
    String? content,
    WinUINotificationType type = WinUINotificationType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionText,
    VoidCallback? onAction,
  }) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(title),
          content: content != null ? Text(content) : null,
          severity: _getSeverity(type),
          action: actionText != null && onAction != null
              ? Button(
                  onPressed: () {
                    close();
                    onAction();
                  },
                  child: Text(actionText),
                )
              : null,
          onClose: close,
        );
      },
      duration: duration,
    );
  }

  /// 显示成功通知
  static void showSuccess(
    BuildContext context, {
    required String title,
    String? content,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      title: title,
      content: content,
      type: WinUINotificationType.success,
      duration: duration,
    );
  }

  /// 显示错误通知
  static void showError(
    BuildContext context, {
    required String title,
    String? content,
    Duration duration = const Duration(seconds: 5),
    String? actionText,
    VoidCallback? onAction,
  }) {
    show(
      context,
      title: title,
      content: content,
      type: WinUINotificationType.error,
      duration: duration,
      actionText: actionText,
      onAction: onAction,
    );
  }

  /// 显示警告通知
  static void showWarning(
    BuildContext context, {
    required String title,
    String? content,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      title: title,
      content: content,
      type: WinUINotificationType.warning,
      duration: duration,
    );
  }

  /// 显示信息通知
  static void showInfo(
    BuildContext context, {
    required String title,
    String? content,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      title: title,
      content: content,
      type: WinUINotificationType.info,
      duration: duration,
    );
  }

  static InfoBarSeverity _getSeverity(WinUINotificationType type) {
    switch (type) {
      case WinUINotificationType.success:
        return InfoBarSeverity.success;
      case WinUINotificationType.error:
        return InfoBarSeverity.error;
      case WinUINotificationType.warning:
        return InfoBarSeverity.warning;
      case WinUINotificationType.info:
        return InfoBarSeverity.info;
    }
  }
}
