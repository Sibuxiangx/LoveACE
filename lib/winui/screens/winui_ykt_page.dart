import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/ykt/card_balance.dart';
import '../../models/ykt/transaction_record.dart';
import '../../models/ykt/utility_models.dart';
import '../../providers/ykt_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/logger_service.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';

/// WinUI 风格的一卡通页面
///
/// 展示校园卡余额、消费记录、电费充值功能
/// 充值模块默认锁定，需要输入密码解锁
class WinUIYKTPage extends StatefulWidget {
  const WinUIYKTPage({super.key});

  @override
  State<WinUIYKTPage> createState() => _WinUIYKTPageState();
}

class _WinUIYKTPageState extends State<WinUIYKTPage> {
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
    WinUIErrorDialog.show(
      context,
      message: message,
      retryable: retryable,
      onRetry: () => _loadData(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<YKTProvider?>(
      builder: (context, provider, child) {
        // Provider 为 null 时显示加载状态
        if (provider == null) {
          return const ScaffoldPage(
            header: PageHeader(title: Text('一卡通')),
            content: WinUILoading(message: '正在初始化...'),
          );
        }

        return ScaffoldPage(
          header: PageHeader(
            title: const Text('一卡通'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.refresh),
                  label: const Text('刷新'),
                  onPressed: _refreshData,
                ),
              ],
            ),
          ),
          content: _buildContent(context, provider),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, YKTProvider provider) {
    // 加载中
    if (provider.state == YKTState.loading) {
      return const WinUILoading(message: '正在加载一卡通信息');
    }

    // 加载完成
    if (provider.state == YKTState.loaded && provider.balance != null) {
      return _buildMainLayout(context, provider);
    }

    // 错误状态
    if (provider.state == YKTState.error) {
      return WinUIEmptyState.needRefresh(
        title: '数据加载失败',
        description: provider.errorMessage ?? '请点击刷新重新加载',
        onAction: _refreshData,
      );
    }

    // 初始状态
    return WinUIEmptyState.noData(
      title: '暂无数据',
      description: '点击右上角刷新按钮加载数据',
      actionText: '刷新',
      onAction: _refreshData,
    );
  }

  Widget _buildMainLayout(BuildContext context, YKTProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：余额卡片 + 充值模块
        SizedBox(
          width: 360,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildBalanceCard(context, provider.balance!),
                const SizedBox(height: 16),
                _buildPaymentCard(context, provider),
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 右侧：消费记录（带独立加载状态）
        Expanded(
          child: _buildTransactionSection(context, provider),
        ),
      ],
    );
  }

  /// 构建消费记录区域（带独立加载状态）
  Widget _buildTransactionSection(BuildContext context, YKTProvider provider) {
    final theme = FluentTheme.of(context);

    // 加载中状态
    if (provider.transactionState == TransactionLoadState.loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(FluentIcons.history, size: 16, color: theme.accentColor),
                const SizedBox(width: 8),
                Text('消费记录', style: theme.typography.subtitle),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 32, height: 32, child: ProgressRing()),
                  const SizedBox(height: 16),
                  Text(
                    '正在加载消费记录...',
                    style: theme.typography.body?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '这可能需要一些时间',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 错误状态
    if (provider.transactionState == TransactionLoadState.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(FluentIcons.history, size: 16, color: theme.accentColor),
                const SizedBox(width: 8),
                Text('消费记录', style: theme.typography.subtitle),
                const Spacer(),
                Button(
                  onPressed: () => provider.refreshTransactions(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.refresh, size: 14),
                      SizedBox(width: 4),
                      Text('重试'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.error_badge,
                    size: 48,
                    color: Colors.red.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载消费记录失败',
                    style: theme.typography.subtitle?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.transactionError ?? '请点击重试按钮重新加载',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 加载完成或初始状态
    return _buildTransactionList(context, provider);
  }

  Widget _buildBalanceCard(BuildContext context, CardBalance balance) {
    final theme = FluentTheme.of(context);

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.payment_card, size: 20, color: theme.accentColor),
              const SizedBox(width: 8),
              Text('校园卡余额', style: theme.typography.subtitle),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      balance.balance.toStringAsFixed(2),
                      style: theme.typography.display?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 48,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        ' 元',
                        style: theme.typography.body?.copyWith(
                          color: theme.inactiveColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(BuildContext context, YKTProvider provider) {
    final theme = FluentTheme.of(context);
    final isUnlocked = provider.isPaymentUnlocked;

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.lightning_bolt,
                size: 20,
                color: isUnlocked ? Colors.orange : theme.inactiveColor,
              ),
              const SizedBox(width: 8),
              Text('电费充值', style: theme.typography.subtitle),
              const Spacer(),
              if (!isUnlocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.lock, size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        '已锁定',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
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
                    FluentIcons.lock,
                    size: 48,
                    color: theme.inactiveColor.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '充值功能已锁定',
                    style: theme.typography.body?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击下方按钮验证密码后解锁',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _showUnlockDialog(context, provider),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.unlock, size: 16),
                        SizedBox(width: 8),
                        Text('解锁充值'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // 解锁状态 - 显示充值功能
            _buildPaymentContent(context, provider),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentContent(BuildContext context, YKTProvider provider) {
    final theme = FluentTheme.of(context);

    return Column(
      children: [
        // 学生信息
        if (provider.studentInfo != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(FluentIcons.contact, size: 16, color: theme.accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.studentInfo!.name,
                        style: theme.typography.bodyStrong,
                      ),
                      Text(
                        '学号: ${provider.studentInfo!.studentId}',
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '余额: ${provider.studentInfo!.balance.toStringAsFixed(2)}元',
                  style: theme.typography.body?.copyWith(
                    color: Colors.blue,
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
              child: FilledButton(
                onPressed: () => _showPaymentDialog(context, provider),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.lightning_bolt, size: 16),
                    SizedBox(width: 8),
                    Text('充值电费'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: () => _showPurchaseHistoryDialog(context, provider),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.history, size: 16),
                  SizedBox(width: 8),
                  Text('充值记录'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 锁定按钮
        Button(
          onPressed: () {
            provider.lockPayment();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FluentIcons.lock, size: 14, color: theme.inactiveColor),
              const SizedBox(width: 8),
              Text(
                '锁定充值功能',
                style: TextStyle(color: theme.inactiveColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionList(BuildContext context, YKTProvider provider) {
    final theme = FluentTheme.of(context);
    final transactions = provider.transactions;
    final records = transactions?.records ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(FluentIcons.history, size: 16, color: theme.accentColor),
              const SizedBox(width: 8),
              Text('消费记录', style: theme.typography.subtitle),
              const Spacer(),
              if (transactions != null)
                Text(
                  '${transactions.startDate} ~ ${transactions.endDate}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              const SizedBox(width: 8),
              Button(
                onPressed: () => provider.refreshTransactions(),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.refresh, size: 14),
                    SizedBox(width: 4),
                    Text('刷新'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 统计信息
        if (transactions != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatChip(
                  context,
                  '共 ${records.length} 条',
                  FluentIcons.list,
                  theme.accentColor,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  context,
                  '支出 ${transactions.totalExpense.toStringAsFixed(2)}元',
                  FluentIcons.remove,
                  Colors.red,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  context,
                  '收入 ${transactions.totalIncome.toStringAsFixed(2)}元',
                  FluentIcons.add,
                  Colors.green,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Divider(),
        Expanded(
          child: records.isEmpty
              ? Center(
                  child: Text(
                    '暂无消费记录',
                    style: theme.typography.body?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: records.length,
                  itemBuilder: (context, index) =>
                      _buildTransactionItem(context, records[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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

  Widget _buildTransactionItem(BuildContext context, TransactionRecord record) {
    final theme = FluentTheme.of(context);
    final isExpense = record.isExpense;
    final color = isExpense ? Colors.red : Colors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.resources.controlStrokeColorDefault,
          ),
        ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExpense ? FluentIcons.remove : FluentIcons.add,
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
                    style: theme.typography.body?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.transactionTime,
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                  if (record.area.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      record.area,
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor.withValues(alpha: 0.7),
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
                  style: theme.typography.bodyStrong?.copyWith(
                    color: color,
                  ),
                ),
                Text(
                  '余额: ${record.balance.toStringAsFixed(2)}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
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
  Future<void> _showUnlockDialog(
    BuildContext context,
    YKTProvider provider,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _UnlockPaymentDialog(
        authProvider: authProvider,
      ),
    );

    if (result == true && mounted) {
      provider.unlockPayment();
      // 加载学生信息
      await provider.loadStudentInfo();
    }
  }

  /// 显示充值对话框
  Future<void> _showPaymentDialog(
    BuildContext context,
    YKTProvider provider,
  ) async {
    if (provider.studentInfo == null) {
      final loaded = await provider.loadStudentInfo();
      if (!loaded) {
        if (mounted) {
          WinUIErrorDialog.show(
            context,
            message: '无法加载学生信息，请稍后重试',
            retryable: true,
            onRetry: () => _showPaymentDialog(context, provider),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final result = await showDialog<UtilityPaymentResult>(
      context: context,
      builder: (dialogContext) => _PaymentDialog(
        provider: provider,
      ),
    );

    if (result != null && mounted) {
      if (result.success) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('充值成功'),
            content: Text(result.message),
            severity: InfoBarSeverity.success,
            action: IconButton(
              icon: const Icon(FluentIcons.clear),
              onPressed: close,
            ),
          ),
        );
      } else {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('充值失败'),
            content: Text(result.message),
            severity: InfoBarSeverity.error,
            action: IconButton(
              icon: const Icon(FluentIcons.clear),
              onPressed: close,
            ),
          ),
        );
      }
    }
  }

  /// 显示购电记录对话框
  Future<void> _showPurchaseHistoryDialog(
    BuildContext context,
    YKTProvider provider,
  ) async {
    await provider.loadPurchaseHistory();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => _PurchaseHistoryDialog(
        purchaseHistory: provider.purchaseHistory,
      ),
    );
  }
}


/// 解锁充值功能对话框
class _UnlockPaymentDialog extends StatefulWidget {
  final AuthProvider authProvider;

  const _UnlockPaymentDialog({
    required this.authProvider,
  });

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

    // 验证密码（与登录时的 UAAP 密码或 EC 密码比对）
    final credentials = widget.authProvider.credentials;
    if (credentials == null) {
      setState(() {
        _isVerifying = false;
        _errorMessage = '无法获取用户信息';
      });
      return;
    }

    // 检查是否匹配 UAAP 密码或 EC 密码
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
    FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(FluentIcons.lock, color: Colors.orange, size: 20),
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
            const SizedBox(height: 8),
            InfoBar(
              title: const Text('安全验证'),
              content: const Text('为保护您的账户安全，请输入登录时使用的 UAAP 密码或 VPN 密码进行验证。'),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
            const SizedBox(height: 16),
            const Text('密码'),
            const SizedBox(height: 8),
            PasswordBox(
              controller: _passwordController,
              placeholder: '请输入 UAAP 密码或 VPN 密码',
              revealMode: _obscurePassword
                  ? PasswordRevealMode.hidden
                  : PasswordRevealMode.visible,
              onSubmitted: (_) => _verify(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _isVerifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isVerifying ? null : _verify,
          child: _isVerifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('验证'),
        ),
      ],
    );
  }
}

/// 电费充值对话框
class _PaymentDialog extends StatefulWidget {
  final YKTProvider provider;

  const _PaymentDialog({
    required this.provider,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  // 选择状态
  String? _selectedDormId;
  String? _selectedDormName;
  String? _selectedBuildingId;
  String? _selectedBuildingName;
  String? _selectedFloorId;
  String? _selectedFloorName;
  String? _selectedRoomId;
  String? _selectedRoomName;

  // 数据
  List<SelectOption> _dorms = [];
  List<SelectOption> _buildings = [];
  List<SelectOption> _floors = [];
  List<SelectOption> _rooms = [];

  // 加载状态
  bool _loadingDorms = true;
  bool _loadingBuildings = false;
  bool _loadingFloors = false;
  bool _loadingRooms = false;
  bool _isPaying = false;

  // 充值金额
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
      await displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('输入错误'),
          content: const Text('请输入有效的充值金额（正整数）'),
          severity: InfoBarSeverity.warning,
          action: IconButton(
            icon: const Icon(FluentIcons.clear),
            onPressed: close,
          ),
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
    FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(FluentIcons.lightning_bolt, color: Colors.orange, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('电费充值'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 校区选择
            const Text('校区'),
            const SizedBox(height: 8),
            _loadingDorms
                ? const Center(child: ProgressRing())
                : ComboBox<String>(
                    isExpanded: true,
                    placeholder: const Text('请选择校区'),
                    value: _selectedDormId,
                    items: _dorms
                        .map((d) => ComboBoxItem<String>(
                              value: d.value,
                              child: Text(d.name),
                            ))
                        .toList(),
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
            const Text('楼栋'),
            const SizedBox(height: 8),
            _loadingBuildings
                ? const Center(child: ProgressRing())
                : ComboBox<String>(
                    isExpanded: true,
                    placeholder: Text(_selectedDormId == null ? '请先选择校区' : '请选择楼栋'),
                    value: _selectedBuildingId,
                    items: _buildings
                        .map((b) => ComboBoxItem<String>(
                              value: b.value,
                              child: Text(b.name),
                            ))
                        .toList(),
                    onChanged: (_selectedDormId == null || _buildings.isEmpty)
                        ? null
                        : (value) {
                            final building =
                                _buildings.firstWhere((b) => b.value == value);
                            setState(() {
                              _selectedBuildingId = value;
                              _selectedBuildingName = building.name;
                            });
                            if (value != null) _loadFloors(value);
                          },
                  ),
            const SizedBox(height: 16),
            // 楼层选择
            const Text('楼层'),
            const SizedBox(height: 8),
            _loadingFloors
                ? const Center(child: ProgressRing())
                : ComboBox<String>(
                    isExpanded: true,
                    placeholder:
                        Text(_selectedBuildingId == null ? '请先选择楼栋' : '请选择楼层'),
                    value: _selectedFloorId,
                    items: _floors
                        .map((f) => ComboBoxItem<String>(
                              value: f.value,
                              child: Text(f.name),
                            ))
                        .toList(),
                    onChanged: (_selectedBuildingId == null || _floors.isEmpty)
                        ? null
                        : (value) {
                            final floor =
                                _floors.firstWhere((f) => f.value == value);
                            setState(() {
                              _selectedFloorId = value;
                              _selectedFloorName = floor.name;
                            });
                            if (value != null) _loadRooms(value);
                          },
                  ),
            const SizedBox(height: 16),
            // 房间选择
            const Text('房间'),
            const SizedBox(height: 8),
            _loadingRooms
                ? const Center(child: ProgressRing())
                : ComboBox<String>(
                    isExpanded: true,
                    placeholder:
                        Text(_selectedFloorId == null ? '请先选择楼层' : '请选择房间'),
                    value: _selectedRoomId,
                    items: _rooms
                        .map((r) => ComboBoxItem<String>(
                              value: r.value,
                              child: Text(r.name),
                            ))
                        .toList(),
                    onChanged: (_selectedFloorId == null || _rooms.isEmpty)
                        ? null
                        : (value) {
                            final room =
                                _rooms.firstWhere((r) => r.value == value);
                            setState(() {
                              _selectedRoomId = value;
                              _selectedRoomName = room.name;
                            });
                          },
                  ),
            const SizedBox(height: 16),
            // 充值金额
            const Text('充值金额（元）'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: NumberBox<int>(
                    value: int.tryParse(_amountController.text) ?? 1,
                    min: 1,
                    max: 500,
                    onChanged: (value) {
                      _amountController.text = (value ?? 1).toString();
                    },
                    mode: SpinButtonPlacementMode.inline,
                  ),
                ),
                const SizedBox(width: 8),
                // 快捷金额按钮
                for (final amount in [10, 50, 100])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Button(
                      onPressed: () {
                        _amountController.text = amount.toString();
                        setState(() {});
                      },
                      child: Text('$amount'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            InfoBar(
              title: const Text('提示'),
              content: const Text('充值金额必须为正整数，充值后将从校园卡余额中扣除。'),
              severity: InfoBarSeverity.info,
              isLong: true,
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _isPaying ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (_selectedRoomId != null && !_isPaying) ? _pay : null,
          child: _isPaying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('确认充值'),
        ),
      ],
    );
  }
}

/// 购电记录对话框
class _PurchaseHistoryDialog extends StatelessWidget {
  final ElectricPurchaseQueryResult? purchaseHistory;

  const _PurchaseHistoryDialog({
    this.purchaseHistory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final records = purchaseHistory?.records ?? [];

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(FluentIcons.history, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('购电记录'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (purchaseHistory != null) ...[
              Row(
                children: [
                  Text(
                    '${purchaseHistory!.startDate} ~ ${purchaseHistory!.endDate}',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${records.length} 条，合计 ${purchaseHistory!.totalAmount.toStringAsFixed(2)} 元',
                    style: theme.typography.caption?.copyWith(
                      color: theme.accentColor,
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
                        style: theme.typography.body?.copyWith(
                          color: theme.inactiveColor,
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
                                color: theme.resources.controlStrokeColorDefault,
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
                                        style: theme.typography.body?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        record.purchaseDate,
                                        style: theme.typography.caption?.copyWith(
                                          color: theme.inactiveColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${record.amount.toStringAsFixed(2)} 元',
                                  style: theme.typography.bodyStrong?.copyWith(
                                    color: Colors.green,
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
