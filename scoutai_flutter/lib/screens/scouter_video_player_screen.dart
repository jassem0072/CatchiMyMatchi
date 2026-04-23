import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/tracking_overlay.dart';

/// Simple video playback screen for scouters viewing a player's video.
/// No analyse button — view-only.
class ScouterVideoPlayerScreen extends StatefulWidget {
  const ScouterVideoPlayerScreen({super.key});

  @override
  State<ScouterVideoPlayerScreen> createState() =>
      _ScouterVideoPlayerScreenState();
}

class _ScouterVideoPlayerScreenState extends State<ScouterVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;
  String _title = 'Video';
  String? _videoId;
  String? _ownerId; // player who owns the video — used as playerId for montage

  // ── Tracking overlay state ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _positions = [];
  String _playerName = '';
  bool _showTracking = true;
  bool _loadingPositions = false;
  double? _selectionT;
  double? _selectionNcx;
  double? _selectionNcy;



  // ── Montage state ──────────────────────────────────────────────────────────
  bool _checkingMontage = false;
  bool? _montageExists;
  bool _generatingMontage = false;
  String? _montageMsg;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videoId != null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _videoId = (args['videoId'] ?? args['_id'] ?? args['id'])?.toString();
      _title = (args['originalName'] ?? args['filename'] ?? 'Video').toString();
      _ownerId = (args['ownerId'] ?? args['playerId'])?.toString();

      // ── Parse tracking positions from lastAnalysis (args are a quick start) ─
      _loadPositionsFromArgs(args);
    } else if (args is String) {
      _videoId = args;
    }

    if (_videoId != null) {
      _initVideo();
      _fetchPositionsFromApi();   // always re-fetch full data from backend
      _fetchPlayerName();
    } else {
      setState(() => _error = 'No video ID provided.');
    }
  }

  // ── Parse positions that come bundled in the route args ──────────────────
  void _loadPositionsFromArgs(Map<String, dynamic> args) {
    final lastName = (args['uploaderName'] ?? args['displayName'] ?? args['playerName'] ?? '').toString();
    if (lastName.isNotEmpty) _playerName = lastName.toUpperCase();

    List<Map<String, dynamic>> found = [];

    final lastAnalysis = args['lastAnalysis'];
    if (lastAnalysis is Map<String, dynamic>) {
      final rawPos = lastAnalysis['positions'];
      if (rawPos is List) {
        found = rawPos.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
      }
    }
    if (found.isEmpty) {
      final rawPos = args['positions'];
      if (rawPos is List) {
        found = rawPos.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
      }
    }
    if (found.isNotEmpty && mounted) setState(() => _positions = found);
  }

  double? _numOrNull(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ── Fetch FULL positions from backend (works for both players & scouters) ─
  Future<void> _fetchPositionsFromApi() async {
    if (_videoId == null) return;
    setState(() => _loadingPositions = true);
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;

      // Dedicated endpoint — no ownership check, accessible to scouters too
      final uri = Uri.parse('${ApiConfig.baseUrl}/videos/$_videoId/positions');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (res.statusCode >= 400) return; // silently fallback to args data

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return;

      // Use player name from API if we don't have one yet
      final apiName = (data['playerName'] ?? '').toString();
      final selT = _numOrNull(data['selectionT']);
      final selNcx = _numOrNull(data['selectionNcx']);
      final selNcy = _numOrNull(data['selectionNcy']);

      final rawPos = data['positions'];
      List<Map<String, dynamic>> found = _positions;
      if (rawPos is List && rawPos.isNotEmpty) {
        found = rawPos
            .whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .toList();

        // Sort by time (backend already sorts, but ensure correctness)
        found.sort((a, b) {
          final ta = (a['t'] as num?)?.toDouble() ?? 0.0;
          final tb = (b['t'] as num?)?.toDouble() ?? 0.0;
          return ta.compareTo(tb);
        });
      }

      if (mounted) {
        setState(() {
          _positions = found;
          _selectionT = selT;
          _selectionNcx = selNcx;
          _selectionNcy = selNcy;
          if (apiName.isNotEmpty) {
            _playerName = apiName.toUpperCase();
          }
        });
      }
    } catch (_) {
      // silently ignore — overlay uses args fallback
    } finally {
      if (mounted) setState(() => _loadingPositions = false);
    }
  }

  // ── Fetch logged-in player display name for the label ─────────────────────
  Future<void> _fetchPlayerName() async {
    if (_playerName.isNotEmpty && !_playerName.contains('.')) return; // already set
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted || res.statusCode >= 400) return;
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        final name = (data['displayName'] ?? data['email'] ?? '').toString();
        final at = name.indexOf('@');
        final display = at > 0 ? name.substring(0, at) : name;
        if (display.isNotEmpty && mounted) {
          setState(() => _playerName = display.toUpperCase());
        }
      }
    } catch (_) {}
  }

  Future<void> _initVideo() async {
    final url = '${ApiConfig.baseUrl}/videos/$_videoId/stream';
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load video: $e');
    }

  }

  // ── Montage methods ────────────────────────────────────────────────────────

  /// Calls the AI to detect whether the video CONTENT is a montage/highlight reel.
  /// Result is NEVER persisted — it is a pure real-time content check.
  Future<void> _checkMontageStatus() async {
    if (_videoId == null) return;
    setState(() {
      _checkingMontage = true;
      _montageMsg = null;
      _montageExists = null;
    });
    try {
      final token = await AuthStorage.loadToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}/videos/$_videoId/detect');
      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(minutes: 3));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final isMontage = body['isMontage'] as bool? ?? false;
        final confidence = ((body['confidence'] as num?)?.toDouble() ?? 0.0) * 100;
        final cutsPm = (body['cutsPerMinute'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _montageExists = isMontage;
          _montageMsg = isMontage
              ? '❌  Already montage/highlight video '
                '(${confidence.round()}% confidence, ${cutsPm.toStringAsFixed(1)} cuts/min).'
              : '✅  Raw match footage — this video is NOT a montage. '
                'You can generate a player highlight reel below.';
        });
      } else {
        final body = _safeJson(res.body);
        final msg = body?['message']?.toString() ?? '';
        setState(() {
          _montageExists = false;
          _montageMsg = '❌  ${msg.isNotEmpty ? msg : 'Detection failed (${res.statusCode}).'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _montageExists = false;
        _montageMsg = '❌  Error: $e';
      });
    } finally {
      if (mounted) setState(() => _checkingMontage = false);
    }
  }

  Future<void> _generateMontage() async {
    if (_videoId == null) return;
    setState(() {
      _generatingMontage = true;
      _montageMsg = 'Generating your highlight reel…';
    });
    try {
      final token = await AuthStorage.loadToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}/videos/$_videoId/montage');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          if (_ownerId != null) 'playerId': _ownerId,
          'forceRegenerate': false,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _montageExists = true;
          _montageMsg = '✅  Montage generated successfully! Tap Watch Montage.';
        });
      } else {
        final body = _safeJson(res.body);
        final msg = body?['message']?.toString() ?? '';
        setState(() {
          _montageMsg = '❌  ${msg.isNotEmpty ? msg : 'Generation failed (${res.statusCode}).'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _montageMsg = '❌  Error: $e');
    } finally {
      if (mounted) setState(() => _generatingMontage = false);
    }
  }

  void _watchMontage() {
    if (_videoId == null) return;
    Navigator.of(context).pushNamed(
      AppRoutes.montage,
      arguments: {
        'videoId': _videoId,
        'title': _title,
        if (_ownerId != null) 'playerId': _ownerId,
      },
    );
  }

  Map<String, dynamic>? _safeJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Cast sheet ─────────────────────────────────────────────────────────────

  Future<void> _startCast() async {
    if (_videoId == null) return;
    final streamUrl = '${ApiConfig.baseUrl}/videos/$_videoId/stream';
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CastSheet(streamUrl: streamUrl, title: _title),
    );
  }

  Future<void> _shareVideoLink() async {
    if (_videoId == null) return;
    final streamUrl = '${ApiConfig.baseUrl}/videos/$_videoId/stream';
    await Share.share(streamUrl, subject: _title);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: 'Generate Highlight Reel',
            onPressed: _videoId != null ? _watchMontage : null,
            icon: const Icon(Icons.movie_creation_outlined, size: 22),
          ),
          IconButton(
            tooltip: 'Cast to TV',
            onPressed: _videoId != null ? _startCast : null,
            icon: const Icon(Icons.cast, size: 22),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: _videoId != null ? _shareVideoLink : null,
            icon: const Icon(Icons.share_outlined, size: 22),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            )
          : !_initialized
              ? const Center(child: CircularProgressIndicator())
              : _buildPlayer(),
    );
  }

  Widget _buildPlayer() {
    final c = _controller!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        // ── Video ───────────────────────────────────────────────────────────
        AspectRatio(
          aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),

              // ── Live tracking overlay (2-second flash at selection moment) ─
              if (_positions.isNotEmpty || _selectionT != null)
                TrackingOverlay(
                  controller: c,
                  positions: _positions,
                  playerName: _playerName,
                  selectionT: _selectionT,
                  selectionNcx: _selectionNcx,
                  selectionNcy: _selectionNcy,
                ),

              // ── Play/pause tap target ────────────────────────────────────
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, val, __) => GestureDetector(
                  onTap: () => val.isPlaying ? c.pause() : c.play(),
                  child: AnimatedOpacity(
                    opacity: val.isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Seek bar ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, val, __) {
              final pos = val.position;
              final dur = val.duration;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: dur.inMilliseconds > 0
                          ? (pos.inMilliseconds / dur.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0,
                      onChanged: (v) => c.seekTo(Duration(
                          milliseconds: (v * dur.inMilliseconds).round())),
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.border,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos),
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                        Text(_fmt(dur),
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),

        // ── Controls ────────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () =>
                  c.seekTo(c.value.position - const Duration(seconds: 10)),
              icon: const Icon(Icons.replay_10,
                  color: AppColors.textMuted, size: 28),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, val, __) => GestureDetector(
                onTap: () => val.isPlaying ? c.pause() : c.play(),
                child: Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    val.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () =>
                  c.seekTo(c.value.position + const Duration(seconds: 10)),
              icon: const Icon(Icons.forward_10,
                  color: AppColors.textMuted, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Montage Card ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _MontageCard(
            checkingMontage: _checkingMontage,
            generatingMontage: _generatingMontage,
            montageExists: _montageExists,
            montageMsg: _montageMsg,
            onCheckStatus: _checkMontageStatus,
            onGenerate: _generateMontage,
            onWatch: _watchMontage,
          ),
        ),
        const SizedBox(height: 12),

        // ── Cast & Share Card ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tv_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tap Cast to send to your TV',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _videoId != null ? _startCast : null,
                  icon: const Icon(Icons.cast,
                      color: AppColors.primary, size: 22),
                  tooltip: 'Cast to TV',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _videoId != null ? _shareVideoLink : null,
                  icon: const Icon(Icons.share_outlined,
                      color: AppColors.primary, size: 22),
                  tooltip: 'Share',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}



// ── Montage Card Widget ───────────────────────────────────────────────────────

class _MontageCard extends StatelessWidget {
  const _MontageCard({
    required this.checkingMontage,
    required this.generatingMontage,
    required this.montageExists,
    required this.montageMsg,
    required this.onCheckStatus,
    required this.onGenerate,
    required this.onWatch,
  });

  final bool checkingMontage;
  final bool generatingMontage;
  final bool? montageExists;
  final String? montageMsg;
  final VoidCallback onCheckStatus;
  final VoidCallback onGenerate;
  final VoidCallback onWatch;

  // ── helpers ────────────────────────────────────────────────────────────────

  Color _msgColor() {
    if (montageExists == true) return AppColors.danger;
    if (montageExists == false) return AppColors.success;
    if (montageMsg != null && montageMsg!.startsWith('❌')) {
      return const Color(0xFFEF4444); // danger red
    }
    return const Color(0xFFF59E0B); // warning amber — clearly visible on dark bg
  }

  @override
  Widget build(BuildContext context) {
    final busy = checkingMontage || generatingMontage;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.movie_creation_outlined,
                    color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video Type Check',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Is this video a highlight reel or raw footage?',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Progress bar while busy ─────────────────────────────────────────
          if (busy) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              checkingMontage ? 'Checking video status…' : 'Generating montage, please wait…',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],

          // ── Status result banner ────────────────────────────────────────────
          if (montageMsg != null && !busy) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _msgColor().withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _msgColor().withValues(alpha: 0.35)),
              ),
              child: Text(
                montageMsg!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _msgColor(),
                  height: 1.4,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Action buttons ─────────────────────────────────────────────────
          Row(
            children: [
              // Check Status — always visible
              OutlinedButton.icon(
                onPressed: busy ? null : onCheckStatus,
                icon: const Icon(Icons.fact_check_outlined, size: 15),
                label: const Text('Check Video Type', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),

              const SizedBox(width: 10),

              // Generate / Watch — depends on status
              if (montageExists == null)
                // Not yet checked: show a muted hint
                const Expanded(
                  child: Text(
                    'Tap "Check Video Type" to analyse the video content.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                )
              else if (montageExists == false)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onGenerate,
                    icon: const Icon(Icons.movie_creation_outlined, size: 16),
                    label: const Text('Generate Highlight (view now)',
                        style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                )
              else if (montageExists == true)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onWatch,
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Already Montage (Watch)',
                        style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Cast Bottom Sheet ─────────────────────────────────────────────────────────

class _CastSheet extends StatefulWidget {
  const _CastSheet({required this.streamUrl, required this.title});

  final String streamUrl;
  final String title;

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  bool _scanning = false;
  bool _permissionDenied = false;
  bool _isWeb = false;
  final List<Map<String, String>> _devices = [];

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    // Only stop BT scan on non-web platforms
    if (!kIsWeb) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  Future<void> _startScan() async {
    // Bluetooth / permission_handler are NOT supported on web
    if (kIsWeb) {
      if (mounted) setState(() { _scanning = false; _isWeb = true; });
      return;
    }

    setState(() {
      _scanning = true;
      _permissionDenied = false;
      _isWeb = false;
      _devices.clear();
    });

    try {
      final btScan = await Permission.bluetoothScan.request();
      final btConnect = await Permission.bluetoothConnect.request();
      if (btScan.isDenied || btConnect.isDenied) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _permissionDenied = true;
          });
        }
        return;
      }

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName.trim();
          if (name.isEmpty) continue;
          final id = r.device.remoteId.str;
          if (mounted && !_devices.any((d) => d['id'] == id)) {
            setState(() => _devices.add({'name': name, 'id': id}));
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      await Future.delayed(const Duration(seconds: 5));
      await sub.cancel();
    } catch (_) {
      // BT not available on this device/platform
    }

    if (mounted) setState(() => _scanning = false);
  }

  Widget _buildDeviceSection(BuildContext context) {
    // ── Web: BT not supported — show browser cast instructions ──────────────
    if (_isWeb) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cast_connected, color: AppColors.primary, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cast from Browser',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                        SizedBox(height: 4),
                        Text(
                          '1. Open the video link in Chrome\n'
                          '2. Tap ⋮ Menu → Cast\n'
                          '3. Select your TV / Chromecast',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Bluetooth scanning is only available on the Android / iOS app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (_scanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'Scanning for Bluetooth devices…',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_permissionDenied) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled,
                color: AppColors.textMuted, size: 36),
            const SizedBox(height: 10),
            const Text(
              'Bluetooth permission denied.\n'
              'Grant access in Settings to scan for devices.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Open Settings'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppColors.textMuted, size: 36),
            const SizedBox(height: 10),
            const Text(
              'No nearby Bluetooth devices found.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Rescan'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._devices.map(
          (d) => _DeviceTile(
            device: d,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'To cast, open ${widget.streamUrl} in your device\'s browser',
                  ),
                  duration: const Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Rescan', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2333) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cast_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cast to TV',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Devices on your network',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Divider(
            height: 1,
            color: AppColors.border.withValues(alpha: 0.5),
            indent: 24,
            endIndent: 24,
          ),
          const SizedBox(height: 8),

          // ── Device section ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDeviceSection(context),
          ),
          const SizedBox(height: 8),

          Divider(
            height: 1,
            color: AppColors.border.withValues(alpha: 0.5),
            indent: 24,
            endIndent: 24,
          ),
          const SizedBox(height: 16),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await launchUrl(
                        Uri.parse(widget.streamUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.open_in_browser, size: 17),
                    label: const Text(
                      'Open in Browser',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await launchUrl(
                        Uri.parse(
                            'https://support.google.com/chromecast'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.screen_share, size: 17),
                    label: const Text(
                      'Mirror Screen',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: widget.streamUrl));
                      if (context.mounted) Navigator.pop(context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to clipboard'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text(
                      'Copy Link',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Share button ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await Share.share(widget.streamUrl, subject: widget.title);
              },
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Share Video Link'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Bottom safe area
          const SizedBox(height: 10),
          SafeArea(
            top: false,
            child: const SizedBox(height: 4),
          ),
        ],
      ),
    );
  }
}

// ── Device Tile ───────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final Map<String, String> device;
  final VoidCallback onTap;

  static bool _isTvLike(String name) {
    final lower = name.toLowerCase();
    return lower.contains('tv') ||
        lower.contains('cast') ||
        lower.contains('chromecast') ||
        lower.contains('display') ||
        lower.contains('screen');
  }

  @override
  Widget build(BuildContext context) {
    final name = device['name'] ?? 'Unknown';
    final id = device['id'] ?? '';
    final shortId = id.length > 8 ? id.substring(id.length - 8) : id;
    final isTv = _isTvLike(name);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.7)),
              ),
              child: Icon(
                isTv ? Icons.tv_rounded : Icons.bluetooth,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    shortId,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Available',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
