import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class IdentifyPlayerScreen extends StatefulWidget {
  const IdentifyPlayerScreen({super.key});

  @override
  State<IdentifyPlayerScreen> createState() => _IdentifyPlayerScreenState();
}

class _IdentifyPlayerScreenState extends State<IdentifyPlayerScreen> {
  VideoPlayerController? _controller;
  String? _videoId;
  bool _initialized = false;
  String? _error;

  // Selection state — normalised 0..1 relative to video display area
  Rect? _selectionRect;
  bool _playerLocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videoId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      _videoId = args is String ? args : null;
      if (_videoId != null) {
        _initVideo();
      } else {
        setState(() => _error = 'No video ID provided.');
      }
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_initialized) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  void _seekRelative(int seconds) {
    final c = _controller;
    if (c == null || !_initialized) return;
    final pos = c.value.position + Duration(seconds: seconds);
    c.seekTo(pos < Duration.zero ? Duration.zero : pos);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onTapVideo(TapDownDetails details, BoxConstraints constraints) {
    final c = _controller;
    if (c == null || !_initialized) return;

    if (c.value.isPlaying) c.pause();

    final nx = details.localPosition.dx / constraints.maxWidth;
    final ny = details.localPosition.dy / constraints.maxHeight;

    const boxW = 0.12;
    const boxH = 0.22;
    final left = (nx - boxW / 2).clamp(0.0, 1.0 - boxW);
    final top = (ny - boxH / 2).clamp(0.0, 1.0 - boxH);

    setState(() {
      _selectionRect = Rect.fromLTWH(left, top, boxW, boxH);
      _playerLocked = true;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionRect = null;
      _playerLocked = false;
    });
  }

  void _confirmSelection() {
    final c = _controller;
    final sel = _selectionRect;
    if (c == null || sel == null || _videoId == null) return;

    final videoW = c.value.size.width;
    final videoH = c.value.size.height;
    final t0 = c.value.position.inMilliseconds / 1000.0;

    final selection = <String, dynamic>{
      't0': t0,
      'x': (sel.left * videoW).round(),
      'y': (sel.top * videoH).round(),
      'w': (sel.width * videoW).round(),
      'h': (sel.height * videoH).round(),
    };

    Navigator.of(context).pushNamed(
      AppRoutes.progress,
      arguments: <String, dynamic>{
        'videoId': _videoId,
        'selection': selection,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(S.of(context).identifyPlayer),
        actions: [
          IconButton(
            onPressed: _playerLocked ? _clearSelection : null,
            icon: const Icon(Icons.refresh),
            tooltip: S.of(context).resetSelection,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
            )
          : !_initialized
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final c = _controller!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Text(
          S.of(context).scrubInstruction,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),

        // --- Video + overlay ---
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTapDown: (d) => _onTapVideo(d, constraints),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoPlayer(c),

                            // Selection rectangle overlay
                            if (_selectionRect != null)
                              Positioned(
                                left: _selectionRect!.left * constraints.maxWidth,
                                top: _selectionRect!.top * constraints.maxHeight,
                                width: _selectionRect!.width * constraints.maxWidth,
                                height: _selectionRect!.height * constraints.maxHeight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.primary, width: 2.5),
                                    borderRadius: BorderRadius.circular(8),
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                  ),
                                ),
                              ),

                            // Badge
                            if (_playerLocked)
                              Positioned(
                                left: 16,
                                top: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.55)),
                                  ),
                                  child: Text(
                                    S.of(context).playerLocked,
                                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 11),
                                  ),
                                ),
                              ),

                            if (!_playerLocked)
                              Positioned(
                                left: 16,
                                top: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    S.of(context).tapOnPlayer,
                                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 11),
                                  ),
                                ),
                              ),

                            // Resolution badge
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${c.value.size.width.toInt()}×${c.value.size.height.toInt()}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Playback controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundIcon(icon: Icons.replay_5, onTap: () => _seekRelative(-5)),
                  const SizedBox(width: 18),
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: c,
                        builder: (_, val, __) => Icon(
                          val.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  _RoundIcon(icon: Icons.forward_5, onTap: () => _seekRelative(5)),
                ],
              ),

              const SizedBox(height: 12),

              // Scrub slider
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, val, __) {
                  final total = val.duration.inMilliseconds.toDouble();
                  final current = val.position.inMilliseconds.toDouble();
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        ),
                        child: Slider(
                          value: total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0,
                          onChanged: (v) {
                            c.seekTo(Duration(milliseconds: (v * total).round()));
                          },
                          activeColor: AppColors.primary,
                          inactiveColor: AppColors.border,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(val.position), style: const TextStyle(color: AppColors.textMuted)),
                            Text(_fmt(val.duration), style: const TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Confirm button
        FilledButton(
          onPressed: _playerLocked ? _confirmSelection : null,
          child: Text(S.of(context).confirmAnalyze),
        ),
        const SizedBox(height: 8),
        if (!_playerLocked)
          Text(
            S.of(context).tapPlayerToEnable,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
          ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 46,
        width: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
