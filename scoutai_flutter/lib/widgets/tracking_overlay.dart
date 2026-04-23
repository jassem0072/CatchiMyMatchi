import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Shows a green downward triangle + player name that can either:
/// - follow for the full tracked timeline ([fullMatch] = true), or
/// - flash for [windowSec] seconds around selection time ([fullMatch] = false).
///
/// Usage inside a [Stack] that wraps a [VideoPlayer]:
/// ```dart
/// if (positions.isNotEmpty)
///   TrackingOverlay(
///     controller: controller,
///     positions: positions,
///     playerName: 'MODRIC',
///   ),
/// ```
class TrackingOverlay extends StatelessWidget {
  const TrackingOverlay({
    super.key,
    required this.controller,
    required this.positions,
    required this.playerName,
    this.selectionT,
    this.selectionNcx,
    this.selectionNcy,
    this.fullMatch = true,
    this.windowSec = 2.0,
  });

  final VideoPlayerController controller;

  /// Sorted list of position maps from the AI analysis.
  /// Each map must have at minimum: 't' (seconds), 'ncx' (0-1), 'ncy' (0-1).
  /// Falls back to 'cx'/'cy' pixel coords if normalized ones are absent.
  final List<Map<String, dynamic>> positions;

  /// Display name shown in the badge (e.g. "MODRIC").
  final String playerName;

  /// Explicit selection time in seconds — the moment the player was tapped
  /// during analysis. When provided, the overlay appears at this timestamp
  /// using [selectionNcx]/[selectionNcy] instead of positions[0].
  final double? selectionT;

  /// Normalized X (0-1) of the selection tap. Used together with [selectionT].
  final double? selectionNcx;

  /// Normalized Y (0-1) of the selection tap. Used together with [selectionT].
  final double? selectionNcy;

  /// How many seconds to show the overlay after the selection time.
  /// Used only when [fullMatch] is false.
  final double windowSec;

  /// When true, keep the label active for the full tracked timeline.
  final bool fullMatch;

  static const double _minCoord = 0.02;
  static const double _maxCoord = 0.98;

  _OverlayPoint? _pointAtTime({
    required double t,
    required double selT,
    required _OverlayPoint selectionPoint,
    required List<_TimedPoint> timeline,
    required bool fullMatch,
  }) {
    if (timeline.isEmpty) return null;

    if (t < selT) return null;

    // Do not render when the target has no nearby track sample.
    // This avoids freezing the badge at an old position when the player
    // disappears or tracker confidence is lost.
    const maxGapSec = 1.8;

    if (t <= timeline.first.t) {
      if ((timeline.first.t - t) > maxGapSec) return null;
      return _OverlayPoint(timeline.first.ncx, timeline.first.ncy);
    }
    if (t >= timeline.last.t) {
      if ((t - timeline.last.t) > maxGapSec) return null;
      return _OverlayPoint(timeline.last.ncx, timeline.last.ncy);
    }

    int lo = 0;
    int hi = timeline.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timeline[mid].t < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    final right = lo;
    final left = math.max(0, right - 1);
    final a = timeline[left];
    final b = timeline[right];

    final dt = (b.t - a.t);
    if (dt > maxGapSec) return null;
    if (dt <= 0.0) {
      return _OverlayPoint(a.ncx, a.ncy);
    }

    // Use the nearest real sample instead of interpolation to avoid visual
    // drift toward other players between sparse detection points.
    final leftDt = (t - a.t).abs();
    final rightDt = (b.t - t).abs();
    final chosen = leftDt <= rightDt ? a : b;
    return _OverlayPoint(chosen.ncx, chosen.ncy);
  }

  // ── Coordinate helpers ────────────────────────────────────────────────────

  double _pt(Map<String, dynamic> p) =>
      (p['t'] as num?)?.toDouble() ?? 0.0;

  double _ncxOf(Map<String, dynamic> p) {
    final v = p['ncx'];
    if (v is num) return v.toDouble();
    final cx = p['cx'];
    return cx is num ? cx.toDouble() / 1920.0 : 0.5;
  }

  double _ncyOf(Map<String, dynamic> p) {
    final v = p['ncy'];
    if (v is num) return v.toDouble();
    final cy = p['cy'];
    return cy is num ? cy.toDouble() / 1080.0 : 0.5;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty && selectionT == null) return const SizedBox.shrink();

    // Prefer explicit selection point (from playerSelections on the backend).
    // Fall back to positions[0] only if no explicit selection was provided.
    final double selT;
    final double selNcx;
    final double selNcy;

    if (selectionT != null && selectionNcx != null && selectionNcy != null) {
      selT   = selectionT!;
      selNcx = selectionNcx!.clamp(_minCoord, _maxCoord);
      selNcy = selectionNcy!.clamp(_minCoord, _maxCoord);
    } else if (positions.isNotEmpty) {
      selT   = _pt(positions[0]);
      selNcx = _ncxOf(positions[0]).clamp(_minCoord, _maxCoord);
      selNcy = _ncyOf(positions[0]).clamp(_minCoord, _maxCoord);
    } else {
      return const SizedBox.shrink();
    }

    final selectionPoint = _OverlayPoint(selNcx, selNcy);
    final timeline = positions
        .map((p) => _TimedPoint(
              t: _pt(p),
              ncx: _ncxOf(p).clamp(_minCoord, _maxCoord),
              ncy: _ncyOf(p).clamp(_minCoord, _maxCoord),
            ))
        .where((p) => p.t.isFinite)
        .toList()
      ..sort((a, b) => a.t.compareTo(b.t));

    // Anchor the first frame of the window to the exact user selection.
    timeline.add(_TimedPoint(t: selT, ncx: selNcx, ncy: selNcy));
    timeline.sort((a, b) => a.t.compareTo(b.t));

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, val, __) {
        final t    = val.position.inMilliseconds / 1000.0;
        final diff = t - selT;

        double opacity = 1.0;
        if (fullMatch && timeline.isNotEmpty) {
          // In full-match mode, tracking starts from the user's selection time.
          final firstT = selT - 0.2;
          final lastT = timeline.last.t + 0.2;
          if (t < firstT || t > lastT) return const SizedBox.shrink();
        } else {
          // Legacy flash mode around selection time.
          if (diff < -0.3 || diff > windowSec) return const SizedBox.shrink();
          // Smooth fade-out in the last 0.4 s.
          opacity = diff > (windowSec - 0.4)
              ? ((windowSec - diff) / 0.4).clamp(0.0, 1.0)
              : 1.0;
        }

        final tracked = _pointAtTime(
          t: t,
          selT: selT,
          selectionPoint: selectionPoint,
          timeline: timeline,
          fullMatch: fullMatch,
        );

        if (tracked == null) return const SizedBox.shrink();

        return _OverlayLabel(
          ncx: tracked.ncx,
          ncy: tracked.ncy,
          opacity: opacity,
          playerName: playerName,
        );
      },
    );
  }
}

class _TimedPoint {
  const _TimedPoint({
    required this.t,
    required this.ncx,
    required this.ncy,
  });

  final double t;
  final double ncx;
  final double ncy;
}

class _OverlayPoint {
  const _OverlayPoint(this.ncx, this.ncy);

  final double ncx;
  final double ncy;
}

// ── Internal label widget ─────────────────────────────────────────────────────

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({
    required this.ncx,
    required this.ncy,
    required this.opacity,
    required this.playerName,
  });

  final double ncx;
  final double ncy;
  final double opacity;
  final String playerName;

  static const double _labelH = 22.0;
  static const double _triH   = 12.0;
  static const double _triW   = 16.0;
  static const double _gap    =  2.0;
  static const double _maxW   = 120.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final px  = ncx * constraints.maxWidth;
      final py  = ncy * constraints.maxHeight;
      final top = math.max(0.0, py - _labelH - _gap - _triH);
      final left =
          (px - _maxW / 2).clamp(0.0, constraints.maxWidth - _maxW);

      return Stack(children: [
        Positioned(
          left:  left,
          top:   top,
          width: _maxW,
          child: Opacity(
            opacity: opacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Name badge ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF00E676),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    playerName.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: _gap),
                // ── Green triangle ─────────────────────────────────────────
                CustomPaint(
                  size: const Size(_triW, _triH),
                  painter: _TrianglePainter(),
                ),
              ],
            ),
          ),
        ),
      ]);
    });
  }
}

// ── Triangle painter ──────────────────────────────────────────────────────────

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, fill);

    // Thin white outline for contrast on bright backgrounds.
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
