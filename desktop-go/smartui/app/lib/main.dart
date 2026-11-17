import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import 'bridge/mygo_bridge.dart';
import 'providers/auth_provider.dart';
import 'providers/smart_course_selection_provider.dart';
import 'services/jwc/jwc_service.dart';
import 'winui/screens/winui_smart_course_selection_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final userId = await callGo('SmartData.UserID') as String? ?? '';
  runApp(SmartCourseApp(userId: userId));
}

class SmartCourseApp extends StatelessWidget {
  const SmartCourseApp({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(userId),
        ),
        ChangeNotifierProvider<SmartCourseSelectionProvider>(
          create: (_) => SmartCourseSelectionProvider(JWCService()),
        ),
      ],
      child: FluentApp(
        title: '智能排课',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: FluentThemeData(fontFamily: 'MiSans'),
        darkTheme: FluentThemeData(brightness: Brightness.dark, fontFamily: 'MiSans'),
        home: const WinUISmartCourseSelectionPage(),
      ),
    );
  }
}
