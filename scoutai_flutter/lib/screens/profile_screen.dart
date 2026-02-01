import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String? _error;
  String? _token;
  Map<String, dynamic>? _me;
  Uint8List? _portraitBytes;
  bool _portraitLoading = false;
  bool _portraitUploading = false;

  MediaType _portraitMediaTypeForFilename(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.webp')) return MediaType('image', 'webp');
    if (name.endsWith('.gif')) return MediaType('image', 'gif');
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return MediaType('image', 'jpeg');
    return MediaType('image', 'jpeg');
  }

  bool _isSupportedPortraitFilename(String filename) {
    final name = filename.toLowerCase();
    return name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.webp') || name.endsWith('.gif');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await AuthStorage.loadToken();
    if (!mounted) return;
    if (token == null) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      return;
    }
    try {
      final me = await AuthApi().me(token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _me = me;
        _loading = false;
      });
      await _loadPortrait();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadPortrait() async {
    final me = _me;
    final token = _token;
    final role = me != null && me['role'] is String ? me['role'] as String : null;
    if (token == null || role != 'player') {
      if (!mounted) return;
      setState(() {
        _portraitBytes = null;
        _portraitLoading = false;
      });
      return;
    }

    setState(() => _portraitLoading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/portrait?ts=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty || !contentType.startsWith('image/')) {
        setState(() {
          _portraitBytes = null;
          _portraitLoading = false;
        });
        return;
      }
      setState(() {
        _portraitBytes = res.bodyBytes;
        _portraitLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _portraitBytes = null;
        _portraitLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadPortrait() async {
    final me = _me;
    final token = _token;
    final role = me != null && me['role'] is String ? me['role'] as String : null;
    if (token == null || role != 'player') return;

    setState(() {
      _error = null;
      _portraitUploading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _portraitUploading = false);
        return;
      }
      final file = result.files.first;
      if (!_isSupportedPortraitFilename(file.name)) {
        setState(() {
          _portraitUploading = false;
          _error = 'Unsupported image type. Please use PNG/JPG/WebP/GIF.';
        });
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Failed to read image');

      final previous = _portraitBytes;
      setState(() => _portraitBytes = bytes);

      final uri = Uri.parse('${ApiConfig.baseUrl}/me/portrait');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
          contentType: _portraitMediaTypeForFilename(file.name),
        ),
      );
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        final body = res.body.trim();
        setState(() {
          _portraitUploading = false;
          _portraitBytes = previous;
          _error = body.isNotEmpty
              ? 'Failed to upload portrait (${res.statusCode}): ${body.length > 200 ? body.substring(0, 200) : body}'
              : 'Failed to upload portrait (${res.statusCode})';
        });
        return;
      }
      setState(() => _portraitUploading = false);
      await _loadPortrait();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _portraitUploading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  Widget _buildAvatar() {
    final me = _me;
    final token = _token;
    final role = me != null && me['role'] is String ? me['role'] as String : null;
    final canShowPortrait = token != null && role == 'player';
    final canUpload = canShowPortrait && !_portraitUploading;

    final portrait = _portraitBytes;

    return Container(
      height: 104,
      width: 104,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF35C4B3), Color(0xFF1D63FF)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: canShowPortrait && portrait != null
                    ? Image.memory(
                        portrait,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return const Center(child: Icon(Icons.person, size: 44, color: Colors.white));
                        },
                      )
                    : const Center(child: Icon(Icons.person, size: 44, color: Colors.white)),
              ),
              if (canShowPortrait && (_portraitLoading || _portraitUploading))
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: const Center(
                      child: SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              if (kIsWeb && canShowPortrait && portrait == null)
                const SizedBox.shrink(),
              if (canShowPortrait)
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canUpload ? _pickAndUploadPortrait : null,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayName() {
    final me = _me;
    if (me != null && me['displayName'] is String && (me['displayName'] as String).trim().isNotEmpty) {
      return (me['displayName'] as String).trim();
    }
    if (me != null && me['email'] is String) {
      final email = (me['email'] as String).trim();
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : email;
    }
    return 'Profile';
  }

  String _email() {
    final me = _me;
    if (me != null && me['email'] is String) return (me['email'] as String).trim();
    return '';
  }

  String _roleLabel() {
    final me = _me;
    if (me != null && me['role'] is String) return (me['role'] as String).toUpperCase();
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Profile'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          const SizedBox(height: 8),
          Center(child: _buildAvatar()),
          const SizedBox(height: 14),
          Text(
            _displayName(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
          ),
          const SizedBox(height: 6),
          Text(
            _email(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ] else if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _load,
                child: const Text('Retry', style: TextStyle(color: AppColors.primary)),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified, color: AppColors.primary, size: 18),
                          SizedBox(width: 8),
                          Text('Role', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _roleLabel(),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 22),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.bar_chart, color: AppColors.primary, size: 18),
                          SizedBox(width: 8),
                          Text('Videos\nAnalyzed', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text('0', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'ACCOUNT SETTINGS',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          _SettingTile(icon: Icons.person_outline, label: 'Edit Profile'),
          _SettingTile(icon: Icons.notifications_none, label: 'Notifications'),
          _SettingTile(icon: Icons.lock_outline, label: 'Security & Privacy'),
          const SizedBox(height: 18),
          const Text(
            'SUBSCRIPTION',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          _SettingTile(icon: Icons.credit_card, label: 'Manage Pro Plan'),
          _SettingTile(icon: Icons.receipt_long, label: 'Billing History'),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _logout,
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
