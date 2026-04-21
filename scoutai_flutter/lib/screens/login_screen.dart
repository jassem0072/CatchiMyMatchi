import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/jwt_utils.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscure = true;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _rememberMe = false;

  bool _prefilledFromArgs = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilledFromArgs) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty) {
      _emailCtrl.text = args.trim();
      _prefilledFromArgs = true;
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _error = null);
    setState(() => _busy = true);
    try {
      final google = GoogleSignIn(
        scopes: const ['email'],
      );

      // Force account chooser.
      try {
        await google.signOut();
      } catch (_) {}

      final account = await google.signIn();
      if (account == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }

      String? idToken;
      String? accessToken;
      String? googleEmail;
      String? googleDisplayName;

      if (kIsWeb) {
        // On web, google_sign_in_web v0.12+ uses GIS. Calling account.authentication
        // triggers the OAuth2 Code Client popup which causes redirect_uri_mismatch.
        // Instead, use the verified account info from signIn() directly.
        googleEmail = account.email;
        googleDisplayName = account.displayName ?? '';
      } else {
        final auth = await account.authentication;
        idToken = auth.idToken;
        accessToken = auth.accessToken;
      }

      String token;
      if (kIsWeb && googleEmail != null && googleEmail.isNotEmpty) {
        // Web flow: use Google-verified email from GIS sign-in
        try {
          token = await AuthApi().googleWeb(email: googleEmail, displayName: googleDisplayName ?? '');
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('role is required')) {
            token = await AuthApi().googleWeb(email: googleEmail, displayName: googleDisplayName ?? '', role: 'player');
          } else {
            rethrow;
          }
        }
      } else {
        if ((idToken == null || idToken.isEmpty) && (accessToken == null || accessToken.isEmpty)) {
          throw Exception('Missing Google token');
        }
        try {
          token = await AuthApi().google(idToken: idToken, accessToken: accessToken);
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('role is required')) {
            token = await AuthApi().google(idToken: idToken, accessToken: accessToken, role: 'player');
          } else {
            rethrow;
          }
        }
      }
      await AuthStorage.saveToken(token, remember: _rememberMe);
      if (!mounted) return;
      final googleHome = await _homeForToken(token);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(googleHome);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<String> _homeForToken(String token) async {
    final role = roleFromToken(token);
    if (role == 'scouter') {
      try {
        final me = await AuthApi().me(token);
        if (me['badgeVerified'] != true) return AppRoutes.profile;
      } catch (_) {}
      return AppRoutes.scouterHome;
    }
    return AppRoutes.playerHome;
  }

  Future<void> _tryAutoLogin() async {
    final token = await AuthStorage.loadToken();
    if (!mounted) return;
    if (token == null) return;
    try {
      await AuthApi().me(token);
      if (!mounted) return;
      final home = await _homeForToken(token);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(home);
      });
    } catch (_) {
      await AuthStorage.clear();
    }
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() => _error = null);

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = S.current.enterEmailPassword);
      return;
    }

    setState(() => _busy = true);
    try {
      final token = await AuthApi().signin(email: email, password: password);
      await AuthStorage.saveToken(token, remember: _rememberMe);
      if (!mounted) return;
      final home = await _homeForToken(token);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(home);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      // If email not verified, redirect to verification screen
      final low = msg.toLowerCase();
      if (low.contains('verify your email') ||
          low.contains('email not verified') ||
          (low.contains('not verified') && low.contains('email')) ||
          low.contains('6-digit')) {
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.verifyCode,
          arguments: {
            'email': email,
            'codeSent': true,
          },
        );
        return;
      }
      setState(() => _error = msg);
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 44, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Center(child: AppLogo(size: 78)),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'ScoutAI',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                s.platformSubtitle,
                style: TextStyle(
                  color: AppColors.txMuted(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 34),
            Text(
              s.welcomeBackScout,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            Text(
              s.emailAddress,
              style: TextStyle(
                color: AppColors.txMuted(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: const InputDecoration(
                hintText: 'scout@club.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.securePassword,
              style: TextStyle(
                color: AppColors.txMuted(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _rememberMe = v ?? false);
                        },
                ),
                Flexible(
                  child: Text(
                    s.rememberMe,
                    style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.of(context).pushNamed(AppRoutes.forgotPassword);
                          },
                    child: Text(
                      s.forgotPassword,
                      style: TextStyle(color: AppColors.txMuted(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      s.signInDashboard,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Divider(color: AppColors.bdr(context).withValues(alpha: 0.8)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    s.orContinueWith,
                    style: TextStyle(
                      color: AppColors.txMuted(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: AppColors.bdr(context).withValues(alpha: 0.8)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _googleSignIn,
              icon: const Icon(Icons.g_mobiledata, size: 24),
              label: Text(s.continueWithGoogle),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    s.newScout,
                    style: TextStyle(color: AppColors.txMuted(context)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.register);
                  },
                  child: Text(
                    s.registerHub,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 64,
        width: 64,
        decoration: BoxDecoration(
          color: AppColors.surf2(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
        ),
        child: Icon(icon, color: AppColors.tx(context), size: 26),
      ),
    );
  }
}
