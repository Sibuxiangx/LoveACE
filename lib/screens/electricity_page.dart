import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/electricity_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/room_selection_dialog.dart';
import '../widgets/app_background.dart';
import '../models/isim/electricity_balance.dart';
import '../models/isim/electricity_usage_record.dart';
import '../models/isim/payment_record.dart';

/// 电费查询页面
///
/// 提供电费余额查询、用电记录和充值记录查询功能
/// 支持自动加载、手动刷新和下拉刷新
/// 支持房间绑定管理
class ElectricityPage extends StatefulWidget {
  const ElectricityPage({super.key});

  @override
  State<ElectricityPage> createState() => _ElectricityPageState();
}

class _ElectricityPageState extends State<ElectricityPage> {
  // 用电记录是否展开
  bool _usageExpanded = false;

  // 充值记录是否展开
  bool _paymentExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  /// 初始化数据：等待绑定信息加载完成后，如果已绑定则自动加载电费数据
  Future<void> _initializeData() async {
    final provider = Provider.of<ElectricityProvider>(context, listen: false);

    // 等待一小段时间，确保 loadBoundRoom 完成
    await Future.delayed(const Duration(milliseconds: 100));

    // 如果已绑定房间，自动加载数据
    if (provider.boundRoomCode != null) {
      await _loadData();
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<ElectricityProvider>(context, listen: false);

    // 如果未绑定房间，不加载数据，不显示错误对话框
    if (provider.boundRoomCode == null) {
      return;
    }

    await provider.loadData(forceRefresh: forceRefresh);

    // 只有在已绑定房间的情况下才显示错误对话框
    if (mounted && provider.state == ElectricityState.error) {
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

  Future<void> _showRebindDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const RoomSelectionDialog(),
    );

    // 如果绑定成功，重新加载数据
    if (result == true && mounted) {
      await _loadData(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final hasBackground = themeProvider.backgroundPath != null;

    return Scaffold(
      backgroundColor: hasBackground ? Colors.transparent : null,
      body: AppBackground(
        child: Consumer<ElectricityProvider>(
          builder: (context, provider, child) {
            // 加载中状态
            if (provider.state == ElectricityState.loading) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '电费查询',
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: null, // 加载中禁用
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  const SliverLoadingIndicator(message: '正在加载电费信息...'),
                ],
              );
            }

            // 加载完成状态
            if (provider.state == ElectricityState.loaded) {
              final info = provider.electricityInfo!;

              return RefreshIndicator(
                onRefresh: _refreshData,
                child: CustomScrollView(
                  slivers: [
                    AdaptiveSliverAppBar(
                      title: '电费查询',
                      actions: [
                        if (provider.boundRoomCode != null)
                          IconButton(
                            icon: const Icon(Icons.edit_location),
                            onPressed: _showRebindDialog,
                            tooltip: '重新绑定',
                          ),
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
                          _buildBalanceCard(
                            info.balance,
                            provider.boundRoomDisplay,
                          ),
                          const SizedBox(height: 16),
                          _buildUsageCard(info.usageRecords),
                          const SizedBox(height: 16),
                          _buildPaymentCard(info.payments),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 错误状态
            if (provider.state == ElectricityState.error) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '电费查询',
                    actions: [
                      if (provider.boundRoomCode != null)
                        IconButton(
                          icon: const Icon(Icons.edit_location),
                          onPressed: _showRebindDialog,
                          tooltip: '重新绑定',
                        ),
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

            // 初始状态 - 检查是否已绑定房间
            if (provider.boundRoomCode == null) {
              // 未绑定房间，显示绑定提示
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(title: '电费查询'),
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.home_outlined,
                              size: 80,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '未绑定房间',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '请先绑定您的宿舍房间\n以便查询电费信息',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 32),
                            FilledButton.icon(
                              onPressed: _showRebindDialog,
                              icon: const Icon(Icons.add_location),
                              label: const Text('绑定房间'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // 已绑定房间但未加载数据
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '电费查询',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit_location),
                      onPressed: _showRebindDialog,
                      tooltip: '重新绑定',
                    ),
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
  }

  /// 构建余额卡片
  Widget _buildBalanceCard(ElectricityBalance balance, String? roomDisplay) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：房间信息
          if (roomDisplay != null) ...[
            Row(
              children: [
                Icon(
                  Icons.home,
                  size: 20,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  roomDisplay,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 中部：总余额
          Center(
            child: Column(
              children: [
                Text(
                  '剩余电量',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: balance.total.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.blue.shade300
                                  : Colors.blue,
                            ),
                      ),
                      TextSpan(
                        text: ' 度',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '(购电: ${balance.remainingPurchased.toStringAsFixed(1)} + 补助: ${balance.remainingSubsidy.toStringAsFixed(1)})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 底部：购电和补助详情
          Row(
            children: [
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '购电',
                  balance.remainingPurchased.toStringAsFixed(1),
                  '度',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '补助',
                  balance.remainingSubsidy.toStringAsFixed(1),
                  '度',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建紧凑信息块
  Widget _buildCompactInfo(
    BuildContext context,
    String label,
    String value,
    String unit,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade300
                        : Colors.blue,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建用电记录卡片
  Widget _buildUsageCard(List<ElectricityUsageRecord> records) {
    // 默认显示最近6条，点击展开显示全部
    final displayRecords = _usageExpanded
        ? records
        : (records.length > 6 ? records.sublist(0, 6) : records);
    final hasMore = records.length > 6;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '用电记录',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '共 ${records.length} 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (records.isEmpty)
            EmptyState.noData(title: '暂无用电记录', description: null)
          else
            Column(
              children: [
                ...displayRecords.map((record) => _buildUsageItem(record)),

                // 展开/收起按钮
                if (hasMore) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _usageExpanded = !_usageExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _usageExpanded ? '收起' : '展开全部 (${records.length}条)',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).primaryColor,
                                ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _usageExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// 构建用电记录项
  Widget _buildUsageItem(ElectricityUsageRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
          // 左侧：时间和用量
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.recordTime,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: record.usageAmount.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.orange.shade300
                                  : Colors.orange,
                            ),
                      ),
                      TextSpan(
                        text: ' 度',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 右侧：电表名称标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              record.meterName,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange.shade300
                    : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建充值记录卡片
  Widget _buildPaymentCard(List<PaymentRecord> payments) {
    // 默认显示最近6条，点击展开显示全部
    final displayPayments = _paymentExpanded
        ? payments
        : (payments.length > 6 ? payments.sublist(0, 6) : payments);
    final hasMore = payments.length > 6;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '充值记录',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '共 ${payments.length} 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (payments.isEmpty)
            EmptyState.noData(title: '暂无充值记录', description: null)
          else
            Column(
              children: [
                ...displayPayments.map((payment) => _buildPaymentItem(payment)),

                // 展开/收起按钮
                if (hasMore) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _paymentExpanded = !_paymentExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _paymentExpanded
                                ? '收起'
                                : '展开全部 (${payments.length}条)',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).primaryColor,
                                ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _paymentExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// 构建充值记录项
  Widget _buildPaymentItem(PaymentRecord payment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
          // 左侧：时间和金额
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.paymentTime,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: payment.amount.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.green.shade300
                                  : Colors.green,
                            ),
                      ),
                      TextSpan(
                        text: ' 元',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 右侧：充值类型标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              payment.paymentType,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.green.shade300
                    : Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
