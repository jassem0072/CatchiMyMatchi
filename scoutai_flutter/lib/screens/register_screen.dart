import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/country_picker.dart';

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

  bool _prefilledFromArgs = false;

  String? _selectedPosition;
  String? _selectedNation;

  bool _busy = false;
  String? _error;

  static const _positions = [
    'GK', 'CB', 'LB', 'RB', 'LWB', 'RWB', 'SW',
    'CDM', 'CM', 'CAM', 'LM', 'RM',
    'LW', 'RW', 'CF', 'ST',
  ];

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    setState(() => _error = null);

    final displayName = _displayNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (displayName.isEmpty) {
      setState(() => _error = S.current.enterName);
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = S.current.enterEmail);
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() => _error = S.current.passwordMinChars);
      return;
    }
    if (password != confirm) {
      setState(() => _error = S.current.passwordsNoMatch);
      return;
    }

    setState(() => _busy = true);
    try {
      final verifiedEmail = await AuthApi().signup(
        email: email,
        password: password,
        role: 'player',
        displayName: displayName,
        position: _selectedPosition ?? '',
        nation: _selectedNation ?? '',
      );
      if (!mounted) return;
      // Navigate to 6-digit code verification screen
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.verifyCode,
        arguments: verifiedEmail,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      final low = msg.toLowerCase();
      if (low.contains('email already in use') || low.contains('already in use')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email already in use. Please log in.')),
        );
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.login,
          arguments: email,
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
      appBar: AppBar(
        title: Text(s.createAccount),
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
            Text(
              s.joinAcademy,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34),
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  color: AppColors.txMuted(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                children: [
                  TextSpan(text: s.startAnalyzing),
                  TextSpan(
                    text: s.aiPerformance,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(text: s.trackingDot),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(s.fullName, style: TextStyle(color: AppColors.txMuted(context))),
            const SizedBox(height: 10),
            TextField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(
                hintText: 'Cristiano Ronaldo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 18),
            Text(s.position, style: TextStyle(color: AppColors.txMuted(context))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedPosition,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.sports_soccer_outlined),
                hintText: 'Select position',
              ),
              items: _positions.map((p) => DropdownMenuItem(
                value: p,
                child: Text(p),
              )).toList(),
              onChanged: (v) => setState(() => _selectedPosition = v),
            ),
            const SizedBox(height: 18),
            Text(s.nation, style: TextStyle(color: AppColors.txMuted(context))),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final picked = await showCountryPicker(context, current: _selectedNation);
                if (picked != null && mounted) setState(() => _selectedNation = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.flag_outlined),
                  hintText: 'Select country',
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: _selectedNation != null
                    ? Row(
                        children: [
                          if (flagForCountry(_selectedNation!).isNotEmpty)
                            Text(flagForCountry(_selectedNation!), style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_selectedNation!, overflow: TextOverflow.ellipsis)),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.emailAddress,
              style: TextStyle(color: AppColors.txMuted(context)),
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
            Text(s.password, style: TextStyle(color: AppColors.txMuted(context))),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: s.minChars,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.confirmPassword,
              style: TextStyle(color: AppColors.txMuted(context)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: s.repeatPassword,
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
                  Text(s.createAccount),
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
                  child: Text(
                    s.logIn,
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
