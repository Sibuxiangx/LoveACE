import '../aufe/connector.dart';
import 'balance_service.dart';
import 'transaction_service.dart';
import 'utility_service.dart';
import 'ykt_config.dart';

/// 一卡通系统服务统一入口
///
/// 提供对一卡通系统所有模块的访问，包括余额查询、消费记录、电费充值等
/// 基于 AUFEConnection 实现，统一管理配置和服务实例
class YKTService {
  final AUFEConnection connection;
  final YKTConfig config;

  /// 余额查询服务
  late final BalanceService balance;

  /// 消费记录查询服务
  late final TransactionService transaction;

  /// 电费充值服务
  late final UtilityService utility;

  /// 创建一卡通系统服务实例
  ///
  /// [connection] AUFE连接器实例，用于网络通信
  YKTService(this.connection) : config = YKTConfig() {
    // 初始化余额查询服务
    balance = BalanceService(connection, config);
    // 初始化消费记录查询服务
    transaction = TransactionService(connection, config);
    // 初始化电费充值服务
    utility = UtilityService(connection, config);
  }

  /// 初始化一卡通会话
  ///
  /// 在使用其他服务前调用，确保会话已建立
  Future<void> initSession() async {
    await balance.initSession();
  }
}
