import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class AnalysisProgressScreen extends StatelessWidget {
  const AnalysisProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const progress = 0.65;

    return GradientScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('AI Analysis Progress'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Pill(label: 'Running', color: AppColors.primary, icon: Icons.sync),
            const SizedBox(height: 18),
            const Text(
              'Match ID #29381',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
            ),
            const SizedBox(height: 6),
            const Text(
              'Real Madrid vs. Barcelona',
              style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
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
                        painter: _RingPainter(progress),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 44),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'PROCESSED',
                            style: TextStyle(
                              color: AppColors.textMuted,
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
                  Row(
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
                        ),
                        child: const Icon(Icons.timer_outlined, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ESTIMATED TIME REMAINING',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'approx. 4 mins left',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _StepRow(done: true, label: 'Uploading and frame extraction'),
                  const _StepRow(done: true, label: 'Player identification'),
                  const _StepRow(running: true, label: 'Detecting player movements...'),
                  const _StepRow(label: 'Generating heatmaps'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () {},
              child: const Text('Cancel Analysis', style: TextStyle(color: AppColors.textMuted)),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.details),
              child: const Text('View Sample Result'),
            ),
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
                color: done ? AppColors.text : AppColors.textMuted,
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
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - 10;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeCap = StrokeCap.round;

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = AppColors.primary
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bg);

    final start = -math.pi / 2;
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
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress;
}
