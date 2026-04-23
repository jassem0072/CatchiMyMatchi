import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../app/scoutai_app.dart';
import '../features/analysis/models/analysis_metrics_dto.dart';
import '../features/analysis/models/analysis_metrics_mapper.dart';
import '../features/analysis/models/speed_sample_point.dart';
import '../features/analysis/services/analysis_metrics_service.dart';
import '../features/profile/providers/profile_providers.dart';
import '../models/player_analysis.dart';
import '../services/pdf_download_helper.dart';
import '../theme/app_colors.dart';
import '../services/translations.dart';
import '../widgets/common.dart';
import '../widgets/fifa_card_stats.dart';
import '../widgets/legendary_player_card.dart';

/// Accepts either:
/// - a `PlayerAnalysis` object (legacy / mock)
/// - a raw `Map<String, dynamic>` from AI response (real analysis)
class AnalysisDetailsScreen extends ConsumerStatefulWidget {
  const AnalysisDetailsScreen({super.key});

  @override
  ConsumerState<AnalysisDetailsScreen> createState() => _AnalysisDetailsScreenState();
}

class _AnalysisDetailsScreenState extends ConsumerState<AnalysisDetailsScreen> {
  static const AnalysisMetricsService _analysisMetricsService = AnalysisMetricsService();

  // ── Profile ──
  String _playerName = 'Player';
  String _position = 'CM';
  Uint8List? _portraitBytes;
  Map<String, dynamic>? _meProfile;
  bool _downloadLoading = false;

  // ── Screenshot controllers ──
  final _screenshotCtrl = ScreenshotController();
  final _heatmapCtrl = ScreenshotController();
  final _speedChartCtrl = ScreenshotController();
  final PageController _insightsPageCtrl = PageController();
  int _insightsPage = 0;

  // ── Parsed metrics (class-level so _onShare can read them) ──
  double _distanceKm = 0;
  double _maxSpeedKmh = 0;
  double _avgSpeedKmh = 0;
  int _sprints = 0;
  int _accelPeaks = 0;
  int _positionCount = 0;
  List<dynamic>? _heatmapCounts;
  int _heatGridW = 0;
  int _heatGridH = 0;
  bool _isCalibrated = false;
  final List<SpeedSamplePoint> _speedSamples = [];
  FifaCardStats _cardStats = FifaCardStats.empty;
  String? _videoId;

  // ── Extended metrics ──
  double? _workRate;
  double? _movingRatio;
  double? _directionChanges;
  double? _matchReadiness;
  Map<String, dynamic>? _movementZones;
  Map<String, dynamic> _homeSummary = <String, dynamic>{};
  int _calibratedCount = 0;
  int _uncalibratedCount = 0;


  bool _argsParsed = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _insightsPageCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsParsed) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null) {
      _parseArgs(args);
      _argsParsed = true;
    }
  }

  void _parseArgs(dynamic args) {
    if (args is Map<String, dynamic>) {
      final parsed = AnalysisMetricsMapper.toEntity(
        AnalysisMetricsDto.fromArgs(args),
      );

      _distanceKm = parsed.distanceKm;
      _maxSpeedKmh = parsed.maxSpeedKmh;
      _avgSpeedKmh = parsed.avgSpeedKmh;
      _sprints = parsed.sprints;
      _accelPeaks = parsed.accelPeaks;
      _positionCount = parsed.positionCount;
      _heatmapCounts = parsed.heatmapCounts;
      _heatGridW = parsed.heatGridW;
      _heatGridH = parsed.heatGridH;
      _isCalibrated = parsed.isCalibrated;

      _workRate = parsed.workRate;
      _movingRatio = parsed.movingRatio;
      _directionChanges = parsed.directionChanges;
      _matchReadiness = parsed.matchReadiness;
      _movementZones = parsed.movementZones;
      _videoId = parsed.videoId;

      _speedSamples
        ..clear()
        ..addAll(
          _analysisMetricsService.buildSpeedSamples(
            positions: parsed.positions,
            meterPerPx: parsed.meterPerPx,
          ),
        );

      _cardStats = computeCardStats(
        parsed.metrics,
        parsed.positions,
        posLabel: _position,
      );
    } else {
      // Legacy PlayerAnalysis model (mock_data.dart removed — use args or zeros)
      final PlayerAnalysis item = args is PlayerAnalysis
          ? args
          : const PlayerAnalysis(
              id: '',
              playerName: 'Player',
              playerNumber: 0,
              matchName: '',
              distanceKm: 0,
              maxSpeedKmh: 0,
              sprints: 0,
              status: AnalysisStatus.done,
            );
      _distanceKm = item.distanceKm;
      _maxSpeedKmh = item.maxSpeedKmh;
      _sprints = item.sprints;
      _avgSpeedKmh = _maxSpeedKmh * 0.55;
    }
  }

  Future<void> _loadProfile() async {
    try {
      final summary = await ref.read(profileServiceProvider).loadProfileSummary();
      if (!mounted) return;
      final me = summary.meRaw;
      final dn = (me['displayName'] as String?)?.trim();
      final email = summary.player.email;
      final at = email.indexOf('@');

      setState(() {
        _meProfile = me;
        _portraitBytes = summary.portraitBytes;
        _playerName = (dn != null && dn.isNotEmpty)
            ? dn
            : (at > 0 ? email.substring(0, at) : summary.player.displayName);
        _position = summary.player.position;
      });

      // Re-compute card stats with updated position if args already parsed
      if (_argsParsed) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map<String, dynamic>) {
          final m = args['metrics'] as Map<String, dynamic>? ?? {};
          final p = args['positions'] as List<dynamic>? ?? [];
          setState(() => _cardStats = computeCardStats(m, p, posLabel: _position));
        }
      }

      if (summary.videos.isNotEmpty) {
        final homeStats = _computeHomePdfStats(summary.videos);
        if (!mounted) return;
        setState(() {
          _homeSummary = homeStats.$1;
          _calibratedCount = homeStats.$3;
          _uncalibratedCount = homeStats.$4;
        });
      }
    } catch (_) {}
  }

  (Map<String, dynamic>, List<Map<String, dynamic>>, int, int) _computeHomePdfStats(List<dynamic> videos) {
    double totalDistKm = 0;
    double totalMaxSpeed = 0;
    double totalAvgSpeed = 0;
    int totalSprints = 0;
    int totalAccelPeaks = 0;
    int totalTrackingPoints = 0;
    int analyzed = 0;
    double bestDistance = 0;
    double bestAvgSpeed = 0;
    int bestSprints = 0;

    int calibrated = 0;
    int uncalibrated = 0;
    final rows = <Map<String, dynamic>>[];

    double sumWalkPct = 0;
    double sumJogPct = 0;
    double sumRunPct = 0;
    double sumHighPct = 0;
    double sumSprintPct = 0;
    int zonesCount = 0;

    double sumWorkRate = 0;
    double sumMovingRatio = 0;
    double sumDirChanges = 0;
    int workRateCount = 0;
    double sumQuality = 0;
    int qualityCount = 0;

    for (final raw in videos) {
      if (raw is! Map) continue;
      final v = Map<String, dynamic>.from(raw);
      final analysis = v['lastAnalysis'];
      if (analysis is! Map) continue;

      final metrics = analysis['metrics'] is Map
          ? Map<String, dynamic>.from(analysis['metrics'] as Map)
          : Map<String, dynamic>.from(analysis);

      analyzed++;

      final distanceMeters = _dbl(metrics['distanceMeters']);
      final distanceKm = distanceMeters > 0
          ? distanceMeters / 1000.0
          : _dbl(metrics['distanceKm']).clamp(0.0, 9999.0);
      final maxSpeed = _dbl(metrics['maxSpeedKmh']).clamp(0.0, 45.0);
      final avgSpeed = _dbl(metrics['avgSpeedKmh']).clamp(0.0, 45.0);
      final sprints = _intVal(metrics['sprintCount']);

      final accelRaw = metrics['accelPeaks'];
      final accelPeaks = accelRaw is List ? accelRaw.length : _intVal(accelRaw);

        final positions = (analysis['positions'] is List)
          ? (analysis['positions'] as List)
          : (metrics['positions'] is List)
            ? (metrics['positions'] as List)
            : const [];
        final trackingPoints = positions.isNotEmpty
          ? positions.length
          : _intVal(metrics['trackingPoints']);

      final movement = metrics['movement'] is Map
          ? Map<String, dynamic>.from(metrics['movement'] as Map)
          : <String, dynamic>{};
      final quality = _dbl(movement['qualityScore']).clamp(0.0, 1.0);
      sumQuality += quality;
      qualityCount++;

      final zones = movement['zones'];
      if (zones is Map) {
        sumWalkPct += _dbl(zones['walking_pct']);
        sumJogPct += _dbl(zones['jogging_pct']);
        sumRunPct += _dbl(zones['running_pct']);
        sumHighPct += _dbl(zones['highSpeed_pct']);
        sumSprintPct += _dbl(zones['sprinting_pct']);
        zonesCount++;
      }

      final wr = _dbl(movement['workRateMetersPerMin']);
      final mr = _dbl(movement['movingRatio']);
      final dc = _dbl(movement['dirChangesPerMin'] ?? movement['directionChangesPerMin']);
      if (wr > 0 || mr > 0 || dc > 0) {
        sumWorkRate += wr;
        sumMovingRatio += mr;
        sumDirChanges += dc;
        workRateCount++;
      }

      final heatmap = metrics['heatmap'] is Map
          ? Map<String, dynamic>.from(metrics['heatmap'] as Map)
          : <String, dynamic>{};
      final coordSpace = (heatmap['coord_space'] as String?) ?? 'image';
      final isCalibrated = coordSpace == 'pitch' ||
          (metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null);

      if (isCalibrated) {
        calibrated++;
      } else {
        uncalibrated++;
      }

      totalDistKm += distanceKm;
      totalMaxSpeed += maxSpeed;
      totalAvgSpeed += avgSpeed > 0 ? avgSpeed : maxSpeed * 0.55;
      totalSprints += sprints;
      totalAccelPeaks += accelPeaks;
      totalTrackingPoints += trackingPoints;

      if (distanceKm > bestDistance) bestDistance = distanceKm;
      if (avgSpeed > bestAvgSpeed) bestAvgSpeed = avgSpeed;
      if (sprints > bestSprints) bestSprints = sprints;

      rows.add({
        'name': (v['originalName'] ?? v['filename'] ?? 'Video').toString(),
        'videoId': (v['_id'] ?? v['id'])?.toString(),
        'date': (v['createdAt'] ?? v['updatedAt'] ?? '').toString(),
        'distanceKm': distanceKm,
        'maxSpeedKmh': maxSpeed,
        'avgSpeedKmh': avgSpeed > 0 ? avgSpeed : maxSpeed * 0.55,
        'sprints': sprints,
        'accelPeaks': accelPeaks,
        'qualityScore': quality,
        'calibrated': isCalibrated,
      });
    }

    final avgDist = analyzed > 0 ? totalDistKm / analyzed : 0.0;
    final avgSpeed = analyzed > 0 ? totalAvgSpeed / analyzed : 0.0;
    final avgSprints = analyzed > 0 ? totalSprints / analyzed : 0.0;

    final summary = <String, dynamic>{
      'totalVideos': videos.length,
      'matchesAnalyzed': analyzed,
      'totalDistanceKm': totalDistKm,
      'avgDistanceKm': avgDist,
      'maxSpeedKmh': analyzed > 0 ? (totalMaxSpeed / analyzed) : 0.0,
      'avgSpeedKmh': avgSpeed,
      'totalSprints': totalSprints,
      'avgSprints': avgSprints,
      'totalAccelPeaks': totalAccelPeaks,
      'totalTrackingPoints': totalTrackingPoints,
      'avgTrackingPoints': analyzed > 0 ? totalTrackingPoints / analyzed : 0.0,
      'bestDistanceKm': bestDistance,
      'bestAvgSpeedKmh': bestAvgSpeed,
      'bestSprints': bestSprints,
      'calibratedCount': calibrated,
      'uncalibratedCount': uncalibrated,
      'avgWalkPct': zonesCount > 0 ? sumWalkPct / zonesCount : 0.0,
      'avgJogPct': zonesCount > 0 ? sumJogPct / zonesCount : 0.0,
      'avgRunPct': zonesCount > 0 ? sumRunPct / zonesCount : 0.0,
      'avgHighPct': zonesCount > 0 ? sumHighPct / zonesCount : 0.0,
      'avgSprintPct': zonesCount > 0 ? sumSprintPct / zonesCount : 0.0,
      'hasZones': zonesCount > 0,
      'avgWorkRate': workRateCount > 0 ? sumWorkRate / workRateCount : 0.0,
      'avgMovingRatio': workRateCount > 0 ? sumMovingRatio / workRateCount : 0.0,
      'avgDirChanges': workRateCount > 0 ? sumDirChanges / workRateCount : 0.0,
      'hasWorkRate': workRateCount > 0,
      'avgReadiness': qualityCount > 0 ? (sumQuality / qualityCount) : 0.0,
    };

    rows.sort((a, b) {
      final qa = (a['qualityScore'] as num?)?.toDouble() ?? 0.0;
      final qb = (b['qualityScore'] as num?)?.toDouble() ?? 0.0;
      return qb.compareTo(qa);
    });

    return (summary, rows, calibrated, uncalibrated);
  }

  int? _ageFromDob(String? dob) {
    if (dob == null || dob.trim().isEmpty) return null;
    final date = DateTime.tryParse(dob.trim());
    if (date == null) return null;
    final now = DateTime.now();
    var age = now.year - date.year;
    final hadBirthday =
        (now.month > date.month) || (now.month == date.month && now.day >= date.day);
    if (!hadBirthday) age -= 1;
    return age < 0 ? null : age;
  }



  @override
  Widget build(BuildContext context) {
    final aggregateCount = ((_homeSummary['matchesAnalyzed'] as num?)?.toInt() ?? 0);
    final hasAggregate = aggregateCount > 0;
    final displayDistanceKm = hasAggregate
      ? ((_homeSummary['avgDistanceKm'] as num?)?.toDouble() ?? _distanceKm)
      : _distanceKm;
    final displayTopSpeed = hasAggregate
      ? ((_homeSummary['maxSpeedKmh'] as num?)?.toDouble() ?? _maxSpeedKmh)
      : _maxSpeedKmh;
    final displayAvgSpeed = hasAggregate
      ? ((_homeSummary['avgSpeedKmh'] as num?)?.toDouble() ?? _avgSpeedKmh)
      : _avgSpeedKmh;
    final displaySprints = hasAggregate
      ? ((_homeSummary['avgSprints'] as num?)?.toDouble() ?? _sprints.toDouble())
      : _sprints.toDouble();
    final displayAccel = hasAggregate
      ? (((_homeSummary['totalAccelPeaks'] as num?)?.toDouble() ?? _accelPeaks.toDouble()) /
        (aggregateCount == 0 ? 1 : aggregateCount))
      : _accelPeaks.toDouble();
    final displayReadiness = hasAggregate
      ? ((_homeSummary['avgReadiness'] as num?)?.toDouble() ?? (_matchReadiness ?? 0.0))
      : (_matchReadiness ?? 0.0);
    final displayTrackingPoints = hasAggregate
      ? ((_homeSummary['totalTrackingPoints'] as num?)?.toInt() ?? _positionCount)
      : _positionCount;

    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(S.of(context).analysisResults),
        actions: [
          if (_videoId != null && _videoId!.isNotEmpty)
            IconButton(
              tooltip: 'Tag a teammate',
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppRoutes.tagTeammates,
                  arguments: {'videoId': _videoId, 'editMode': true},
                );
              },
              icon: const Icon(Icons.person_add_alt_1, size: 22),
            ),

          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          // ── FIFA Player Card (wrapped for screenshot capture) ──
          Screenshot(
            controller: _screenshotCtrl,
            child: LegendaryPlayerCard(
              name: _playerName,
              stats: _cardStats,
              position: _position,
              portraitBytes: _portraitBytes,
            ),
          ),
          const SizedBox(height: 18),

          // ── Summary card ──
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      S.of(context).aiAnalysisComplete,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  hasAggregate
                      ? 'General result computed from $aggregateCount analyzed videos. '
                          'Below are the aggregated performance metrics.'
                      : '$_positionCount tracking points detected across the video. '
                          'Below are the computed performance metrics.',
                  style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tracking points analyzed: $displayTrackingPoints',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Data Quality Warning ──
          if (!_isCalibrated) ...[
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UNCALIBRATED DATA',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This analysis was run without pitch calibration. '
                          'Speed, distance, and heatmap data are estimated from pixel movement and may not be accurate. '
                          'For reliable metrics, use pitch calibration during analysis.',
                          style: TextStyle(
                            color: AppColors.txMuted(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Primary stats row ──
          Row(
            children: [
              MetricTile(
                label: S.of(context).distance,
                value: '${_distanceKm.toStringAsFixed(2)} km',
              ),
              const SizedBox(width: 10),
              MetricTile(
                label: S.of(context).topSpeed,
                value: '${_maxSpeedKmh.toStringAsFixed(1)} km/h',
                valueColor: AppColors.success,
              ),
              const SizedBox(width: 10),
              MetricTile(
                label: S.of(context).sprints,
                value: '$_sprints',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Secondary stats row ──
          Row(
            children: [
              MetricTile(
                label: S.of(context).avgSpeed,
                value: '${_avgSpeedKmh.toStringAsFixed(1)} km/h',
              ),
              const SizedBox(width: 10),
              MetricTile(
                label: S.of(context).accelPeaks,
                value: '$_accelPeaks',
                valueColor: AppColors.primary,
              ),
              const SizedBox(width: 10),
              MetricTile(
                label: S.of(context).positions,
                value: '$displayTrackingPoints',
              ),
            ],
          ),

          // ── Extended stats row (work rate, activity, direction) ──
          if (_workRate != null || _movingRatio != null || _directionChanges != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (_workRate != null) ...[
                  MetricTile(
                    label: 'Work Rate',
                    value: '${_workRate!.toStringAsFixed(0)} m/min',
                    valueColor: AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                ],
                if (_movingRatio != null) ...[
                  MetricTile(
                    label: 'Activity',
                    value: '${(_movingRatio! * 100).toStringAsFixed(0)}%',
                  ),
                  const SizedBox(width: 10),
                ],
                if (_directionChanges != null)
                  MetricTile(
                    label: 'Dir. Changes',
                    value: '${_directionChanges!.toStringAsFixed(1)}/min',
                    valueColor: AppColors.primary,
                  ),
              ],
            ),
          ],

          // ── Swipe Insights (left/right) ──
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'MATCH INSIGHTS',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              Text(
                'Swipe left/right',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 350,
            child: PageView(
              controller: _insightsPageCtrl,
              onPageChanged: (i) => setState(() => _insightsPage = i),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.analytics_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'PERFORMANCE SCORE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.3,
                            color: AppColors.primary,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _KpiBar(label: 'Endurance', value: (displayDistanceKm / 12.0).clamp(0.0, 1.0)),
                      const SizedBox(height: 8),
                      _KpiBar(label: 'Top Speed', value: (displayTopSpeed / 35.0).clamp(0.0, 1.0)),
                      const SizedBox(height: 8),
                      _KpiBar(label: 'Intensity', value: (displaySprints / 25.0).clamp(0.0, 1.0)),
                      const SizedBox(height: 8),
                      _KpiBar(label: 'Agility', value: (displayAccel / 30.0).clamp(0.0, 1.0)),
                      const SizedBox(height: 8),
                      _KpiBar(
                        label: 'Work Rate',
                        value: _workRate != null ? (_workRate! / 150.0).clamp(0.0, 1.0) : 0.0,
                      ),
                    ],
                  ),
                ),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MATCH READINESS',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _KpiBar(label: 'Readiness Score', value: displayReadiness.clamp(0.0, 1.0)),
                      const SizedBox(height: 6),
                      Text(
                        (hasAggregate || _matchReadiness != null)
                            ? '${(displayReadiness * 100).toStringAsFixed(0)}% quality confidence from movement consistency and tracking stability.'
                            : 'No readiness score available for this match.',
                        style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PLAYER RADAR (MATCH)',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: SizedBox(
                          height: 220,
                          width: 220,
                          child: _PlayerRadarChartMatch(stats: _cardStats),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'OVR ${_cardStats.ovr}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        S.of(context).speedTimeline,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: AppColors.primary),
                      ),
                      const SizedBox(height: 10),
                      _speedSamples.length >= 2
                          ? Screenshot(
                              controller: _speedChartCtrl,
                              child: _RealSpeedChart(samples: _speedSamples, height: 180),
                            )
                          : SizedBox(
                              height: 180,
                              child: Center(
                                child: Text(
                                  S.of(context).notEnoughData,
                                  style: const TextStyle(color: AppColors.textMuted),
                                ),
                              ),
                            ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${S.of(context).peakVelocity}\n${displayTopSpeed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${S.of(context).averageVelocity}\n${displayAvgSpeed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final active = i == _insightsPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),

          // ── Movement Zones ──
          if (_movementZones != null) ...[
            const SizedBox(height: 18),
            const Text(
              'MOVEMENT ZONES',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: _MovementZonesBar(zones: _movementZones!),
            ),
          ],

          const SizedBox(height: 18),

          // ── Heatmap ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.of(context).fieldHeatmap,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              if (_heatGridW > 0)
                Text(
                  '$_heatGridW×$_heatGridH grid',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: _heatmapCounts != null && _heatGridW > 0 && _heatGridH > 0
                ? Screenshot(
                    controller: _heatmapCtrl,
                    child: _RealHeatmap(
                      counts: _heatmapCounts!,
                      gridW: _heatGridW,
                      gridH: _heatGridH,
                    ),
                  )
                : Container(
                    height: 170,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1D3B3A), Color(0xFF2E5B40), Color(0xFF0F1B2B)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        S.of(context).noHeatmapData,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 18),

          // ── Export PDF Report button ──
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloadLoading ? null : _downloadPdf,
              icon: _downloadLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 20),
              label: const Text('Download PDF Report'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ── Chat with AI Coach ──
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D63FF), Color(0xFF00B0FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1D63FF).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    AppRoutes.aiCoach,
                    arguments: {
                      'pac': _cardStats.pac,
                      'sho': _cardStats.sho,
                      'pas': _cardStats.pas,
                      'dri': _cardStats.dri,
                      'def': _cardStats.def,
                      'phy': _cardStats.phy,
                      'ovr': _cardStats.ovr,
                      'position': _position,
                      'maxSpeedKmh': _maxSpeedKmh.toStringAsFixed(1),
                      'avgSpeedKmh': _avgSpeedKmh.toStringAsFixed(1),
                      'distanceKm': _distanceKm.toStringAsFixed(2),
                      'sprints': _sprints,
                      'trackingPoints': _positionCount,
                    },
                  );
                },
                icon: const Icon(Icons.smart_toy, size: 20),
                label: const Text('Chat with AI Coach'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Next Button → Home ──
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.playerHome,
                  (route) => false,
                );
              },
              icon: const Icon(Icons.home_outlined, size: 20),
              label: const Text('Next'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf() async {
    if (_downloadLoading) return;
    setState(() => _downloadLoading = true);
    try {
      final pdfBytes = await _buildProfessionalPdfBytes();
      final safeName = _playerName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final now = DateTime.now();
      final fileName = 'ScoutAI_Report_${safeName}_${now.millisecondsSinceEpoch}.pdf';
      if (!mounted) return;
      final didWebDownload = await triggerPdfDownload(pdfBytes, fileName);
      if (didWebDownload) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF downloaded: $fileName'), backgroundColor: const Color(0xFF16A34A)),
        );
        return;
      }

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save analysis report as PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: pdfBytes,
      );
      if (saved == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download canceled')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF downloaded: $fileName'), backgroundColor: const Color(0xFF16A34A)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF download error: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
    } finally {
      if (mounted) setState(() => _downloadLoading = false);
    }
  }

  Future<Uint8List> _buildProfessionalPdfBytes() async {
    final name = _playerName;
    final position = _position;
    final nation = (_meProfile?['nation'] ?? '').toString();
    final email = (_meProfile?['email'] ?? '').toString();
    final height = (_meProfile?['height'] ?? _meProfile?['heightCm'] ?? '').toString();
    final dob = (_meProfile?['dateOfBirth'] as String?)?.trim() ?? '';
    final age = _ageFromDob(dob);

    final analyzed = ((_homeSummary['matchesAnalyzed'] as num?)?.toInt() ?? 0) > 0
      ? ((_homeSummary['matchesAnalyzed'] as num?)?.toInt() ?? 0)
      : 1;
    final totalDistKm = ((_homeSummary['totalDistanceKm'] as num?)?.toDouble() ?? _distanceKm);
    final avgDistKm = ((_homeSummary['avgDistanceKm'] as num?)?.toDouble() ?? _distanceKm);
    final topSpeed = _maxSpeedKmh;
    final avgSpeed = _avgSpeedKmh;
    final totalSprints = ((_homeSummary['totalSprints'] as num?)?.toInt() ?? _sprints);
    final bestDistKm = ((_homeSummary['bestDistanceKm'] as num?)?.toDouble() ?? _distanceKm);
    final bestSpeed = ((_homeSummary['bestAvgSpeedKmh'] as num?)?.toDouble() ?? _avgSpeedKmh);
    final bestSprints = ((_homeSummary['bestSprints'] as num?)?.toInt() ?? _sprints);

    final walk = ((_homeSummary['avgWalkPct'] as num?)?.toDouble() ?? _dbl(_movementZones?['walking_pct']));
    final jog = ((_homeSummary['avgJogPct'] as num?)?.toDouble() ?? _dbl(_movementZones?['jogging_pct']));
    final run = ((_homeSummary['avgRunPct'] as num?)?.toDouble() ?? _dbl(_movementZones?['running_pct']));
    final high = ((_homeSummary['avgHighPct'] as num?)?.toDouble() ?? _dbl(_movementZones?['highSpeed_pct']));
    final spr = ((_homeSummary['avgSprintPct'] as num?)?.toDouble() ?? _dbl(_movementZones?['sprinting_pct']));
    final hasZones = _homeSummary['hasZones'] == true || (walk + jog + run + high + spr) > 0;

    final workRate = ((_homeSummary['avgWorkRate'] as num?)?.toDouble() ?? (_workRate ?? 0));
    final activity = ((_homeSummary['avgMovingRatio'] as num?)?.toDouble() ?? (_movingRatio ?? 0));
    final dirChanges = ((_homeSummary['avgDirChanges'] as num?)?.toDouble() ?? (_directionChanges ?? 0));
    final hasWorkRate = _homeSummary['hasWorkRate'] == true || workRate > 0 || activity > 0 || dirChanges > 0;

    final fifaStats = _cardStats;
    final now = DateTime.now();
    String fmt1(double v) => v.toStringAsFixed(1);

    final doc = pw.Document();
    final portrait = _portraitBytes != null && _portraitBytes!.isNotEmpty ? pw.MemoryImage(_portraitBytes!) : null;

    pw.Widget title(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A))),
    );

    pw.Widget paragraph(String text) => pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF334155), lineSpacing: 2),
    );

    pw.Widget infoRow(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(children: [
        pw.SizedBox(width: 110, child: pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF475569)))),
        pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)))),
      ]),
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32)),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0)))),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('SCOUTAI PROFESSIONAL REPORT', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A))),
              pw.Text('Player scouting dossier', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
            ]),
            pw.Text('${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
          ]),
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber}', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
        ),
        build: (_) => [
          title('1. Executive Summary'),
          paragraph('This report provides a complete technical overview of the player profile, physical output, movement behavior, and match-by-match performance derived from analyzed video data.'),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC), border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                width: 62,
                height: 62,
                decoration: pw.BoxDecoration(borderRadius: const pw.BorderRadius.all(pw.Radius.circular(31)), border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1))),
                child: portrait != null ? pw.ClipRRect(horizontalRadius: 31, verticalRadius: 31, child: pw.Image(portrait, fit: pw.BoxFit.cover)) : pw.Center(child: pw.Text(name.isNotEmpty ? name[0].toUpperCase() : 'P')),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A))),
                  pw.SizedBox(height: 6),
                  infoRow('Position', position),
                  if (nation.isNotEmpty) infoRow('Nationality', nation),
                  if (age != null) infoRow('Age', '$age years'),
                  if (height.isNotEmpty) infoRow('Height', '$height cm'),
                  if (email.isNotEmpty) infoRow('Email', email),
                  infoRow('Overall Rating (OVR)', '${fifaStats.ovr}'),
                ]),
              ),
            ]),
          ),
          title('2. Performance Overview'),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            cellStyle: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF1E293B)),
            headers: const ['Metric', 'Value'],
            data: [
              ['Matches analyzed', '$analyzed'],
              ['Total distance', '${totalDistKm.toStringAsFixed(2)} km'],
              ['Average distance / match', '${avgDistKm.toStringAsFixed(2)} km'],
              ['Top speed', '${fmt1(topSpeed)} km/h'],
              ['Average speed', '${fmt1(avgSpeed)} km/h'],
              ['Total sprints', '$totalSprints'],
              ['Calibrated videos', '$_calibratedCount'],
              ['Uncalibrated videos', '$_uncalibratedCount'],
            ],
          ),
          title('3. Technical Profile (FIFA-style attributes)'),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            headers: const ['Attribute', 'Score'],
            data: [
              ['Pace (PAC)', '${fifaStats.pac}'],
              ['Shooting (SHO)', '${fifaStats.sho}'],
              ['Passing (PAS)', '${fifaStats.pas}'],
              ['Dribbling (DRI)', '${fifaStats.dri}'],
              ['Defending (DEF)', '${fifaStats.def}'],
              ['Physical (PHY)', '${fifaStats.phy}'],
            ],
          ),
          title('4. Movement and Intensity Analysis'),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            headers: const ['Category', 'Value'],
            data: [
              ['Walking zone', hasZones ? '${fmt1(walk)}%' : 'No data'],
              ['Jogging zone', hasZones ? '${fmt1(jog)}%' : 'No data'],
              ['Running zone', hasZones ? '${fmt1(run)}%' : 'No data'],
              ['High-speed zone', hasZones ? '${fmt1(high)}%' : 'No data'],
              ['Sprinting zone', hasZones ? '${fmt1(spr)}%' : 'No data'],
              ['Work rate', hasWorkRate ? '${fmt1(workRate)} m/min' : 'No data'],
              ['Activity ratio', hasWorkRate ? '${(activity * 100).toStringAsFixed(0)}%' : 'No data'],
              ['Directional changes', hasWorkRate ? '${fmt1(dirChanges)} /min' : 'No data'],
            ],
          ),
          title('5. Tactical Heatmap'),
          _buildPdfHeatmapSection(),
          title('6. Best Match Records'),
          pw.Bullet(text: 'Best distance: ${bestDistKm.toStringAsFixed(2)} km'),
          pw.Bullet(text: 'Best average speed: ${fmt1(bestSpeed)} km/h'),
          pw.Bullet(text: 'Best sprints in one match: $bestSprints'),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildPdfHeatmapSection() {
    if (_heatmapCounts == null || _heatmapCounts!.isEmpty || _heatGridW <= 0 || _heatGridH <= 0) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF8FAFC),
          border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Text('No tactical heatmap data available.'),
      );
    }

    final raw = _heatmapCounts!;
    final srcH = raw.length;
    final srcW = raw.first.length;
    const outW = 36;
    const outH = 24;

    double sampleBilinear(double x, double y) {
      final x0 = x.floor().clamp(0, srcW - 1);
      final y0 = y.floor().clamp(0, srcH - 1);
      final x1 = (x0 + 1).clamp(0, srcW - 1);
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final dx = (x - x0).clamp(0.0, 1.0);
      final dy = (y - y0).clamp(0.0, 1.0);

      final v00 = (raw[y0][x0] is num) ? (raw[y0][x0] as num).toDouble() : 0.0;
      final v10 = (raw[y0][x1] is num) ? (raw[y0][x1] as num).toDouble() : 0.0;
      final v01 = (raw[y1][x0] is num) ? (raw[y1][x0] as num).toDouble() : 0.0;
      final v11 = (raw[y1][x1] is num) ? (raw[y1][x1] as num).toDouble() : 0.0;

      final top = v00 * (1 - dx) + v10 * dx;
      final bot = v01 * (1 - dx) + v11 * dx;
      return top * (1 - dy) + bot * dy;
    }

    final reduced = List.generate(outH, (_) => List.filled(outW, 0.0));
    for (int r = 0; r < outH; r++) {
      for (int c = 0; c < outW; c++) {
        final sx = (c / (outW - 1)) * (srcW - 1);
        final sy = (r / (outH - 1)) * (srcH - 1);
        reduced[r][c] = sampleBilinear(sx, sy);
      }
    }

    final smoothed = List.generate(outH, (_) => List.filled(outW, 0.0));
    for (int r = 0; r < outH; r++) {
      for (int c = 0; c < outW; c++) {
        double acc = 0;
        int n = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            final rr = r + dr;
            final cc = c + dc;
            if (rr < 0 || rr >= outH || cc < 0 || cc >= outW) continue;
            acc += reduced[rr][cc];
            n++;
          }
        }
        smoothed[r][c] = n > 0 ? (acc / n) : reduced[r][c];
      }
    }

    double maxVal = 0;
    for (final row in smoothed) {
      for (final v in row) {
        if (v > maxVal) maxVal = v;
      }
    }
    if (maxVal <= 0) maxVal = 1;

    return pw.Container(
      height: 180,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF8FAFC),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Center(
        child: pw.Container(
          width: 540,
          height: 350,
          child: pw.FittedBox(
            fit: pw.BoxFit.contain,
            child: pw.Container(
              width: 108,
              height: 72,
              child: pw.Stack(
                children: [
                  pw.Container(color: const PdfColor.fromInt(0xFF2E7D32)),
                  pw.Column(
                    children: [
                      for (int r = 0; r < outH; r++)
                        pw.Row(
                          children: [
                            for (int c = 0; c < outW; c++)
                              pw.Container(
                                width: 3,
                                height: 3,
                                color: _pdfHeatColor(smoothed[r][c] / maxVal),
                              ),
                          ],
                        ),
                    ],
                  ),
                  pw.Positioned(left: 1, top: 1, child: pw.Container(width: 106, height: 70, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.6)))),
                  pw.Positioned(left: 54, top: 1, child: pw.Container(width: 0.6, height: 70, color: const PdfColor.fromInt(0xCCFFFFFF))),
                  pw.Positioned(left: 47, top: 29, child: pw.Container(width: 14, height: 14, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.5), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7))))),
                  pw.Positioned(left: 1, top: 22, child: pw.Container(width: 17, height: 28, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.5)))),
                  pw.Positioned(left: 90, top: 22, child: pw.Container(width: 17, height: 28, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.5)))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PdfColor _pdfHeatColor(double t) {
    final v = t.clamp(0.0, 1.0);
    if (v < 0.2) return const PdfColor.fromInt(0xFF4CAF50);
    if (v < 0.4) return const PdfColor.fromInt(0xFF8BC34A);
    if (v < 0.6) return const PdfColor.fromInt(0xFFFFEB3B);
    if (v < 0.8) return const PdfColor.fromInt(0xFFFF9800);
    return const PdfColor.fromInt(0xFFF44336);
  }

  static double _dbl(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _intVal(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

// ── Movement Zones Bar Widget ────────────────────────────────────────────────

class _MovementZonesBar extends StatelessWidget {
  const _MovementZonesBar({required this.zones});

  final Map<String, dynamic> zones;

  static const _labels = ['Walking', 'Jogging', 'Running', 'High Speed', 'Sprinting'];
  static const _keys = ['walking', 'jogging', 'running', 'highSpeed', 'sprinting'];
  static const _colors = [
    Color(0xFF4CAF50),
    Color(0xFF8BC34A),
    Color(0xFFFFB300),
    Color(0xFFFF7043),
    Color(0xFFE53935),
  ];

  @override
  Widget build(BuildContext context) {
    final values = _keys.map((k) {
      final v = zones[k];
      return v is num ? v.toDouble() : 0.0;
    }).toList();
    final total = values.fold(0.0, (a, b) => a + b);
    final normalized = total > 0 ? values.map((v) => v / total).toList() : values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 20,
            child: Row(
              children: List.generate(_keys.length, (i) {
                final flex = (normalized[i] * 1000).round();
                if (flex == 0) return const SizedBox.shrink();
                return Expanded(flex: flex, child: Container(color: _colors[i]));
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: List.generate(_labels.length, (i) {
            final pct = total > 0 ? (values[i] / total * 100) : 0.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: _colors[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_labels[i]} ${pct.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

/// Renders a smooth Gaussian-blurred heatmap on a striped grass pitch
class _RealHeatmap extends StatelessWidget {
  const _RealHeatmap({
    required this.counts,
    required this.gridW,
    required this.gridH,
  });

  final List<dynamic> counts;
  final int gridW;
  final int gridH;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _PitchHeatmapPainter(counts: counts, gridW: gridW, gridH: gridH),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PitchHeatmapPainter extends CustomPainter {
  _PitchHeatmapPainter({required this.counts, required this.gridW, required this.gridH});

  final List<dynamic> counts;
  final int gridW;
  final int gridH;

  Color _heatColor(double t) {
    if (t < 0.2) return const Color(0xFF4CAF50);
    if (t < 0.4) return const Color(0xFF8BC34A);
    if (t < 0.6) return const Color(0xFFFFEB3B);
    if (t < 0.8) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bg = Paint()..color = const Color(0xFF2E7D32);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bg);

    if (gridW <= 0 || gridH <= 0 || counts.isEmpty) {
      _drawPitchLines(canvas, w, h);
      return;
    }

    double maxVal = 0;
    for (var r = 0; r < counts.length; r++) {
      final row = counts[r];
      if (row is! List) continue;
      for (final v in row) {
        final d = (v is num) ? v.toDouble() : 0.0;
        if (d > maxVal) maxVal = d;
      }
    }

    if (maxVal > 0) {
      final resX = (w / 4).ceil();
      final resY = (h / 4).ceil();
      final field = List.generate(resY, (_) => List.filled(resX, 0.0));

      final cellW = w / gridW;
      final cellH = h / gridH;
      final sigmaX = cellW * 1.8;
      final sigmaY = cellH * 1.8;

      for (var r = 0; r < gridH && r < counts.length; r++) {
        final rowData = counts[r];
        if (rowData is! List) continue;
        for (var c = 0; c < gridW && c < rowData.length; c++) {
          final v = (rowData[c] is num) ? (rowData[c] as num).toDouble() : 0.0;
          if (v <= 0) continue;
          final norm = v / maxVal;
          final cx = (c + 0.5) * cellW;
          final cy = (r + 0.5) * cellH;
          final fcx = cx / w * resX;
          final fcy = cy / h * resY;
          final fSigX = sigmaX / w * resX;
          final fSigY = sigmaY / h * resY;
          final rx = (fSigX * 3).ceil();
          final ry = (fSigY * 3).ceil();
          final minFx = (fcx - rx).floor().clamp(0, resX - 1);
          final maxFx = (fcx + rx).ceil().clamp(0, resX - 1);
          final minFy = (fcy - ry).floor().clamp(0, resY - 1);
          final maxFy = (fcy + ry).ceil().clamp(0, resY - 1);
          for (var fy = minFy; fy <= maxFy; fy++) {
            for (var fx = minFx; fx <= maxFx; fx++) {
              final dx = fx - fcx;
              final dy = fy - fcy;
              final g = math.exp(
                -(dx * dx) / (2 * fSigX * fSigX) - (dy * dy) / (2 * fSigY * fSigY),
              );
              field[fy][fx] += norm * g;
            }
          }
        }
      }

      double fieldMax = 0;
      for (final row in field) {
        for (final v in row) {
          if (v > fieldMax) fieldMax = v;
        }
      }
      if (fieldMax <= 0) fieldMax = 1;

      final pw = w / resX;
      final ph = h / resY;
      for (var fy = 0; fy < resY; fy++) {
        for (var fx = 0; fx < resX; fx++) {
          final v = field[fy][fx];
          if (v <= 0.01) continue;
          final t = (v / fieldMax).clamp(0.0, 1.0);
          if (t < 0.08) continue;
          final color = _heatColor(t).withValues(alpha: 0.35 + t * 0.55);
          canvas.drawRect(
            Rect.fromLTWH(fx * pw, fy * ph, pw + 0.5, ph + 0.5),
            Paint()..color = color,
          );
        }
      }
    }

    _drawPitchLines(canvas, w, h);
  }

  void _drawPitchLines(Canvas canvas, double w, double h) {
    final lp = Paint()
      ..color = const Color(0xBBFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(3, 3, w - 6, h - 6), lp);
    canvas.drawLine(Offset(w / 2, 3), Offset(w / 2, h - 3), lp);
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.16, lp);
    canvas.drawCircle(Offset(w / 2, h / 2), 3, Paint()..color = const Color(0xBBFFFFFF));
    canvas.drawRect(Rect.fromLTWH(3, h * 0.2, w * 0.17, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.17, h * 0.2, w * 0.17, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(3, h * 0.35, w * 0.07, h * 0.3), lp);
    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.07, h * 0.35, w * 0.07, h * 0.3), lp);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.17 + 3, h / 2), width: h * 0.16, height: h * 0.16),
      -0.6,
      1.2,
      false,
      lp,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w - w * 0.17 - 3, h / 2), width: h * 0.16, height: h * 0.16),
      math.pi - 0.6,
      1.2,
      false,
      lp,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchHeatmapPainter old) => false;
}

class _RealSpeedChart extends StatelessWidget {
  const _RealSpeedChart({required this.samples, this.height = 130});

  final List<SpeedSamplePoint> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SpeedChartPainter(samples: samples)),
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  _SpeedChartPainter({required this.samples});
  final List<SpeedSamplePoint> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final smoothed = <SpeedSamplePoint>[];
    const window = 3;
    for (int i = 0; i < samples.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = math.max(0, i - window); j <= math.min(samples.length - 1, i + window); j++) {
        sum += samples[j].kmh;
        count++;
      }
      smoothed.add(SpeedSamplePoint(t: samples[i].t, kmh: sum / count));
    }

    final tMin = smoothed.first.t;
    final tMax = smoothed.last.t;
    final tRange = tMax - tMin;
    if (tRange <= 0) return;

    double maxSpeed = 0;
    for (final s in smoothed) {
      if (s.kmh > maxSpeed) maxSpeed = s.kmh;
    }
    if (maxSpeed <= 0) maxSpeed = 1;
    maxSpeed *= 1.1;

    const padTop = 8.0;
    const padBottom = 4.0;
    final chartH = size.height - padTop - padBottom;

    final points = <Offset>[];
    for (final s in smoothed) {
      final x = ((s.t - tMin) / tRange) * size.width;
      final y = padTop + chartH * (1 - (s.kmh / maxSpeed).clamp(0.0, 1.0));
      points.add(Offset(x, y));
    }

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = padTop + chartH * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x551D63FF), Color(0x001D63FF)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cp1x = (points[i - 1].dx + points[i].dx) / 2;
      linePath.cubicTo(cp1x, points[i - 1].dy, cp1x, points[i].dy, points[i].dx, points[i].dy);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColors.primary.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.primary
        ..strokeCap = StrokeCap.round,
    );

    int peakIdx = 0;
    for (int i = 1; i < smoothed.length; i++) {
      if (smoothed[i].kmh > smoothed[peakIdx].kmh) peakIdx = i;
    }
    if (peakIdx < points.length) {
      canvas.drawCircle(points[peakIdx], 5, Paint()..color = AppColors.success);
      canvas.drawCircle(points[peakIdx], 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter old) => false;
}

class _PlayerRadarChartMatch extends StatelessWidget {
  const _PlayerRadarChartMatch({required this.stats});

  final FifaCardStats stats;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarMatchPainter(stats: stats),
      size: const Size(220, 220),
    );
  }
}

class _RadarMatchPainter extends CustomPainter {
  _RadarMatchPainter({required this.stats});

  final FifaCardStats stats;
  static const _labels = ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY'];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 28;
    final n = _labels.length;
    final step = 2 * math.pi / n;
    final values = [stats.pac, stats.sho, stats.pas, stats.dri, stats.def, stats.phy];
    const gridColor = Color(0x30FFFFFF);
    const accent = AppColors.primary;

    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + i * step;
        final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..color = gridColor);
    }

    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      canvas.drawLine(
        center,
        Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a)),
        Paint()..color = gridColor..strokeWidth = 0.8,
      );
    }

    final dp = Path();
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      final r = radius * (values[i] / 99).clamp(0.0, 1.0);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) {
        dp.moveTo(p.dx, p.dy);
      } else {
        dp.lineTo(p.dx, p.dy);
      }
    }
    dp.close();

    canvas.drawPath(dp, Paint()..style = PaintingStyle.fill..color = accent.withValues(alpha: 0.22));
    canvas.drawPath(dp, Paint()..style = PaintingStyle.stroke..color = accent..strokeWidth = 2.5);

    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      final r = radius * (values[i] / 99).clamp(0.0, 1.0);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      canvas.drawCircle(p, 4, Paint()..color = accent);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);

      final lo = Offset(center.dx + (radius + 20) * math.cos(a), center.dy + (radius + 20) * math.sin(a));
      final tp = TextPainter(
        text: TextSpan(
          text: '${_labels[i]}\n${values[i]}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lo.dx - tp.width / 2, lo.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarMatchPainter old) => old.stats.ovr != stats.ovr;
}

// ── KPI Bar Widget ────────────────────────────────────────────────────────────

class _KpiBar extends StatelessWidget {
  const _KpiBar({required this.label, required this.value});

  final String label;
  final double value; // 0.0 to 1.0

  Color _barColor() {
    if (value >= 0.75) return AppColors.success;
    if (value >= 0.45) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: _barColor(),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).round()}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: _barColor(),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
