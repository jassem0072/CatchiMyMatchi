import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../screens/ai_coach_chat_screen.dart';
import '../screens/montage_screen.dart';
import '../screens/analysis_details_screen.dart';
import '../screens/analysis_progress_screen.dart';
import '../screens/billing_history_screen.dart';
import '../screens/comparator_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/help_support_screen.dart';
import '../screens/identify_player_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/login_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/playback_screen.dart';
import '../screens/player_detail_screen.dart';
import '../screens/player_shell.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/register_screen.dart';
import '../screens/verify_code_screen.dart';
import '../screens/scouter_shell.dart';
import '../screens/scouter_video_player_screen.dart';
import '../screens/security_privacy_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tag_teammates_screen.dart';
import '../screens/terms_screen.dart';
import '../screens/upload_video_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../services/locale_notifier.dart';

class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const dashboard = '/dashboard';       // legacy — routes to player shell
  static const playerHome = '/player-home';
  static const scouterHome = '/scouter-home';
  static const uploadVideo = '/upload-video';
  static const identifyPlayer = '/identify-player';
  static const progress = '/analysis-progress';
  static const details = '/analysis-details';
  static const playback = '/playback';
  static const profile = '/profile';
  static const settings = '/settings';
  static const notifications = '/notifications';
  static const comparator = '/comparator';
  static const playerDetail = '/player-detail';
  static const scouterVideoPlayer = '/scouter-video-player';
  static const terms = '/terms';
  static const editProfile = '/edit-profile';
  static const securityPrivacy = '/security-privacy';
  static const billingHistory = '/billing-history';
  static const privacyPolicy = '/privacy-policy';
  static const helpSupport = '/help-support';
  static const tagTeammates = '/tag-teammates';
  static const verifyCode = '/verify-code';
  static const aiCoach = '/ai-coach';
  static const montage = '/montage';
}

class ScoutAiApp extends StatelessWidget {
  const ScoutAiApp({super.key});

  String _computeInitialRoute() {
    if (!kIsWeb) return AppRoutes.login;
    final frag = Uri.base.fragment.trim();
    if (frag.isEmpty) return AppRoutes.login;
    return frag.startsWith('/') ? frag : '/$frag';
  }

  Route<dynamic> _routeFor(String? name, {Object? arguments}) {
    final raw = (name ?? AppRoutes.login).trim();
    final uri = Uri.parse(raw.isEmpty ? AppRoutes.login : raw);
    final path = uri.path.isNotEmpty ? uri.path : AppRoutes.login;
    RouteSettings rs(String p) => RouteSettings(name: p, arguments: arguments);
    switch (path) {
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen(), settings: rs(path));
      case AppRoutes.register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen(), settings: rs(path));
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen(), settings: rs(path));
      case AppRoutes.dashboard:
      case AppRoutes.playerHome:
        return MaterialPageRoute(builder: (_) => const PlayerShell(), settings: rs(path));
      case AppRoutes.scouterHome:
        return MaterialPageRoute(builder: (_) => const ScouterShell(), settings: rs(path));
      case AppRoutes.uploadVideo:
        return MaterialPageRoute(builder: (_) => const UploadVideoScreen(), settings: rs(path));
      case AppRoutes.identifyPlayer:
        return MaterialPageRoute(builder: (_) => const IdentifyPlayerScreen(), settings: rs(path));
      case AppRoutes.progress:
        return MaterialPageRoute(builder: (_) => const AnalysisProgressScreen(), settings: rs(path));
      case AppRoutes.details:
        return MaterialPageRoute(builder: (_) => const AnalysisDetailsScreen(), settings: rs(path));
      case AppRoutes.playback:
        return MaterialPageRoute(builder: (_) => const PlaybackScreen(), settings: rs(path));
      case AppRoutes.profile:
        return MaterialPageRoute(builder: (_) => const ProfileScreen(), settings: rs(path));
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen(), settings: rs(path));
      case AppRoutes.notifications:
        return MaterialPageRoute(builder: (_) => const NotificationsScreen(), settings: rs(path));
      case AppRoutes.comparator:
        return MaterialPageRoute(builder: (_) => const ComparatorScreen(), settings: rs(path));
      case AppRoutes.playerDetail:
        return MaterialPageRoute(builder: (_) => const PlayerDetailScreen(), settings: rs(path));
      case AppRoutes.scouterVideoPlayer:
        return MaterialPageRoute(builder: (_) => const ScouterVideoPlayerScreen(), settings: rs(path));
      case AppRoutes.terms:
        return MaterialPageRoute(builder: (_) => const TermsScreen(), settings: rs(path));
      case AppRoutes.editProfile:
        return MaterialPageRoute(builder: (_) => const EditProfileScreen(), settings: rs(path));
      case AppRoutes.securityPrivacy:
        return MaterialPageRoute(builder: (_) => const SecurityPrivacyScreen(), settings: rs(path));
      case AppRoutes.billingHistory:
        return MaterialPageRoute(builder: (_) => const BillingHistoryScreen(), settings: rs(path));
      case AppRoutes.privacyPolicy:
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen(), settings: rs(path));
      case AppRoutes.helpSupport:
        return MaterialPageRoute(builder: (_) => const HelpSupportScreen(), settings: rs(path));
      case AppRoutes.tagTeammates:
        return MaterialPageRoute(builder: (_) => const TagTeammatesScreen(), settings: rs(path));
      case AppRoutes.verifyCode:
        return MaterialPageRoute(builder: (_) => const VerifyCodeScreen(), settings: rs(path));
      case AppRoutes.aiCoach:
        return MaterialPageRoute(builder: (_) => const AiCoachChatScreen(), settings: rs(path));
      case AppRoutes.montage:
        return MaterialPageRoute(builder: (_) => const MontageScreen(), settings: rs(path));
    }

    return MaterialPageRoute(builder: (_) => const LoginScreen(), settings: rs(AppRoutes.login));
  }

  @override
  Widget build(BuildContext context) {
    final initialRoute = _computeInitialRoute();
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (_, themeMode, __) {
        return ValueListenableBuilder<Locale>(
          valueListenable: LocaleNotifier.instance,
          builder: (_, locale, __) {
        return MaterialApp(
          title: 'ScoutAI',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          locale: locale,
          initialRoute: initialRoute,
      onGenerateInitialRoutes: (route) {
        final routes = <Route<dynamic>>[];
        final path = Uri.parse(route).path;
        if (path != AppRoutes.login &&
            path != AppRoutes.register &&
            path != AppRoutes.forgotPassword &&
            path != AppRoutes.dashboard &&
            path != AppRoutes.playerHome &&
            path != AppRoutes.scouterHome) {
          routes.add(_routeFor(AppRoutes.playerHome));
        }
        routes.add(_routeFor(route));
        return routes;
      },
      onGenerateRoute: (settings) => _routeFor(settings.name, arguments: settings.arguments),
    );
          },
        );
      },
    );
  }
}
