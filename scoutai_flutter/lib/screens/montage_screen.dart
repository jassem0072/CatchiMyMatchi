import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Screen for generating and viewing a highlight reel montage.
/// Accepts arguments: { 'videoId': String, 'title': String?, 'playerId': String? }
class MontageScreen extends StatefulWidget {
  const MontageScreen({super.key});

  @override
  State<MontageScreen> createState() => _MontageScreenState();
}

class _MontageScreenState extends State<MontageScreen> {
  String? _videoId;
  String? _playerId;
  String _title = 'Highlight Reel';

  bool _generating = false;
  bool _generated = false;
  String? _error;
  int _clipCount = 0;
  double _duration = 0;

  VideoPlayerController? _controller;
  bool _videoInitialized = false;
  bool _videoError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videoId != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _videoId = (args['videoId'] ?? args['_id'] ?? args['id'])?.toString();
      _title = (args['title'] ?? args['originalName'] ?? 'Highlight Reel').toString();
      // playerId: the analyzed player's ID — used to pick the right playerAnalyses entry
      _playerId = (args['playerId'] ?? args['ownerId'])?.toString();
    } else if (args is String) {
      _videoId = args;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_videoId == null) return;
    setState(() {
      _generating = true;
      _error = null;
      _generated = false;
      _videoInitialized = false;
      _videoError = false;
    });

    try {
      final token = await AuthStorage.loadToken();
      final url = '${ApiConfig.baseUrl}/videos/$_videoId/montage';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          if (_playerId != null) 'playerId': _playerId,
        }),
      ).timeout(const Duration(minutes: 6));

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _clipCount = (data['clipCount'] as num?)?.toInt() ?? 0;
        _duration = (data['duration'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          _generating = false;
          _generated = true;
        });
        _initVideo();
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final msg = body?['message'] ?? 'Generation failed (${response.statusCode})';
        setState(() {
          _generating = false;
          _error = msg.toString();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _initVideo() async {
    final url = '${ApiConfig.baseUrl}/videos/$_videoId/montage/stream';
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _videoInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _videoError = true);
    }
  }

  Future<void> _shareLink() async {
    if (_videoId == null) return;
    final url = '${ApiConfig.baseUrl}/videos/$_videoId/montage/stream';
    await Share.share(url, subject: '$_title — Highlight Reel');
  }

  Future<void> _copyLink() async {
    if (_videoId == null) return;
    final url = '${ApiConfig.baseUrl}/videos/$_videoId/montage/stream';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Montage link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _fmtDuration(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Highlight Reel',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        actions: [
          if (_generated) ...[
            IconButton(
              tooltip: 'Copy link',
              onPressed: _copyLink,
              icon: const Icon(Icons.copy, size: 20),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: _shareLink,
              icon: const Icon(Icons.share_outlined, size: 22),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          // ── Header Card ──
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.movie_creation_outlined,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Highlight Reel',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _title,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Automatically detects and clips your best sprint moments and acceleration peaks from the video analysis.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Error ──
          if (_error != null) ...[
            GlassCard(
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Generated Stats ──
          if (_generated && _clipCount > 0) ...[
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.content_cut,
                    label: 'Clips',
                    value: '$_clipCount',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: _fmtDuration(_duration),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Video Player ──
          if (_generated) ...[
            if (_videoError)
              GlassCard(
                child: Column(
                  children: [
                    const Icon(Icons.videocam_off,
                        color: AppColors.textMuted, size: 40),
                    const SizedBox(height: 10),
                    const Text(
                      'Could not load video preview.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _shareLink,
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Share Link'),
                    ),
                  ],
                ),
              )
            else if (!_videoInitialized)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              _buildVideoPlayer(),
            const SizedBox(height: 16),
          ],

          // ── Generate Button ──
          if (!_generated || _error != null) ...[
            if (_generating)
              GlassCard(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                      'Generating highlights…',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This may take a moment depending on video length.',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _videoId != null ? _generate : null,
                  icon: const Icon(Icons.auto_awesome, size: 20),
                  label: Text(
                    _error != null ? 'Retry Generation' : 'Generate Highlight Reel',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
          ],

          // ── Regenerate button (when already generated) ──
          if (_generated && _error == null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _generating ? null : _generate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final c = _controller!;
    return Column(
      children: [
        // Video
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (_, val, __) => GestureDetector(
                    onTap: () => val.isPlaying ? c.pause() : c.play(),
                    child: AnimatedOpacity(
                      opacity: val.isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        height: 60,
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 36),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Seek bar
        ValueListenableBuilder<VideoPlayerValue>(
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

        // Controls
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
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Icon(
                    val.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 30,
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
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
