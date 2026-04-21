import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Edit Profile screen — lets the user update display name, position, nation.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;
  String? _token;

  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _nationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _nationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode >= 400) throw Exception('Failed to load profile');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _token = token;
        _nameCtrl.text = (data['displayName'] ?? '').toString();
        _positionCtrl.text = (data['position'] ?? '').toString();
        _nationCtrl.text = (data['nation'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _save() async {
    final token = _token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      final body = jsonEncode({
        'displayName': _nameCtrl.text.trim(),
        'position': _positionCtrl.text.trim(),
        'nation': _nationCtrl.text.trim(),
      });
      final res = await http.patch(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }, body: body);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        throw Exception('Save failed (${res.statusCode})');
      }
      setState(() { _saving = false; _success = S.current.saved; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.editProfile),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Text(s.displayName, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline),
                    hintText: s.fullName,
                  ),
                ),
                const SizedBox(height: 18),
                Text(s.position, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _positionCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.sports_soccer_outlined),
                    hintText: 'ST, CM, GK...',
                  ),
                ),
                const SizedBox(height: 18),
                Text(s.nation, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nationCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.flag_outlined),
                    hintText: 'TN, FR, US...',
                  ),
                ),
                const SizedBox(height: 24),
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
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(s.save),
                ),
              ],
            ),
    );
  }
}
