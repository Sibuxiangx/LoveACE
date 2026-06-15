import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/electricity_provider.dart';

/// 房间选择对话框
///
/// 提供三级联动选择器：楼栋 → 楼层 → 房间
/// 用户选择完成后绑定房间并重新加载数据
class RoomSelectionDialog extends StatefulWidget {
  const RoomSelectionDialog({super.key});

  @override
  State<RoomSelectionDialog> createState() => _RoomSelectionDialogState();
}

class _RoomSelectionDialogState extends State<RoomSelectionDialog> {
  // 加载状态
  bool _isLoading = false;
  String? _errorMessage;

  // 楼栋列表
  List<Map<String, String>> _buildings = [];
  Map<String, String>? _selectedBuilding;

  // 楼层列表
  List<Map<String, String>> _floors = [];
  Map<String, String>? _selectedFloor;

  // 房间列表
  List<Map<String, String>> _rooms = [];
  Map<String, String>? _selectedRoom;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
  }

  /// 加载楼栋列表
  Future<void> _loadBuildings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final electricityProvider = Provider.of<ElectricityProvider>(
        context,
        listen: false,
      );

      // 获取 ISIMService 实例
      // 注意：这里假设 ISIMService 已经在 Provider 中注册
      // 如果没有，需要从 connection 创建
      final connection = authProvider.connection;
      if (connection == null) {
        throw Exception('未登录');
      }

      final isimService = electricityProvider.isimService;
      final response = await isimService.getBuildings();

      if (response.success && response.data != null) {
        setState(() {
          _buildings = response.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.error ?? '获取楼栋列表失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '获取楼栋列表失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 加载楼层列表
  Future<void> _loadFloors(String buildingCode) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _floors = [];
      _selectedFloor = null;
      _rooms = [];
      _selectedRoom = null;
    });

    try {
      final electricityProvider = Provider.of<ElectricityProvider>(
        context,
        listen: false,
      );
      final isimService = electricityProvider.isimService;
      final response = await isimService.getFloors(buildingCode);

      if (response.success && response.data != null) {
        setState(() {
          _floors = response.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.error ?? '获取楼层列表失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '获取楼层列表失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 加载房间列表
  Future<void> _loadRooms(String floorCode) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _rooms = [];
      _selectedRoom = null;
    });

    try {
      final electricityProvider = Provider.of<ElectricityProvider>(
        context,
        listen: false,
      );
      final isimService = electricityProvider.isimService;
      final response = await isimService.getRooms(floorCode);

      if (response.success && response.data != null) {
        setState(() {
          _rooms = response.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.error ?? '获取房间列表失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '获取房间列表失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 确认绑定
  Future<void> _confirmBinding() async {
    if (_selectedRoom == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择房间')));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final electricityProvider = Provider.of<ElectricityProvider>(
        context,
        listen: false,
      );

      final userId = authProvider.credentials?.userId;
      if (userId == null) {
        throw Exception('未登录');
      }

      final roomCode = _selectedRoom!['code']!;
      final roomDisplay =
          '${_selectedBuilding!['name']} ${_selectedFloor!['name']} ${_selectedRoom!['name']}';

      // 绑定房间
      await electricityProvider.bindRoom(roomCode, roomDisplay, userId);

      // 关闭对话框
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '绑定房间失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Row(
        children: [
          Icon(
            Icons.meeting_room,
            color: isDark
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 12),
          const Text('选择房间'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 提示信息
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.blue.shade300.withValues(alpha: 0.3)
                        : Colors.blue.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '请依次选择楼栋、楼层和房间',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.blue.shade300 : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 错误提示
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 楼栋选择
              _buildDropdown(
                label: '楼栋',
                value: _selectedBuilding,
                items: _buildings,
                onChanged: (building) {
                  setState(() {
                    _selectedBuilding = building;
                    _selectedFloor = null;
                    _selectedRoom = null;
                    _floors = [];
                    _rooms = [];
                  });
                  if (building != null) {
                    _loadFloors(building['code']!);
                  }
                },
                enabled: !_isLoading && _buildings.isNotEmpty,
              ),

              const SizedBox(height: 20),

              // 楼层选择
              _buildDropdown(
                label: '楼层',
                value: _selectedFloor,
                items: _floors,
                onChanged: (floor) {
                  setState(() {
                    _selectedFloor = floor;
                    _selectedRoom = null;
                    _rooms = [];
                  });
                  if (floor != null) {
                    _loadRooms(floor['code']!);
                  }
                },
                enabled:
                    !_isLoading &&
                    _selectedBuilding != null &&
                    _floors.isNotEmpty,
              ),

              const SizedBox(height: 20),

              // 房间选择
              _buildDropdown(
                label: '房间',
                value: _selectedRoom,
                items: _rooms,
                onChanged: (room) {
                  setState(() {
                    _selectedRoom = room;
                  });
                },
                enabled:
                    !_isLoading && _selectedFloor != null && _rooms.isNotEmpty,
              ),

              // 加载指示器
              if (_isLoading) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _isLoading || _selectedRoom == null ? null : _confirmBinding,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('确认绑定'),
        ),
      ],
    );
  }

  /// 构建下拉选择器
  Widget _buildDropdown({
    required String label,
    required Map<String, String>? value,
    required List<Map<String, String>> items,
    required ValueChanged<Map<String, String>?> onChanged,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<Map<String, String>>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabled: enabled,
            filled: true,
            fillColor: enabled
                ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          hint: Text(
            '请选择$label',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          items: items.map((item) {
            return DropdownMenuItem<Map<String, String>>(
              value: item,
              child: Text(
                item['name'] ?? '',
                style: const TextStyle(fontSize: 15),
              ),
            );
          }).toList(),
          onChanged: enabled ? onChanged : null,
          isExpanded: true,
        ),
      ],
    );
  }
}
