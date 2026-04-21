import 'dart:math' as math;



import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;



import '../app/scoutai_app.dart';

import '../services/api_config.dart';

import '../services/auth_api.dart';

import '../services/auth_storage.dart';

import '../theme/app_colors.dart';

import '../widgets/fifa_card_stats.dart';

import '../services/translations.dart';

import '../widgets/legendary_player_card.dart';
import '../widgets/country_picker.dart';

import 'dart:typed_data';



class PlayerHomeTab extends StatefulWidget {

  const PlayerHomeTab({super.key});



  @override

  State<PlayerHomeTab> createState() => _PlayerHomeTabState();

}



class _PlayerHomeTabState extends State<PlayerHomeTab> {

  bool _loading = true;

  String? _error;

  Map<String, dynamic>? _me;

  List<dynamic> _videos = [];

  Map<String, dynamic> _stats = {};

  Uint8List? _portraitBytes;



  @override

  void initState() {

    super.initState();

    _load();

  }



  Future<void> _load() async {

    setState(() { _loading = true; _error = null; });

    final token = await AuthStorage.loadToken();

    if (!mounted) return;

    if (token == null) return;

    try {

      final me = await AuthApi().me(token);

      // Load videos for stats

      final vUri = Uri.parse('${ApiConfig.baseUrl}/me/videos');

      final vRes = await http.get(vUri, headers: {'Authorization': 'Bearer $token'});

      List<dynamic> videos = [];

      if (vRes.statusCode < 400) {

        final parsed = jsonDecode(vRes.body);

        if (parsed is List) videos = parsed;

      }

      // Load portrait silently

      Uint8List? portraitBytes;

      try {

        final pUri = Uri.parse('${ApiConfig.baseUrl}/me/portrait?ts=${DateTime.now().millisecondsSinceEpoch}');

        final pRes = await http.get(pUri, headers: {'Authorization': 'Bearer $token'});

        final ct = (pRes.headers['content-type'] ?? '').toLowerCase();

        if (pRes.statusCode < 400 && pRes.bodyBytes.isNotEmpty && ct.startsWith('image/')) {

          portraitBytes = pRes.bodyBytes;

        }

      } catch (_) {}

      if (!mounted) return;

      setState(() {

        _me = me;

        _videos = List<dynamic>.from(videos)..sort((a, b) {
          // Compute OVR for each video; -1 for unanalyzed (sorts to end)
          int extractOvr(dynamic x) {
            if (x is! Map) return -1;
            final la = x['lastAnalysis'];
            if (la is! Map) return -1;
            final metrics = la['metrics'] is Map
                ? Map<String, dynamic>.from(la['metrics'] as Map)
                : <String, dynamic>{};
            final positions = la['positions'] is List
                ? la['positions'] as List<dynamic>
                : <dynamic>[];
            return computeCardStats(metrics, positions).ovr;
          }
          return extractOvr(b).compareTo(extractOvr(a)); // highest OVR first
        });

        _stats = _computeStats(videos);

        _portraitBytes = portraitBytes;

        _loading = false;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });

    }

  }



  Future<void> _toggleVisibility(String videoId, String currentVisibility) async {

    final token = await AuthStorage.loadToken();

    if (token == null) return;

    final newVis = currentVisibility == 'private' ? 'public' : 'private';

    try {

      final res = await http.patch(

        Uri.parse('${ApiConfig.baseUrl}/me/videos/$videoId/visibility'),

        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},

        body: jsonEncode({'visibility': newVis}),

      );

      if (res.statusCode < 400) {

        // Update local video list

        for (int i = 0; i < _videos.length; i++) {

          if (_videos[i] is Map) {

            final v = _videos[i] as Map;

            if ((v['_id'] ?? v['id'])?.toString() == videoId) {

              _videos[i] = Map<String, dynamic>.from(v)..['visibility'] = newVis;

              break;

            }

          }

        }

        if (mounted) setState(() {});

        if (mounted) {

          ScaffoldMessenger.of(context).showSnackBar(

            SnackBar(

              content: Text('Video is now ${newVis == 'public' ? 'public' : 'private'}'),

              backgroundColor: newVis == 'public' ? const Color(0xFF00E676) : const Color(0xFFFF7043),

              duration: const Duration(seconds: 2),

            ),

          );

        }

      }

    } catch (_) {}

  }



  List<Map<String, dynamic>> _perVideo = [];



  // Aggregated heatmap from all videos

  List<List<double>>? _heatCounts;

  int _heatGridW = 0;

  int _heatGridH = 0;

  int _calibratedCount = 0;

  int _uncalibratedCount = 0;



  Map<String, dynamic> _computeStats(List<dynamic> videos) {

    double totalDist = 0;

    double maxSpeed = 0;

    int totalSprints = 0;

    int analyzed = 0;

    double totalAvgSpeed = 0;

    double totalDuration = 0;

    int totalAccelPeaks = 0;

    double bestDist = 0;

    double bestAvgSpeed = 0;

    int bestSprints = 0;

    final perVideo = <Map<String, dynamic>>[];



    // For aggregated heatmap

    List<List<double>>? mergedHeat;

    int hW = 0, hH = 0;

    int calCount = 0, uncalCount = 0;



    // Movement zones & work rate accumulators

    double sumWalkPct = 0, sumJogPct = 0, sumRunPct = 0, sumHighPct = 0, sumSprintPct = 0;

    int zonesCount = 0;

    double sumWorkRate = 0, sumMovingRatio = 0, sumDirChanges = 0;

    int workRateCount = 0;



    for (final v in videos) {

      if (v is! Map) continue;

      final a = v['lastAnalysis'];

      if (a is! Map) continue;

      analyzed++;

      final metrics = a['metrics'] is Map ? a['metrics'] as Map : a;

      final d = _toDouble(metrics['distanceKm'] ?? metrics['distance_km'] ?? metrics['distanceMeters']);

      final ms = _toDouble(metrics['maxSpeedKmh'] ?? metrics['max_speed_kmh'] ?? metrics['maxSpeed']).clamp(0.0, 45.0);

      final avgS = _toDouble(metrics['avgSpeedKmh'] ?? metrics['avg_speed_kmh'] ?? metrics['avgSpeed']).clamp(0.0, 45.0);

      final sp = _toInt(metrics['sprintCount'] ?? metrics['sprints']);

      final dur = _toDouble(metrics['durationSeconds'] ?? metrics['duration'] ?? 0);

      final accelList = metrics['accelPeaks'];

      final accelCount = accelList is List ? accelList.length : _toInt(accelList);



      // Extract heatmap grid + calibration status from this video's analysis

      final heatmap = metrics['heatmap'];

      String coordSpace = 'image';

      if (heatmap is Map) {

        coordSpace = (heatmap['coord_space'] as String?) ?? 'image';

        final counts = heatmap['counts'];

        final gw = _toInt(heatmap['grid_w']);

        final gh = _toInt(heatmap['grid_h']);

        if (counts is List && gw > 0 && gh > 0) {

          if (mergedHeat == null || hW != gw || hH != gh) {

            hW = gw;

            hH = gh;

            mergedHeat ??= List.generate(gh, (_) => List.filled(gw, 0.0));

          }

          for (var r = 0; r < gh && r < counts.length; r++) {

            final row = counts[r];

            if (row is! List) continue;

            for (var c = 0; c < gw && c < row.length; c++) {

              mergedHeat[r][c] += (row[c] is num) ? (row[c] as num).toDouble() : 0.0;

            }

          }

        }

      }

      final isCal = coordSpace == 'pitch' ||

          (metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null);

      if (isCal) { calCount++; } else { uncalCount++; }



      // Movement analytics extraction

      final movement = metrics['movement'];

      double qualityScore = 0;

      if (movement is Map) {

        final zones = movement['zones'];

        if (zones is Map) {

          sumWalkPct += _toDouble(zones['walking_pct']);

          sumJogPct += _toDouble(zones['jogging_pct']);

          sumRunPct += _toDouble(zones['running_pct']);

          sumHighPct += _toDouble(zones['highSpeed_pct']);

          sumSprintPct += _toDouble(zones['sprinting_pct']);

          zonesCount++;

        }

        final wr = _toDouble(movement['workRateMetersPerMin']);

        final mr = _toDouble(movement['movingRatio']);

        final dc = _toDouble(movement['dirChangesPerMin']);

        if (wr > 0 || mr > 0 || dc > 0) {

          sumWorkRate += wr;

          sumMovingRatio += mr;

          sumDirChanges += dc;

          workRateCount++;

        }

        qualityScore = _toDouble(movement['qualityScore']);

      }



      totalDist += d;

      if (ms > maxSpeed) maxSpeed = ms;

      totalSprints += sp;

      totalAvgSpeed += avgS > 0 ? avgS : ms * 0.6;

      totalDuration += dur;

      totalAccelPeaks += accelCount;

      if (d > bestDist) bestDist = d;

      if (avgS > bestAvgSpeed) bestAvgSpeed = avgS;

      if (sp > bestSprints) bestSprints = sp;



      perVideo.add({

        'name': (v['originalName'] ?? v['filename'] ?? 'Match $analyzed').toString(),

        'distance': d,

        'maxSpeed': ms,

        'avgSpeed': avgS > 0 ? avgS : ms * 0.6,

        'sprints': sp,

        'accelPeaks': accelCount,

        'hasAnalysis': true,

        'calibrated': isCal,

        'qualityScore': qualityScore,

      });

    }

    _perVideo = perVideo;

    _heatCounts = mergedHeat;

    _heatGridW = hW;

    _heatGridH = hH;

    _calibratedCount = calCount;

    _uncalibratedCount = uncalCount;



    final avgSpeed = analyzed > 0 ? totalAvgSpeed / analyzed : 0.0;

    final avgDistPerMatch = analyzed > 0 ? totalDist / analyzed : 0.0;

    final avgSprintsPerMatch = analyzed > 0 ? totalSprints / analyzed : 0.0;

    return {

      'totalDistance': totalDist,

      'maxSpeed': maxSpeed,

      'avgSpeed': avgSpeed,

      'avgDistPerMatch': avgDistPerMatch,

      'totalSprints': totalSprints,

      'avgSprintsPerMatch': avgSprintsPerMatch,

      'matchesAnalyzed': analyzed,

      'totalVideos': videos.length,

      'totalDuration': totalDuration,

      'totalAccelPeaks': totalAccelPeaks,

      'bestDistance': bestDist,

      'bestAvgSpeed': bestAvgSpeed,

      'bestSprints': bestSprints,

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

    };

  }



  double _toDouble(dynamic v) {

    if (v is num) return v.toDouble();

    if (v is String) return double.tryParse(v) ?? 0;

    return 0;

  }



  int _toInt(dynamic v) {

    if (v is int) return v;

    if (v is num) return v.round();

    if (v is String) return int.tryParse(v) ?? 0;

    return 0;

  }



  String _displayName() {

    final me = _me;

    if (me != null && me['displayName'] is String && (me['displayName'] as String).trim().isNotEmpty) {

      return (me['displayName'] as String).trim();

    }

    if (me != null && me['email'] is String) {

      final email = (me['email'] as String).trim();

      final at = email.indexOf('@');

      return at > 0 ? email.substring(0, at) : email;

    }

    return 'Player';

  }



  /// Compute FIFA card stats from the best-analyzed video.

  FifaCardStats _computeFifaStats(String posLabel) {

    FifaCardStats? best;

    for (final v in _videos) {

      if (v is! Map) continue;

      final a = v['lastAnalysis'];

      if (a is! Map) continue;

      final metrics = a['metrics'] is Map ? Map<String, dynamic>.from(a['metrics'] as Map) : <String, dynamic>{};

      final positions = a['positions'] is List ? a['positions'] as List<dynamic> : <dynamic>[];

      final stats = computeCardStats(metrics, positions, posLabel: posLabel);

      if (best == null || stats.ovr > best.ovr) {

        best = stats;

      }

    }

    return best ?? FifaCardStats.empty;

  }





  @override

  Widget build(BuildContext context) {

    if (_loading) {

      return const Center(child: CircularProgressIndicator());

    }

    if (_error != null) {

      return Center(

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            Text(_error!, style: const TextStyle(color: AppColors.danger)),

            const SizedBox(height: 12),

            OutlinedButton(onPressed: _load, child: Text(S.of(context).retry)),

          ],

        ),

      );

    }



    final position = (_me?['position'] as String?)?.toUpperCase() ?? 'CM';

    final nation = (_me?['nation'] as String?) ?? '';

    final fifaStats = _computeFifaStats(position);

    final displayName = _displayName();

    final analyzed = (_stats['matchesAnalyzed'] as int?) ?? 0;

    final topSpeed = (_stats['maxSpeed'] as num? ?? 0).toDouble();

    final avgSpeed = (_stats['avgSpeed'] as num? ?? 0).toDouble();

    final totalDist = (_stats['totalDistance'] as num? ?? 0).toDouble();

    final avgDist = (_stats['avgDistPerMatch'] as num? ?? 0).toDouble();



    return RefreshIndicator(

      onRefresh: _load,

      child: ListView(

        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),

        children: [

          // ═══════════ PLAYER CARD ═══════════

          LegendaryPlayerCard(

            name: displayName,

            stats: fifaStats,

            position: position,

            nation: nation,

            portraitBytes: _portraitBytes,

          ),

          const SizedBox(height: 16),

          // ═══════════ PRIVATE INFO CARD ═══════════

          _PrivateInfoCard(
            me: _me,
            fifaStats: fifaStats,
            onCompleteProfile: () async {
              final updated = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _CompleteProfileSheet(me: _me),
              );
              if (updated == true && mounted) _load();
            },
          ),

          const SizedBox(height: 24),



          // ═══════════ DATA QUALITY CHECK ═══════════

          if (_uncalibratedCount > 0 && analyzed > 0)

            Padding(

              padding: const EdgeInsets.only(bottom: 16),

              child: Container(

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(

                  color: const Color(0xFF2A2000),

                  borderRadius: BorderRadius.circular(14),

                  border: Border.all(color: const Color(0x50FFD740)),

                ),

                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  const Icon(Icons.warning_amber_rounded, color: _kGold, size: 20),

                  const SizedBox(width: 10),

                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    Text(

                      _calibratedCount > 0

                          ? '$_uncalibratedCount of $analyzed analyses uncalibrated'

                          : 'All analyses uncalibrated',

                      style: const TextStyle(color: _kGold, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),

                    ),

                    const SizedBox(height: 4),

                    const Text(

                      'Speed, distance, and heatmap data may be inaccurate. Use pitch calibration for reliable metrics.',

                      style: TextStyle(color: _kTextM, fontSize: 11, height: 1.3),

                    ),

                  ])),

                ]),

              ),

            ),



          // ═══════════ 1. PLAYER RADAR ═══════════

          _DashSection(icon: Icons.hexagon_outlined, title: 'PLAYER RADAR'),

          const SizedBox(height: 10),

          _DashCard(

            child: Column(children: [

              SizedBox(height: 220, width: 220, child: _PlayerRadarChart(stats: fifaStats)),

              const SizedBox(height: 8),

              Container(

                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),

                decoration: BoxDecoration(

                  color: _kAccent,

                  borderRadius: BorderRadius.circular(20),

                ),

                child: Text('OVR ${fifaStats.ovr}',

                  style: const TextStyle(color: _kTextW, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),

              ),

            ]),

          ),

          const SizedBox(height: 20),



          // ═══════════ 2. MATCH READINESS ═══════════

          _DashSection(icon: Icons.flash_on, title: 'MATCH READINESS'),

          const SizedBox(height: 10),

          Row(children: [

            // Mental circular

            Expanded(child: _DashCard(

              child: Column(children: [

                const SizedBox(height: 4),

                SizedBox(

                  height: 90, width: 90,

                  child: CustomPaint(painter: _MentalRingPainter(

                    pct: analyzed > 0 ? (fifaStats.ovr / 99).clamp(0.0, 1.0) : 0.0,

                  )),

                ),

                const SizedBox(height: 8),

                const Text('MENTAL', style: TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),

              ]),

            )),

            const SizedBox(width: 10),

            // Morale trend line chart

            Expanded(child: _DashCard(

              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const Text('MORALE TREND', style: TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),

                const SizedBox(height: 8),

                SizedBox(

                  height: 80, width: double.infinity,

                  child: CustomPaint(painter: _MoraleTrendPainter(perVideo: _perVideo)),

                ),

              ]),

            )),

          ]),

          const SizedBox(height: 20),



          // ═══════════ 3. TACTICAL HEATMAP ═══════════

          _DashSection(icon: Icons.grid_on, title: 'TACTICAL HEATMAP'),

          const SizedBox(height: 10),

          _DashCard(

            child: Column(children: [

              if (_heatCounts != null && _heatGridW > 0 && _heatGridH > 0)

                ClipRRect(

                  borderRadius: BorderRadius.circular(12),

                  child: AspectRatio(

                    aspectRatio: _heatGridW / _heatGridH,

                    child: CustomPaint(painter: _RealPitchHeatmapPainter(

                      counts: _heatCounts!, gridW: _heatGridW, gridH: _heatGridH,

                    )),

                  ),

                )

              else

                SizedBox(

                  height: 180, width: double.infinity,

                  child: CustomPaint(painter: _FallbackPitchPainter(position: position)),

                ),

              const SizedBox(height: 8),

              Text(

                _heatCounts != null ? 'AGGREGATED FROM $analyzed MATCHES' : 'PREFERRED ZONES',

                style: const TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),

              ),

            ]),

          ),

          const SizedBox(height: 20),



          // ═══════════ 4. SPEED & DISTANCE ═══════════

          _DashSection(icon: Icons.speed, title: 'SPEED & DISTANCE'),

          const SizedBox(height: 10),

          Row(children: [

            _SpeedDistCard(icon: Icons.flash_on, label: 'Top Speed', value: '${topSpeed.toStringAsFixed(1)} km/h', iconColor: _kGreen),

            const SizedBox(width: 10),

            _SpeedDistCard(icon: Icons.map, label: 'Total Distance', value: '${totalDist.toStringAsFixed(1)} m', iconColor: _kAccent),

          ]),

          const SizedBox(height: 10),

          Row(children: [

            _SpeedDistCard(icon: Icons.trending_up, label: 'Avg Speed', value: '${avgSpeed.toStringAsFixed(1)} km/h', iconColor: const Color(0xFFFFA726)),

            const SizedBox(width: 10),

            _SpeedDistCard(icon: Icons.straighten, label: 'Avg Dist/Match', value: '${avgDist.toStringAsFixed(1)} m', iconColor: _kAccent),

          ]),

          const SizedBox(height: 20),



          // ═══════════ 4b. MOVEMENT ZONES ═══════════

          Builder(builder: (_) {

            final hasReal = _stats['hasZones'] == true;

            final walk = hasReal ? (_stats['avgWalkPct'] as num? ?? 0).toDouble() : 35.0;

            final jog  = hasReal ? (_stats['avgJogPct']  as num? ?? 0).toDouble() : 28.0;

            final run  = hasReal ? (_stats['avgRunPct']  as num? ?? 0).toDouble() : 20.0;

            final high = hasReal ? (_stats['avgHighPct'] as num? ?? 0).toDouble() : 12.0;

            final spr  = hasReal ? (_stats['avgSprintPct'] as num? ?? 0).toDouble() : 5.0;

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              _DashSection(icon: Icons.directions_run, title: 'MOVEMENT ZONES'),

              const SizedBox(height: 10),

              _DashCard(

                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  ClipRRect(

                    borderRadius: BorderRadius.circular(8),

                    child: SizedBox(

                      height: 28,

                      child: Row(children: [

                        if (walk > 0) Flexible(flex: (walk * 10).round().clamp(1, 1000), child: Container(color: const Color(0xFF78909C))),

                        if (jog > 0)  Flexible(flex: (jog * 10).round().clamp(1, 1000),  child: Container(color: const Color(0xFF26C6DA))),

                        if (run > 0)  Flexible(flex: (run * 10).round().clamp(1, 1000),  child: Container(color: const Color(0xFF66BB6A))),

                        if (high > 0) Flexible(flex: (high * 10).round().clamp(1, 1000), child: Container(color: const Color(0xFFFFA726))),

                        if (spr > 0)  Flexible(flex: (spr * 10).round().clamp(1, 1000),  child: Container(color: const Color(0xFFEF5350))),

                      ]),

                    ),

                  ),

                  const SizedBox(height: 14),

                  Wrap(spacing: 16, runSpacing: 8, children: [

                    _ZoneLegend(color: const Color(0xFF78909C), label: 'Walk', pct: walk),

                    _ZoneLegend(color: const Color(0xFF26C6DA), label: 'Jog', pct: jog),

                    _ZoneLegend(color: const Color(0xFF66BB6A), label: 'Run', pct: run),

                    _ZoneLegend(color: const Color(0xFFFFA726), label: 'High', pct: high),

                    _ZoneLegend(color: const Color(0xFFEF5350), label: 'Sprint', pct: spr),

                  ]),

                  if (!hasReal) ...[

                    const SizedBox(height: 10),

                    Container(

                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

                      decoration: BoxDecoration(color: const Color(0x20FFD740), borderRadius: BorderRadius.circular(8)),

                      child: const Row(mainAxisSize: MainAxisSize.min, children: [

                        Icon(Icons.info_outline, size: 13, color: Color(0xFFFFD740)),

                        SizedBox(width: 6),

                        Text('Demo data — calibrate pitch for real zones', style: TextStyle(color: Color(0xFFFFD740), fontSize: 10, fontWeight: FontWeight.w600)),

                      ]),

                    ),

                  ],

                ]),

              ),

              const SizedBox(height: 20),

            ]);

          }),



          // ═══════════ 4c. WORK RATE & INTENSITY ═══════════

          Builder(builder: (_) {

            final hasReal = _stats['hasWorkRate'] == true;

            final wr = hasReal ? (_stats['avgWorkRate'] as num? ?? 0).toDouble() : 85.2;

            final mr = hasReal ? (_stats['avgMovingRatio'] as num? ?? 0).toDouble() : 0.72;

            final dc = hasReal ? (_stats['avgDirChanges'] as num? ?? 0).toDouble() : 8.4;

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              _DashSection(icon: Icons.local_fire_department, title: 'WORK RATE & INTENSITY'),

              const SizedBox(height: 10),

              Row(children: [

                _SpeedDistCard(icon: Icons.directions_run, label: 'Work Rate', value: '${wr.toStringAsFixed(1)} m/min', iconColor: const Color(0xFFFF7043)),

                const SizedBox(width: 10),

                _SpeedDistCard(icon: Icons.directions_walk, label: 'Activity', value: '${(mr * 100).toStringAsFixed(0)}%', iconColor: const Color(0xFF26C6DA)),

              ]),

              const SizedBox(height: 10),

              Row(children: [

                _SpeedDistCard(icon: Icons.swap_calls, label: 'Dir. Changes', value: '${dc.toStringAsFixed(1)} /min', iconColor: const Color(0xFFAB47BC)),

                const SizedBox(width: 10),

                Expanded(child: Container()),

              ]),

              if (!hasReal) ...[

                const SizedBox(height: 8),

                Container(

                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

                  decoration: BoxDecoration(color: const Color(0x20FFD740), borderRadius: BorderRadius.circular(8)),

                  child: const Row(mainAxisSize: MainAxisSize.min, children: [

                    Icon(Icons.info_outline, size: 13, color: Color(0xFFFFD740)),

                    SizedBox(width: 6),

                    Text('Demo data — calibrate pitch for real metrics', style: TextStyle(color: Color(0xFFFFD740), fontSize: 10, fontWeight: FontWeight.w600)),

                  ]),

                ),

              ],

              const SizedBox(height: 20),

            ]);

          }),



          // ═══════════ 5. BEST RECORDS ═══════════

          if (analyzed > 0) ...[

            _DashSection(icon: Icons.emoji_events, title: 'BEST RECORDS'),

            const SizedBox(height: 10),

            SingleChildScrollView(

              scrollDirection: Axis.horizontal,

              child: Row(children: [

                _GoldRecordChip(label: 'BEST SPEED', value: '${topSpeed.toStringAsFixed(1)} km/h'),

                const SizedBox(width: 10),

                _GoldRecordChip(label: 'BEST DISTANCE', value: '${(_stats['bestDistance'] as num? ?? 0).toStringAsFixed(0)} m'),

                const SizedBox(width: 10),

                _GoldRecordChip(label: 'BEST SPRINTS', value: '${_stats['bestSprints'] ?? 0} in match'),

                const SizedBox(width: 10),

                _GoldRecordChip(label: 'BEST AVG SPEED', value: '${(_stats['bestAvgSpeed'] as num? ?? 0).toStringAsFixed(1)} km/h'),

              ]),

            ),

            const SizedBox(height: 20),

          ],



          // ═══════════ MATCH BREAKDOWN (sorted by best performance) ═══════════

          _DashSection(icon: Icons.table_chart, title: 'MATCH BREAKDOWN'),

          const SizedBox(height: 10),

          if (_videos.isEmpty)

            _DashCard(

              child: Text(

                S.of(context).noVideosYetTap,

                style: const TextStyle(color: _kTextM),

              ),

            )

          else

            for (int i = 0; i < _videos.length; i++) ...[

              _RecentVideoTile(

                video: _videos[i] is Map ? Map<String, dynamic>.from(_videos[i] as Map) : {},

                onTap: () {

                  final v = _videos[i] is Map ? Map<String, dynamic>.from(_videos[i] as Map) : <String, dynamic>{};

                  final videoId = v['_id']?.toString();

                  if (videoId == null) return;

                  final hasAnalysis = v['lastAnalysis'] is Map;

                  if (hasAnalysis) {

                    final analysis = Map<String, dynamic>.from(v['lastAnalysis'] as Map);

                    analysis['_videoId'] = videoId;

                    Navigator.of(context).pushNamed(

                      AppRoutes.details,

                      arguments: analysis,

                    );

                  } else {

                    // For tagged videos without analysis, go to identify player flow

                    Navigator.of(context).pushNamed(

                      AppRoutes.identifyPlayer,

                      arguments: videoId,

                    );

                  }

                },

                onToggleVisibility: () {

                  final v = _videos[i] is Map ? Map<String, dynamic>.from(_videos[i] as Map) : <String, dynamic>{};

                  final videoId = (v['_id'] ?? v['id'])?.toString();

                  if (videoId == null) return;

                  final currentVis = (v['visibility'] ?? 'public').toString();

                  _toggleVisibility(videoId, currentVis);

                },

              ),

              const SizedBox(height: 8),

            ],

        ],

      ),

    );

  }

}



// ═══════════════════════════════════════════════════════

// DASHBOARD HELPER WIDGETS

// ═══════════════════════════════════════════════════════



const _kCard = Color(0xFF151B2D);

const _kAccent = Color(0xFF2979FF);

const _kGreen = Color(0xFF00E676);

const _kGold = Color(0xFFFFD740);

const _kTextW = Colors.white;

const _kTextM = Color(0xFF8899AA);



// ── Section header ──

class _DashSection extends StatelessWidget {

  const _DashSection({required this.icon, required this.title});

  final IconData icon;

  final String title;



  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 2),

      child: Row(children: [

        Icon(icon, size: 16, color: _kAccent),

        const SizedBox(width: 8),

        Text(title, style: const TextStyle(color: _kTextW, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.6)),

      ]),

    );

  }

}



// ── Dark card container ──

class _DashCard extends StatelessWidget {

  const _DashCard({required this.child});

  final Widget child;



  @override

  Widget build(BuildContext context) {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(

        color: _kCard,

        borderRadius: BorderRadius.circular(16),

      ),

      child: child,

    );

  }

}



// ── Radar chart ──

class _PlayerRadarChart extends StatelessWidget {

  const _PlayerRadarChart({required this.stats});

  final FifaCardStats stats;



  @override

  Widget build(BuildContext context) {

    return CustomPaint(

      painter: _RadarPainter(stats: stats),

      size: const Size(220, 220),

    );

  }

}



class _RadarPainter extends CustomPainter {

  _RadarPainter({required this.stats});

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



    // Grid rings

    for (var ring = 1; ring <= 4; ring++) {

      final r = radius * ring / 4;

      final path = Path();

      for (var i = 0; i < n; i++) {

        final a = -math.pi / 2 + i * step;

        final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

        if (i == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }

      }

      path.close();

      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..color = gridColor);

    }

    // Axes

    for (var i = 0; i < n; i++) {

      final a = -math.pi / 2 + i * step;

      canvas.drawLine(center, Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a)),

        Paint()..color = gridColor..strokeWidth = 0.8);

    }

    // Data polygon

    final dp = Path();

    for (var i = 0; i < n; i++) {

      final a = -math.pi / 2 + i * step;

      final r = radius * (values[i] / 99).clamp(0.0, 1.0);

      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

      if (i == 0) { dp.moveTo(p.dx, p.dy); } else { dp.lineTo(p.dx, p.dy); }

    }

    dp.close();

    canvas.drawPath(dp, Paint()..style = PaintingStyle.fill..color = _kAccent.withValues(alpha: 0.22));

    canvas.drawPath(dp, Paint()..style = PaintingStyle.stroke..color = _kAccent..strokeWidth = 2.5);

    // Dots + labels

    for (var i = 0; i < n; i++) {

      final a = -math.pi / 2 + i * step;

      final r = radius * (values[i] / 99).clamp(0.0, 1.0);

      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

      canvas.drawCircle(p, 4, Paint()..color = _kAccent);

      canvas.drawCircle(p, 2, Paint()..color = Colors.white);

      final lo = Offset(center.dx + (radius + 20) * math.cos(a), center.dy + (radius + 20) * math.sin(a));

      final tp = TextPainter(

        text: TextSpan(text: '${_labels[i]}\n${values[i]}',

          style: const TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w800, height: 1.3)),

        textAlign: TextAlign.center, textDirection: TextDirection.ltr,

      )..layout();

      tp.paint(canvas, Offset(lo.dx - tp.width / 2, lo.dy - tp.height / 2));

    }

  }



  @override

  bool shouldRepaint(covariant _RadarPainter old) => old.stats.ovr != stats.ovr;

}



// ── Mental ring (circular progress) ──

class _MentalRingPainter extends CustomPainter {

  _MentalRingPainter({required this.pct});

  final double pct;



  @override

  void paint(Canvas canvas, Size size) {

    final center = Offset(size.width / 2, size.height / 2);

    final r = math.min(size.width, size.height) / 2 - 6;

    // Background ring

    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = const Color(0x20FFFFFF));

    // Progress arc

    final sweep = 2 * math.pi * pct;

    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, sweep, false,

      Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = _kGreen);

    // Percentage text

    final pctText = '${(pct * 100).round()}%';

    final tp = TextPainter(

      text: TextSpan(text: pctText, style: const TextStyle(color: _kGreen, fontSize: 22, fontWeight: FontWeight.w900)),

      textDirection: TextDirection.ltr,

    )..layout();

    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

  }



  @override

  bool shouldRepaint(covariant _MentalRingPainter old) => old.pct != pct;

}



// ── Morale trend line chart ──

class _MoraleTrendPainter extends CustomPainter {

  _MoraleTrendPainter({required this.perVideo});

  final List<Map<String, dynamic>> perVideo;



  @override

  void paint(Canvas canvas, Size size) {

    // Build normalized scores from per-video data

    final scores = <double>[];

    for (final v in perVideo) {

      final d = (v['distance'] as num? ?? 0).toDouble();

      final s = (v['maxSpeed'] as num? ?? 0).toDouble();

      scores.add((d + s).clamp(0.0, 200.0) / 200.0);

    }

    if (scores.isEmpty) {

      scores.addAll([0.3, 0.5, 0.7]);

    }



    final w = size.width;

    final h = size.height;

    final n = scores.length;



    // Grid lines

    for (var i = 0; i < 4; i++) {

      final y = h * i / 3;

      canvas.drawLine(Offset(0, y), Offset(w, y), Paint()..color = const Color(0x15FFFFFF));

    }

    // X-axis labels

    for (var i = 0; i < n; i++) {

      final x = n == 1 ? w / 2 : w * i / (n - 1);

      final tp = TextPainter(

        text: TextSpan(text: '${i + 1}', style: const TextStyle(color: Color(0x60FFFFFF), fontSize: 8)),

        textDirection: TextDirection.ltr,

      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, h - tp.height));

    }



    // Line path

    final path = Path();

    final pts = <Offset>[];

    for (var i = 0; i < n; i++) {

      final x = n == 1 ? w / 2 : w * i / (n - 1);

      final y = (h - 14) * (1 - scores[i]) + 2;

      pts.add(Offset(x, y));

      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }

    }

    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..color = _kGreen..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);

    // Fill below

    final fill = Path.from(path)..lineTo(pts.last.dx, h)..lineTo(pts.first.dx, h)..close();

    canvas.drawPath(fill, Paint()..shader = const LinearGradient(

      begin: Alignment.topCenter, end: Alignment.bottomCenter,

      colors: [Color(0x4000E676), Color(0x0000E676)],

    ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // Dots

    for (final p in pts) {

      canvas.drawCircle(p, 3, Paint()..color = _kGreen);

    }

  }



  @override

  bool shouldRepaint(covariant _MoraleTrendPainter old) => true;

}



// ── Real heatmap on a pitch – smooth Gaussian style ──

class _RealPitchHeatmapPainter extends CustomPainter {

  _RealPitchHeatmapPainter({required this.counts, required this.gridW, required this.gridH});

  final List<List<double>> counts;

  final int gridW;

  final int gridH;



  // Professional heatmap spectrum: green → cyan → blue → yellow → orange → red

  static const _spectrum = [

    Color(0xFF1B8A2F), // 0.0  dark green (pitch)

    Color(0xFF2DB84B), // 0.1  green

    Color(0xFF7FD858), // 0.2  lime

    Color(0xFFCCF03D), // 0.3  yellow-green

    Color(0xFFFFFF00), // 0.4  yellow

    Color(0xFFFFD200), // 0.5  gold

    Color(0xFFFF9800), // 0.6  orange

    Color(0xFFFF5722), // 0.7  deep orange

    Color(0xFFE91E1E), // 0.8  red

    Color(0xFFB71C1C), // 0.9  dark red

    Color(0xFF880E0E), // 1.0  deep red

  ];



  Color _heatColor(double t) {

    final clamped = t.clamp(0.0, 1.0);

    final idx = clamped * (_spectrum.length - 1);

    final lo = idx.floor().clamp(0, _spectrum.length - 2);

    final frac = idx - lo;

    return Color.lerp(_spectrum[lo], _spectrum[lo + 1], frac)!;

  }



  @override

  void paint(Canvas canvas, Size size) {

    final w = size.width;

    final h = size.height;



    // ── Grass background with stripes ──

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E7D32));

    final stripeCount = 12;

    for (var i = 0; i < stripeCount; i++) {

      if (i.isEven) continue;

      final sw = w / stripeCount;

      canvas.drawRect(

        Rect.fromLTWH(i * sw, 0, sw, h),

        Paint()..color = const Color(0xFF388E3C),

      );

    }



    // ── Build smooth heat field ──

    // Upsample grid to a pixel-level density map using Gaussian splats

    double maxVal = 0;

    for (final row in counts) {

      for (final v in row) {

        if (v > maxVal) maxVal = v;

      }

    }

    if (maxVal <= 0) {

      _drawPitchLines(canvas, w, h);

      return;

    }



    // Resolution for the smooth map (higher = smoother but slower)

    final resX = (w / 4).ceil();

    final resY = (h / 4).ceil();

    final field = List.generate(resY, (_) => List.filled(resX, 0.0));



    final cellW = w / gridW;

    final cellH = h / gridH;

    // Gaussian radius in pixels

    final sigmaX = cellW * 1.8;

    final sigmaY = cellH * 1.8;



    // For each grid cell with data, splat a Gaussian into the field

    for (var r = 0; r < gridH && r < counts.length; r++) {

      for (var c = 0; c < gridW && c < counts[r].length; c++) {

        final v = counts[r][c];

        if (v <= 0) continue;

        final norm = v / maxVal;

        // Center of this grid cell in pixel coords

        final cx = (c + 0.5) * cellW;

        final cy = (r + 0.5) * cellH;

        // Map to field coords

        final fcx = cx / w * resX;

        final fcy = cy / h * resY;

        final fSigX = sigmaX / w * resX;

        final fSigY = sigmaY / h * resY;

        // Splat radius (3 sigma)

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

            final g = math.exp(-(dx * dx) / (2 * fSigX * fSigX) - (dy * dy) / (2 * fSigY * fSigY));

            field[fy][fx] += norm * g;

          }

        }

      }

    }



    // Find max in field for normalization

    double fieldMax = 0;

    for (final row in field) {

      for (final v in row) {

        if (v > fieldMax) fieldMax = v;

      }

    }

    if (fieldMax <= 0) fieldMax = 1;



    // ── Render smooth heat pixels ──

    final pw = w / resX;

    final ph = h / resY;

    for (var fy = 0; fy < resY; fy++) {

      for (var fx = 0; fx < resX; fx++) {

        final v = field[fy][fx];

        if (v <= 0.01) continue;

        final t = (v / fieldMax).clamp(0.0, 1.0);

        // Threshold: only show heat above 8% to keep pitch visible

        if (t < 0.08) continue;

        final color = _heatColor(t).withValues(alpha: 0.35 + t * 0.55);

        canvas.drawRect(

          Rect.fromLTWH(fx * pw, fy * ph, pw + 0.5, ph + 0.5),

          Paint()..color = color,

        );

      }

    }



    // ── Pitch lines on top ──

    _drawPitchLines(canvas, w, h);

  }



  void _drawPitchLines(Canvas canvas, double w, double h) {

    final lp = Paint()

      ..color = const Color(0xBBFFFFFF)

      ..style = PaintingStyle.stroke

      ..strokeWidth = 1.5;

    // Outline

    canvas.drawRect(Rect.fromLTWH(3, 3, w - 6, h - 6), lp);

    // Center line

    canvas.drawLine(Offset(w / 2, 3), Offset(w / 2, h - 3), lp);

    // Center circle

    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.16, lp);

    // Center dot

    canvas.drawCircle(Offset(w / 2, h / 2), 3, Paint()..color = const Color(0xBBFFFFFF));

    // Penalty areas

    canvas.drawRect(Rect.fromLTWH(3, h * 0.2, w * 0.17, h * 0.6), lp);

    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.17, h * 0.2, w * 0.17, h * 0.6), lp);

    // Goal areas

    canvas.drawRect(Rect.fromLTWH(3, h * 0.35, w * 0.07, h * 0.3), lp);

    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.07, h * 0.35, w * 0.07, h * 0.3), lp);

    // Penalty arcs (simplified as small arcs)

    canvas.drawArc(

      Rect.fromCenter(center: Offset(w * 0.17 + 3, h / 2), width: h * 0.16, height: h * 0.16),

      -0.6, 1.2, false, lp,

    );

    canvas.drawArc(

      Rect.fromCenter(center: Offset(w - w * 0.17 - 3, h / 2), width: h * 0.16, height: h * 0.16),

      math.pi - 0.6, 1.2, false, lp,

    );

  }



  @override

  bool shouldRepaint(covariant _RealPitchHeatmapPainter old) => false;

}



// ── Fallback pitch (no heatmap data yet) ──

class _FallbackPitchPainter extends CustomPainter {

  _FallbackPitchPainter({required this.position});

  final String position;



  @override

  void paint(Canvas canvas, Size size) {

    final w = size.width;

    final h = size.height;

    canvas.drawRRect(

      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)),

      Paint()..color = const Color(0xFF1B5E20),

    );

    canvas.clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)));

    final lp = Paint()..color = const Color(0x60FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.2;

    canvas.drawRect(Rect.fromLTWH(4, 4, w - 8, h - 8), lp);

    canvas.drawLine(Offset(w / 2, 4), Offset(w / 2, h - 4), lp);

    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.18, lp);

    canvas.drawRect(Rect.fromLTWH(4, h * 0.2, w * 0.16, h * 0.6), lp);

    canvas.drawRect(Rect.fromLTWH(w - 4 - w * 0.16, h * 0.2, w * 0.16, h * 0.6), lp);

    canvas.drawRect(Rect.fromLTWH(4, h * 0.35, w * 0.07, h * 0.3), lp);

    canvas.drawRect(Rect.fromLTWH(w - 4 - w * 0.07, h * 0.35, w * 0.07, h * 0.3), lp);



    // "No data" text

    final tp = TextPainter(

      text: const TextSpan(text: 'No heatmap data yet', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),

      textDirection: TextDirection.ltr,

    )..layout();

    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h / 2 - tp.height / 2));

  }



  @override

  bool shouldRepaint(covariant _FallbackPitchPainter old) => false;

}



// ── Recent video tile ──

class _RecentVideoTile extends StatelessWidget {

  const _RecentVideoTile({required this.video, this.onTap, this.onToggleVisibility});

  final Map<String, dynamic> video;

  final VoidCallback? onTap;

  final VoidCallback? onToggleVisibility;



  double _extractQuality(Map<String, dynamic> v) {

    final a = v['lastAnalysis'];

    if (a is! Map) return 0;

    final m = a['metrics'];

    if (m is! Map) return 0;

    final mov = m['movement'];

    if (mov is! Map) return 0;

    return (mov['qualityScore'] as num?)?.toDouble() ?? 0;

  }

  int _extractOvr(Map<String, dynamic> v) {
    final a = v['lastAnalysis'];
    if (a is! Map) return -1;
    final metrics = a['metrics'] is Map
        ? Map<String, dynamic>.from(a['metrics'] as Map)
        : <String, dynamic>{};
    final positions = a['positions'] is List
        ? a['positions'] as List<dynamic>
        : <dynamic>[];
    return computeCardStats(metrics, positions).ovr;
  }

  String _formatAnalysisTime(Map<String, dynamic> v) {
    final raw = v['lastAnalysisAt'] ?? v['updatedAt'];
    if (raw == null) return '';
    DateTime? dt;
    try { dt = DateTime.parse(raw.toString()).toLocal(); } catch (_) { return ''; }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }



  @override

  Widget build(BuildContext context) {

    final name = (video['originalName'] ?? video['filename'] ?? 'Video').toString();

    final hasAnalysis = video['lastAnalysis'] is Map;

    final isTagged = video['isTagged'] == true;

    final uploaderName = (video['uploaderName'] ?? '').toString();

    final visibility = (video['visibility'] ?? 'public').toString();

    final isPrivate = visibility == 'private';

    final quality = _extractQuality(video);



    // Subtitle logic

    String subtitle;

    if (isTagged && !hasAnalysis) {

      subtitle = 'Tap to analyze yourself';

    } else if (hasAnalysis) {

      subtitle = 'Tap to view results';

    } else {

      subtitle = 'Tap to start analysis';

    }



    // Status badge

    final String statusLabel;

    final Color statusColor;

    if (isTagged && !hasAnalysis) {

      statusLabel = 'Not analyzed';

      statusColor = const Color(0xFFFFA726);

    } else if (hasAnalysis) {

      statusLabel = 'Analyzed';

      statusColor = _kGreen;

    } else {

      statusLabel = 'Pending';

      statusColor = _kAccent;

    }



    return GestureDetector(

      onTap: onTap,

      child: Container(

        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

        decoration: BoxDecoration(

          color: _kCard,

          borderRadius: BorderRadius.circular(14),

          border: isTagged ? Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3), width: 1) : null,

        ),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(children: [

              Container(

                height: 38, width: 38,

                decoration: BoxDecoration(

                  color: const Color(0xFF1E2A40),

                  borderRadius: BorderRadius.circular(10),

                ),

                child: Icon(

                  isTagged ? Icons.person_pin : (hasAnalysis ? Icons.analytics_outlined : Icons.videocam),

                  color: isTagged ? const Color(0xFF8B5CF6) : (hasAnalysis ? _kGreen : _kAccent),

                  size: 18,

                ),

              ),

              const SizedBox(width: 12),

              Expanded(

                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  Text(name, overflow: TextOverflow.ellipsis,

                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _kTextW)),

                  const SizedBox(height: 3),

                  Text(subtitle, style: const TextStyle(color: _kTextM, fontSize: 11)),

                ]),

              ),

              if (hasAnalysis) ...[_QualityBadge(score: quality > 0 ? quality : 0.65), const SizedBox(width: 6)],

              Container(

                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

                decoration: BoxDecoration(

                  color: statusColor.withValues(alpha: 0.15),

                  borderRadius: BorderRadius.circular(8),

                ),

                child: Text(statusLabel,

                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),

              ),

              const SizedBox(width: 4),

              const Icon(Icons.chevron_right, color: _kTextM, size: 18),

            ]),

            // OVR + analysis time row (analyzed videos only)
            if (hasAnalysis) ...[
              const SizedBox(height: 7),
              Row(children: [
                const Icon(Icons.stars_rounded, size: 12, color: _kAccent),
                const SizedBox(width: 4),
                Text(
                  'OVR ${_extractOvr(video)}',
                  style: const TextStyle(fontSize: 11, color: _kAccent, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (_formatAnalysisTime(video).isNotEmpty) ...[
                  const Icon(Icons.access_time, size: 11, color: _kTextM),
                  const SizedBox(width: 3),
                  Text(
                    _formatAnalysisTime(video),
                    style: const TextStyle(fontSize: 11, color: _kTextM),
                  ),
                ],
              ]),
            ],

            // Tagged video info row

            if (isTagged) ...[

              const SizedBox(height: 8),

              Row(children: [

                // "Tagged" badge

                Container(

                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),

                  decoration: BoxDecoration(

                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),

                    borderRadius: BorderRadius.circular(6),

                  ),

                  child: Row(mainAxisSize: MainAxisSize.min, children: [

                    const Icon(Icons.sell, size: 10, color: Color(0xFF8B5CF6)),

                    const SizedBox(width: 4),

                    Text('Tagged by $uploaderName',

                      style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 9, fontWeight: FontWeight.w700)),

                  ]),

                ),

                const SizedBox(width: 8),

                // Visibility toggle

                GestureDetector(

                  onTap: onToggleVisibility,

                  child: Container(

                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),

                    decoration: BoxDecoration(

                      color: (isPrivate ? const Color(0xFFFF7043) : _kGreen).withValues(alpha: 0.15),

                      borderRadius: BorderRadius.circular(6),

                    ),

                    child: Row(mainAxisSize: MainAxisSize.min, children: [

                      Icon(isPrivate ? Icons.lock_outline : Icons.public, size: 10,

                        color: isPrivate ? const Color(0xFFFF7043) : _kGreen),

                      const SizedBox(width: 4),

                      Text(isPrivate ? 'Private' : 'Public',

                        style: TextStyle(

                          color: isPrivate ? const Color(0xFFFF7043) : _kGreen,

                          fontSize: 9, fontWeight: FontWeight.w700)),

                    ]),

                  ),

                ),

              ]),

            ],

          ],

        ),

      ),

    );

  }

}



// ── Speed & Distance card ──

class _SpeedDistCard extends StatelessWidget {

  const _SpeedDistCard({required this.icon, required this.label, required this.value, required this.iconColor});

  final IconData icon;

  final String label;

  final String value;

  final Color iconColor;



  @override

  Widget build(BuildContext context) {

    return Expanded(

      child: Container(

        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),

        decoration: BoxDecoration(

          color: _kCard,

          borderRadius: BorderRadius.circular(14),

        ),

        child: Row(children: [

          Icon(icon, size: 18, color: iconColor),

          const SizedBox(width: 10),

          Expanded(child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text(label, style: const TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600)),

              const SizedBox(height: 2),

              Text(value, style: const TextStyle(color: _kTextW, fontSize: 15, fontWeight: FontWeight.w900)),

            ],

          )),

        ]),

      ),

    );

  }

}



// ── Gold record chip (horizontal scrollable) ──

class _GoldRecordChip extends StatelessWidget {

  const _GoldRecordChip({required this.label, required this.value});

  final String label;

  final String value;



  @override

  Widget build(BuildContext context) {

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

      decoration: BoxDecoration(

        color: _kCard,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: _kGold.withValues(alpha: 0.3)),

      ),

      child: Row(mainAxisSize: MainAxisSize.min, children: [

        const Icon(Icons.emoji_events, size: 14, color: _kGold),

        const SizedBox(width: 8),

        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Text(label, style: const TextStyle(color: _kGold, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6)),

          const SizedBox(height: 2),

          Text(value, style: const TextStyle(color: _kTextW, fontSize: 14, fontWeight: FontWeight.w900)),

        ]),

      ]),

    );

  }

}



// ── Match breakdown card ──

class _MatchBreakdownCard extends StatelessWidget {

  const _MatchBreakdownCard({required this.index, required this.data});

  final int index;

  final Map<String, dynamic> data;



  @override

  Widget build(BuildContext context) {

    final name = (data['name'] ?? 'Match $index').toString();

    final dist = (data['distance'] as num? ?? 0).toDouble();

    final maxSpd = (data['maxSpeed'] as num? ?? 0).toDouble();

    final avgSpd = (data['avgSpeed'] as num? ?? 0).toDouble();

    final sprints = (data['sprints'] as int?) ?? 0;

    final accel = (data['accelPeaks'] as int?) ?? 0;

    final cal = data['calibrated'] == true;



    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: _kCard,

        borderRadius: BorderRadius.circular(14),

      ),

      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(children: [

          Container(

            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

            decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),

            child: Text('#$index', style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w900, fontSize: 12)),

          ),

          const SizedBox(width: 10),

          Expanded(child: Text(name, overflow: TextOverflow.ellipsis,

            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _kTextW))),

          Icon(

            cal ? Icons.verified : Icons.warning_amber_rounded,

            color: cal ? _kGreen : _kGold,

            size: 16,

          ),

        ]),

        const SizedBox(height: 14),

        Row(children: [

          _MiniStat(label: 'DIST', value: '${dist.toStringAsFixed(0)}m', color: _kAccent),

          _MiniStat(label: 'TOP', value: maxSpd.toStringAsFixed(1), color: _kGreen),

          _MiniStat(label: 'AVG', value: avgSpd.toStringAsFixed(1), color: const Color(0xFFFFA726)),

          _MiniStat(label: 'SPR', value: '$sprints', color: const Color(0xFFEF5350)),

          _MiniStat(label: 'ACC', value: '$accel', color: _kGold),

        ]),

      ]),

    );

  }

}



class _MiniStat extends StatelessWidget {

  const _MiniStat({required this.label, required this.value, required this.color});

  final String label;

  final String value;

  final Color color;



  @override

  Widget build(BuildContext context) {

    return Expanded(

      child: Column(children: [

        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _kTextW)),

        const SizedBox(height: 2),

        Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 9, color: color, letterSpacing: 0.5)),

      ]),

    );

  }

}



// ── Zone legend item ──

class _ZoneLegend extends StatelessWidget {

  const _ZoneLegend({required this.color, required this.label, required this.pct});

  final Color color;

  final String label;

  final double pct;



  @override

  Widget build(BuildContext context) {

    return Row(mainAxisSize: MainAxisSize.min, children: [

      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),

      const SizedBox(width: 5),

      Text('$label ${pct.toStringAsFixed(1)}%', style: const TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600)),

    ]);

  }

}



// ── Quality badge for video tiles ──

class _QualityBadge extends StatelessWidget {

  const _QualityBadge({required this.score});

  final double score;



  @override

  Widget build(BuildContext context) {

    final String emoji;

    final String label;

    final Color bg;

    final Color fg;

    if (score > 0.8) {

      emoji = '\u2B50'; label = 'Excellent'; bg = const Color(0x30FFD740); fg = _kGold;

    } else if (score > 0.5) {

      emoji = '\u2705'; label = 'Good'; bg = const Color(0x3000E676); fg = _kGreen;

    } else {

      emoji = '\u26A0\uFE0F'; label = 'Low'; bg = const Color(0x30FF7043); fg = const Color(0xFFFF7043);

    }

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),

      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),

      child: Text('$emoji $label', style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w700)),

    );

  }

}

// ══════════════════════════════════════════════════════════════════════════════
// PRIVATE INFO CARD
// ══════════════════════════════════════════════════════════════════════════════

class _PrivateInfoCard extends StatelessWidget {
  const _PrivateInfoCard({
    required this.me,
    required this.fifaStats,
    required this.onCompleteProfile,
  });
  final Map<String, dynamic>? me;
  final FifaCardStats fifaStats;
  final VoidCallback onCompleteProfile;

  int _age() {
    final dob = me?['dateOfBirth'] ?? me?['dob'] ?? me?['birthDate'];
    if (dob == null) return -1;
    try {
      // Handle both ISO string and Dart DateTime-like objects
      final str = dob.toString();
      if (str.isEmpty || str == 'null') return -1;
      final dt = DateTime.parse(str);
      final now = DateTime.now();
      int age = now.year - dt.year;
      if (now.month < dt.month || (now.month == dt.month && now.day < dt.day)) age--;
      return age >= 0 ? age : -1;
    } catch (_) { return -1; }
  }

  int _height() {
    final h = me?['height'] ?? me?['heightCm'];
    if (h == null) return -1;
    if (h is num) return h.round();
    // Handle '175.0' strings from JSON double serialization
    final parsed = double.tryParse(h.toString());
    if (parsed != null) return parsed.round();
    return -1;
  }

  bool get _isProfileIncomplete {
    final age = _age();
    final ht = _height();
    final pos = (me?['position'] as String?)?.trim() ?? '';
    final nat = (me?['nation'] ?? me?['country'] ?? '').toString().trim();
    return age < 0 || ht < 0 || pos.isEmpty || nat.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final age = _age();
    final ht = _height();
    final position = (me?['position'] as String?)?.toUpperCase() ?? '';
    final country = (me?['nation'] ?? me?['country'] ?? '').toString();
    final flag = country.isNotEmpty ? flagForCountry(country) : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGold.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lock_outline, size: 14, color: _kGold),
            const SizedBox(width: 6),
            const Text(
              'PRIVATE INFO',
              style: TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
            const Spacer(),
            if (_isProfileIncomplete)
              GestureDetector(
                onTap: onCompleteProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF2979FF), Color(0xFF00B0FF)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_outlined, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Complete profile', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _InfoTile(
              icon: Icons.cake_outlined,
              label: 'Age',
              value: age >= 0 ? '$age yrs' : '—',
              missing: age < 0,
            )),
            Expanded(child: _InfoTile(
              icon: Icons.flag_outlined,
              label: 'Country',
              value: country.isNotEmpty ? '$flag $country' : '—',
              missing: country.isEmpty,
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _InfoTile(
              icon: Icons.sports_soccer,
              label: 'Position',
              value: position.isNotEmpty ? position : '—',
              missing: position.isEmpty,
            )),
            Expanded(child: _InfoTile(
              icon: Icons.star_outline,
              label: 'Avg Rating',
              value: fifaStats.ovr > 0 ? '${fifaStats.ovr}' : '—',
              missing: false,
              valueColor: fifaStats.ovr >= 80
                  ? const Color(0xFFFFD600)
                  : fifaStats.ovr >= 65
                      ? const Color(0xFF76FF03)
                      : null,
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _InfoTile(
              icon: Icons.height,
              label: 'Height',
              value: ht >= 0 ? '$ht cm' : '—',
              missing: ht < 0,
            )),
            const Expanded(child: SizedBox()),
          ]),
          if (_isProfileIncomplete) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onCompleteProfile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2979FF), Color(0xFF00B0FF)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.person_add_alt_1, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Complete your profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.missing,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool missing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: missing ? _kTextM : _kAccent),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            Text(
              value,
              style: TextStyle(
                color: missing ? _kTextM : (valueColor ?? _kTextW),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontStyle: missing ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COMPLETE PROFILE SHEET
// ══════════════════════════════════════════════════════════════════════════════

const _kProfilePositions = [
  'GK', 'CB', 'LB', 'RB', 'LWB', 'RWB',
  'CDM', 'CM', 'CAM', 'LM', 'RM',
  'LW', 'RW', 'CF', 'ST',
];

class _CompleteProfileSheet extends StatefulWidget {
  const _CompleteProfileSheet({required this.me});
  final Map<String, dynamic>? me;

  @override
  State<_CompleteProfileSheet> createState() => _CompleteProfileSheetState();
}

class _CompleteProfileSheetState extends State<_CompleteProfileSheet> {
  final _heightCtrl = TextEditingController();
  String? _selectedPosition;
  String? _selectedNation;
  DateTime? _selectedDob;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = widget.me;
    if (me != null) {
      _selectedPosition = (me['position'] as String?)?.toUpperCase();
      _selectedNation = (me['nation'] ?? me['country'] as String?);
      final h = me['height'] ?? me['heightCm'];
      if (h != null) {
        if (h is num) {
          _heightCtrl.text = h.round().toString();
        } else {
          final parsed = double.tryParse(h.toString());
          _heightCtrl.text = parsed != null ? parsed.round().toString() : h.toString();
        }
      }
      final dob = me['dateOfBirth'] ?? me['dob'] ?? me['birthDate'];
      if (dob != null) {
        try { _selectedDob = DateTime.parse(dob.toString()); } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _busy = true; _error = null; });
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) throw Exception('Not logged in');
      final heightRaw = _heightCtrl.text.trim();
      final heightParsed = heightRaw.isEmpty ? null : (double.tryParse(heightRaw)?.round());
      await AuthApi().updateProfile(
        token,
        position: _selectedPosition,
        nation: _selectedNation,
        dateOfBirth: _selectedDob != null
            ? '${_selectedDob!.year.toString().padLeft(4, '0')}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}'
            : null,
        height: heightParsed,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF151B2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? const Color(0xFF8899AA) : Colors.black54;
    final borderColor = isDark ? const Color(0xFF2A3550) : Colors.black12;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.person_add_alt_1, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Complete your profile', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 18)),
              ]),
            ),
            Divider(color: borderColor, height: 24),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  // ── Position ──
                  Text('POSITION', style: TextStyle(color: mutedColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final pos in _kProfilePositions)
                      GestureDetector(
                        onTap: () => setState(() => _selectedPosition = _selectedPosition == pos ? null : pos),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _selectedPosition == pos ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _selectedPosition == pos ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25)),
                          ),
                          child: Text(pos, style: TextStyle(
                            color: _selectedPosition == pos ? Colors.white : AppColors.primary,
                            fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Country ──
                  Text('COUNTRY', style: TextStyle(color: mutedColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showCountryPicker(context, current: _selectedNation);
                      if (picked != null && mounted) setState(() => _selectedNation = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedNation != null
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedNation != null ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(children: [
                        if (_selectedNation != null) ...[
                          Text(flagForCountry(_selectedNation!), style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_selectedNation!, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14))),
                          GestureDetector(onTap: () => setState(() => _selectedNation = null),
                            child: Icon(Icons.close, size: 18, color: mutedColor)),
                        ] else ...[
                          Icon(Icons.public, size: 20, color: mutedColor),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Select country', style: TextStyle(color: mutedColor, fontSize: 14))),
                          Icon(Icons.arrow_drop_down, color: mutedColor),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Date of Birth ──
                  Text('DATE OF BIRTH', style: TextStyle(color: mutedColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDob ?? DateTime(now.year - 18, now.month, now.day),
                        firstDate: DateTime(1950),
                        lastDate: DateTime(now.year - 10, now.month, now.day),
                        helpText: 'Select date of birth',
                      );
                      if (picked != null && mounted) setState(() => _selectedDob = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.cake_outlined),
                        hintText: 'Date of birth',
                        suffixIcon: _selectedDob != null
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _selectedDob = null),
                              )
                            : const Icon(Icons.arrow_drop_down),
                      ),
                      child: _selectedDob != null
                          ? Text(
                              '${_selectedDob!.day.toString().padLeft(2, '0')} / '
                              '${_selectedDob!.month.toString().padLeft(2, '0')} / '
                              '${_selectedDob!.year}',
                              style: TextStyle(color: textColor),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Height ──
                  Text('HEIGHT', style: TextStyle(color: mutedColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _heightCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    decoration: const InputDecoration(
                      hintText: '175',
                      prefixIcon: Icon(Icons.height_outlined),
                      suffixText: 'cm',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
