import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;
  String _title = 'Video';
  String? _videoId;
  Map<String, dynamic>? _videoData;
  Map<String, dynamic>? _analysis;
  bool _isTagged = false;
  String _uploaderName = '';
  String _visibility = 'public';
  bool _togglingVisibility = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videoId != null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _videoId = (args['videoId'] ?? args['_id'] ?? args['id'])?.toString();
      _title = (args['originalName'] ?? args['filename'] ?? 'Video').toString();
      _videoData = args;
      _isTagged = args['isTagged'] == true;
      _uploaderName = (args['uploaderName'] ?? '').toString();
      _visibility = (args['visibility'] ?? 'public').toString();
      // For tagged videos, lastAnalysis is already correct from /me/videos
      _analysis = args['lastAnalysis'] is Map<String, dynamic>
          ? args['lastAnalysis'] as Map<String, dynamic>
          : null;
    } else if (args is String) {
      _videoId = args;
    }

    if (_videoId != null) {
      _initVideo();
      if (_videoData == null) _loadVideoDetails();
    } else {
      setState(() => _error = 'No video ID provided.');
    }
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

  Future<void> _loadVideoDetails() async {
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      // Use /me/videos/:id which returns correct analysis per user
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/me/videos/$_videoId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _videoData = data;
          _title = (data['originalName'] ?? data['filename'] ?? 'Video').toString();
          _isTagged = data['isTagged'] == true;
          _uploaderName = (data['uploaderName'] ?? '').toString();
          _visibility = (data['visibility'] ?? 'public').toString();
          // lastAnalysis is already correct per user from the backend
          _analysis = data['lastAnalysis'] is Map<String, dynamic>
              ? data['lastAnalysis'] as Map<String, dynamic>
              : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _startCast() async {
    if (_videoId == null) return;
    final streamUrl = '${ApiConfig.baseUrl}/videos/$_videoId/stream';
    await Clipboard.setData(ClipboardData(text: streamUrl));
    if (!mounted) return;
    // Show bottom sheet with cast options
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cast to TV',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'Open the video link on your TV or cast-capable app.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(streamUrl,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: streamUrl));
                      if (mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Link'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await Share.share(streamUrl, subject: _title);
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVideoLink() async {
    if (_videoId == null) return;
    final streamUrl = '${ApiConfig.baseUrl}/videos/$_videoId/stream';
    await Share.share(streamUrl, subject: _title);
  }

  Future<void> _toggleVisibility() async {
    if (_videoId == null || _togglingVisibility) return;
    setState(() => _togglingVisibility = true);
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      final newVis = _visibility == 'private' ? 'public' : 'private';
      final res = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/me/videos/$_videoId/visibility'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'visibility': newVis}),
      );
      if (res.statusCode < 400 && mounted) {
        setState(() => _visibility = newVis);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video is now ${newVis == 'public' ? 'public' : 'private'}'),
            backgroundColor: newVis == 'public' ? AppColors.success : AppColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _togglingVisibility = false);
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

  double _dbl(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  int _intVal(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_title, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        actions: [
          if (_isTagged)
            IconButton(
              tooltip: _visibility == 'private' ? 'Make Public' : 'Make Private',
              onPressed: _togglingVisibility ? null : _toggleVisibility,
              icon: Icon(
                _visibility == 'private' ? Icons.lock_outline : Icons.public,
                color: _visibility == 'private' ? AppColors.warning : AppColors.success,
                size: 22,
              ),
            ),
          IconButton(
            tooltip: 'Generate Highlight Reel',
            onPressed: _videoId != null
                ? () => Navigator.of(context).pushNamed(
                      AppRoutes.montage,
                      arguments: {
                        'videoId': _videoId,
                        'title': _title,
                        if (_videoData?['ownerId'] != null) 'playerId': _videoData!['ownerId'],
                      },
                    )
                : null,
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
            icon: const Icon(Icons.share_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                ],
              ),
            )
          : !_initialized
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final c = _controller!;
    final metrics = _analysis?['metrics'] is Map
        ? Map<String, dynamic>.from(_analysis!['metrics'] as Map)
        : <String, dynamic>{};
    final summary = _analysis?['summary'] is Map
        ? Map<String, dynamic>.from(_analysis!['summary'] as Map)
        : <String, dynamic>{};
    final hasAnalysis = _analysis != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
      children: [
        // ── Video Player ──
        AspectRatio(
          aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              // Play/Pause overlay
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, val, __) {
                  return GestureDetector(
                    onTap: () => val.isPlaying ? c.pause() : c.play(),
                    child: AnimatedOpacity(
                      opacity: val.isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        height: 64, width: 64,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // ── Controls ──
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
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: dur.inMilliseconds > 0
                          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                          : 0,
                      onChanged: (v) {
                        c.seekTo(Duration(milliseconds: (v * dur.inMilliseconds).round()));
                      },
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.border,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        Text(_fmt(dur), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // Play controls row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () {
                final pos = c.value.position;
                c.seekTo(pos - const Duration(seconds: 10));
              },
              icon: const Icon(Icons.replay_10, color: AppColors.textMuted, size: 28),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, val, __) {
                return GestureDetector(
                  onTap: () => val.isPlaying ? c.pause() : c.play(),
                  child: Container(
                    height: 56, width: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      val.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 32,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                final pos = c.value.position;
                c.seekTo(pos + const Duration(seconds: 10));
              },
              icon: const Icon(Icons.forward_10, color: AppColors.textMuted, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Tagged video info banner ──
        if (_isTagged) ...[          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.sell, size: 16, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Tagged by $_uploaderName',
                  style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w700, fontSize: 13),
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_visibility == 'private' ? AppColors.warning : AppColors.success).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _visibility == 'private' ? 'Private' : 'Public',
                    style: TextStyle(
                      color: _visibility == 'private' ? AppColors.warning : AppColors.success,
                      fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ),
        ],

        // ── Analyze button (if no analysis) ──
        if (!hasAnalysis)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: FilledButton.icon(
              onPressed: () {
                // Navigate to identify player so the tagged player can select themselves
                Navigator.of(context).pushNamed(
                  AppRoutes.identifyPlayer,
                  arguments: _videoId,
                );
              },
              icon: const Icon(Icons.analytics_outlined),
              label: Text(_isTagged ? 'Analyze Yourself' : 'Analyze Video'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),

        // ── Metrics (if analysis exists) ──
        if (hasAnalysis) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Text('LIVE METRICS',
              style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(child: _MetricCard(
                  label: 'Max Speed',
                  value: '${_dbl(metrics['maxSpeedKmh'] ?? summary['max_speed_kmh']).toStringAsFixed(1)} km/h',
                  accent: AppColors.success,
                )),
                const SizedBox(width: 10),
                Expanded(child: _MetricCard(
                  label: 'Distance',
                  value: '${(_dbl(metrics['distanceMeters'] ?? summary['total_distance_m']) / 1000).toStringAsFixed(2)} km',
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(child: _MetricCard(
                  label: 'Sprints',
                  value: '${_intVal(metrics['sprints'] ?? summary['sprint_count'])}',
                  accent: AppColors.warning,
                )),
                const SizedBox(width: 10),
                Expanded(child: _MetricCard(
                  label: 'Avg Speed',
                  value: '${_dbl(metrics['avgSpeedKmh'] ?? summary['avg_speed_kmh']).toStringAsFixed(1)} km/h',
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(child: _MetricCard(
                  label: 'Accel Peaks',
                  value: '${_intVal(metrics['accelPeaks'] ?? summary['accel_peaks'])}',
                  accent: AppColors.danger,
                )),
                const SizedBox(width: 10),
                Expanded(child: _MetricCard(
                  label: 'Duration',
                  value: '${_dbl(summary['duration_s'] ?? metrics['durationS']).toStringAsFixed(0)} s',
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── View Full Analysis ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppRoutes.details,
                  arguments: _videoData ?? {'lastAnalysis': _analysis},
                );
              },
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('View Full Analysis'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),

          // Re-analyze button
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppRoutes.identifyPlayer,
                  arguments: _videoId,
                );
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Re-analyze'),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.accent});
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(
            fontWeight: FontWeight.w900, fontSize: 18,
            color: accent ?? AppColors.tx(context),
          )),
        ],
      ),
    );
  }
}
