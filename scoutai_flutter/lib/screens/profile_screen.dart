import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/jwt_utils.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  String? _token;
  Map<String, dynamic>? _me;
  Uint8List? _portraitBytes;
  bool _portraitLoading = false;
  bool _portraitUploading = false;
  bool _upgrading = false;
  Uint8List? _badgeBytes;
  bool _badgeLoading = false;
  bool _badgeUploading = false;
  DateTime? _countdownTarget;
  Duration _timeRemaining = Duration.zero;

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
    _startCountdown();
  }

  void _startCountdown() {
    Future.doWhile(() async {
      if (!mounted) return false;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      
      if (_countdownTarget != null) {
        final now = DateTime.now();
        final remaining = _countdownTarget!.difference(now);
        if (mounted) {
          setState(() {
            _timeRemaining = remaining.isNegative ? Duration.zero : remaining;
          });
        }
      }
      return true;
    });
  }

  @override
  void dispose() {
    super.dispose();
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
      
      // Set countdown target from subscription expiry
      DateTime? expiresAt;
      final expiresAtStr = me['subscriptionExpiresAt'] as String?;
      if (expiresAtStr != null) {
        try {
          expiresAt = DateTime.parse(expiresAtStr);
        } catch (_) {}
      }
      
      setState(() {
        _token = token;
        _me = me;
        _loading = false;
        _countdownTarget = expiresAt;
      });
      await _loadPortrait();
      await _loadBadge();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadBadge() async {
    final token = _token;
    if (token == null) return;
    setState(() => _badgeLoading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/badge?ts=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty || !ct.startsWith('image/')) {
        setState(() { _badgeBytes = null; _badgeLoading = false; });
        return;
      }
      setState(() { _badgeBytes = res.bodyBytes; _badgeLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _badgeBytes = null; _badgeLoading = false; });
    }
  }

  Future<void> _pickAndUploadBadge() async {
    final token = _token;
    if (token == null) return;
    setState(() { _error = null; _badgeUploading = true; });
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _badgeUploading = false);
        return;
      }
      final file = result.files.first;
      if (!_isSupportedPortraitFilename(file.name)) {
        setState(() { _badgeUploading = false; _error = S.current.unsupportedImage; });
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Failed to read image');

      setState(() => _badgeBytes = bytes);

      final uri = Uri.parse('${ApiConfig.baseUrl}/me/badge');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: file.name,
        contentType: _portraitMediaTypeForFilename(file.name),
      ));
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _badgeUploading = false; _error = 'Failed to upload badge (${res.statusCode})'; });
        return;
      }
      setState(() => _badgeUploading = false);
      await _loadBadge();
    } catch (e) {
      if (!mounted) return;
      setState(() { _badgeUploading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _verifyBadge() async {
    final token = _token;
    if (token == null) return;
    setState(() { _error = null; _badgeUploading = true; });
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/verify-badge');
      final res = await http.post(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _badgeUploading = false; _error = 'Verification failed (${res.statusCode})'; });
        return;
      }
      // Re-fetch profile
      final me = await AuthApi().me(token);
      if (!mounted) return;
      setState(() { _me = me; _badgeUploading = false; });
      if (me['role'] == 'scouter' && me['badgeVerified'] == true) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.scouterHome, (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _badgeUploading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _loadPortrait() async {
    final token = _token;
    if (token == null) {
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
    final token = _token;
    if (token == null) return;

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
          _error = S.current.unsupportedImage;
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

  Future<void> _handleUpgradeToScouter() async {
    setState(() {
      _upgrading = true;
      _error = null;
    });

    try {
      final token = _token;
      if (token == null) throw Exception('Not authenticated');

      final currentRole = _me?['role'] as String? ?? 'player';
      final currentTier = _me?['subscriptionTier'] as String?;
      final expiresAtStr = _me?['subscriptionExpiresAt'] as String?;
      final isExpired = expiresAtStr != null &&
          DateTime.tryParse(expiresAtStr)?.isBefore(DateTime.now()) == true;

      // Show in-app payment dialog
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _InAppPaymentDialog(
          token: token,
          currentTier: currentRole == 'scouter' ? currentTier : null,
          isExpired: isExpired,
        ),
      );

      if (result == null || !mounted) {
        // User cancelled
        setState(() => _upgrading = false);
        return;
      }

      // Payment succeeded — save new token
      final newToken = result['accessToken'] as String?;
      if (newToken != null && newToken.isNotEmpty) {
        await AuthStorage.saveToken(newToken);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).upgradedSuccess),
          backgroundColor: AppColors.primary,
        ),
      );

      if (currentRole == 'scouter') {
        // Already a scouter upgrading tier — reload profile in place
        await _load();
      } else {
        // Player becoming scouter — navigate to scouter home
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.scouterHome,
          (_) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _upgrading = false);
    }
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  Widget _buildAvatar() {
    final token = _token;
    final canShowPortrait = token != null;
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

  bool get _isUnverifiedScouter {
    final me = _me;
    if (me == null) return false;
    return me['role'] == 'scouter' && me['badgeVerified'] != true;
  }

  Widget _buildCountdownTimer() {
    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;
    final seconds = _timeRemaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surf2(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'TIME REMAINING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeUnit(days.toString().padLeft(2, '0'), 'DAYS'),
              _buildTimeUnit(hours.toString().padLeft(2, '0'), 'HOURS'),
              _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'MINUTES'),
              _buildTimeUnit(seconds.toString().padLeft(2, '0'), 'SECONDS'),
            ],
          ),
        ],
      ),
    );
  }

  /// Shows info about lower tiers that are paused while a higher tier is active.
  List<Widget> _buildPausedTierInfo(String activeTier, DateTime now) {
    final widgets = <Widget>[];
    if (activeTier == 'elite' || activeTier == 'premium') {
      // Show basic resumption info if basic is queued
      final basicStr = _me?['basicExpiresAt'] as String?;
      if (basicStr != null) {
        final basicExpiry = DateTime.tryParse(basicStr);
        if (basicExpiry != null && basicExpiry.isAfter(now)) {
          widgets.add(const SizedBox(height: 10));
          widgets.add(
            Row(
              children: [
                const Icon(Icons.star_outline, size: 13, color: Color(0xFFCD7F32)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Basic resumes on ${basicExpiry.day}/${basicExpiry.month}/${basicExpiry.year}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFCD7F32)),
                  ),
                ),
              ],
            ),
          );
        }
      }
      if (activeTier == 'elite') {
        // Show premium resumption info
        final premStr = _me?['premiumExpiresAt'] as String?;
        if (premStr != null) {
          final premExpiry = DateTime.tryParse(premStr);
          if (premExpiry != null && premExpiry.isAfter(now)) {
            widgets.add(const SizedBox(height: 6));
            widgets.add(
              Row(
                children: [
                  const Icon(Icons.star_half, size: 13, color: Color(0xFFC0C0C0)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Premium resumes on ${premExpiry.day}/${premExpiry.month}/${premExpiry.year}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFC0C0C0)),
                    ),
                  ),
                ],
              ),
            );
          }
        }
      }
    }
    return widgets;
  }

  Widget _buildTimeUnit(String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF00d4ff)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionStatus() {
    final tier = _me?['subscriptionTier'] as String? ?? 'basic';
    final expiresAtStr = _me?['subscriptionExpiresAt'] as String?;
    final now = DateTime.now();
    DateTime? expiresAt;
    
    if (expiresAtStr != null) {
      try {
        expiresAt = DateTime.parse(expiresAtStr);
      } catch (_) {}
    }
    
    final isExpired = expiresAt != null && expiresAt.isBefore(now);
    final daysLeft = expiresAt != null ? expiresAt.difference(now).inDays : 0;
    
    final tierLabels = {'basic': 'Basic (€199)', 'premium': 'Premium (€299)', 'elite': 'Elite (€449)'};
    final tierColors = {'basic': const Color(0xFFCD7F32), 'premium': const Color(0xFFC0C0C0), 'elite': const Color(0xFFFFD700)};
    
    final canUpgrade = tier == 'basic' || tier == 'premium';
    final buttonLabel = isExpired ? 'Renew Subscription' : (canUpgrade ? 'Upgrade Tier' : 'Renew Subscription');
    
    return Column(
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: tierColors[tier],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tierLabels[tier] ?? 'Unknown',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                  const Spacer(),
                  if (isExpired)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: const Text('EXPIRED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.danger)),
                    )
                  else if (daysLeft <= 7)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Text('$daysLeft days left', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.orange)),
                    )
                  else
                    Text('$daysLeft days left', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              if (isExpired)
                const Text(
                  'Subscription expired. Renew to access player data.',
                  style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600),
                )
              else if (expiresAt != null) ...[
                Text(
                  'Expires on ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                _buildCountdownTimer(),
                // Show paused lower-tier info
                ..._buildPausedTierInfo(tier, now),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _upgrading ? null : _handleUpgradeToScouter,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF00d4ff)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.rocket_launch, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white),
                  ),
                ),
                if (_upgrading)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  const Icon(Icons.chevron_right, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      appBar: AppBar(
        leading: _isUnverifiedScouter
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  final role = _me != null && _me!['role'] is String
                      ? _me!['role'] as String
                      : (_token != null ? roleFromToken(_token!) : 'player');
                  final home = role == 'scouter'
                      ? AppRoutes.scouterHome
                      : AppRoutes.playerHome;
                  Navigator.of(context).pushNamedAndRemoveUntil(home, (_) => false);
                },
              ),
        title: Text(s.profile),
        actions: [
          IconButton(onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings), icon: const Icon(Icons.settings)),
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
          if (_isUnverifiedScouter) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Please upload your diploma or badge to verify your scouter account. You cannot browse players until verified.',
                      style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                child: Text(s.retry, style: const TextStyle(color: AppColors.primary)),
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
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bar_chart, color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(s.videosAnalyzed, style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
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
          Text(
            s.accountSettings,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          _SettingTile(icon: Icons.person_outline, label: s.editProfile, onTap: () => Navigator.of(context).pushNamed(AppRoutes.editProfile)),
          _SettingTile(icon: Icons.notifications_none, label: s.notifications, onTap: () => Navigator.of(context).pushNamed(AppRoutes.notifications)),
          _SettingTile(icon: Icons.lock_outline, label: s.securityPrivacy, onTap: () => Navigator.of(context).pushNamed(AppRoutes.securityPrivacy)),
          // ── Badge / Diploma Verification (scouters only) ──
          if (_me != null && _me!['role'] == 'scouter') ...[
            const SizedBox(height: 22),
            Text(
              'VERIFICATION',
              style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
            ),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 38,
                        width: 38,
                        decoration: BoxDecoration(
                          color: AppColors.surf2(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
                        ),
                        child: Icon(
                          _me!['badgeVerified'] == true ? Icons.verified : Icons.workspace_premium,
                          color: _me!['badgeVerified'] == true ? Colors.green : AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Badge / Diploma', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(
                              _me!['badgeVerified'] == true
                                  ? 'Your diploma is verified'
                                  : 'Upload your certificate for verification',
                              style: TextStyle(
                                color: _me!['badgeVerified'] == true ? Colors.green : AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_me!['badgeVerified'] == true)
                    // Already verified - show badge image if available
                    if (_badgeBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _badgeBytes!,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text('Verified', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                        ),
                      )
                  else if (_badgeLoading || _badgeUploading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20),
                      child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                  else if (_badgeBytes != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _badgeBytes!,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Icon(Icons.broken_image, size: 40, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _pickAndUploadBadge,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Change'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _verifyBadge,
                            icon: const Icon(Icons.verified_outlined, size: 18),
                            label: const Text('Verify'),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Center(
                      child: GestureDetector(
                        onTap: _pickAndUploadBadge,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
                            color: AppColors.primary.withValues(alpha: 0.05),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 32),
                              SizedBox(height: 8),
                              Text('Tap to upload', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                              SizedBox(height: 4),
                              Text('PNG, JPG, WebP supported', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            s.subscription,
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 12),
          if (_me != null && _me!['role'] == 'player')
            _UpgradeTile(
              onTap: _upgrading ? null : _handleUpgradeToScouter,
              busy: _upgrading,
            )
          else if (_me != null && _me!['role'] == 'scouter')
            _buildSubscriptionStatus(),
          _SettingTile(icon: Icons.receipt_long, label: s.billingHistory, onTap: () => Navigator.of(context).pushNamed(AppRoutes.billingHistory)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _logout,
            child: Text(s.logout),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: AppColors.surf2(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
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
              if (onTap != null) Icon(Icons.chevron_right, color: AppColors.txMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({required this.onTap, this.busy = false});

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D63FF), Color(0xFF35C4B3)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.rocket_launch, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  S.current.upgradeToScouter,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white),
                ),
              ),
              if (busy)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              else
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-app payment dialog with plan selection and card fields.
class _InAppPaymentDialog extends StatefulWidget {
  const _InAppPaymentDialog({required this.token, this.currentTier, this.isExpired = false});

  final String token;
  final String? currentTier;  // null = player (no tier yet)
  final bool isExpired;

  @override
  State<_InAppPaymentDialog> createState() => _InAppPaymentDialogState();
}

class _InAppPaymentDialogState extends State<_InAppPaymentDialog> {
  final _cardCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvcCtrl = TextEditingController();
  bool _processing = false;
  String? _error;

  // Subscription Tiers
  static final List<Map<String, dynamic>> _tiers = [
    {'key': 'basic', 'label': 'Basic', 'price': 199, 'features': 'View & follow players'},
    {'key': 'premium', 'label': 'Premium', 'price': 299, 'features': 'All player data access', 'popular': true},
    {'key': 'elite', 'label': 'Elite', 'price': 449, 'features': 'Full scouter features'},
  ];
  String _selectedTier = 'basic';

  // Available tiers: always show all 3. Pre-select the next upgrade above current tier.
  List<Map<String, dynamic>> get _availableTiers => _tiers;

  @override
  void initState() {
    super.initState();
    // Pre-select the next logical tier above the current one
    final current = widget.currentTier;
    if (current == null || widget.isExpired) {
      _selectedTier = 'basic';
    } else if (current == 'basic') {
      _selectedTier = 'premium';
    } else if (current == 'premium') {
      _selectedTier = 'elite';
    } else {
      _selectedTier = 'elite';
    }
  }

  int get _selectedPrice =>
      _tiers.firstWhere((t) => t['key'] == _selectedTier)['price'] as int;

  @override
  void dispose() {
    _cardCtrl.dispose();
    _expiryCtrl.dispose();
    _cvcCtrl.dispose();
    super.dispose();
  }

  bool get _formValid {
    final card = _cardCtrl.text.replaceAll(' ', '');
    final expiry = _expiryCtrl.text.trim();
    final cvc = _cvcCtrl.text.trim();
    return card.length >= 13 && expiry.length >= 4 && cvc.length >= 3;
  }

  List<Widget> _buildTierFeatures(String tier) {
    final features = <Widget>[];
    
    if (tier == 'basic') {
      features.addAll([
        _buildFeatureRow('View all players', true),
        _buildFeatureRow('Follow players', true),
        _buildFeatureRow('Private player data', false),
        _buildFeatureRow('Full analytics access', false),
        _buildFeatureRow('Advanced scouting tools', false),
      ]);
    } else if (tier == 'premium') {
      features.addAll([
        _buildFeatureRow('View all players', true),
        _buildFeatureRow('Follow players', true),
        _buildFeatureRow('Private player data', true),
        _buildFeatureRow('Full analytics access', true),
        _buildFeatureRow('Advanced scouting tools', false),
      ]);
    } else if (tier == 'elite') {
      features.addAll([
        _buildFeatureRow('View all players', true),
        _buildFeatureRow('Follow players', true),
        _buildFeatureRow('Private player data', true),
        _buildFeatureRow('Full analytics access', true),
        _buildFeatureRow('Advanced scouting tools', true),
      ]);
    }
    
    return features;
  }

  Widget _buildFeatureRow(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            color: enabled ? AppColors.primary : Colors.white.withValues(alpha: 0.2),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: enabled ? null : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formValid) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final card = _cardCtrl.text.replaceAll(' ', '');
      final expiryParts = _expiryCtrl.text.trim().split('/');
      final month = int.tryParse(expiryParts[0].trim()) ?? 0;
      var year = int.tryParse(expiryParts.length > 1 ? expiryParts[1].trim() : '') ?? 0;
      if (year < 100) year += 2000;
      final cvc = _cvcCtrl.text.trim();

      if (month < 1 || month > 12) throw Exception('Invalid expiry month');
      if (year < 2024) throw Exception('Invalid expiry year');

      final result = await AuthApi().payAndUpgrade(
        widget.token,
        cardNumber: card,
        expMonth: month,
        expYear: year,
        cvc: cvc,
        tier: _selectedTier,
      );

      if (!mounted) return;

      if (result['status'] == 'upgraded') {
        Navigator.of(context).pop(result);
      } else {
        setState(() {
          _processing = false;
          _error = S.current.paymentNotCompleted;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.rocket_launch, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(S.current.upgradeToScouter, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tier selector
            const Text('Choose Your Tier', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 10),
            Column(
              children: _availableTiers.map((tier) {
                final key = tier['key'] as String;
                final selected = _selectedTier == key;
                final popular = tier['popular'] as bool? ?? false;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTier = key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppColors.primary : Colors.white24,
                        width: selected ? 2 : 1,
                      ),
                      color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary : Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            key == 'basic' ? Icons.star_outline : key == 'premium' ? Icons.star_half : Icons.stars,
                            color: selected ? Colors.white : AppColors.textMuted,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      tier['label'] as String,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: selected ? AppColors.primary : null,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (popular) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('POPULAR', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tier['features'] as String,
                                style: TextStyle(fontSize: 11, color: selected ? AppColors.primary : AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '€${tier['price']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: selected ? AppColors.primary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // What's Included for selected tier
            const Text('What\'s Included', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            ..._buildTierFeatures(_selectedTier),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(S.current.videosWillBeRemoved, style: const TextStyle(fontSize: 13, color: Colors.orange))),
            ]),
            const SizedBox(height: 16),

            // Card number
            Text(S.current.cardNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _cardCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
                _CardNumberFormatter(),
              ],
              decoration: const InputDecoration(
                hintText: '4242 4242 4242 4242',
                prefixIcon: Icon(Icons.credit_card),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),

            // Expiry + CVV row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.current.expiry, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _expiryCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                          _ExpiryDateFormatter(),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'MM/YY',
                          prefixIcon: Icon(Icons.calendar_today, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CVV', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _cvcCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(
                          hintText: '···',
                          prefixIcon: Icon(Icons.lock_outline, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.of(context).pop(null),
          child: Text(S.current.cancel),
        ),
        FilledButton.icon(
          onPressed: (_processing || !_formValid) ? null : _submit,
          icon: _processing
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.payment, size: 18),
          label: Text(_processing ? S.current.processingPayment : 'Pay €$_selectedPrice'),
        ),
      ],
    );
  }
}

/// Display a single feature row with checkmarks for each tier
class _TierFeature extends StatelessWidget {
  const _TierFeature({required this.label, required this.basic, required this.premium, required this.elite});
  final String label;
  final bool basic;
  final bool premium;
  final bool elite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          _FeatureCheck(enabled: basic),
          _FeatureCheck(enabled: premium),
          _FeatureCheck(enabled: elite),
        ],
      ),
    );
  }
}

class _FeatureCheck extends StatelessWidget {
  const _FeatureCheck({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: enabled
          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 14)
          : Icon(Icons.cancel, color: Colors.white.withValues(alpha: 0.15), size: 14),
    );
  }
}

/// Formats card number with spaces every 4 digits.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Formats expiry as MM/YY.
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length && i < 4; i++) {
      if (i == 2) buf.write('/');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
