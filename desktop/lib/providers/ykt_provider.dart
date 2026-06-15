import 'package:flutter/foundation.dart';
import '../models/ykt/card_balance.dart';
import '../models/ykt/transaction_record.dart';
import '../models/ykt/utility_models.dart';
import '../services/ykt/ykt_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 一卡通页面状态
enum YKTState {
  initial,
  loading,
  loaded,
  error,
}

/// 消费记录加载状态
enum TransactionLoadState {
  initial,
  loading,
  loaded,
  error,
}

/// 一卡通 Provider
///
/// 管理一卡通余额、消费记录、电费充值等功能
class YKTProvider extends ChangeNotifier {
  final YKTService yktService;

  // 缓存键
  static const String _cacheKeyBalance = 'ykt_balance';
  static const String _cacheKeyTransactions = 'ykt_transactions';
  static const String _cacheKeyPurchaseHistory = 'ykt_purchase_history';
  static const Duration _cacheDuration = Duration(minutes: 10);

  // 主状态（余额）
  YKTState _state = YKTState.initial;
  String? _errorMessage;
  bool _isRetryable = false;

  // 消费记录单独的加载状态
  TransactionLoadState _transactionState = TransactionLoadState.initial;
  String? _transactionError;

  // 数据
  CardBalance? _balance;
  TransactionQueryResult? _transactions;
  StudentInfo? _studentInfo;
  ElectricPurchaseQueryResult? _purchaseHistory;

  // 充值模块解锁状态
  bool _isPaymentUnlocked = false;

  // Getters
  YKTState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isRetryable => _isRetryable;
  CardBalance? get balance => _balance;
  TransactionQueryResult? get transactions => _transactions;
  StudentInfo? get studentInfo => _studentInfo;
  ElectricPurchaseQueryResult? get purchaseHistory => _purchaseHistory;
  bool get isPaymentUnlocked => _isPaymentUnlocked;
  YKTService get service => yktService;

  // 消费记录状态 Getters
  TransactionLoadState get transactionState => _transactionState;
  String? get transactionError => _transactionError;
  bool get isTransactionLoading => _transactionState == TransactionLoadState.loading;

  YKTProvider(this.yktService);

  /// 加载数据
  Future<void> loadData({bool forceRefresh = false}) async {
    if (forceRefresh) {
      LoggerService.info('🔄 强制刷新，清除缓存');
      await _clearCache();
      await _loadFromNetwork();
      return;
    }

    final cacheLoaded = await _loadFromCache();
    if (cacheLoaded) {
      LoggerService.info('✅ 使用缓存数据');
      return;
    }

    LoggerService.info('📭 缓存不可用，从网络加载');
    await _loadFromNetwork();
  }

  /// 从缓存加载
  Future<bool> _loadFromCache() async {
    try {
      LoggerService.info('📦 尝试从缓存加载一卡通数据');

      final cachedBalance = await CacheManager.get<CardBalance>(
        key: _cacheKeyBalance,
        fromJson: (json) => CardBalance.fromJson(json),
      );

      final cachedTransactionsWrapper =
          await CacheManager.get<Map<String, dynamic>>(
        key: _cacheKeyTransactions,
        fromJson: (json) => json,
      );

      if (cachedBalance != null) {
        _balance = cachedBalance;
        _state = YKTState.loaded;
        _errorMessage = null;
        _isRetryable = false;

        if (cachedTransactionsWrapper != null) {
          _transactions =
              TransactionQueryResult.fromJson(cachedTransactionsWrapper);
          _transactionState = TransactionLoadState.loaded;
        }

        notifyListeners();
        LoggerService.info('✅ 从缓存加载一卡通数据成功');
        return true;
      }

      LoggerService.info('📭 缓存数据不完整');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载一卡通数据失败', error: e);
      return false;
    }
  }

  /// 从网络加载
  Future<void> _loadFromNetwork() async {
    _state = YKTState.loading;
    _errorMessage = null;
    _isRetryable = false;
    _transactionState = TransactionLoadState.initial;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载一卡通数据');

      // 初始化会话
      await yktService.initSession();

      // 获取余额
      final balanceResponse = await yktService.balance.getBalance();
      if (!balanceResponse.success) {
        _state = YKTState.error;
        _errorMessage = balanceResponse.error ?? '获取余额失败';
        _isRetryable = balanceResponse.retryable;
        notifyListeners();
        return;
      }

      _balance = balanceResponse.data;
      _state = YKTState.loaded;
      _errorMessage = null;
      _isRetryable = false;

      // 余额加载成功，先通知UI更新
      notifyListeners();
      LoggerService.info('✅ 余额加载成功: ${_balance?.balanceText}');

      // 保存余额到缓存
      await _saveBalanceToCache();

      // 异步加载消费记录（不阻塞主流程）
      _loadTransactionsAsync();
    } catch (e) {
      _state = YKTState.error;
      _errorMessage = '加载一卡通数据失败: ${e.toString()}';
      _isRetryable = true;
      notifyListeners();
      LoggerService.error('❌ 从网络加载一卡通数据失败', error: e);
    }
  }

  /// 异步加载消费记录
  Future<void> _loadTransactionsAsync() async {
    _transactionState = TransactionLoadState.loading;
    _transactionError = null;
    notifyListeners();

    try {
      LoggerService.info('🌐 开始加载消费记录...');

      final transactionsResponse = await yktService.transaction
          .getRecentTransactions()
          .timeout(
            const Duration(seconds: 600), // 600秒超时
            onTimeout: () {
              LoggerService.warning('⚠️ 获取消费记录超时');
              throw Exception('消费记录加载超时，请稍后重试');
            },
          );

      if (transactionsResponse.success && transactionsResponse.data != null) {
        _transactions = transactionsResponse.data;
        _transactionState = TransactionLoadState.loaded;
        _transactionError = null;

        // 保存到缓存
        await _saveTransactionsToCache();

        LoggerService.info('✅ 消费记录加载成功: ${_transactions?.count}条');
      } else {
        _transactionState = TransactionLoadState.error;
        _transactionError = transactionsResponse.error ?? '获取消费记录失败';
        LoggerService.warning('⚠️ 获取消费记录失败: $_transactionError');
      }
    } catch (e) {
      _transactionState = TransactionLoadState.error;
      _transactionError = e.toString();
      LoggerService.error('❌ 加载消费记录异常', error: e);
    }

    notifyListeners();
  }

  /// 单独刷新消费记录
  Future<void> refreshTransactions() async {
    await CacheManager.remove(_cacheKeyTransactions);
    await _loadTransactionsAsync();
  }

  /// 保存余额到缓存
  Future<void> _saveBalanceToCache() async {
    try {
      if (_balance != null) {
        await CacheManager.set(
          key: _cacheKeyBalance,
          data: _balance!,
          duration: _cacheDuration,
          toJson: (d) => d.toJson(),
        );
        LoggerService.info('💾 余额已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存余额到缓存失败', error: e);
    }
  }

  /// 保存消费记录到缓存
  Future<void> _saveTransactionsToCache() async {
    try {
      if (_transactions != null) {
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKeyTransactions,
          data: _transactions!.toJson(),
          duration: _cacheDuration,
          toJson: (d) => d,
        );
        LoggerService.info('💾 消费记录已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存消费记录到缓存失败', error: e);
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    await CacheManager.remove(_cacheKeyBalance);
    await CacheManager.remove(_cacheKeyTransactions);
    await CacheManager.remove(_cacheKeyPurchaseHistory);
  }

  /// 重置 Provider 状态（用于切换账号时）
  ///
  /// 清除所有缓存数据和内存状态，锁定充值模块
  Future<void> reset() async {
    LoggerService.info('🔄 重置一卡通 Provider 状态');

    // 清除缓存
    await _clearCache();

    // 重置状态
    _state = YKTState.initial;
    _errorMessage = null;
    _isRetryable = false;
    _transactionState = TransactionLoadState.initial;
    _transactionError = null;

    // 清除数据
    _balance = null;
    _transactions = null;
    _studentInfo = null;
    _purchaseHistory = null;

    // 锁定充值模块
    _isPaymentUnlocked = false;

    notifyListeners();
    LoggerService.info('✅ 一卡通 Provider 状态已重置');
  }

  /// 刷新数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }

  /// 解锁充值模块
  void unlockPayment() {
    _isPaymentUnlocked = true;
    notifyListeners();
  }

  /// 锁定充值模块
  void lockPayment() {
    _isPaymentUnlocked = false;
    notifyListeners();
  }

  /// 加载学生信息（用于充值）
  Future<bool> loadStudentInfo() async {
    try {
      LoggerService.info('🌐 加载学生信息');
      final response = await yktService.utility.getPageInfo();
      if (response.success && response.data != null) {
        _studentInfo = response.data;
        notifyListeners();
        LoggerService.info('✅ 加载学生信息成功');
        return true;
      }
      LoggerService.error('❌ 加载学生信息失败: ${response.error}');
      return false;
    } catch (e) {
      LoggerService.error('❌ 加载学生信息失败', error: e);
      return false;
    }
  }

  /// 加载购电明细
  Future<bool> loadPurchaseHistory() async {
    try {
      LoggerService.info('🌐 加载购电明细');

      // 尝试从缓存加载
      final cachedWrapper = await CacheManager.get<Map<String, dynamic>>(
        key: _cacheKeyPurchaseHistory,
        fromJson: (json) => json,
      );

      if (cachedWrapper != null) {
        _purchaseHistory = ElectricPurchaseQueryResult.fromJson(cachedWrapper);
        notifyListeners();
        LoggerService.info('✅ 从缓存加载购电明细成功');
        return true;
      }

      // 从网络加载
      final response = await yktService.utility.getRecentPurchaseHistory();
      if (response.success && response.data != null) {
        _purchaseHistory = response.data;

        // 保存到缓存
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKeyPurchaseHistory,
          data: _purchaseHistory!.toJson(),
          duration: _cacheDuration,
          toJson: (d) => d,
        );

        notifyListeners();
        LoggerService.info('✅ 加载购电明细成功');
        return true;
      }
      LoggerService.error('❌ 加载购电明细失败: ${response.error}');
      return false;
    } catch (e) {
      LoggerService.error('❌ 加载购电明细失败', error: e);
      return false;
    }
  }

  /// 执行电费充值
  Future<UtilityPaymentResult?> payElectricity(
      UtilityPaymentRequest request) async {
    try {
      LoggerService.info('⚡ 执行电费充值: ${request.money}元');
      final response = await yktService.utility.pay(request);
      if (response.success && response.data != null) {
        // 充值成功后刷新余额
        if (response.data!.success) {
          await loadData(forceRefresh: true);
        }
        return response.data;
      }
      return UtilityPaymentResult(
          success: false, message: response.error ?? '充值失败');
    } catch (e) {
      LoggerService.error('❌ 电费充值失败', error: e);
      return UtilityPaymentResult(success: false, message: '充值失败: $e');
    }
  }
}
