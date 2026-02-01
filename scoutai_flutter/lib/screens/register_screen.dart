import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _obscure = true;
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _nationCtrl = TextEditingController();

  String? _role;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _positionCtrl.dispose();
    _nationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    final displayName = _displayNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;
    final role = _role;

    if (role == null) {
      setState(() => _error = 'Select a role (player or scouter)');
      return;
    }
    if (displayName.isEmpty) {
      setState(() => _error = 'Enter your name');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email');
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() => _busy = true);
    try {
      final token = await AuthApi().signup(
        email: email,
        password: password,
        role: role,
        displayName: displayName,
        position: role == 'player' ? _positionCtrl.text : null,
        nation: role == 'player' ? _nationCtrl.text : null,
      );
      await AuthStorage.saveToken(token);
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
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Center(child: AppLogo(size: 66)),
            const SizedBox(height: 18),
            const Text(
              'Join the Academy',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34),
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                children: [
                  TextSpan(text: 'Start analyzing matches with '),
                  TextSpan(
                    text: 'AI\nperformance',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(text: ' tracking.'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text('Role', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _role,
              items: const [
                DropdownMenuItem(value: 'player', child: Text('Player')),
                DropdownMenuItem(value: 'scouter', child: Text('Scouter')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _role = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.badge_outlined),
                hintText: 'Choose your role',
              ),
            ),
            const SizedBox(height: 18),
            const Text('Full Name', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            TextField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(
                hintText: 'Cristiano Ronaldo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            if (_role == 'player') ...[
              const SizedBox(height: 18),
              const Text('Position (player)', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              TextField(
                controller: _positionCtrl,
                decoration: const InputDecoration(
                  hintText: 'ST',
                  prefixIcon: Icon(Icons.sports_soccer_outlined),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Nation (player)', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              TextField(
                controller: _nationCtrl,
                decoration: const InputDecoration(
                  hintText: 'TN',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Email Address',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'scout@academy.ai',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Password', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: 'Min. 6 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Confirm Password',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Repeat password',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_busy) ...[
                    const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Text('Create Account'),
                  const SizedBox(width: 10),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
                  },
                  child: const Text(
                    'Log In',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w900,
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
