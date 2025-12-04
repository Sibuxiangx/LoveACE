import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

/// Inline color palette selector widget
///
/// Displays predefined colors and extracted color from background
class ColorPaletteSelector extends StatelessWidget {
  final AppColorScheme currentScheme;
  final Color customColor;
  final bool hasBackground;
  final Function(AppColorScheme) onSchemeSelected;

  const ColorPaletteSelector({
    super.key,
    required this.currentScheme,
    required this.customColor,
    required this.hasBackground,
    required this.onSchemeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final predefinedSchemes = ThemeProvider.getPredefinedSchemes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Predefined colors section
        Text(
          '预设配色',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: predefinedSchemes.map((schemeData) {
            return _buildColorCircle(
              context,
              color: schemeData.color,
              isSelected: currentScheme == schemeData.scheme,
              onTap: () => onSchemeSelected(schemeData.scheme),
            );
          }).toList(),
        ),
        // Extracted color section (only show when background is set)
        if (hasBackground) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            '背景提取配色',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildColorCircle(
                context,
                color: customColor,
                isSelected: currentScheme == AppColorScheme.custom,
                onTap: () => onSchemeSelected(AppColorScheme.custom),
                showIcon: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '从背景图片自动提取的主色调',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Build a single color circle
  Widget _buildColorCircle(
    BuildContext context, {
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    bool showIcon = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isSelected
            ? Icon(Icons.check, color: _getContrastColor(color), size: 24)
            : showIcon
            ? Icon(
                Icons.auto_awesome,
                color: _getContrastColor(color),
                size: 20,
              )
            : null,
      ),
    );
  }

  /// Get contrasting color for icon visibility
  Color _getContrastColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
