import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/image_brightness.dart';
import '../utils/platform/platform_util.dart';

/// Color scheme options for the app
enum AppColorScheme {
  blue,
  green,
  purple,
  orange,
  red,
  cyan,
  pink,
  indigo,
  teal,
  amber,
  deepOrange,
  lime,
  custom,
}

/// Provider for managing app theme and appearance settings
///
/// Handles theme mode (light/dark/system), color scheme selection,
/// and persistence of user preferences
///
/// Usage example:
/// ```dart
/// final themeProvider = Provider.of<ThemeProvider>(context);
///
/// // Change theme mode
/// themeProvider.setThemeMode(ThemeMode.dark);
///
/// // Change color scheme
/// themeProvider.setColorScheme(AppColorScheme.green);
///
/// // Get current theme data
/// final lightTheme = themeProvider.lightTheme;
/// final darkTheme = themeProvider.darkTheme;
/// ```
class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _colorSchemeKey = 'color_scheme';
  static const String _customColorKey = 'custom_color';
  static const String _backgroundPathKey = 'background_path';
  static const String _backgroundBlurKey = 'background_blur';
  static const String _cardOpacityLightKey = 'card_opacity_light';
  static const String _cardOpacityDarkKey = 'card_opacity_dark';
  static const String _navigationOpacityKey = 'navigation_opacity';
  static const String _appBarOpacityKey = 'appbar_opacity';
  static const String _appBarBlurKey = 'appbar_blur';

  ThemeMode _themeMode = ThemeMode.system;
  AppColorScheme _colorScheme = AppColorScheme.blue;
  Color _customColor = Colors.blue;
  String? _backgroundPath;
  double _backgroundBlur = 10.0;
  double _cardOpacityLight = 0.85; // Card opacity for light mode
  double _cardOpacityDark = 0.85; // Card opacity for dark mode
  double _backgroundBrightness = 0.5; // 0.0 = dark, 1.0 = bright
  double _navigationOpacity = 0.3; // Navigation bar/rail background opacity
  double _appBarOpacity = 0.3; // AppBar background opacity
  double _appBarBlur = 10.0; // AppBar blur intensity (default: 10.0)

  ThemeProvider() {
    _loadPreferences();
  }

  /// Get current theme mode
  ThemeMode get themeMode => _themeMode;

  /// Get current color scheme
  AppColorScheme get colorScheme => _colorScheme;

  /// Get custom color
  Color get customColor => _customColor;

  /// Get background image path
  String? get backgroundPath => _backgroundPath;

  /// Get background blur intensity
  double get backgroundBlur => _backgroundBlur;

  /// Get card opacity for current theme mode
  double get cardOpacity {
    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    return isDarkMode ? _cardOpacityDark : _cardOpacityLight;
  }

  /// Get background brightness (0.0 = dark, 1.0 = bright)
  double get backgroundBrightness => _backgroundBrightness;

  /// Get navigation opacity
  double get navigationOpacity => _navigationOpacity;

  /// Get appbar opacity
  double get appBarOpacity => _appBarOpacity;

  /// Get appbar blur intensity
  double get appBarBlur => _appBarBlur;

  /// Check if navigation text should be light (for dark backgrounds)
  bool get shouldUseLightNavigationText =>
      _backgroundPath != null &&
      ImageBrightness.shouldUseLightText(_backgroundBrightness);

  /// Get navigation text color based on background, theme, and opacity
  Color get navigationTextColor {
    if (_backgroundPath == null) return Colors.black87;

    // Get surface color from current theme
    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final surfaceColor = isDarkMode
        ? darkTheme.colorScheme.surface
        : lightTheme.colorScheme.surface;

    return ImageBrightness.getTextColor(
      _backgroundBrightness,
      themeColor: surfaceColor,
      opacity: _navigationOpacity,
    );
  }

  /// Get navigation icon color based on background, theme, and opacity
  Color get navigationIconColor {
    if (_backgroundPath == null) return Colors.black87;

    // Get surface color from current theme
    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final surfaceColor = isDarkMode
        ? darkTheme.colorScheme.surface
        : lightTheme.colorScheme.surface;

    return ImageBrightness.getIconColor(
      _backgroundBrightness,
      themeColor: surfaceColor,
      opacity: _navigationOpacity,
    );
  }

  /// Get appbar text color based on background, theme, and appbar opacity
  Color get appBarTextColor {
    if (_backgroundPath == null) return Colors.black87;

    // Get surface color from current theme
    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final surfaceColor = isDarkMode
        ? darkTheme.colorScheme.surface
        : lightTheme.colorScheme.surface;

    return ImageBrightness.getTextColor(
      _backgroundBrightness,
      themeColor: surfaceColor,
      opacity: _appBarOpacity,
    );
  }

  /// Get appbar icon color based on background, theme, and appbar opacity
  Color get appBarIconColor {
    if (_backgroundPath == null) return Colors.black87;

    // Get surface color from current theme
    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final surfaceColor = isDarkMode
        ? darkTheme.colorScheme.surface
        : lightTheme.colorScheme.surface;

    return ImageBrightness.getIconColor(
      _backgroundBrightness,
      themeColor: surfaceColor,
      opacity: _appBarOpacity,
    );
  }

  /// Get light theme data
  ThemeData get lightTheme => _buildLightTheme();

  /// Get dark theme data
  ThemeData get darkTheme => _buildDarkTheme();

  /// Set theme mode
  ///
  /// [mode] - The theme mode to set (light, dark, or system)
  /// Saves preference and notifies listeners
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();
    await savePreferences();
  }

  /// Set color scheme
  ///
  /// [scheme] - The color scheme to set
  /// Saves preference and notifies listeners
  Future<void> setColorScheme(AppColorScheme scheme) async {
    if (_colorScheme == scheme) return;

    _colorScheme = scheme;
    notifyListeners();
    await savePreferences();
  }

  /// Set custom color
  ///
  /// [color] - The custom color to set
  /// Automatically switches to custom scheme and saves preference
  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    _colorScheme = AppColorScheme.custom;
    notifyListeners();
    await savePreferences();
  }

  /// Set background image path
  ///
  /// [path] - The path to the background image
  /// Saves preference and notifies listeners
  Future<void> setBackgroundPath(String? path) async {
    if (_backgroundPath == path) return;

    _backgroundPath = path;

    // Calculate brightness of new background
    if (path != null) {
      _backgroundBrightness = await ImageBrightness.calculateBrightness(path);

      // Auto-calculate recommended opacities for all UI elements
      // Calculate for both light and dark modes
      final currentMode = _themeMode;

      // Calculate for light mode
      _themeMode = ThemeMode.light;
      _cardOpacityLight = calculateRecommendedCardOpacity();

      // Calculate for dark mode
      _themeMode = ThemeMode.dark;
      _cardOpacityDark = calculateRecommendedCardOpacity();

      // Restore original mode
      _themeMode = currentMode;

      _navigationOpacity = calculateRecommendedNavigationOpacity();
      _appBarOpacity = calculateRecommendedAppBarOpacity();
    } else {
      _backgroundBrightness = 0.5; // Reset to default
      _cardOpacityLight = 0.85;
      _cardOpacityDark = 0.85;
      _navigationOpacity = 0.3;
      _appBarOpacity = 0.3;
    }

    notifyListeners();
    await savePreferences();
  }

  /// Update background blur intensity without saving (for real-time preview)
  ///
  /// [blur] - The blur intensity (0.0 to 20.0)
  /// Only notifies listeners, does not save to disk
  void updateBackgroundBlur(double blur) {
    final clampedBlur = blur.clamp(0.0, 20.0);
    if (_backgroundBlur == clampedBlur) return;

    _backgroundBlur = clampedBlur;
    notifyListeners();
  }

  /// Set background blur intensity
  ///
  /// [blur] - The blur intensity (0.0 to 20.0)
  /// Saves preference and notifies listeners
  Future<void> setBackgroundBlur(double blur) async {
    updateBackgroundBlur(blur);
    await savePreferences();
  }

  /// Update card opacity without saving (for real-time preview)
  ///
  /// [opacity] - The card opacity (0.0 to 1.0)
  /// Only notifies listeners, does not save to disk
  void updateCardOpacity(double opacity) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);

    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    if (isDarkMode) {
      if (_cardOpacityDark == clampedOpacity) return;
      _cardOpacityDark = clampedOpacity;
    } else {
      if (_cardOpacityLight == clampedOpacity) return;
      _cardOpacityLight = clampedOpacity;
    }

    notifyListeners();
  }

  /// Set card opacity for current theme mode
  ///
  /// [opacity] - The card opacity (0.0 to 1.0)
  /// Saves preference and notifies listeners
  Future<void> setCardOpacity(double opacity) async {
    updateCardOpacity(opacity);
    await savePreferences();
  }

  /// Update navigation opacity without saving (for real-time preview)
  ///
  /// [opacity] - The navigation bar/rail background opacity (0.0 to 1.0)
  /// Only notifies listeners, does not save to disk
  void updateNavigationOpacity(double opacity) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    if (_navigationOpacity == clampedOpacity) return;

    _navigationOpacity = clampedOpacity;
    notifyListeners();
  }

  /// Set navigation opacity
  ///
  /// [opacity] - The navigation bar/rail background opacity (0.0 to 1.0)
  /// Saves preference and notifies listeners
  Future<void> setNavigationOpacity(double opacity) async {
    updateNavigationOpacity(opacity);
    await savePreferences();
  }

  /// Update appbar opacity without saving (for real-time preview)
  ///
  /// [opacity] - The appbar background opacity (0.0 to 1.0)
  /// Only notifies listeners, does not save to disk
  void updateAppBarOpacity(double opacity) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    if (_appBarOpacity == clampedOpacity) return;

    _appBarOpacity = clampedOpacity;
    notifyListeners();
  }

  /// Set appbar opacity
  ///
  /// [opacity] - The appbar background opacity (0.0 to 1.0)
  /// Saves preference and notifies listeners
  Future<void> setAppBarOpacity(double opacity) async {
    updateAppBarOpacity(opacity);
    await savePreferences();
  }

  /// Update appbar blur intensity without saving (for real-time preview)
  ///
  /// [blur] - The blur intensity (0.0 to 20.0)
  /// Only notifies listeners, does not save to disk
  void updateAppBarBlur(double blur) {
    final clampedBlur = blur.clamp(0.0, 20.0);
    if (_appBarBlur == clampedBlur) return;

    _appBarBlur = clampedBlur;
    notifyListeners();
  }

  /// Set appbar blur intensity
  ///
  /// [blur] - The blur intensity (0.0 to 20.0)
  /// Saves preference and notifies listeners
  Future<void> setAppBarBlur(double blur) async {
    updateAppBarBlur(blur);
    await savePreferences();
  }

  /// Calculate recommended navigation opacity based on background brightness
  double calculateRecommendedNavigationOpacity() {
    if (_backgroundPath == null) return 0.3;

    // 根据背景亮度计算推荐的导航栏透明度
    // 深色背景需要更高的透明度以保持可见性
    if (_backgroundBrightness < 0.3) {
      return 0.4; // 很暗的背景
    } else if (_backgroundBrightness < 0.5) {
      return 0.35; // 暗背景
    } else if (_backgroundBrightness < 0.7) {
      return 0.3; // 中等背景
    } else {
      return 0.25; // 亮背景
    }
  }

  /// Calculate recommended appbar opacity based on background brightness
  double calculateRecommendedAppBarOpacity() {
    if (_backgroundPath == null) return 0.3;

    // AppBar 通常需要比导航栏稍微透明一点，以便更好地展示背景
    if (_backgroundBrightness < 0.3) {
      return 0.35;
    } else if (_backgroundBrightness < 0.5) {
      return 0.3;
    } else if (_backgroundBrightness < 0.7) {
      return 0.25;
    } else {
      return 0.2;
    }
  }

  /// Reset navigation opacity to recommended value
  Future<void> resetNavigationOpacity() async {
    _navigationOpacity = calculateRecommendedNavigationOpacity();
    notifyListeners();
    await savePreferences();
  }

  /// Reset appbar opacity to recommended value
  Future<void> resetAppBarOpacity() async {
    _appBarOpacity = calculateRecommendedAppBarOpacity();
    notifyListeners();
    await savePreferences();
  }

  /// Reset appbar blur to default value (10.0)
  Future<void> resetAppBarBlur() async {
    _appBarBlur = 10.0;
    notifyListeners();
    await savePreferences();
  }

  /// Calculate recommended card opacity based on background brightness and theme mode
  double calculateRecommendedCardOpacity() {
    if (_backgroundPath == null) return 0.85;

    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    return ImageBrightness.calculateOptimalCardOpacity(
      _backgroundBrightness,
      isDarkMode,
    );
  }

  /// Reset card opacity to recommended value for current theme mode
  Future<void> resetCardOpacity() async {
    final isDarkMode =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    if (isDarkMode) {
      _cardOpacityDark = calculateRecommendedCardOpacity();
    } else {
      _cardOpacityLight = calculateRecommendedCardOpacity();
    }

    notifyListeners();
    await savePreferences();
  }

  /// Save preferences to local storage
  Future<void> savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, _themeMode.name);
      await prefs.setString(_colorSchemeKey, _colorScheme.name);
      await prefs.setInt(
        _customColorKey,
        (_customColor.a * 255).toInt() << 24 |
            (_customColor.r * 255).toInt() << 16 |
            (_customColor.g * 255).toInt() << 8 |
            (_customColor.b * 255).toInt(),
      );
      await prefs.setDouble(_backgroundBlurKey, _backgroundBlur);
      await prefs.setDouble(_cardOpacityLightKey, _cardOpacityLight);
      await prefs.setDouble(_cardOpacityDarkKey, _cardOpacityDark);
      await prefs.setDouble(_navigationOpacityKey, _navigationOpacity);
      await prefs.setDouble(_appBarOpacityKey, _appBarOpacity);
      await prefs.setDouble(_appBarBlurKey, _appBarBlur);

      if (_backgroundPath != null) {
        await prefs.setString(_backgroundPathKey, _backgroundPath!);
      } else {
        await prefs.remove(_backgroundPathKey);
      }
    } catch (e) {
      debugPrint('Failed to save theme preferences: $e');
    }
  }

  /// Load preferences from local storage
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load theme mode
      final themeModeStr = prefs.getString(_themeModeKey);
      if (themeModeStr != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == themeModeStr,
          orElse: () => ThemeMode.system,
        );
      }

      // Load color scheme
      final colorSchemeStr = prefs.getString(_colorSchemeKey);
      if (colorSchemeStr != null) {
        _colorScheme = AppColorScheme.values.firstWhere(
          (scheme) => scheme.name == colorSchemeStr,
          orElse: () => AppColorScheme.blue,
        );
      }

      // Load custom color
      final customColorValue = prefs.getInt(_customColorKey);
      if (customColorValue != null) {
        _customColor = Color(customColorValue);
      }

      // Load background path
      _backgroundPath = prefs.getString(_backgroundPathKey);

      // Calculate brightness if background exists
      if (_backgroundPath != null) {
        _backgroundBrightness = await ImageBrightness.calculateBrightness(
          _backgroundPath!,
        );
      }

      // Load background blur
      final blurValue = prefs.getDouble(_backgroundBlurKey);
      if (blurValue != null) {
        _backgroundBlur = blurValue;
      }

      // Load card opacity for light mode
      final opacityLightValue = prefs.getDouble(_cardOpacityLightKey);
      if (opacityLightValue != null) {
        _cardOpacityLight = opacityLightValue;
      }

      // Load card opacity for dark mode
      final opacityDarkValue = prefs.getDouble(_cardOpacityDarkKey);
      if (opacityDarkValue != null) {
        _cardOpacityDark = opacityDarkValue;
      }

      // Load navigation opacity
      final navigationOpacityValue = prefs.getDouble(_navigationOpacityKey);
      if (navigationOpacityValue != null) {
        _navigationOpacity = navigationOpacityValue;
      }

      // Load appbar opacity
      final appBarOpacityValue = prefs.getDouble(_appBarOpacityKey);
      if (appBarOpacityValue != null) {
        _appBarOpacity = appBarOpacityValue;
      }

      // Load appbar blur
      final appBarBlurValue = prefs.getDouble(_appBarBlurKey);
      if (appBarBlurValue != null) {
        _appBarBlur = appBarBlurValue;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load theme preferences: $e');
    }
  }

  /// Build light theme based on current color scheme
  ThemeData _buildLightTheme() {
    final colorScheme = _getColorScheme(Brightness.light);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      fontFamily: PlatformUtil.isWindows ? 'MiSans' : null,

      // AppBar theme
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),

      // Card theme
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
    );
  }

  /// Build dark theme based on current color scheme
  ThemeData _buildDarkTheme() {
    final colorScheme = _getColorScheme(Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      fontFamily: PlatformUtil.isWindows ? 'MiSans' : null,

      // AppBar theme
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),

      // Card theme
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
    );
  }

  /// Get color scheme based on brightness and selected color
  ColorScheme _getColorScheme(Brightness brightness) {
    switch (_colorScheme) {
      case AppColorScheme.blue:
        return _buildColorScheme(Colors.blue, brightness);
      case AppColorScheme.green:
        return _buildColorScheme(Colors.green, brightness);
      case AppColorScheme.purple:
        return _buildColorScheme(Colors.purple, brightness);
      case AppColorScheme.orange:
        return _buildColorScheme(Colors.orange, brightness);
      case AppColorScheme.red:
        return _buildColorScheme(Colors.red, brightness);
      case AppColorScheme.cyan:
        return _buildColorScheme(Colors.cyan, brightness);
      case AppColorScheme.pink:
        return _buildColorScheme(Colors.pink, brightness);
      case AppColorScheme.indigo:
        return _buildColorScheme(Colors.indigo, brightness);
      case AppColorScheme.teal:
        return _buildColorScheme(Colors.teal, brightness);
      case AppColorScheme.amber:
        return _buildColorScheme(Colors.amber, brightness);
      case AppColorScheme.deepOrange:
        return _buildColorScheme(Colors.deepOrange, brightness);
      case AppColorScheme.lime:
        return _buildColorScheme(Colors.lime, brightness);
      case AppColorScheme.custom:
        return _buildColorScheme(_customColor, brightness);
    }
  }

  /// Build color scheme from seed color
  ColorScheme _buildColorScheme(Color seedColor, Brightness brightness) {
    return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  }

  /// Get predefined color schemes with their colors
  static List<({AppColorScheme scheme, Color color, String name})>
  getPredefinedSchemes() {
    return [
      (scheme: AppColorScheme.blue, color: Colors.blue, name: '蓝色'),
      (scheme: AppColorScheme.green, color: Colors.green, name: '绿色'),
      (scheme: AppColorScheme.purple, color: Colors.purple, name: '紫色'),
      (scheme: AppColorScheme.orange, color: Colors.orange, name: '橙色'),
      (scheme: AppColorScheme.red, color: Colors.red, name: '红色'),
      (scheme: AppColorScheme.cyan, color: Colors.cyan, name: '青色'),
      (scheme: AppColorScheme.pink, color: Colors.pink, name: '粉色'),
      (scheme: AppColorScheme.indigo, color: Colors.indigo, name: '靛蓝'),
      (scheme: AppColorScheme.teal, color: Colors.teal, name: '青绿'),
      (scheme: AppColorScheme.amber, color: Colors.amber, name: '琥珀'),
      (scheme: AppColorScheme.deepOrange, color: Colors.deepOrange, name: '深橙'),
      (scheme: AppColorScheme.lime, color: Colors.lime, name: '青柠'),
    ];
  }

  /// Get color scheme name for display
  String getColorSchemeName(AppColorScheme scheme) {
    if (scheme == AppColorScheme.custom) {
      return '自定义';
    }
    final predefined = getPredefinedSchemes().firstWhere(
      (s) => s.scheme == scheme,
      orElse: () =>
          (scheme: AppColorScheme.blue, color: Colors.blue, name: '蓝色'),
    );
    return predefined.name;
  }

  /// Get theme mode name for display
  String getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}
