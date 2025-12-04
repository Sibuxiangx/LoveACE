import 'package:flutter/material.dart';

/// 更多功能项模型
///
/// 表示一个可导航的功能入口
class MoreFeatureItem {
  /// 功能唯一标识
  final String id;

  /// 功能标题
  final String title;

  /// 功能描述
  final String description;

  /// 功能图标
  final IconData icon;

  /// 导航路由
  final String route;

  const MoreFeatureItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
  });
}
