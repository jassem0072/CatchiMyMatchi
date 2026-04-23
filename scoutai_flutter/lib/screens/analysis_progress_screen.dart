import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/scoutai_app.dart';
import '../features/analysis/models/analysis_run_request.dart';
import '../features/analysis/models/analysis_selection_dto.dart';
import '../features/analysis/models/analysis_selection_mapper.dart';
import '../features/analysis/providers/analysis_run_providers.dart';
import '../features/analysis/models/analysis_run_result.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../services/translations.dart';
import '../widgets/common.dart';

/// Receives route arguments:
/// ```
/// { 'videoId': String, 'selection': { t0, x, y, w, h } }
/// ```
/// Calls POST /videos/:id/analyze and shows progress, then navigates to details.
class AnalysisProgressScreen extends ConsumerStatefulWidget {
  const AnalysisProgressScreen({super.key});

  @override
  ConsumerState<AnalysisProgressScreen> createState() => _AnalysisProgressScreenState();
}

class _AnalysisProgressScreenState extends ConsumerState<AnalysisProgressScreen>
    with SingleTickerProviderStateMixin {
  bool _started = false;
  bool _done = false;
  String? _error;
  AnalysisRunResult? _result;

  // Animated progress ring
  late final AnimationController _ringCtrl;
  int _stepIndex = 0; // 0=uploading, 1=identification, 2=movements, 3=heatmaps

  final _steps = const [
    'Sending video to AI engine',
    'Player identification (YOLO)',
    'Tracking & movement detection',
    'Computing metrics & heatmap',
  ];

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _runAnalysis();
    }
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map<String, dynamic>) {
      setState(() => _error = 'Missing analysis parameters.');
      return;
    }

    final videoId = args['videoId'] as String?;
    final selection = args['selection'] as Map<String, dynamic>?;
    if (videoId == null || selection == null) {
      setState(() => _error = 'Invalid parameters (videoId or selection missing).');
      return;
    }

    final token = await AuthStorage.loadToken();
    if (token == null) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      return;
    }

    // Step progression simulation (since the API is synchronous / long-running)
    _advanceSteps();

    try {
      final selectionEntity = AnalysisSelectionMapper.toEntity(
        AnalysisSelectionDto.fromJson(selection),
      );

      final request = AnalysisRunRequest(
        videoId: videoId,
        selection: selectionEntity,
        samplingFps: 4,
      );

      final result = await ref.read(analysisRunServiceProvider).runAnalysis(request);
      if (!mounted) return;
      setState(() {
        _done = true;
        _result = result;
        _stepIndex = _steps.length; // all done
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error: $e');
    }
  }

  /// Advance step indicators while waiting for the API response
  void _advanceSteps() async {
    for (var i = 1; i < _steps.length; i++) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted || _done || _error != null) return;
      setState(() => _stepIndex = i);
    }
  }

  void _viewResult() {
    if (_result == null) return;
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.details,
      arguments: _result!.raw,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(S.of(context).aiAnalysis),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          children: [
            const SizedBox(height: 10),

            if (_error != null) ...[
              const Pill(label: 'Error', color: AppColors.danger, icon: Icons.error_outline),
              const SizedBox(height: 18),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(S.of(context).goBack),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (!_done) ...[
              Pill(label: S.of(context).analyzing, color: AppColors.primary, icon: Icons.sync),
              const SizedBox(height: 18),
              Text(
                S.of(context).aiProcessing,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(height: 6),
              Text(
                S.of(context).mayTakeFewMinutes,
                style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 26),
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: 220,
                    width: 220,
                    child: AnimatedBuilder(
                      animation: _ringCtrl,
                      builder: (_, __) {
                        final fakeProgress = (_stepIndex / _steps.length).clamp(0.0, 0.95);
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(220, 220),
                              painter: _RingPainter(fakeProgress, _ringCtrl.value),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${(fakeProgress * 100).round()}%',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 44),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'PROCESSING',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.4,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Step list
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _StepRow(
                        label: _steps[i],
                        done: i < _stepIndex,
                        running: i == _stepIndex,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
              ),
            ] else ...[
              Pill(label: S.of(context).complete, color: AppColors.success, icon: Icons.check_circle),
              const SizedBox(height: 18),
              Text(
                S.of(context).analysisComplete,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(height: 6),
              Text(
                S.of(context).aiFinished,
                style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 26),
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: 220,
                    width: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(220, 220),
                          painter: _RingPainter(1.0, 0),
                        ),
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 64, color: AppColors.success),
                            SizedBox(height: 6),
                            Text(
                              'DONE',
                              style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final step in _steps) _StepRow(label: step, done: true),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _viewResult,
                child: Text(S.of(context).viewResults),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, this.done = false, this.running = false});

  final String label;
  final bool done;
  final bool running;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    if (done) {
      icon = Icons.check_circle;
      color = AppColors.success;
    } else if (running) {
      icon = Icons.track_changes;
      color = AppColors.primary;
    } else {
      icon = Icons.radio_button_unchecked;
      color = AppColors.textMuted;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done ? AppColors.tx(context) : AppColors.txMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.rotation);

  final double progress;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    final radius = math.min(size.width, size.height) / 2 - 10;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeCap = StrokeCap.round;

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = progress >= 1.0 ? AppColors.success : AppColors.primary
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bg);

    final start = -math.pi / 2 + (progress < 1.0 ? rotation * 0.3 : 0);
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.rotation != rotation;
}
