import 'package:flutter/material.dart';
import '../models/more_feature_item.dart';
import '../services/logger_service.dart';

/// 更多功能状态枚举
enum MoreState {
  /// 初始状态
  initial,

  /// 已加载功能列表
  loaded,
}

/// 更多功能管理器 Provider
///
/// 管理更多功能列表的状态和导航
class MoreProvider extends ChangeNotifier {
  MoreState _state = MoreState.initial;
  List<MoreFeatureItem> _features = [];

  /// 当前状态
  MoreState get state => _state;

  /// 功能列表
  List<MoreFeatureItem> get features => _features;

  MoreProvider() {
    initialize();
  }

  /// 初始化功能列表
  void initialize() {
    LoggerService.info('📋 初始化更多功能列表');

    _features = [
      const MoreFeatureItem(
        id: 'exam_info',
        title: '考试信息',
        description: '查看考试安排和座位信息',
        icon: Icons.assignment,
        route: '/exam-info',
      ),
      const MoreFeatureItem(
        id: 'training_plan',
        title: '培养方案完成情况',
        description: '查看培养方案完成进度和预估毕业学分',
        icon: Icons.school,
        route: '/training-plan',
      ),
      const MoreFeatureItem(
        id: 'competition_info',
        title: '学科竞赛',
        description: '查看获奖项目和学分汇总',
        icon: Icons.emoji_events,
        route: '/competition-info',
      ),
      const MoreFeatureItem(
        id: 'electricity',
        title: '电费查询',
        description: '查看宿舍电费余额、用电记录和充值记录',
        icon: Icons.electric_bolt,
        route: '/electricity',
      ),
      const MoreFeatureItem(
        id: 'labor_club',
        title: '劳动俱乐部',
        description: '查看劳动修课进度、报名活动和扫码签到',
        icon: Icons.group_work,
        route: '/labor-club',
      ),
    ];

    _state = MoreState.loaded;
    notifyListeners();

    LoggerService.info('✅ 更多功能列表初始化完成，共 ${_features.length} 个功能');
  }

  /// 导航到指定功能
  ///
  /// [context] 上下文
  /// [featureId] 功能ID
  void navigateToFeature(BuildContext context, String featureId) {
    LoggerService.info('🔗 导航到功能: $featureId');

    final feature = _features.firstWhere(
      (f) => f.id == featureId,
      orElse: () => throw Exception('功能不存在: $featureId'),
    );

    Navigator.pushNamed(context, feature.route);
    LoggerService.info('✅ 导航成功: ${feature.title}');
  }
}
