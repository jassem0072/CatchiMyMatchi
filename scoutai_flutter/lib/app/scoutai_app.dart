import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../screens/analysis_details_screen.dart';
import '../screens/analysis_progress_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/identify_player_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/login_screen.dart';
import '../screens/playback_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/register_screen.dart';
import '../screens/upload_video_screen.dart';
import '../theme/app_theme.dart';

class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const dashboard = '/dashboard';
  static const uploadVideo = '/upload-video';
  static const identifyPlayer = '/identify-player';
  static const progress = '/analysis-progress';
  static const details = '/analysis-details';
  static const playback = '/playback';
  static const profile = '/profile';
}

class ScoutAiApp extends StatelessWidget {
  const ScoutAiApp({super.key});

  String _computeInitialRoute() {
    if (!kIsWeb) return AppRoutes.login;
    final frag = Uri.base.fragment.trim();
    if (frag.isEmpty) return AppRoutes.login;
    return frag.startsWith('/') ? frag : '/$frag';
  }

  Route<dynamic> _routeFor(String? name) {
    final raw = (name ?? AppRoutes.login).trim();
    final uri = Uri.parse(raw.isEmpty ? AppRoutes.login : raw);
    final path = uri.path.isNotEmpty ? uri.path : AppRoutes.login;
    switch (path) {
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen(), settings: RouteSettings(name: path));
      case AppRoutes.register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen(), settings: RouteSettings(name: path));
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen(), settings: RouteSettings(name: path));
      case AppRoutes.dashboard:
        return MaterialPageRoute(builder: (_) => const DashboardScreen(), settings: RouteSettings(name: path));
      case AppRoutes.uploadVideo:
        return MaterialPageRoute(builder: (_) => const UploadVideoScreen(), settings: RouteSettings(name: path));
      case AppRoutes.identifyPlayer:
        return MaterialPageRoute(builder: (_) => const IdentifyPlayerScreen(), settings: RouteSettings(name: path));
      case AppRoutes.progress:
        return MaterialPageRoute(builder: (_) => const AnalysisProgressScreen(), settings: RouteSettings(name: path));
      case AppRoutes.details:
        return MaterialPageRoute(builder: (_) => const AnalysisDetailsScreen(), settings: RouteSettings(name: path));
      case AppRoutes.playback:
        return MaterialPageRoute(builder: (_) => const PlaybackScreen(), settings: RouteSettings(name: path));
      case AppRoutes.profile:
        return MaterialPageRoute(builder: (_) => const ProfileScreen(), settings: RouteSettings(name: path));
    }

    return MaterialPageRoute(builder: (_) => const LoginScreen(), settings: RouteSettings(name: AppRoutes.login));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScoutAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      initialRoute: _computeInitialRoute(),
      onGenerateInitialRoutes: (initialRoute) => <Route<dynamic>>[_routeFor(initialRoute)],
      onGenerateRoute: (settings) => _routeFor(settings.name),
    );
  }
}
