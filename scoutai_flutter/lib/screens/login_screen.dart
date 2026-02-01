import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
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

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<String?> _pickRole() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose your role'),
          content: const Text('Select how you want to use ScoutAI.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('player'),
              child: const Text('Player'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('scouter'),
              child: const Text('Scouter'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _googleSignIn() async {
    setState(() => _error = null);
    setState(() => _busy = true);
    try {
      const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
      final google = GoogleSignIn(
        scopes: const ['openid', 'email', 'profile'],
        clientId: kIsWeb && webClientId.isNotEmpty ? webClientId : null,
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
      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if ((idToken == null || idToken.isEmpty) && (accessToken == null || accessToken.isEmpty)) {
        throw Exception('Missing Google token');
      }

      String token;
      try {
        token = await AuthApi().google(idToken: idToken, accessToken: accessToken);
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('role is required')) {
          final role = await _pickRole();
          if (role == null) throw Exception('Role selection cancelled');
          token = await AuthApi().google(idToken: idToken, accessToken: accessToken, role: role);
        } else {
          rethrow;
        }
      }
      await AuthStorage.saveToken(token, remember: _rememberMe);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
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

  Future<void> _tryAutoLogin() async {
    final token = await AuthStorage.loadToken();
    if (!mounted) return;
    if (token == null) return;
    try {
      await AuthApi().me(token);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
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
      setState(() => _error = 'Enter email and password');
      return;
    }

    setState(() => _busy = true);
    try {
      final token = await AuthApi().signin(email: email, password: password);
      await AuthStorage.saveToken(token, remember: _rememberMe);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const Center(
              child: Text(
                'Professional Match Analysis Platform',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 34),
            const Text(
              'Welcome Back, Scout',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            const Text(
              'EMAIL ADDRESS',
              style: TextStyle(
                color: AppColors.textMuted,
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
            const Text(
              'SECURE PASSWORD',
              style: TextStyle(
                color: AppColors.textMuted,
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
                const Text(
                  'Remember me',
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          Navigator.of(context).pushNamed(AppRoutes.forgotPassword);
                        },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('SIGN IN TO DASHBOARD'),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Divider(color: AppColors.border.withValues(alpha: 0.8)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'OR CONTINUE WITH',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: AppColors.border.withValues(alpha: 0.8)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _googleSignIn,
              icon: const Icon(Icons.g_mobiledata, size: 24),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'New scout on the team? ',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.register);
                  },
                  child: const Text(
                    'Register Hub',
                    style: TextStyle(
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
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
        ),
        child: Icon(icon, color: AppColors.text, size: 26),
      ),
    );
  }
}
