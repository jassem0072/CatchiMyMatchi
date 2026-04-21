import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/jwt_utils.dart';
import '../theme/app_colors.dart';

class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({super.key});

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _email;
  bool _resending = false;

  bool _initFromArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initFromArgs) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String) {
      _email = args;
      _codeSent = false;
    } else if (args is Map) {
      final e = args['email'];
      final cs = args['codeSent'];
      if (e is String) _email = e;
      _codeSent = cs == true;
    }
    _initFromArgs = true;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _sendCode() async {
    final email = _email;
    if (email == null || email.isEmpty) {
      setState(() => _error = 'Email missing');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthApi().resendCode(email: email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      final low = msg.toLowerCase();
      if (low.contains('already verified')) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email already verified. Please log in.')),
        );
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.login,
          arguments: email,
        );
        return;
      }
      if (low.contains('user not found')) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No account found for this email. Please sign up first.')),
        );
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.register,
          arguments: email,
        );
        return;
      }
      setState(() {
        _error = msg;
        _busy = false;
      });
    }
  }

  Future<void> _verify() async {
    final code = _code.trim();
    if (code.length != 6) {
      setState(() => _error = 'Please enter the full 6-digit code');
      return;
    }
    final email = _email;
    if (email == null || email.isEmpty) {
      setState(() => _error = 'Email missing');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final token = await AuthApi().verifyCode(email: email, code: code);
      await AuthStorage.saveToken(token, remember: true);
      if (!mounted) return;

      final role = roleFromToken(token);
      final home = role == 'scouter' ? AppRoutes.scouterHome : AppRoutes.playerHome;
      Navigator.of(context).pushReplacementNamed(home);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      final low = msg.toLowerCase();
      if (low.contains('user not found')) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No account found for this email. Please sign up first.')),
        );
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.register,
          arguments: email,
        );
        return;
      }
      setState(() {
        _error = msg;
        _busy = false;
      });
    }
  }

  Future<void> _resend() async {
    final email = _email;
    if (email == null || email.isEmpty) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await AuthApi().resendCode(email: email);
      if (!mounted) return;
      setState(() => _resending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New code sent! Check your inbox.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      final low = msg.toLowerCase();
      if (low.contains('already verified')) {
        setState(() => _resending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email already verified. Please log in.')),
        );
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.login,
          arguments: email,
        );
        return;
      }
      if (low.contains('user not found')) {
        setState(() => _resending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No account found for this email. Please sign up first.')),
        );
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.register,
          arguments: email,
        );
        return;
      }
      setState(() {
        _error = msg;
        _resending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _codeSent ? Icons.mark_email_read_rounded : Icons.verified_user_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Verify Your Email',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  _email ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),

                if (!_codeSent) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Click the button below to send a 6-digit\nverification code to your email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.txMuted(context), fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _sendCode,
                      icon: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _busy ? 'Sending...' : 'Send Verification Code',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    'Enter the 6-digit code we sent to your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.txMuted(context), fontSize: 14),
                  ),
                  const SizedBox(height: 24),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 8.0;
                      final raw = (constraints.maxWidth - gap * 5) / 6;
                      final w = (raw.isFinite ? raw : 0.0).clamp(0.0, 44.0) as double;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (i) {
                          return Container(
                            width: w,
                            height: 52,
                            margin: EdgeInsets.only(right: i < 5 ? gap : 0),
                            child: TextField(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              maxLength: 1,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                ),
                                filled: true,
                                fillColor: AppColors.surface.withValues(alpha: 0.5),
                              ),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (val) {
                                if (val.isNotEmpty && i < 5) {
                                  _focusNodes[i + 1].requestFocus();
                                }
                                if (val.isEmpty && i > 0) {
                                  _focusNodes[i - 1].requestFocus();
                                }
                              },
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : _verify,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Didn't receive it? ", style: TextStyle(color: AppColors.txMuted(context), fontSize: 13)),
                      GestureDetector(
                        onTap: _resending ? null : _resend,
                        child: Text(
                          _resending ? 'Sending...' : 'Resend Code',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed(
                    AppRoutes.login,
                    arguments: _email,
                  ),
                  child: Text('Back to Login', style: TextStyle(color: AppColors.txMuted(context))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
