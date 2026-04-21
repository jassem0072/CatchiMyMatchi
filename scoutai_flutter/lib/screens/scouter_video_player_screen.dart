import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

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
  String? _ownerId;   // player who owns the video — used as playerId for montage

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videoId != null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _videoId = (args['videoId'] ?? args['_id'] ?? args['id'])?.toString();
      _title = (args['originalName'] ?? args['filename'] ?? 'Video').toString();
      _ownerId = (args['ownerId'] ?? args['playerId'])?.toString();
    } else if (args is String) {
      _videoId = args;
    }

    if (_videoId != null) {
      _initVideo();
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

  Future<void> _startCast() async {
    if (_videoId == null) return;
    final streamUrl = '${ApiConfig.baseUrl}/videos/$_videoId/stream';
    await Clipboard.setData(ClipboardData(text: streamUrl));
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
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

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'Generate Highlight Reel',
            onPressed: _videoId != null
                ? () => Navigator.of(context).pushNamed(
                      AppRoutes.montage,
                      arguments: {
                        'videoId': _videoId,
                        'title': _title,
                        if (_ownerId != null) 'playerId': _ownerId,
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
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
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
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
      children: [
        // ── Video ──
        AspectRatio(
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

        // ── Seek bar ──
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

        // ── Controls ──
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
        const SizedBox(height: 24),

        // ── Cast & Share info bar ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: GlassCard(
            child: Row(
              children: [
                const Icon(Icons.tv, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tap cast icon to watch on TV, or share the video link.',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _videoId != null ? _startCast : null,
                  icon: const Icon(Icons.cast, color: AppColors.primary, size: 22),
                  tooltip: 'Cast to TV',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
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

// ── Cast Bottom Sheet ─────────────────────────────────────────────────────────

class _CastSheet extends StatelessWidget {
  const _CastSheet({required this.streamUrl, required this.title});
  final String streamUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cast, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cast to TV',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    SizedBox(height: 2),
                    Text('Send this video to your TV or cast device',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // URL display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: AppColors.textMuted, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    streamUrl,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: streamUrl));
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await Share.share(streamUrl, subject: title);
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
