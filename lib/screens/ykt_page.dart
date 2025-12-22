import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ykt/card_balance.dart';
import '../models/ykt/transaction_record.dart';
import '../models/ykt/utility_models.dart';
import '../providers/ykt_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/logger_service.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/app_background.dart';

/// 一卡通页面
///
/// 展示校园卡余额、消费记录、电费充值功能
/// 充值模块默认锁定，需要输入密码解锁
class YKTPage extends StatefulWidget {
  const YKTPage({super.key});

  @override
  State<YKTPage> createState() => _YKTPageState();
}

class _YKTPageState extends State<YKTPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<YKTProvider?>(context, listen: false);
    if (provider == null) return;

    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == YKTState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    await _loadData(forceRefresh: true);
  }

  void _showErrorDialog(String message, bool retryable) {
    showDialog(
      context: context,
      builder: (context) => RetryableErrorDialog(
        message: message,
        retryable: retryable,
        onRetry: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final hasBackground = themeProvider.backgroundPath != null;

        return Scaffold(
          backgroundColor: hasBackground ? Colors.transparent : null,
          body: AppBackground(
            child: Consumer<YKTProvider?>(
              builder: (context, provider, child) {
                if (provider == null) {
                  return CustomScrollView(
                    slivers: [
                      const AdaptiveSliverAppBar(title: '一卡通'),
                      const SliverLoadingIndicator(message: '正在初始化...'),
                    ],
                  );
                }

                if (provider.state == YKTState.loading) {
                  return CustomScrollView(
                    slivers: [
                      AdaptiveSliverAppBar(
                        title: '一卡通',
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _refreshData,
                            tooltip: '刷新',
                          ),
                        ],
                      ),
                      const SliverLoadingIndicator(message: '正在加载一卡通信息...'),
                    ],
                  );
                }

                if (provider.state == YKTState.loaded && provider.balance != null) {
                  return RefreshIndicator(
                    onRefresh: _refreshData,
                    child: CustomScrollView(
                      slivers: [
                        AdaptiveSliverAppBar(
                          title: '一卡通',
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _refreshData,
                              tooltip: '刷新',
                            ),
                          ],
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              _buildBalanceCard(context, provider.balance!),
                              const SizedBox(height: 16),
                              _buildPaymentCard(context, provider),
                              const SizedBox(height: 16),
                              _buildTransactionCard(context, provider),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (provider.state == YKTState.error) {
                  return CustomScrollView(
                    slivers: [
                      AdaptiveSliverAppBar(
                        title: '一卡通',
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _refreshData,
                            tooltip: '刷新',
                          ),
                        ],
                      ),
                      SliverFillRemaining(
                        child: EmptyState.needRefresh(
                          title: '数据加载失败',
                          description: provider.errorMessage ?? '请点击刷新重新加载',
                          onAction: _refreshData,
                        ),
                      ),
                    ],
                  );
                }

                return CustomScrollView(
                  slivers: [
                    AdaptiveSliverAppBar(
                      title: '一卡通',
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _refreshData,
                          tooltip: '刷新',
                        ),
                      ],
                    ),
                    SliverFillRemaining(
                      child: EmptyState.noData(
                        title: '暂无数据',
                        description: '点击右上角刷新按钮加载数据',
                        actionText: '刷新',
                        onAction: _refreshData,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 构建余额卡片
  Widget _buildBalanceCard(BuildContext context, CardBalance balance) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).primaryColor;
    final blueColor = isDark ? Colors.blue.shade300 : Colors.blue;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card, size: 20, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                '校园卡余额',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  balance.balance.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: blueColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    ' 元',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建充值卡片
  Widget _buildPaymentCard(BuildContext context, YKTProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUnlocked = provider.isPaymentUnlocked;
    final orangeColor = isDark ? Colors.orange.shade300 : Colors.orange;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt,
                size: 20,
                color: isUnlocked
                    ? orangeColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '电费充值',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (!isUnlocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: orangeColor.withValues(alpha: isDark ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 12, color: orangeColor),
                      const SizedBox(width: 4),
                      Text(
                        '已锁定',
                        style: TextStyle(
                          fontSize: 11,
                          color: orangeColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isUnlocked) ...[
            // 锁定状态
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '充值功能已锁定',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击下方按钮验证密码后解锁',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showUnlockDialog(context, provider),
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('解锁充值'),
                  ),
                ],
              ),
            ),
          ] else ...[
            // 解锁状态
            _buildPaymentContent(context, provider),
          ],
        ],
      ),
    );
  }

  /// 构建充值内容
  Widget _buildPaymentContent(BuildContext context, YKTProvider provider) {
    final primaryColor = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).primaryColor;

    return Column(
      children: [
        // 学生信息
        if (provider.studentInfo != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.person, size: 16, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.studentInfo!.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '学号: ${provider.studentInfo!.studentId}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '余额: ${provider.studentInfo!.balance.toStringAsFixed(2)}元',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade300
                        : Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 充值按钮
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _showPaymentDialog(context, provider),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('充值电费'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _showPurchaseHistoryDialog(context, provider),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('充值记录'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 锁定按钮
        TextButton.icon(
          onPressed: () => provider.lockPayment(),
          icon: Icon(
            Icons.lock,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          label: Text(
            '锁定充值功能',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }


  /// 构建消费记录卡片
  Widget _buildTransactionCard(BuildContext context, YKTProvider provider) {
    final primaryColor = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).primaryColor;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 20, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                '消费记录',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (provider.transactions != null)
                Text(
                  '${provider.transactions!.startDate} ~ ${provider.transactions!.endDate}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => provider.refreshTransactions(),
                tooltip: '刷新消费记录',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 根据消费记录状态显示不同内容
          _buildTransactionContent(context, provider),
        ],
      ),
    );
  }

  /// 构建消费记录内容
  Widget _buildTransactionContent(BuildContext context, YKTProvider provider) {
    // 加载中
    if (provider.transactionState == TransactionLoadState.loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                '正在加载消费记录...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '这可能需要一些时间',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 错误状态
    if (provider.transactionState == TransactionLoadState.error) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.red.shade300.withValues(alpha: 0.5)
                    : Colors.red.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                '加载消费记录失败',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                provider.transactionError ?? '请点击重试按钮重新加载',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => provider.refreshTransactions(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // 加载完成
    final transactions = provider.transactions;
    final records = transactions?.records ?? [];

    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '暂无消费记录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).primaryColor;
    final redColor = isDark ? Colors.red.shade300 : Colors.red;
    final greenColor = isDark ? Colors.green.shade300 : Colors.green;

    // 预先获取要显示的记录
    final displayRecords = records.take(10).toList();

    return Column(
      children: [
        // 统计信息
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildStatChip(context, '共 ${records.length} 条', Icons.list, primaryColor, isDark),
            _buildStatChip(context, '支出 ${transactions!.totalExpense.toStringAsFixed(2)}元', Icons.remove, redColor, isDark),
            _buildStatChip(context, '收入 ${transactions.totalIncome.toStringAsFixed(2)}元', Icons.add, greenColor, isDark),
          ],
        ),
        const SizedBox(height: 12),
        // 消费记录列表（最多显示10条）
        for (final record in displayRecords)
          _buildTransactionItem(context, record, isDark),
        if (records.length > 10) ...[
          const SizedBox(height: 8),
          Text(
            '仅显示最近 10 条记录',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 构建统计标签
  Widget _buildStatChip(BuildContext context, String text, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// 构建消费记录项
  Widget _buildTransactionItem(BuildContext context, TransactionRecord record, bool isDark) {
    final isExpense = record.isExpense;
    final color = isExpense
        ? (isDark ? Colors.red.shade300 : Colors.red)
        : (isDark ? Colors.green.shade300 : Colors.green);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExpense ? Icons.remove : Icons.add,
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.operationType,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.transactionTime,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (record.area.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      record.area,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 金额
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  record.amountText,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  '余额: ${record.balance.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 显示解锁对话框
  Future<void> _showUnlockDialog(BuildContext context, YKTProvider provider) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _UnlockPaymentDialog(authProvider: authProvider),
    );

    if (result == true && mounted) {
      provider.unlockPayment();
      await provider.loadStudentInfo();
    }
  }

  /// 显示充值对话框
  Future<void> _showPaymentDialog(BuildContext context, YKTProvider provider) async {
    if (provider.studentInfo == null) {
      final loaded = await provider.loadStudentInfo();
      if (!loaded) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => RetryableErrorDialog(
              message: '无法加载学生信息，请稍后重试',
              retryable: true,
              onRetry: () => _showPaymentDialog(context, provider),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final result = await showDialog<UtilityPaymentResult>(
      context: context,
      builder: (dialogContext) => _PaymentDialog(provider: provider),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '充值成功: ${result.message}' : '充值失败: ${result.message}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  /// 显示购电记录对话框
  Future<void> _showPurchaseHistoryDialog(BuildContext context, YKTProvider provider) async {
    await provider.loadPurchaseHistory();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => _PurchaseHistoryDialog(purchaseHistory: provider.purchaseHistory),
    );
  }
}

/// 解锁充值功能对话框
class _UnlockPaymentDialog extends StatefulWidget {
  final AuthProvider authProvider;

  const _UnlockPaymentDialog({required this.authProvider});

  @override
  State<_UnlockPaymentDialog> createState() => _UnlockPaymentDialogState();
}

class _UnlockPaymentDialogState extends State<_UnlockPaymentDialog> {
  final _passwordController = TextEditingController();
  bool _isVerifying = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = '请输入密码');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final credentials = widget.authProvider.credentials;
    if (credentials == null) {
      setState(() {
        _isVerifying = false;
        _errorMessage = '无法获取用户信息';
      });
      return;
    }

    if (password == credentials.password || password == credentials.ecPassword) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isVerifying = false;
        _errorMessage = '密码错误，请输入登录时使用的 UAAP 密码或 VPN 密码';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.lock,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade300
                  : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('解锁充值功能'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange.withValues(alpha: 0.15)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.shade300.withValues(alpha: 0.3)
                      : Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.shade300
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '为保护您的账户安全，请输入登录时使用的 UAAP 密码或 VPN 密码进行验证。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.orange.shade300
                            : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '请输入 UAAP 密码或 VPN 密码',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isVerifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isVerifying ? null : _verify,
          child: _isVerifying
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('验证'),
        ),
      ],
    );
  }
}


/// 电费充值对话框
class _PaymentDialog extends StatefulWidget {
  final YKTProvider provider;

  const _PaymentDialog({required this.provider});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String? _selectedDormId;
  String? _selectedDormName;
  String? _selectedBuildingId;
  String? _selectedBuildingName;
  String? _selectedFloorId;
  String? _selectedFloorName;
  String? _selectedRoomId;
  String? _selectedRoomName;

  List<SelectOption> _dorms = [];
  List<SelectOption> _buildings = [];
  List<SelectOption> _floors = [];
  List<SelectOption> _rooms = [];

  bool _loadingDorms = true;
  bool _loadingBuildings = false;
  bool _loadingFloors = false;
  bool _loadingRooms = false;
  bool _isPaying = false;

  final _amountController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _loadDorms();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadDorms() async {
    try {
      final response = await widget.provider.service.utility.getDormList();
      if (response.success && response.data != null) {
        setState(() {
          _dorms = response.data!;
          _loadingDorms = false;
        });
      } else {
        setState(() => _loadingDorms = false);
      }
    } catch (e) {
      LoggerService.error('加载校区失败', error: e);
      setState(() => _loadingDorms = false);
    }
  }

  Future<void> _loadBuildings(String dormId, String dormName) async {
    setState(() {
      _loadingBuildings = true;
      _buildings = [];
      _floors = [];
      _rooms = [];
      _selectedBuildingId = null;
      _selectedBuildingName = null;
      _selectedFloorId = null;
      _selectedFloorName = null;
      _selectedRoomId = null;
      _selectedRoomName = null;
    });

    try {
      final response = await widget.provider.service.utility.getBuildingList(
        dormId: dormId,
        dormName: dormName,
      );
      if (response.success && response.data != null) {
        setState(() {
          _buildings = response.data!;
          _loadingBuildings = false;
        });
      } else {
        setState(() => _loadingBuildings = false);
      }
    } catch (e) {
      LoggerService.error('加载楼栋失败', error: e);
      setState(() => _loadingBuildings = false);
    }
  }

  Future<void> _loadFloors(String buildingId) async {
    setState(() {
      _loadingFloors = true;
      _floors = [];
      _rooms = [];
      _selectedFloorId = null;
      _selectedFloorName = null;
      _selectedRoomId = null;
      _selectedRoomName = null;
    });

    try {
      final response = await widget.provider.service.utility.getFloorList(
        dormId: _selectedDormId!,
        buildingId: buildingId,
        dormName: _selectedDormName!,
      );
      if (response.success && response.data != null) {
        setState(() {
          _floors = response.data!;
          _loadingFloors = false;
        });
      } else {
        setState(() => _loadingFloors = false);
      }
    } catch (e) {
      LoggerService.error('加载楼层失败', error: e);
      setState(() => _loadingFloors = false);
    }
  }

  Future<void> _loadRooms(String floorId) async {
    setState(() {
      _loadingRooms = true;
      _rooms = [];
      _selectedRoomId = null;
      _selectedRoomName = null;
    });

    try {
      final response = await widget.provider.service.utility.getRoomList(
        dormId: _selectedDormId!,
        buildingId: _selectedBuildingId!,
        floorId: floorId,
        dormName: _selectedDormName!,
      );
      if (response.success && response.data != null) {
        setState(() {
          _rooms = response.data!;
          _loadingRooms = false;
        });
      } else {
        setState(() => _loadingRooms = false);
      }
    } catch (e) {
      LoggerService.error('加载房间失败', error: e);
      setState(() => _loadingRooms = false);
    }
  }

  Future<void> _pay() async {
    if (_selectedRoomId == null || widget.provider.studentInfo == null) return;

    final amountText = _amountController.text.trim();
    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效的充值金额（正整数）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isPaying = true);

    final request = UtilityPaymentRequest(
      roomId: _selectedRoomId!,
      dormId: _selectedDormId!,
      dormName: _selectedDormName!,
      buildName: _selectedBuildingName!,
      floorName: _selectedFloorName!,
      roomName: _selectedRoomName!,
      accId: widget.provider.studentInfo!.accId,
      balances: widget.provider.studentInfo!.balance.toString(),
      money: amount,
    );

    final result = await widget.provider.payElectricity(request);

    setState(() => _isPaying = false);

    if (mounted && result != null) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.bolt,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade300
                  : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('电费充值'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 校区选择
              _buildDropdown(
                label: '校区',
                value: _selectedDormId,
                items: _dorms,
                loading: _loadingDorms,
                hint: '请选择校区',
                onChanged: (value) {
                  final dorm = _dorms.firstWhere((d) => d.value == value);
                  setState(() {
                    _selectedDormId = value;
                    _selectedDormName = dorm.name;
                  });
                  if (value != null) _loadBuildings(value, dorm.name);
                },
              ),
              const SizedBox(height: 16),
              // 楼栋选择
              _buildDropdown(
                label: '楼栋',
                value: _selectedBuildingId,
                items: _buildings,
                loading: _loadingBuildings,
                hint: _selectedDormId == null ? '请先选择校区' : '请选择楼栋',
                enabled: _selectedDormId != null && _buildings.isNotEmpty,
                onChanged: (value) {
                  final building = _buildings.firstWhere((b) => b.value == value);
                  setState(() {
                    _selectedBuildingId = value;
                    _selectedBuildingName = building.name;
                  });
                  if (value != null) _loadFloors(value);
                },
              ),
              const SizedBox(height: 16),
              // 楼层选择
              _buildDropdown(
                label: '楼层',
                value: _selectedFloorId,
                items: _floors,
                loading: _loadingFloors,
                hint: _selectedBuildingId == null ? '请先选择楼栋' : '请选择楼层',
                enabled: _selectedBuildingId != null && _floors.isNotEmpty,
                onChanged: (value) {
                  final floor = _floors.firstWhere((f) => f.value == value);
                  setState(() {
                    _selectedFloorId = value;
                    _selectedFloorName = floor.name;
                  });
                  if (value != null) _loadRooms(value);
                },
              ),
              const SizedBox(height: 16),
              // 房间选择
              _buildDropdown(
                label: '房间',
                value: _selectedRoomId,
                items: _rooms,
                loading: _loadingRooms,
                hint: _selectedFloorId == null ? '请先选择楼层' : '请选择房间',
                enabled: _selectedFloorId != null && _rooms.isNotEmpty,
                onChanged: (value) {
                  final room = _rooms.firstWhere((r) => r.value == value);
                  setState(() {
                    _selectedRoomId = value;
                    _selectedRoomName = room.name;
                  });
                },
              ),
              const SizedBox(height: 16),
              // 充值金额
              Text('充值金额（元）', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '请输入金额',
                ),
              ),
              const SizedBox(height: 8),
              // 快捷金额按钮
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in [10, 50, 100])
                    OutlinedButton(
                      onPressed: () {
                        _amountController.text = amount.toString();
                        setState(() {});
                      },
                      child: Text('$amount 元'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // 提示信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade300.withValues(alpha: 0.3)
                        : Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade300
                          : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '充值金额必须为正整数，充值后将从校园卡余额中扣除。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPaying ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (_selectedRoomId != null && !_isPaying) ? _pay : null,
          child: _isPaying
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('确认充值'),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<SelectOption> items,
    required bool loading,
    required String hint,
    bool enabled = true,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        if (loading)
          const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
        else
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint,
            ),
            items: items.map((item) => DropdownMenuItem(
              value: item.value,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: enabled ? onChanged : null,
          ),
      ],
    );
  }
}


/// 购电记录对话框
class _PurchaseHistoryDialog extends StatelessWidget {
  final ElectricPurchaseQueryResult? purchaseHistory;

  const _PurchaseHistoryDialog({this.purchaseHistory});

  @override
  Widget build(BuildContext context) {
    final records = purchaseHistory?.records ?? [];

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.history,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.green.shade300
                  : Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('购电记录'),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (purchaseHistory != null) ...[
              Row(
                children: [
                  Text(
                    '${purchaseHistory!.startDate} ~ ${purchaseHistory!.endDate}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${records.length} 条，合计 ${purchaseHistory!.totalAmount.toStringAsFixed(2)} 元',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
            ],
            Expanded(
              child: records.isEmpty
                  ? Center(
                      child: Text(
                        '暂无购电记录',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record.roomInfo,
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        record.purchaseDate,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${record.amount.toStringAsFixed(2)} 元',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.green.shade300
                                        : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
