import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/country_picker.dart';
import '../widgets/fifa_card_stats.dart';
import '../widgets/legendary_player_card.dart';

/// Detailed view of a player (used by scouters from Marketplace/Following).
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _player;
  Map<String, dynamic>? _dashboard;
  bool _isFavorite = false;
  Uint8List? _portraitBytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && _player == null) {
      _player = args;
      _isFavorite = args['isFavorite'] == true;
      _loadDashboard();
    }
  }

  Future<void> _loadDashboard() async {
    final player = _player;
    if (player == null) return;
    final playerId = (player['_id'] ?? player['id'])?.toString() ?? '';
    if (playerId.isEmpty) {
      setState(() { _loading = false; });
      return;
    }
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/players/$playerId/dashboard');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode >= 400) {
        debugPrint('GET $uri -> ${res.statusCode}');
        if (res.body.isNotEmpty) debugPrint(res.body);
        throw Exception('Failed to load player dashboard (HTTP ${res.statusCode})');
      }
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        _dashboard = data is Map<String, dynamic> ? data : null;
        _loading = false;
      });
      _computeRichStats();
      // Load portrait
      _loadPortrait(playerId);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadPortrait(String playerId) async {
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;
      final pUri = Uri.parse('${ApiConfig.baseUrl}/players/$playerId/portrait');
      final pRes = await http.get(pUri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final ct = (pRes.headers['content-type'] ?? '').toLowerCase();
      if (pRes.statusCode < 400 && pRes.bodyBytes.isNotEmpty && ct.startsWith('image/')) {
        setState(() => _portraitBytes = pRes.bodyBytes);
      }
    } catch (_) {}
  }

  // Rich stats computed from dashboard videos
  List<Map<String, dynamic>> _perVideo = [];
  Map<String, dynamic> _aggStats = {};
  List<List<double>>? _heatCounts;
  int _heatGridW = 0, _heatGridH = 0;

  FifaCardStats _computeFifaStats(String posLabel) {
    if (_dashboard == null) return FifaCardStats.empty;
    final videos = _dashboard!['videos'] is List ? _dashboard!['videos'] as List : [];
    FifaCardStats? best;
    for (final v in videos) {
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

  void _computeRichStats() {
    if (_dashboard == null) return;
    final videos = _dashboard!['videos'] is List ? _dashboard!['videos'] as List : [];
    double totalDist = 0, maxSpeed = 0, totalAvgSpeed = 0;
    int totalSprints = 0, analyzed = 0, totalAccelPeaks = 0;
    double bestDist = 0, bestAvgSpeed = 0;
    int bestSprints = 0;
    final perVideo = <Map<String, dynamic>>[];
    List<List<double>>? mergedHeat;
    int hW = 0, hH = 0;

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
      final accelList = metrics['accelPeaks'];
      final accelCount = accelList is List ? accelList.length : _toInt(accelList);

      // Heatmap
      final heatmap = metrics['heatmap'];
      if (heatmap is Map) {
        final counts = heatmap['counts'];
        final gw = _toInt(heatmap['grid_w']);
        final gh = _toInt(heatmap['grid_h']);
        if (counts is List && gw > 0 && gh > 0) {
          if (mergedHeat == null || hW != gw || hH != gh) {
            hW = gw; hH = gh;
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
      totalAccelPeaks += accelCount;
      if (d > bestDist) bestDist = d;
      if (avgS > bestAvgSpeed) bestAvgSpeed = avgS;
      if (sp > bestSprints) bestSprints = sp;

      perVideo.add({
        'name': (v['originalName'] ?? v['filename'] ?? 'Match $analyzed').toString(),
        'distance': d, 'maxSpeed': ms,
        'avgSpeed': avgS > 0 ? avgS : ms * 0.6,
        'sprints': sp, 'accelPeaks': accelCount,
        'calibrated': (metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null),
        'qualityScore': qualityScore,
      });
    }
    _perVideo = perVideo;
    _heatCounts = mergedHeat;
    _heatGridW = hW;
    _heatGridH = hH;
    _aggStats = {
      'totalDistance': totalDist, 'maxSpeed': maxSpeed,
      'avgSpeed': analyzed > 0 ? totalAvgSpeed / analyzed : 0.0,
      'avgDistPerMatch': analyzed > 0 ? totalDist / analyzed : 0.0,
      'totalSprints': totalSprints, 'matchesAnalyzed': analyzed,
      'totalVideos': videos.length, 'totalAccelPeaks': totalAccelPeaks,
      'bestDistance': bestDist, 'bestAvgSpeed': bestAvgSpeed, 'bestSprints': bestSprints,
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

  Future<void> _toggleFavorite() async {
    final player = _player;
    if (player == null) return;
    final playerId = (player['_id'] ?? player['id'])?.toString() ?? '';
    if (playerId.isEmpty) return;
    final token = await AuthStorage.loadToken();
    if (token == null) return;
    try {
      if (_isFavorite) {
        await http.delete(
          Uri.parse('${ApiConfig.baseUrl}/favorites/$playerId'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } else {
        await http.post(
          Uri.parse('${ApiConfig.baseUrl}/favorites/$playerId'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final name = (player?['displayName'] ?? player?['email'] ?? 'Player').toString();
    final position = (player?['position'] ?? '').toString();
    final nation = (player?['nation'] ?? '').toString();
    final fifaStats = _computeFifaStats(position.isNotEmpty ? position : 'CM');
    final analyzed = (_aggStats['matchesAnalyzed'] as int?) ?? 0;
    final topSpeed = (_aggStats['maxSpeed'] as num? ?? 0).toDouble();
    final avgSpeed = (_aggStats['avgSpeed'] as num? ?? 0).toDouble();
    final totalDist = (_aggStats['totalDistance'] as num? ?? 0).toDouble();
    final avgDist = (_aggStats['avgDistPerMatch'] as num? ?? 0).toDouble();

    return GradientScaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          // ── Challenges button ──
          IconButton(
            onPressed: () => _showChallengesSheet(context),
            tooltip: 'View Challenges',
            icon: const Icon(Icons.emoji_events_outlined, color: Color(0xFFFFD740)),
          ),
          // ── Follow / Unfollow ──
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.redAccent : Colors.white,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _loadDashboard, child: Text(S.of(context).retry)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    // ═══════════ PLAYER CARD ═══════════
                    LegendaryPlayerCard(
                      name: name,
                      stats: fifaStats,
                      position: position.isNotEmpty ? position : 'CM',
                      nation: nation,
                      portraitBytes: _portraitBytes,
                    ),
                    const SizedBox(height: 16),

                    // ═══════════ PLAYER INFO (scouter view) ═══════════
                    _PlayerInfoCard(player: player, fifaStats: fifaStats),
                    const SizedBox(height: 20),

                    // ═══════════ PLAYER RADAR ═══════════
                    _sectionHeader(Icons.hexagon_outlined, 'PLAYER RADAR'),
                    const SizedBox(height: 10),
                    _card(child: Column(children: [
                      SizedBox(height: 220, width: 220, child: CustomPaint(painter: _RadarPainter(stats: fifaStats), size: const Size(220, 220))),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                        decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(20)),
                        child: Text('OVR ${fifaStats.ovr}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
                      ),
                    ])),
                    const SizedBox(height: 20),

                    // ═══════════ MATCH READINESS ═══════════
                    _sectionHeader(Icons.flash_on, 'MATCH READINESS'),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _card(child: Column(children: [
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 90, width: 90,
                          child: CustomPaint(painter: _MentalRingPainter(
                            pct: analyzed > 0 ? (fifaStats.ovr / 99).clamp(0.0, 1.0) : 0.0,
                          )),
                        ),
                        const SizedBox(height: 8),
                        const Text('MENTAL', style: TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ]))),
                      const SizedBox(width: 10),
                      Expanded(child: _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('SPEED TREND', style: TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80, width: double.infinity,
                          child: CustomPaint(painter: _MoraleTrendPainter(perVideo: _perVideo)),
                        ),
                      ]))),
                    ]),
                    const SizedBox(height: 20),

                    // ═══════════ SPEED & DISTANCE ═══════════
                    _sectionHeader(Icons.speed, 'SPEED & DISTANCE'),
                    const SizedBox(height: 10),
                    Row(children: [
                      _speedCard(Icons.flash_on, 'Top Speed', '${topSpeed.toStringAsFixed(1)} km/h', _kGreen),
                      const SizedBox(width: 10),
                      _speedCard(Icons.map, 'Total Distance', '${totalDist.toStringAsFixed(1)} m', _kAccent),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _speedCard(Icons.trending_up, 'Avg Speed', '${avgSpeed.toStringAsFixed(1)} km/h', const Color(0xFFFFA726)),
                      const SizedBox(width: 10),
                      _speedCard(Icons.straighten, 'Avg Dist/Match', '${avgDist.toStringAsFixed(1)} m', _kAccent),
                    ]),
                    const SizedBox(height: 20),

                    // ═══════════ MOVEMENT ZONES ═══════════
                    Builder(builder: (_) {
                      final hasReal = _aggStats['hasZones'] == true;
                      final walk = hasReal ? (_aggStats['avgWalkPct'] as num? ?? 0).toDouble() : 35.0;
                      final jog  = hasReal ? (_aggStats['avgJogPct']  as num? ?? 0).toDouble() : 28.0;
                      final run  = hasReal ? (_aggStats['avgRunPct']  as num? ?? 0).toDouble() : 20.0;
                      final high = hasReal ? (_aggStats['avgHighPct'] as num? ?? 0).toDouble() : 12.0;
                      final spr  = hasReal ? (_aggStats['avgSprintPct'] as num? ?? 0).toDouble() : 5.0;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionHeader(Icons.directions_run, 'MOVEMENT ZONES'),
                        const SizedBox(height: 10),
                        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            _zoneLegend(const Color(0xFF78909C), 'Walk', walk),
                            _zoneLegend(const Color(0xFF26C6DA), 'Jog', jog),
                            _zoneLegend(const Color(0xFF66BB6A), 'Run', run),
                            _zoneLegend(const Color(0xFFFFA726), 'High', high),
                            _zoneLegend(const Color(0xFFEF5350), 'Sprint', spr),
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
                        ])),
                        const SizedBox(height: 20),
                      ]);
                    }),

                    // ═══════════ WORK RATE & INTENSITY ═══════════
                    Builder(builder: (_) {
                      final hasReal = _aggStats['hasWorkRate'] == true;
                      final wr = hasReal ? (_aggStats['avgWorkRate'] as num? ?? 0).toDouble() : 85.2;
                      final mr = hasReal ? (_aggStats['avgMovingRatio'] as num? ?? 0).toDouble() : 0.72;
                      final dc = hasReal ? (_aggStats['avgDirChanges'] as num? ?? 0).toDouble() : 8.4;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionHeader(Icons.local_fire_department, 'WORK RATE & INTENSITY'),
                        const SizedBox(height: 10),
                        Row(children: [
                          _speedCard(Icons.directions_run, 'Work Rate', '${wr.toStringAsFixed(1)} m/min', const Color(0xFFFF7043)),
                          const SizedBox(width: 10),
                          _speedCard(Icons.directions_walk, 'Activity', '${(mr * 100).toStringAsFixed(0)}%', const Color(0xFF26C6DA)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          _speedCard(Icons.swap_calls, 'Dir. Changes', '${dc.toStringAsFixed(1)} /min', const Color(0xFFAB47BC)),
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

                    // ═══════════ TACTICAL HEATMAP ═══════════
                    _sectionHeader(Icons.grid_on, 'TACTICAL HEATMAP'),
                    const SizedBox(height: 10),
                    _card(child: Column(children: [
                      if (_heatCounts != null && _heatGridW > 0 && _heatGridH > 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _heatGridW / _heatGridH,
                            child: CustomPaint(painter: _HeatmapPainter(counts: _heatCounts!, gridW: _heatGridW, gridH: _heatGridH)),
                          ),
                        )
                      else
                        SizedBox(
                          height: 180, width: double.infinity,
                          child: CustomPaint(painter: _FallbackPitchPainter(position: position.isNotEmpty ? position : 'CM')),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        _heatCounts != null ? 'AGGREGATED FROM $analyzed MATCHES' : 'NO HEATMAP DATA YET',
                        style: const TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                    ])),
                    const SizedBox(height: 20),

                    // ═══════════ BEST RECORDS ═══════════
                    if (analyzed > 0) ...[
                      _sectionHeader(Icons.emoji_events, 'BEST RECORDS'),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _goldChip('BEST SPEED', '${topSpeed.toStringAsFixed(1)} km/h'),
                          const SizedBox(width: 10),
                          _goldChip('BEST DISTANCE', '${(_aggStats['bestDistance'] as num? ?? 0).toStringAsFixed(0)} m'),
                          const SizedBox(width: 10),
                          _goldChip('BEST SPRINTS', '${_aggStats['bestSprints'] ?? 0} in match'),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ═══════════ MATCH BREAKDOWN ═══════════
                    if (_perVideo.isNotEmpty) ...[
                      _sectionHeader(Icons.table_chart, 'MATCH BREAKDOWN'),
                      const SizedBox(height: 10),
                      for (int i = 0; i < _perVideo.length; i++) ...[
                        _matchBreakdown(i + 1, _perVideo[i]),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 12),
                    ],

                    // ═══════════ VIDEOS ═══════════
                    _sectionHeader(Icons.videocam, 'MATCH VIDEOS'),
                    const SizedBox(height: 10),
                    ..._buildVideoList(),
                    const SizedBox(height: 20),

                    // ═══════════ SEND VIDEO REQUEST ═══════════
                    _buildVideoRequestButton(),
                    const SizedBox(height: 12),
                  ],
                ),
    );
  }

  // ── Dashboard helper builders ──

  static const _kCard = Color(0xFF151B2D);
  static const _kAccent = Color(0xFF2979FF);
  static const _kGreen = Color(0xFF00E676);
  static const _kGold = Color(0xFFFFD740);
  static const _kTextM = Color(0xFF8899AA);

  Widget _sectionHeader(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 16, color: _kAccent),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.6)),
    ]);
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      child: child,
    );
  }

  Widget _speedCard(IconData icon, String label, String value, Color iconColor) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
        ])),
      ]),
    ));
  }

  Widget _zoneLegend(Color color, String label, double pct) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 5),
      Text('$label ${pct.toStringAsFixed(1)}%', style: const TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _goldChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events, size: 14, color: _kGold),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: _kGold, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }

  Widget _matchBreakdown(int index, Map<String, dynamic> data) {
    final name = (data['name'] ?? 'Match $index').toString();
    final dist = (data['distance'] as num? ?? 0).toDouble();
    final maxSpd = (data['maxSpeed'] as num? ?? 0).toDouble();
    final avgSpd = (data['avgSpeed'] as num? ?? 0).toDouble();
    final sprints = (data['sprints'] as int?) ?? 0;
    final accel = (data['accelPeaks'] as int?) ?? 0;
    final cal = data['calibrated'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text('#$index', style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white))),
          Icon(cal ? Icons.verified : Icons.warning_amber_rounded, color: cal ? _kGreen : _kGold, size: 16),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _miniStat('DIST', '${dist.toStringAsFixed(0)}m', _kAccent),
          _miniStat('TOP', maxSpd.toStringAsFixed(1), _kGreen),
          _miniStat('AVG', avgSpd.toStringAsFixed(1), const Color(0xFFFFA726)),
          _miniStat('SPR', '$sprints', const Color(0xFFEF5350)),
          _miniStat('ACC', '$accel', _kGold),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(child: Column(children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 9, color: color, letterSpacing: 0.5)),
    ]));
  }

  List<Widget> _buildVideoList() {
    if (_dashboard == null || _dashboard!['videos'] is! List) {
      return [_card(child: const Text('No data available', style: TextStyle(color: _kTextM)))];
    }
    final videos = _dashboard!['videos'] as List;
    if (videos.isEmpty) {
      return [_card(child: const Text('No videos uploaded yet', style: TextStyle(color: _kTextM)))];
    }
    final widgets = <Widget>[];
    for (final v in videos) {
      final vMap = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
      widgets.add(_VideoTile(
        video: vMap,
        onTap: () {
          final videoId = (vMap['_id'] ?? vMap['id'])?.toString();
          if (videoId != null && videoId.isNotEmpty) {
            Navigator.of(context).pushNamed('/scouter-video-player', arguments: vMap);
          }
        },
      ));
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  Widget _buildVideoRequestButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: _showVideoRequestDialog,
        icon: const Icon(Icons.videocam_outlined, size: 20),
        label: const Text('Send Video Request'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }

  void _showVideoRequestDialog() {
    final controller = TextEditingController();
    final name = (_player?['displayName'] ?? 'this player').toString();

    showDialog(
      context: context,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surf(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.videocam, color: Color(0xFF8B5CF6), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Request Video from $name',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Describe what kind of video you want. The player will see this in their notifications.',
                    style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'e.g. "I\'d like to see a video of your dribbling skills in a 1v1 situation, and some free kicks..."',
                      hintStyle: TextStyle(color: AppColors.txMuted(context).withValues(alpha: 0.5), fontSize: 13),
                      fillColor: AppColors.surface.withValues(alpha: 0.7),
                      filled: true,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Quick suggestion chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _quickChip(controller, 'Dribbling skills'),
                      _quickChip(controller, 'Match highlights'),
                      _quickChip(controller, 'Set pieces'),
                      _quickChip(controller, 'Defensive work'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final msg = controller.text.trim();
                          if (msg.isEmpty) return;
                          setDialogState(() => sending = true);
                          final success = await _sendVideoRequest(msg);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Video request sent! The player will see it in their notifications.'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to send request. Try again.'),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                  child: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send Request'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _quickChip(TextEditingController ctrl, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        final current = ctrl.text;
        if (current.isNotEmpty && !current.endsWith(' ')) {
          ctrl.text = '$current, ${label.toLowerCase()}';
        } else {
          ctrl.text = '${current}I\'d like to see a video showing your ${label.toLowerCase()}';
        }
        ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
      },
    );
  }

  Future<bool> _sendVideoRequest(String message) async {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    if (playerId.isEmpty) return false;
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return false;
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications/video-request'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'playerId': playerId, 'message': message}),
      );
      return res.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  void _showChallengesSheet(BuildContext context) {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    final name = (_player?['displayName'] ?? _player?['email'] ?? 'Player').toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChallengesSheet(playerId: playerId, playerName: name),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, this.onTap});

  final Map<String, dynamic> video;
  final VoidCallback? onTap;

  double _extractQuality(Map<String, dynamic> v) {
    final a = v['lastAnalysis'];
    if (a is! Map) return 0;
    final m = a['metrics'];
    if (m is! Map) return 0;
    final mov = m['movement'];
    if (mov is! Map) return 0;
    return (mov['qualityScore'] as num?)?.toDouble() ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final name = (video['originalName'] ?? video['filename'] ?? 'Video').toString();
    final hasAnalysis = video['lastAnalysis'] is Map;
    final isTagged = video['isTagged'] == true;
    final uploaderName = (video['uploaderName'] ?? '').toString();
    final quality = _extractQuality(video);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.videocam, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  if (isTagged && uploaderName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Uploaded by $uploaderName',
                      style: TextStyle(
                        color: AppColors.primary.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isTagged)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.person_pin, color: AppColors.primary, size: 18),
              ),
            if (hasAnalysis) ...[_QualityBadge(score: quality > 0 ? quality : 0.65), const SizedBox(width: 6)],
            if (onTap != null) ...[
              const Icon(Icons.play_circle_outline, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 8),
            ],
            Pill(
              label: hasAnalysis ? 'Analyzed' : 'Processing',
              color: hasAnalysis ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ══════════════════════════════════════════════════════════════

const _pAccent = Color(0xFF2979FF);
const _pTextM = Color(0xFF8899AA);

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
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      canvas.drawLine(center, Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a)),
        Paint()..color = gridColor..strokeWidth = 0.8);
    }
    final dp = Path();
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      final r = radius * (values[i] / 99).clamp(0.0, 1.0);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) { dp.moveTo(p.dx, p.dy); } else { dp.lineTo(p.dx, p.dy); }
    }
    dp.close();
    canvas.drawPath(dp, Paint()..style = PaintingStyle.fill..color = _pAccent.withValues(alpha: 0.22));
    canvas.drawPath(dp, Paint()..style = PaintingStyle.stroke..color = _pAccent..strokeWidth = 2.5);
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      final r = radius * (values[i] / 99).clamp(0.0, 1.0);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      canvas.drawCircle(p, 4, Paint()..color = _pAccent);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);
      final lo = Offset(center.dx + (radius + 20) * math.cos(a), center.dy + (radius + 20) * math.sin(a));
      final tp = TextPainter(
        text: TextSpan(text: '${_labels[i]}\n${values[i]}',
          style: const TextStyle(color: _pTextM, fontSize: 10, fontWeight: FontWeight.w800, height: 1.3)),
        textAlign: TextAlign.center, textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lo.dx - tp.width / 2, lo.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.stats.ovr != stats.ovr;
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.counts, required this.gridW, required this.gridH});
  final List<List<double>> counts;
  final int gridW, gridH;

  static const _spectrum = [
    Color(0xFF1B8A2F), Color(0xFF2DB84B), Color(0xFF7FD858),
    Color(0xFFCCF03D), Color(0xFFFFFF00), Color(0xFFFFD200),
    Color(0xFFFF9800), Color(0xFFFF5722), Color(0xFFE91E1E),
    Color(0xFFB71C1C), Color(0xFF880E0E),
  ];

  Color _heatColor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final idx = clamped * (_spectrum.length - 1);
    final lo = idx.floor().clamp(0, _spectrum.length - 2);
    return Color.lerp(_spectrum[lo], _spectrum[lo + 1], idx - lo)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E7D32));
    final stripeCount = 12;
    for (var i = 1; i < stripeCount; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * w / stripeCount, 0, w / stripeCount, h), Paint()..color = const Color(0xFF388E3C));
    }

    double maxVal = 0;
    for (final row in counts) { for (final v in row) { if (v > maxVal) maxVal = v; } }
    if (maxVal <= 0) { _drawPitchLines(canvas, w, h); return; }

    final resX = (w / 4).ceil(), resY = (h / 4).ceil();
    final field = List.generate(resY, (_) => List.filled(resX, 0.0));
    final cellW = w / gridW, cellH = h / gridH;
    final sigmaX = cellW * 1.8, sigmaY = cellH * 1.8;

    for (var r = 0; r < gridH && r < counts.length; r++) {
      for (var c = 0; c < gridW && c < counts[r].length; c++) {
        final v = counts[r][c];
        if (v <= 0) continue;
        final norm = v / maxVal;
        final cx = (c + 0.5) * cellW, cy = (r + 0.5) * cellH;
        final fcx = cx / w * resX, fcy = cy / h * resY;
        final fSigX = sigmaX / w * resX, fSigY = sigmaY / h * resY;
        final rx = (fSigX * 3).ceil(), ry = (fSigY * 3).ceil();
        for (var fy = (fcy - ry).floor().clamp(0, resY - 1); fy <= (fcy + ry).ceil().clamp(0, resY - 1); fy++) {
          for (var fx = (fcx - rx).floor().clamp(0, resX - 1); fx <= (fcx + rx).ceil().clamp(0, resX - 1); fx++) {
            final dx = fx - fcx, dy = fy - fcy;
            field[fy][fx] += norm * math.exp(-(dx * dx) / (2 * fSigX * fSigX) - (dy * dy) / (2 * fSigY * fSigY));
          }
        }
      }
    }

    double fieldMax = 0;
    for (final row in field) { for (final v in row) { if (v > fieldMax) fieldMax = v; } }
    if (fieldMax <= 0) fieldMax = 1;

    final pw = w / resX, ph = h / resY;
    for (var fy = 0; fy < resY; fy++) {
      for (var fx = 0; fx < resX; fx++) {
        final t = (field[fy][fx] / fieldMax).clamp(0.0, 1.0);
        if (t < 0.08) continue;
        canvas.drawRect(Rect.fromLTWH(fx * pw, fy * ph, pw + 0.5, ph + 0.5), Paint()..color = _heatColor(t).withValues(alpha: 0.35 + t * 0.55));
      }
    }
    _drawPitchLines(canvas, w, h);
  }

  void _drawPitchLines(Canvas canvas, double w, double h) {
    final lp = Paint()..color = const Color(0xBBFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(3, 3, w - 6, h - 6), lp);
    canvas.drawLine(Offset(w / 2, 3), Offset(w / 2, h - 3), lp);
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.16, lp);
    canvas.drawCircle(Offset(w / 2, h / 2), 3, Paint()..color = const Color(0xBBFFFFFF));
    canvas.drawRect(Rect.fromLTWH(3, h * 0.2, w * 0.17, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.17, h * 0.2, w * 0.17, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(3, h * 0.35, w * 0.07, h * 0.3), lp);
    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.07, h * 0.35, w * 0.07, h * 0.3), lp);
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) => false;
}

class _MentalRingPainter extends CustomPainter {
  _MentalRingPainter({required this.pct});
  final double pct;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 6;
    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = const Color(0x20FFFFFF));
    final sweep = 2 * math.pi * pct;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, sweep, false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = const Color(0xFF00E676));
    final pctText = '${(pct * 100).round()}%';
    final tp = TextPainter(
      text: TextSpan(text: pctText, style: const TextStyle(color: Color(0xFF00E676), fontSize: 22, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MentalRingPainter old) => old.pct != pct;
}

class _MoraleTrendPainter extends CustomPainter {
  _MoraleTrendPainter({required this.perVideo});
  final List<Map<String, dynamic>> perVideo;

  @override
  void paint(Canvas canvas, Size size) {
    final scores = <double>[];
    for (final v in perVideo) {
      final d = (v['distance'] as num? ?? 0).toDouble();
      final s = (v['maxSpeed'] as num? ?? 0).toDouble();
      scores.add((d + s).clamp(0.0, 200.0) / 200.0);
    }
    if (scores.isEmpty) scores.addAll([0.3, 0.5, 0.7]);

    final w = size.width, h = size.height;
    final n = scores.length;
    for (var i = 0; i < 4; i++) {
      final y = h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), Paint()..color = const Color(0x15FFFFFF));
    }
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : w * i / (n - 1);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: const TextStyle(color: Color(0x60FFFFFF), fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, h - tp.height));
    }
    final path = Path();
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : w * i / (n - 1);
      final y = (h - 14) * (1 - scores[i]) + 2;
      pts.add(Offset(x, y));
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF00E676)..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
    final fill = Path.from(path)..lineTo(pts.last.dx, h)..lineTo(pts.first.dx, h)..close();
    canvas.drawPath(fill, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0x4000E676), Color(0x0000E676)],
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    for (final p in pts) {
      canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF00E676));
    }
  }

  @override
  bool shouldRepaint(covariant _MoraleTrendPainter old) => true;
}

class _FallbackPitchPainter extends CustomPainter {
  _FallbackPitchPainter({required this.position});
  final String position;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)), Paint()..color = const Color(0xFF1B5E20));
    canvas.clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)));
    final lp = Paint()..color = const Color(0x60FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawRect(Rect.fromLTWH(4, 4, w - 8, h - 8), lp);
    canvas.drawLine(Offset(w / 2, 4), Offset(w / 2, h - 4), lp);
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.18, lp);
    canvas.drawRect(Rect.fromLTWH(4, h * 0.2, w * 0.16, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(w - 4 - w * 0.16, h * 0.2, w * 0.16, h * 0.6), lp);
    final tp = TextPainter(
      text: const TextSpan(text: 'No heatmap data yet', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FallbackPitchPainter old) => false;
}

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
      emoji = '\u2B50'; label = 'Excellent'; bg = const Color(0x30FFD740); fg = const Color(0xFFFFD740);
    } else if (score > 0.5) {
      emoji = '\u2705'; label = 'Good'; bg = const Color(0x3000E676); fg = const Color(0xFF00E676);
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
// PLAYER INFO CARD (scouter view — age, country, position, OVR, height)
// ══════════════════════════════════════════════════════════════════════════════

class _PlayerInfoCard extends StatelessWidget {
  const _PlayerInfoCard({required this.player, required this.fifaStats});
  final Map<String, dynamic>? player;
  final FifaCardStats fifaStats;

  static const _kCard = Color(0xFF151B2D);
  static const _kGold = Color(0xFFFFD740);

  int _age() {
    final dob = player?['dateOfBirth'] ?? player?['dob'] ?? player?['birthDate'];
    if (dob == null) return -1;
    try {
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
    final h = player?['height'] ?? player?['heightCm'];
    if (h == null) return -1;
    if (h is num) return h.round();
    final parsed = double.tryParse(h.toString());
    if (parsed != null) return parsed.round();
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final age = _age();
    final ht = _height();
    final position = (player?['position'] as String?)?.toUpperCase() ?? '';
    final country = (player?['nation'] ?? player?['country'] ?? '').toString();
    final flag = country.isNotEmpty ? flagForCountry(country) : '';

    // Only show card if there's at least some data
    final hasAny = age >= 0 || ht >= 0 || position.isNotEmpty || country.isNotEmpty || fifaStats.ovr > 0;
    if (!hasAny) return const SizedBox.shrink();

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
            const Icon(Icons.person_outline, size: 14, color: _kGold),
            const SizedBox(width: 6),
            const Text(
              'PLAYER INFO',
              style: TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _InfoRow(icon: Icons.cake_outlined, label: 'Age',
              value: age >= 0 ? '$age yrs' : '—', missing: age < 0)),
            Expanded(child: _InfoRow(icon: Icons.flag_outlined, label: 'Country',
              value: country.isNotEmpty ? '$flag $country' : '—', missing: country.isEmpty)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _InfoRow(icon: Icons.sports_soccer, label: 'Position',
              value: position.isNotEmpty ? position : '—', missing: position.isEmpty)),
            Expanded(child: _InfoRow(
              icon: Icons.star_outline, label: 'Avg Rating',
              value: fifaStats.ovr > 0 ? '${fifaStats.ovr}' : '—',
              missing: false,
              valueColor: fifaStats.ovr >= 80
                  ? const Color(0xFFFFD600)
                  : fifaStats.ovr >= 65 ? const Color(0xFF76FF03) : null,
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _InfoRow(icon: Icons.height, label: 'Height',
              value: ht >= 0 ? '$ht cm' : '—', missing: ht < 0)),
            const Expanded(child: SizedBox()),
          ]),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon, required this.label,
    required this.value, required this.missing,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool missing;
  final Color? valueColor;

  static const _kAccent = Color(0xFF2979FF);
  static const _kTextM  = Color(0xFF8899AA);

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Icon(icon, size: 15, color: missing ? _kTextM : _kAccent),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        Text(value, style: TextStyle(
          color: missing ? _kTextM : (valueColor ?? Colors.white),
          fontSize: 13, fontWeight: FontWeight.w700,
          fontStyle: missing ? FontStyle.italic : FontStyle.normal,
        )),
      ]),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CHALLENGES SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _ChallengesSheet extends StatefulWidget {
  const _ChallengesSheet({required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<_ChallengesSheet> createState() => _ChallengesSheetState();
}

class _ChallengesSheetState extends State<_ChallengesSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _challenges = [];

  static const _kCard  = Color(0xFF151B2D);
  static const _kAccent = Color(0xFF2979FF);
  static const _kGreen = Color(0xFF00E676);
  static const _kTextM = Color(0xFF8899AA);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.playerId.isEmpty) {
      setState(() { _loading = false; _error = 'No player ID'; });
      return;
    }
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;
      final uri = Uri.parse('${ApiConfig.baseUrl}/players/${widget.playerId}/challenges');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _loading = false; _error = 'Could not load challenges (HTTP ${res.statusCode})'; });
        return;
      }
      final parsed = jsonDecode(res.body);
      final list = parsed is List
          ? parsed.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];
      setState(() { _challenges = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed': return _kGreen;
      case 'in_progress': return _kAccent;
      case 'failed': return const Color(0xFFEF5350);
      default: return _kTextM;
    }
  }

  IconData _statusIcon(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed': return Icons.check_circle;
      case 'in_progress': return Icons.timelapse;
      case 'failed': return Icons.cancel;
      default: return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF151B2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? const Color(0xFF2A3550) : Colors.black12;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
                const Icon(Icons.emoji_events_outlined, color: Color(0xFFFFD740), size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${widget.playerName}\'s Challenges',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
            Divider(color: borderColor, height: 24),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: Color(0xFFEF5350))),
                        ))
                      : _challenges.isEmpty
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.emoji_events_outlined, size: 48, color: Color(0xFF8899AA)),
                              const SizedBox(height: 12),
                              Text('No challenges yet', style: TextStyle(color: _kTextM, fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 6),
                              Text('This player hasn\'t completed any challenges.', style: TextStyle(color: _kTextM, fontSize: 13)),
                            ]))
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _challenges.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final c = _challenges[i];
                                final title = (c['title'] ?? c['name'] ?? c['challengeId'] ?? 'Challenge').toString();
                                final desc = (c['description'] ?? '').toString();
                                final status = (c['status'] ?? '').toString();
                                final progress = (c['progress'] as num?)?.toDouble() ?? 0;
                                final target = (c['target'] as num?)?.toDouble() ?? 0;
                                final statusColor = _statusColor(status);
                                final statusIcon = _statusIcon(status);
                                final pct = target > 0 ? (progress / target).clamp(0.0, 1.0) : (status == 'completed' ? 1.0 : 0.0);

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _kCard,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Icon(statusIcon, size: 16, color: statusColor),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(title,
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      )),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status.isEmpty ? 'pending' : status.replaceAll('_', ' ').toUpperCase(),
                                          style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                                        ),
                                      ),
                                    ]),
                                    if (desc.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(desc, style: const TextStyle(color: _kTextM, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                    if (target > 0) ...[
                                      const SizedBox(height: 10),
                                      Row(children: [
                                        Expanded(child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: pct,
                                            minHeight: 6,
                                            backgroundColor: Colors.white12,
                                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                          ),
                                        )),
                                        const SizedBox(width: 10),
                                        Text('${progress.toInt()} / ${target.toInt()}',
                                          style: TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w700)),
                                      ]),
                                    ],
                                  ]),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
