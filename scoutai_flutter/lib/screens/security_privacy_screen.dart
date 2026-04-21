import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Security & Privacy screen — change password, delete account.
class SecurityPrivacyScreen extends StatefulWidget {
  const SecurityPrivacyScreen({super.key});

  @override
  State<SecurityPrivacyScreen> createState() => _SecurityPrivacyScreenState();
}

class _SecurityPrivacyScreenState extends State<SecurityPrivacyScreen> {
  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  /// Parse a NestJS error body (JSON with "message" key) to a human-readable string.
  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final msg = data['message'];
        if (msg is List) return msg.join(', ');
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return body;
  }

  Future<void> _changePassword() async {
    final s = S.current;
    final current = _currentPwdCtrl.text;
    final newPwd = _newPwdCtrl.text;
    final confirm = _confirmPwdCtrl.text;

    if (current.isEmpty || newPwd.isEmpty) {
      setState(() => _error = s.enterEmailPassword);
      return;
    }
    if (newPwd.length < 6) {
      setState(() => _error = s.passwordMinChars);
      return;
    }
    if (newPwd != confirm) {
      setState(() => _error = s.passwordsNoMatch);
      return;
    }

    setState(() { _busy = true; _error = null; _success = null; });
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/password');
      final res = await http.patch(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }, body: jsonEncode({
        'currentPassword': current,
        'newPassword': newPwd,
      }));
      if (!mounted) return;
      if (res.statusCode >= 400) {
        final msg = _parseError(res.body.trim());
        throw Exception(msg.isNotEmpty ? msg : 'Failed (${res.statusCode})');
      }
      _currentPwdCtrl.clear();
      _newPwdCtrl.clear();
      _confirmPwdCtrl.clear();
      setState(() { _busy = false; _success = s.saved; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteAccount),
        content: Text(s.deleteAccountWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.deleteAccount),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = await AuthStorage.loadToken();
    if (token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      await http.delete(uri, headers: {'Authorization': 'Bearer $token'});
    } catch (_) {}
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.securityPrivacy),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Text(
            s.changePassword,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 16),
          Text(s.currentPassword, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _currentPwdCtrl,
            obscureText: !_showCurrent,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
              hintText: s.password,
              suffixIcon: IconButton(
                icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showCurrent = !_showCurrent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(s.newPassword, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _newPwdCtrl,
            obscureText: !_showNew,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
              hintText: s.minChars,
              suffixIcon: IconButton(
                icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showNew = !_showNew),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(s.confirmPassword, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmPwdCtrl,
            obscureText: !_showConfirm,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
              hintText: s.repeatPassword,
              suffixIcon: IconButton(
                icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showConfirm = !_showConfirm),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          if (_success != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_success!, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
            ),
          FilledButton(
            onPressed: _busy ? null : _changePassword,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.save),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            onPressed: _confirmDeleteAccount,
            child: Text(s.deleteAccount),
          ),
        ],
      ),
    );
  }
}
