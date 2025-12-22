import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants/app_constants.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/academic_provider.dart';
import 'providers/aac_provider.dart';
import 'providers/term_provider.dart';
import 'providers/term_score_provider.dart';
import 'providers/more_provider.dart';
import 'providers/pinned_features_provider.dart';
import 'providers/exam_provider.dart';
import 'providers/training_plan_provider.dart';
import 'providers/competition_provider.dart';
import 'providers/electricity_provider.dart';
import 'providers/labor_club_provider.dart';
import 'providers/manifest_provider.dart';
import 'providers/course_schedule_provider.dart';
import 'providers/smart_course_selection_provider.dart';
import 'providers/ykt_provider.dart';
import 'services/session_manager.dart';
import 'services/jwc/jwc_service.dart';
import 'services/aac/aac_service.dart';
import 'services/aac/aac_config.dart';
import 'services/competition/competition_service.dart';
import 'services/competition/competition_config.dart';
import 'services/isim/isim_service.dart';
import 'services/isim/isim_config.dart';
import 'services/labor_club/labor_club_service.dart';
import 'services/labor_club/ldjlb_config.dart';
import 'services/ykt/ykt_service.dart';
import 'services/cache_manager.dart';
import 'services/logger_service.dart';
import 'services/manifest_service.dart';
import 'utils/platform/platform_util.dart';
// Mobile screens
import 'screens/home_screen.dart';
import 'screens/more_page.dart';
import 'screens/exam_info_page.dart';
import 'screens/training_plan_page.dart';
import 'screens/competition_page.dart';
import 'screens/electricity_page.dart';
import 'screens/labor_club_page.dart';
import 'screens/scan_sign_in_page.dart';
import 'screens/ykt_page.dart';
// Desktop (WinUI) screens
import 'winui/screens/winui_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 清除所有缓存（app重启时）
  await CacheManager.clear();
  LoggerService.info('🗑️ 已清除所有缓存（app启动）');

  // 初始化 SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // 创建 ManifestService
  final manifestService = ManifestService(
    dio: Dio(),
    manifestUrl: AppConstants.manifestUrl,
  );

  runApp(MyApp(prefs: prefs, manifestService: manifestService));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  final ManifestService manifestService;

  const MyApp({
    super.key,
    required this.prefs,
    required this.manifestService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Theme Provider - manages app theme and color scheme
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // Auth Provider - manages authentication state
        ChangeNotifierProvider(create: (_) => AuthProvider()),

        // Manifest Provider - manages app announcements and OTA updates
        ChangeNotifierProvider(
          create: (_) => ManifestProvider(
            service: manifestService,
            prefs: prefs,
          ),
        ),

        // Academic Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, AcademicProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create AcademicProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final jwcService = JWCService(authProvider.connection!);
              return AcademicProvider(jwcService);
            }
            return previous;
          },
        ),

        // AAC Provider - depends on AuthProvider for AACService
        ChangeNotifierProxyProvider<AuthProvider, AACProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create AACProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final aacService = AACService(
                authProvider.connection!,
                AACConfig(),
              );
              return AACProvider(aacService);
            }
            return previous;
          },
        ),

        // Term Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, TermProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create TermProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final jwcService = JWCService(authProvider.connection!);
              return TermProvider(jwcService);
            }
            return previous;
          },
        ),

        // Term Score Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, TermScoreProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create TermScoreProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final jwcService = JWCService(authProvider.connection!);
              return TermScoreProvider(jwcService);
            }
            return previous;
          },
        ),

        // More Provider - manages more features list
        ChangeNotifierProvider(create: (_) => MoreProvider()),

        // Pinned Features Provider - manages pinned features on home page
        ChangeNotifierProvider(create: (_) => PinnedFeaturesProvider()),

        // Exam Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, ExamProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create ExamProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final jwcService = JWCService(authProvider.connection!);
              return ExamProvider(jwcService);
            }
            return previous;
          },
        ),

        // Training Plan Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, TrainingPlanProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create TrainingPlanProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final jwcService = JWCService(authProvider.connection!);
              return TrainingPlanProvider(jwcService);
            }
            return previous;
          },
        ),

        // Course Schedule Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, CourseScheduleProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create CourseScheduleProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final jwcService = JWCService(authProvider.connection!);
              return CourseScheduleProvider(jwcService);
            }
            return previous;
          },
        ),

        // Competition Provider - depends on AuthProvider for CompetitionService
        ChangeNotifierProxyProvider<AuthProvider, CompetitionProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create CompetitionProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final competitionService = CompetitionService(
                authProvider.connection!,
                CompetitionConfig(),
              );
              return CompetitionProvider(competitionService);
            }
            return previous;
          },
        ),

        // Electricity Provider - depends on AuthProvider for ISIMService
        ChangeNotifierProxyProvider<AuthProvider, ElectricityProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create ElectricityProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              // 如果已经有 provider 实例，直接返回
              if (previous != null) {
                return previous;
              }

              // 创建新的 provider 实例
              final isimService = ISIMService(
                authProvider.connection!,
                ISIMConfig(),
              );
              final provider = ElectricityProvider(isimService);

              // 异步加载绑定的房间信息
              provider.loadBoundRoom(authProvider.connection!.userId);

              return provider;
            }
            return previous;
          },
        ),

        // Labor Club Provider - depends on AuthProvider for LaborClubService
        ChangeNotifierProxyProvider<AuthProvider, LaborClubProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create LaborClubProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              final laborClubService = LaborClubService(
                authProvider.connection!,
                LDJLBConfig(),
              );
              return LaborClubProvider(laborClubService);
            }
            return previous;
          },
        ),

        // YKT Provider - depends on AuthProvider for YKTService
        ChangeNotifierProxyProvider<AuthProvider, YKTProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create YKTProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              // 如果已经有 provider 实例，直接返回
              if (previous != null) {
                return previous;
              }

              // 创建新的 provider 实例
              final yktService = YKTService(authProvider.connection!);
              return YKTProvider(yktService);
            }
            // 用户未认证时，清理旧实例
            return null;
          },
        ),

        // Smart Course Selection Provider - depends on AuthProvider for JWCService
        ChangeNotifierProxyProvider<AuthProvider, SmartCourseSelectionProvider?>(
          create: (_) => null,
          update: (context, authProvider, previous) {
            // Only create SmartCourseSelectionProvider when user is authenticated
            if (authProvider.isAuthenticated &&
                authProvider.connection != null) {
              // 如果已经有 provider 实例，直接返回
              if (previous != null) {
                return previous;
              }

              // 创建新的 provider 实例
              final jwcService = JWCService(authProvider.connection!);
              return SmartCourseSelectionProvider(jwcService);
            }
            return previous;
          },
        ),

        // Session Manager - depends on AuthProvider
        ProxyProvider<AuthProvider, SessionManager>(
          update: (context, authProvider, previous) {
            // Dispose previous session manager if it exists
            previous?.dispose();
            return SessionManager(authProvider);
          },
          dispose: (context, sessionManager) => sessionManager.dispose(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          // 根据平台选择不同的 App
          if (PlatformUtil.isDesktop) {
            // 桌面端使用 FluentApp (WinUI 风格)
            return fluent.FluentApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              theme: _buildFluentTheme(themeProvider, fluent.Brightness.light),
              darkTheme: _buildFluentTheme(themeProvider, fluent.Brightness.dark),
              themeMode: _convertThemeMode(themeProvider.themeMode),
              home: const WinUIHomeScreen(),
            );
          } else {
            // 移动端使用 MaterialApp
            return MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              theme: themeProvider.lightTheme,
              darkTheme: themeProvider.darkTheme,
              themeMode: themeProvider.themeMode,
              home: const HomeScreen(),
              routes: {
                '/more': (context) => const MorePage(),
                '/exam-info': (context) => const ExamInfoPage(),
                '/training-plan': (context) => const TrainingPlanPage(),
                '/competition-info': (context) => const CompetitionPage(),
                '/electricity': (context) => const ElectricityPage(),
                '/labor-club': (context) => const LaborClubPage(),
                '/labor-club/scan': (context) => const ScanSignInPage(),
                '/ykt': (context) => const YKTPage(),
              },
            );
          }
        },
      ),
    );
  }

  /// 构建 FluentTheme 数据
  fluent.FluentThemeData _buildFluentTheme(
    ThemeProvider themeProvider,
    fluent.Brightness brightness,
  ) {
    // 获取主题颜色
    final colorScheme = brightness == fluent.Brightness.light
        ? themeProvider.lightTheme.colorScheme
        : themeProvider.darkTheme.colorScheme;

    return fluent.FluentThemeData(
      brightness: brightness,
      accentColor: fluent.AccentColor.swatch({
        'darkest': colorScheme.primary,
        'darker': colorScheme.primary,
        'dark': colorScheme.primary,
        'normal': colorScheme.primary,
        'light': colorScheme.primaryContainer,
        'lighter': colorScheme.primaryContainer,
        'lightest': colorScheme.primaryContainer,
      }),
      fontFamily: PlatformUtil.isWindows ? 'MiSans' : null,
    );
  }

  /// 转换 ThemeMode 到 fluent.ThemeMode
  fluent.ThemeMode _convertThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return fluent.ThemeMode.light;
      case ThemeMode.dark:
        return fluent.ThemeMode.dark;
      case ThemeMode.system:
        return fluent.ThemeMode.system;
    }
  }
}
