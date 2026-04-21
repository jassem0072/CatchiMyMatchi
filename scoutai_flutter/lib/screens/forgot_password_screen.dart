import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      try {
        final frag = Uri.base.fragment; // e.g. /forgot-password?email=...&token=...
        final idx = frag.indexOf('?');
        if (idx >= 0) {
          final u = Uri.parse(frag.startsWith('/') ? frag : '/$frag');
          final email = (u.queryParameters['email'] ?? '').trim();
          final token = (u.queryParameters['token'] ?? '').trim();
          if (email.isNotEmpty) _emailCtrl.text = email;
          if (token.isNotEmpty) _tokenCtrl.text = token;
          if (token.isNotEmpty) {
            _info = 'Token loaded from email link. Choose a new password.';
          }
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestToken() async {
    final email = _emailCtrl.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });

    if (email.isEmpty) {
      setState(() => _error = 'Enter your email');
      return;
    }

    setState(() => _busy = true);
    try {
      await AuthApi().forgotPassword(email: email);
      setState(() => _info = 'If this email exists, a reset token was sent. Check your email.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;

    setState(() {
      _error = null;
      _info = null;
    });

    if (email.isEmpty || token.isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'Fill email, token and new password');
      return;
    }

    setState(() => _busy = true);
    try {
      await AuthApi().resetPassword(email: email, token: token, newPassword: newPassword);
      if (!mounted) return;
      setState(() => _info = 'Password updated. You can login now.');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
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
      appBar: AppBar(
        title: Text(S.of(context).forgotPassword),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        children: [
          const SizedBox(height: 8),
          const Center(child: AppLogo(size: 72)),
          const SizedBox(height: 18),
          Text(
            S.of(context).resetYourPassword,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 10),
          Text(
            S.of(context).resetInstructions,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          Text(
            S.of(context).emailAddress,
            style: const TextStyle(
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
            decoration: const InputDecoration(
              hintText: 'scout@club.com',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _requestToken,
            child: Text(S.of(context).requestResetToken),
          ),
          const SizedBox(height: 18),
          Text(
            S.of(context).token,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tokenCtrl,
            decoration: InputDecoration(
              hintText: S.of(context).pasteToken,
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            S.of(context).newPasswordLabel,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _newPasswordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: '••••••••',
              prefixIcon: Icon(Icons.lock_outline),
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
          if (_info != null) ...[
            Text(
              _info!,
              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: _busy ? null : _resetPassword,
            child: Text(S.of(context).resetPassword),
          ),
        ],
      ),
    );
  }
}
