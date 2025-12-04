import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/background_manager.dart';
import '../services/logger_service.dart';

/// Background settings widget with loading indicator
class BackgroundSettings extends StatefulWidget {
  final String? currentBackgroundPath;
  final double currentBlur;
  final Function(String?) onBackgroundChanged;
  final Function(double) onBlurChanged;
  final Function(Color) onColorExtracted;

  const BackgroundSettings({
    super.key,
    required this.currentBackgroundPath,
    required this.currentBlur,
    required this.onBackgroundChanged,
    required this.onBlurChanged,
    required this.onColorExtracted,
  });

  @override
  State<BackgroundSettings> createState() => _BackgroundSettingsState();
}

class _BackgroundSettingsState extends State<BackgroundSettings> {
  final BackgroundManager _backgroundManager = BackgroundManager();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBackgroundPreview(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickBackground,
                icon: const Icon(Icons.image),
                label: const Text('选择背景'),
              ),
            ),
            if (widget.currentBackgroundPath != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _removeBackground,
                icon: const Icon(Icons.delete_outline),
                label: const Text('移除'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        if (widget.currentBackgroundPath != null) ...[
          const SizedBox(height: 16),
          _buildBlurSlider(),
        ],
      ],
    );
  }

  Widget _buildBackgroundPreview() {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: widget.currentBackgroundPath != null
            ? _buildImagePreview()
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(widget.currentBackgroundPath!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            LoggerService.warning('Failed to load background image: $error');
            return _buildPlaceholder();
          },
        ),
        if (widget.currentBlur > 0)
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: widget.currentBlur,
              sigmaY: widget.currentBlur,
            ),
            child: Container(color: Colors.transparent),
          ),
        if (widget.currentBlur > 0)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '模糊: ${widget.currentBlur.toStringAsFixed(1)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wallpaper,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '未设置背景',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurSlider() {
    return _SmoothBlurSlider(
      value: widget.currentBlur,
      onChanged: widget.onBlurChanged,
    );
  }

  Future<void> _pickBackground() async {
    try {
      final imageFile = await _backgroundManager.pickImage();
      if (imageFile == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在处理图片并提取配色...'),
                ],
              ),
            ),
          ),
        ),
      );

      final savedPath = await _backgroundManager.saveBackground(imageFile);
      if (savedPath == null) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('保存背景失败')));
        }
        return;
      }

      final dominantColor = await _backgroundManager.extractDominantColor(
        savedPath,
      );
      if (dominantColor != null) {
        widget.onColorExtracted(dominantColor);
      }

      widget.onBackgroundChanged(savedPath);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('背景已设置，已自动提取配色')));
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to pick background',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置背景失败: $e')));
      }
    }
  }

  Future<void> _removeBackground() async {
    try {
      await _backgroundManager.removeCurrentBackground();
      widget.onBackgroundChanged(null);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('背景已移除')));
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'Failed to remove background',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移除背景失败: $e')));
      }
    }
  }
}

/// 丝滑的模糊强度滑动条
class _SmoothBlurSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _SmoothBlurSlider({required this.value, required this.onChanged});

  @override
  State<_SmoothBlurSlider> createState() => _SmoothBlurSliderState();
}

class _SmoothBlurSliderState extends State<_SmoothBlurSlider> {
  double? _localValue;
  bool _isDragging = false;

  double get _currentValue =>
      _isDragging ? (_localValue ?? widget.value) : widget.value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.blur_on, size: 20),
            const SizedBox(width: 8),
            Text('模糊强度', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
          ),
          child: Slider(
            value: _currentValue,
            min: 0,
            max: 20,
            divisions: 100,
            label: _currentValue.toStringAsFixed(1),
            onChanged: (value) {
              // 只更新本地状态，不触发 Provider
              setState(() {
                _localValue = value;
                _isDragging = true;
              });
            },
            onChangeEnd: (value) {
              // 拖动结束时保存并清除本地状态
              setState(() {
                _isDragging = false;
                _localValue = null;
              });
              widget.onChanged(value);
            },
          ),
        ),
      ],
    );
  }
}
