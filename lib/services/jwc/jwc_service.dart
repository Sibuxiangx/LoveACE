import '../aufe/connector.dart';
import 'academic_service.dart';
import 'exam_service.dart';
import 'jwc_config.dart';
import 'plan_service.dart';
import 'score_service.dart';
import 'term_service.dart';

/// 教务系统服务统一入口
///
/// 提供对教务系统所有模块的访问，包括学术信息、成绩、课表等
/// 基于 AUFEConnection 实现，统一管理配置和服务实例
class JWCService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// 学术信息服务
  late final AcademicService academic;

  /// 学期信息服务
  late final TermService term;

  /// 成绩查询服务
  late final ScoreService score;

  /// 考试信息服务
  late final ExamService exam;

  /// 培养方案服务
  late final PlanService plan;

  // 预留其他模块扩展点
  // late final ScheduleService schedule;

  /// 创建教务系统服务实例
  ///
  /// [connection] AUFE连接器实例，用于网络通信
  JWCService(this.connection) : config = JWCConfig() {
    // 初始化学术信息服务
    academic = AcademicService(connection, config);

    // 初始化学期信息服务
    term = TermService(connection, config);

    // 初始化成绩查询服务
    score = ScoreService(connection, config);

    // 初始化考试信息服务
    exam = ExamService(connection, config, academic);

    // 初始化培养方案服务
    plan = PlanService(connection, config);

    // 未来可以在这里初始化其他服务模块
    // schedule = ScheduleService(connection, config);
  }
}
