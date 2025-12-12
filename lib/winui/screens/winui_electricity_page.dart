import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/isim/electricity_balance.dart';
import '../../models/isim/electricity_usage_record.dart';
import '../../models/isim/payment_record.dart';
import '../../providers/electricity_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/isim/isim_service.dart';
import '../../services/logger_service.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';

/// WinUI 风格的电费查询页面
///
/// 使用 Card 展示电费余额统计
/// 使用两个 ListView 分别展示用电记录和充值记录
/// 使用 ContentDialog 实现房间选择
/// 复用 ElectricityProvider 进行数据管理
/// _Requirements: 5.1, 5.2, 5.3, 5.4_
class WinUIElectricityPage extends StatefulWidget {
  const WinUIElectricityPage({super.key});

  @override
  State<WinUIElectricityPage> createState() => _WinUIElectricityPageState();
}

class _WinUIElectricityPageState extends State<WinUIElectricityPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final provider = Provider.of<ElectricityProvider>(context, listen: false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (provider.boundRoomCode != null) {
      await _loadData();
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<ElectricityProvider>(context, listen: false);
    if (provider.boundRoomCode == null) return;

    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == ElectricityState.error) {
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

  Future<void> _showRoomSelectionDialog() async {
    // 在显示 dialog 之前获取所需的 providers
    final electricityProvider = Provider.of<ElectricityProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // ISIMService 从 ElectricityProvider 获取
    final isimService = electricityProvider.isimService;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _WinUIRoomSelectionDialog(
        isimService: isimService,
        electricityProvider: electricityProvider,
        authProvider: authProvider,
      ),
    );

    if (result == true && mounted) {
      await _loadData(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ElectricityProvider>(
      builder: (context, provider, child) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('电费查询'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                if (provider.boundRoomCode != null)
                  CommandBarButton(
                    icon: const Icon(FluentIcons.edit),
                    label: const Text('重新绑定'),
                    onPressed: _showRoomSelectionDialog,
                  ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.refresh),
                  label: const Text('刷新'),
                  onPressed: provider.boundRoomCode != null ? _refreshData : null,
                ),
              ],
            ),
          ),
          content: _buildContent(context, provider),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, ElectricityProvider provider) {
    // 未绑定房间
    if (provider.boundRoomCode == null) {
      return _buildUnboundState(context);
    }

    // 加载中
    if (provider.state == ElectricityState.loading) {
      return const WinUILoading(message: '正在加载电费信息');
    }

    // 加载完成
    if (provider.state == ElectricityState.loaded && provider.electricityInfo != null) {
      return _buildMainLayout(context, provider);
    }

    // 错误状态
    if (provider.state == ElectricityState.error) {
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

  Widget _buildUnboundState(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(FluentIcons.home, size: 80, color: theme.accentColor.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Text('未绑定房间', style: theme.typography.title),
          const SizedBox(height: 12),
          Text(
            '请先绑定您的宿舍房间\n以便查询电费信息',
            textAlign: TextAlign.center,
            style: theme.typography.body?.copyWith(color: theme.inactiveColor),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _showRoomSelectionDialog,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.add_home, size: 16),
                SizedBox(width: 8),
                Text('绑定房间'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainLayout(BuildContext context, ElectricityProvider provider) {
    final info = provider.electricityInfo!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：余额统计卡片
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildBalanceCard(context, info.balance, provider.boundRoomDisplay),
          ),
        ),
        Container(
          width: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 右侧：用电记录和充值记录
        Expanded(
          child: Row(
            children: [
              // 用电记录
              Expanded(
                child: _buildUsageList(context, info.usageRecords),
              ),
              Container(
                width: 1,
                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
              ),
              // 充值记录
              Expanded(
                child: _buildPaymentList(context, info.payments),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(BuildContext context, ElectricityBalance balance, String? roomDisplay) {
    final theme = FluentTheme.of(context);

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 房间信息
          if (roomDisplay != null) ...[
            Row(
              children: [
                Icon(FluentIcons.home, size: 20, color: theme.accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(roomDisplay, style: theme.typography.subtitle),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
          ],
          // 总余额
          Center(
            child: Column(
              children: [
                Text('剩余电量', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      balance.total.toStringAsFixed(1),
                      style: theme.typography.display?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(' 度', style: theme.typography.body?.copyWith(color: theme.inactiveColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '(购电: ${balance.remainingPurchased.toStringAsFixed(1)} + 补助: ${balance.remainingSubsidy.toStringAsFixed(1)})',
                  style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          // 详细信息
          Row(
            children: [
              Expanded(child: _buildStatItem(context, '购电', '${balance.remainingPurchased.toStringAsFixed(1)}度', Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatItem(context, '补助', '${balance.remainingSubsidy.toStringAsFixed(1)}度', Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, Color color) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
          const SizedBox(height: 4),
          Text(value, style: theme.typography.bodyStrong?.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildUsageList(BuildContext context, List<ElectricityUsageRecord> records) {
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(FluentIcons.lightning_bolt, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text('用电记录', style: theme.typography.subtitle),
              const Spacer(),
              Text('共 ${records.length} 条', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: records.isEmpty
              ? Center(child: Text('暂无用电记录', style: theme.typography.body?.copyWith(color: theme.inactiveColor)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: records.length,
                  itemBuilder: (context, index) => _buildUsageItem(context, records[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildUsageItem(BuildContext context, ElectricityUsageRecord record) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.resources.controlStrokeColorDefault),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.recordTime, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        record.usageAmount.toStringAsFixed(1),
                        style: theme.typography.bodyStrong?.copyWith(color: Colors.orange),
                      ),
                      Text(' 度', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                record.meterName,
                style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentList(BuildContext context, List<PaymentRecord> payments) {
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(FluentIcons.money, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text('充值记录', style: theme.typography.subtitle),
              const Spacer(),
              Text('共 ${payments.length} 条', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: payments.isEmpty
              ? Center(child: Text('暂无充值记录', style: theme.typography.body?.copyWith(color: theme.inactiveColor)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: payments.length,
                  itemBuilder: (context, index) => _buildPaymentItem(context, payments[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildPaymentItem(BuildContext context, PaymentRecord payment) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.resources.controlStrokeColorDefault),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(payment.paymentTime, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        payment.amount.toStringAsFixed(2),
                        style: theme.typography.bodyStrong?.copyWith(color: Colors.green),
                      ),
                      Text(' 元', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                payment.paymentType,
                style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WinUI 风格的房间选择对话框
class _WinUIRoomSelectionDialog extends StatefulWidget {
  final ISIMService isimService;
  final ElectricityProvider electricityProvider;
  final AuthProvider authProvider;

  const _WinUIRoomSelectionDialog({
    required this.isimService,
    required this.electricityProvider,
    required this.authProvider,
  });

  @override
  State<_WinUIRoomSelectionDialog> createState() => _WinUIRoomSelectionDialogState();
}

class _WinUIRoomSelectionDialogState extends State<_WinUIRoomSelectionDialog> {
  // 选择状态
  String? _selectedBuilding;
  String? _selectedFloor;
  String? _selectedRoom;

  // 数据
  List<Map<String, String>> _buildings = [];
  List<Map<String, String>> _floors = [];
  List<Map<String, String>> _rooms = [];

  // 加载状态
  bool _loadingBuildings = true;
  bool _loadingFloors = false;
  bool _loadingRooms = false;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
  }

  Future<void> _loadBuildings() async {
    try {
      final response = await widget.isimService.getBuildings();
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

  Future<void> _loadFloors(String buildingCode) async {
    setState(() {
      _loadingFloors = true;
      _floors = [];
      _rooms = [];
      _selectedFloor = null;
      _selectedRoom = null;
    });

    try {
      final response = await widget.isimService.getFloors(buildingCode);
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

  Future<void> _loadRooms(String floorCode) async {
    setState(() {
      _loadingRooms = true;
      _rooms = [];
      _selectedRoom = null;
    });

    try {
      final response = await widget.isimService.getRooms(floorCode);
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

  Future<void> _bindRoom() async {
    if (_selectedRoom == null) return;

    final room = _rooms.firstWhere((r) => r['code'] == _selectedRoom);
    final building = _buildings.firstWhere((b) => b['code'] == _selectedBuilding);
    final displayText = '${building['name']} ${room['name']}';

    try {
      final userId = widget.authProvider.credentials?.userId ?? '';
      await widget.electricityProvider.bindRoom(_selectedRoom!, displayText, userId);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      LoggerService.error('绑定房间失败', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('选择房间'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 楼栋选择
            const Text('楼栋'),
            const SizedBox(height: 8),
            _loadingBuildings
                ? const Center(child: ProgressRing())
                : ComboBox<String>(
                    isExpanded: true,
                    placeholder: const Text('请选择楼栋'),
                    value: _selectedBuilding,
                    items: _buildings.map((b) => ComboBoxItem<String>(
                      value: b['code'],
                      child: Text(b['name'] ?? ''),
                    )).toList(),
                    onChanged: (value) {
                      setState(() => _selectedBuilding = value);
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
                    placeholder: Text(_selectedBuilding == null ? '请先选择楼栋' : '请选择楼层'),
                    value: _selectedFloor,
                    items: _floors.map((f) => ComboBoxItem<String>(
                      value: f['code'],
                      child: Text(f['name'] ?? ''),
                    )).toList(),
                    onChanged: (_selectedBuilding == null || _floors.isEmpty) ? null : (value) {
                      setState(() => _selectedFloor = value);
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
                    placeholder: Text(_selectedFloor == null ? '请先选择楼层' : '请选择房间'),
                    value: _selectedRoom,
                    items: _rooms.map((r) => ComboBoxItem<String>(
                      value: r['code'],
                      child: Text(r['name'] ?? ''),
                    )).toList(),
                    onChanged: (_selectedFloor == null || _rooms.isEmpty) ? null : (value) {
                      setState(() => _selectedRoom = value);
                    },
                  ),
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        FilledButton(
          onPressed: _selectedRoom != null ? _bindRoom : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
