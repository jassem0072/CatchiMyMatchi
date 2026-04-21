import 'dart:math' as math;

/// FIFA-style stat computation from AI analysis metrics + positions.
/// Ported from fronttest/app.js computeCardStats() logic.

class FifaCardStats {
  final int pac;
  final int sho;
  final int pas;
  final int dri;
  final int def;
  final int phy;
  final int ovr;

  const FifaCardStats({
    required this.pac,
    required this.sho,
    required this.pas,
    required this.dri,
    required this.def,
    required this.phy,
    required this.ovr,
  });

  /// Default "empty" card.
  static const empty = FifaCardStats(pac: 50, sho: 50, pas: 50, dri: 50, def: 50, phy: 50, ovr: 50);

  List<MapEntry<String, int>> get entries => [
        MapEntry('PAC', pac),
        MapEntry('SHO', sho),
        MapEntry('PAS', pas),
        MapEntry('DRI', dri),
        MapEntry('DEF', def),
        MapEntry('PHY', phy),
      ];
}

/// Path-based stats computed from raw position array.
class _PathStats {
  final double totalPx;
  final double maxPxPerS;
  final double medianPxPerS;
  final double maxPxPerS2;
  final double turnDegPerS;
  final double smoothness;
  final double durationS;
  final int directionChanges;
  final double movingRatio;

  const _PathStats({
    required this.totalPx,
    required this.maxPxPerS,
    required this.medianPxPerS,
    required this.maxPxPerS2,
    required this.turnDegPerS,
    required this.smoothness,
    required this.durationS,
    required this.directionChanges,
    required this.movingRatio,
  });
}

/// Normalise [value] to FIFA 1-99 scale using [min]..[max] range.
int scoreFromRange(double value, double min, double max) {
  if (max <= min) return 50;
  final s = 1 + (value - min) / (max - min) * 98;
  return s.round().clamp(1, 99);
}

/// Compute path-based stats from AI positions array.
/// Each position is expected to have keys: `t` (seconds), `cx`, `cy` (pixels).
_PathStats _computePathStats(List<dynamic> positions) {
  if (positions.length < 2) {
    return const _PathStats(
      totalPx: 0,
      maxPxPerS: 0,
      medianPxPerS: 0,
      maxPxPerS2: 0,
      turnDegPerS: 0,
      smoothness: 1,
      durationS: 0,
      directionChanges: 0,
      movingRatio: 0,
    );
  }

  double totalPx = 0;
  double totalAngle = 0;
  int segCount = 0;
  int dirChanges = 0;
  int movingFrames = 0;
  final speeds = <double>[];
  final accels = <double>[];
  double prevSpeed = 0;

  for (int i = 1; i < positions.length; i++) {
    final cur = positions[i] as Map<String, dynamic>;
    final prev = positions[i - 1] as Map<String, dynamic>;

    final dx = _d(cur['cx']) - _d(prev['cx']);
    final dy = _d(cur['cy']) - _d(prev['cy']);
    final dist = math.sqrt(dx * dx + dy * dy);
    final dt = _d(cur['t']) - _d(prev['t']);
    totalPx += dist;

    if (dt > 0) {
      final speed = dist / dt;
      speeds.add(speed);
      if (speed > 2.0) movingFrames++; // > 2 px/s = moving
      final accel = (speed - prevSpeed).abs() / dt;
      accels.add(accel);
      prevSpeed = speed;
    }

    if (i >= 2) {
      final prev2 = positions[i - 2] as Map<String, dynamic>;
      final dx0 = _d(prev['cx']) - _d(prev2['cx']);
      final dy0 = _d(prev['cy']) - _d(prev2['cy']);
      final len0 = math.sqrt(dx0 * dx0 + dy0 * dy0);
      final len1 = math.sqrt(dx * dx + dy * dy);
      if (len0 > 1 && len1 > 1) {
        final dot = dx * dx0 + dy * dy0;
        final cross = dx * dy0 - dy * dx0;
        final angle = math.atan2(cross.abs(), dot).abs();
        totalAngle += angle;
        segCount++;
        // Significant direction change: > 30 degrees
        if (angle > math.pi / 6) dirChanges++;
      }
    }
  }

  // Median-filter speeds to reject single-frame outliers
  speeds.sort();
  final medianSpeed = speeds.isNotEmpty
      ? speeds[speeds.length ~/ 2]
      : 0.0;
  // Percentile-95 speed (more robust than raw max)
  final p95Idx = (speeds.length * 0.95).floor().clamp(0, speeds.length - 1);
  final maxPxPerS = speeds.isNotEmpty ? speeds[p95Idx] : 0.0;
  // Median acceleration
  accels.sort();
  final maxPxPerS2 = accels.isNotEmpty
      ? accels[(accels.length * 0.90).floor().clamp(0, accels.length - 1)]
      : 0.0;

  final first = positions.first as Map<String, dynamic>;
  final last = positions.last as Map<String, dynamic>;
  final durationS = _d(last['t']) - _d(first['t']);

  final turnDegPerS = (segCount > 0 && durationS > 0)
      ? (totalAngle * 180 / math.pi) / durationS
      : 0.0;
  final smoothness = segCount > 0 ? 1 - (totalAngle / (math.pi * segCount)) : 1.0;
  final movingRatio = speeds.isNotEmpty ? movingFrames / speeds.length : 0.0;

  return _PathStats(
    totalPx: totalPx,
    maxPxPerS: maxPxPerS,
    medianPxPerS: medianSpeed,
    maxPxPerS2: maxPxPerS2,
    turnDegPerS: turnDegPerS,
    smoothness: smoothness,
    durationS: durationS,
    directionChanges: dirChanges,
    movingRatio: movingRatio,
  );
}

/// Physical cap: no human runs faster than ~44 km/h (Usain Bolt).
const _kMaxHumanKmh = 45.0;

/// Blend a raw score toward the baseline based on confidence factor.
/// With low confidence the stat regresses toward [base] (default 45).
/// The exponent softens the regression so stats remain more differentiated.
int _blendToBase(int raw, double confidence, {int base = 45}) {
  // Use sqrt to soften: even 0.5 confidence → 0.71 blend factor
  final f = math.sqrt(confidence.clamp(0.0, 1.0));
  return (base + (raw - base) * f).round().clamp(1, 99);
}

/// Compute FIFA card stats from AI analysis result.
///
/// [metrics] — the `metrics` object from AI response
/// [positions] — the `positions` array from AI response
/// [posLabel] — player position label (e.g. 'ST', 'CB', 'CM')
FifaCardStats computeCardStats(
  Map<String, dynamic> metrics,
  List<dynamic> positions, {
  String posLabel = 'CM',
}) {
  final path = _computePathStats(positions);
  final nPoints = positions.length;

  // ── AI movement analytics (from backend — smoothed & filtered) ──
  final movement = metrics['movement'] as Map<String, dynamic>? ?? {};
  final hasMovement = movement.isNotEmpty;

  // ── Data quality & confidence ──
  final hasCalibration =
      metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null;

  // Use AI-computed quality score if available, else fall back to heuristic
  double confidence;
  if (hasMovement && _d(movement['qualityScore']) > 0) {
    confidence = _d(movement['qualityScore']).clamp(0.0, 1.0);
  } else {
    final pointConf = ((nPoints - 10) / 100.0).clamp(0.0, 1.0);
    final calFactor = hasCalibration ? 1.0 : 0.7;
    confidence = (pointConf * calFactor).clamp(0.0, 1.0);
  }

  // ── Extract calibrated metrics (clamped to physical limits) ──
  final maxKmh = _d(metrics['maxSpeedKmh']).clamp(0.0, _kMaxHumanKmh);
  final avgKmh = _d(metrics['avgSpeedKmh']).clamp(0.0, _kMaxHumanKmh);
  final distM = _d(metrics['distanceMeters']);
  final sprintCount = _d(metrics['sprintCount']).round();
  final durationSec = hasMovement
      ? _d(movement['totalDurationSec'])
      : path.durationS;
  final durationMin = durationSec > 0 ? durationSec / 60.0 : 1.0;

  // ── PAC (Pace) — top speed ──
  // Real football: jogging 8-12, running 15-20, fast 22-28, sprint 30-35, elite 36+
  // Prefer: calibrated km/h > normalized speed > pixel speed > raw path
  final hasNorm = hasMovement && _d(movement['normMaxSpeedPerSec']) > 0;
  int pacRaw;
  if (hasCalibration && maxKmh > 0) {
    pacRaw = scoreFromRange(maxKmh, 8, 38);
  } else if (hasNorm) {
    // Normalized coords (0-1 range): zoom-invariant, most accurate without calibration
    pacRaw = scoreFromRange(_d(movement['normMaxSpeedPerSec']), 0.01, 0.25);
  } else if (hasMovement && _d(movement['maxPxPerSec']) > 0) {
    pacRaw = scoreFromRange(_d(movement['maxPxPerSec']), 15, 350);
  } else {
    pacRaw = scoreFromRange(path.maxPxPerS, 20, 400);
  }

  // ── DRI (Dribbling / Agility) — direction changes & turn rate ──
  double dirChangesPerMin;
  double turnDegPerS;
  if (hasMovement) {
    dirChangesPerMin = _d(movement['dirChangesPerMin']);
    turnDegPerS = _d(movement['avgTurnDegPerSec']);
  } else {
    dirChangesPerMin = durationMin > 0
        ? path.directionChanges / durationMin
        : 0.0;
    turnDegPerS = path.turnDegPerS;
  }
  final turnScore = scoreFromRange(turnDegPerS, 1, 35);
  final dirScore = scoreFromRange(dirChangesPerMin, 1, 30);
  final driRaw = (0.5 * turnScore + 0.5 * dirScore).round().clamp(1, 99);

  // ── PAS (Passing / Movement intelligence) — smoothness + consistency ──
  final movingRatio = hasMovement
      ? _d(movement['movingRatio'])
      : path.movingRatio;
  final smoothScore = scoreFromRange(path.smoothness, 0.2, 0.8);
  final moveScore = scoreFromRange(movingRatio, 0.2, 0.85);
  final pasRaw = (0.55 * smoothScore + 0.45 * moveScore).round().clamp(1, 99);

  // ── DEF (Defending / Work rate) — distance per minute ──
  int defRaw;
  if (hasMovement && _d(movement['workRateMetersPerMin']) > 0) {
    defRaw = scoreFromRange(_d(movement['workRateMetersPerMin']), 30, 140);
  } else if (hasCalibration && distM > 0) {
    defRaw = scoreFromRange(distM / durationMin, 30, 140);
  } else if (hasNorm) {
    // Normalized distance / minute (zoom-invariant)
    final normPerMin = _d(movement['normTotalDist']) / durationMin;
    defRaw = scoreFromRange(normPerMin, 0.05, 2.0);
  } else if (hasMovement && _d(movement['totalPxDist']) > 0) {
    final pxPerMin = _d(movement['totalPxDist']) / durationMin;
    defRaw = scoreFromRange(pxPerMin, 80, 2500);
  } else {
    final pxPerMin = durationMin > 0 ? path.totalPx / durationMin : 0.0;
    defRaw = scoreFromRange(pxPerMin, 100, 3000);
  }

  // ── SHO (Shooting / Explosive power) — acceleration + sprint ability ──
  int accelScore;
  if (hasMovement && _d(movement['avgAccelMps2']) > 0) {
    // Calibrated real m/s²
    accelScore = scoreFromRange(_d(movement['avgAccelMps2']), 0.2, 3.5);
  } else if (hasNorm) {
    // Normalized acceleration (zoom-invariant)
    accelScore = scoreFromRange(_d(movement['normP90AccelPerS2']), 0.001, 0.15);
  } else if (hasMovement && _d(movement['p90AccelPxPerS2']) > 0) {
    accelScore = scoreFromRange(_d(movement['p90AccelPxPerS2']), 0.5, 8.0);
  } else {
    accelScore = scoreFromRange(path.maxPxPerS2, 0.5, 8.0);
  }
  int sprintScore;
  if (hasCalibration) {
    sprintScore = scoreFromRange(sprintCount.toDouble(), 0, 6);
  } else {
    // Use pace as proxy when no sprint data
    sprintScore = ((pacRaw * 0.6) + 20).round().clamp(1, 99);
  }
  final shoRaw = (0.40 * accelScore + 0.35 * pacRaw + 0.25 * sprintScore)
      .round()
      .clamp(1, 99);

  // ── PHY (Physical / Endurance) — stamina + sustained effort ──
  double avgSpeedScore;
  if (hasCalibration && avgKmh > 0) {
    avgSpeedScore = scoreFromRange(avgKmh, 3, 16).toDouble();
  } else if (hasNorm) {
    avgSpeedScore = scoreFromRange(_d(movement['normMedianSpeedPerSec']), 0.005, 0.12).toDouble();
  } else if (hasMovement && _d(movement['medianPxPerSec']) > 0) {
    avgSpeedScore = scoreFromRange(_d(movement['medianPxPerSec']), 8, 180).toDouble();
  } else {
    avgSpeedScore = scoreFromRange(path.medianPxPerS, 10, 200).toDouble();
  }
  final phyRaw = (0.30 * defRaw + 0.30 * avgSpeedScore + 0.25 * accelScore + 0.15 * moveScore)
      .round()
      .clamp(1, 99);

  // ── Apply confidence: low data → stats regress toward baseline ──
  final pac = _blendToBase(pacRaw, confidence);
  final sho = _blendToBase(shoRaw, confidence);
  final pas = _blendToBase(pasRaw, confidence);
  final dri = _blendToBase(driRaw, confidence);
  final def = _blendToBase(defRaw, confidence);
  final phy = _blendToBase(phyRaw, confidence);

  // ── OVR = simple average of all 6 stats ──
  final ovr = ((pac + sho + pas + dri + def + phy) / 6.0).round().clamp(1, 99);

  return FifaCardStats(pac: pac, sho: sho, pas: pas, dri: dri, def: def, phy: phy, ovr: ovr);
}

double _d(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
