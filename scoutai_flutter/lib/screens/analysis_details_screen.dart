import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';

import '../app/scoutai_app.dart';
import '../data/mock_data.dart';
import '../models/player_analysis.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/share_service.dart';
import '../theme/app_colors.dart';
import '../services/translations.dart';
import '../widgets/common.dart';
import '../widgets/fifa_card_stats.dart';
import '../widgets/legendary_player_card.dart';

/// Accepts either:
/// - a `PlayerAnalysis` object (legacy / mock)
/// - a raw `Map<String, dynamic>` from AI response (real analysis)
class AnalysisDetailsScreen extends StatefulWidget {
  const AnalysisDetailsScreen({super.key});

  @override
  State<AnalysisDetailsScreen> createState() => _AnalysisDetailsScreenState();
}

class _AnalysisDetailsScreenState extends State<AnalysisDetailsScreen> {
  // ── Profile ──
  String _playerName = 'Player';
  String _position = 'CM';
  Uint8List? _portraitBytes;
  List<dynamic> _playerVideos = [];
  bool _videosLoading = true;
  bool _shareLoading = false;

  // ── Screenshot controllers ──
  final _screenshotCtrl = ScreenshotController();
  final _heatmapCtrl = ScreenshotController();
  final _speedChartCtrl = ScreenshotController();

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
  List<_SpeedSample> _speedSamples = [];
  FifaCardStats _cardStats = FifaCardStats.empty;
  String? _videoId;

  // ── Extended metrics ──
  double? _workRate;
  double? _movingRatio;
  double? _directionChanges;
  Map<String, dynamic>? _movementZones;

  bool _argsParsed = false;
  String? _ownerId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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
      final metrics = args['metrics'] as Map<String, dynamic>? ?? {};
      _distanceKm = _dbl(metrics['distanceMeters']) / 1000.0;
      _maxSpeedKmh = _dbl(metrics['maxSpeedKmh']).clamp(0.0, 45.0);
      _avgSpeedKmh = _dbl(metrics['avgSpeedKmh']).clamp(0.0, 45.0);
      _sprints = _intVal(metrics['sprintCount']);
      _accelPeaks = _intVal(metrics['accelPeaks']);
      final positions = args['positions'];
      _positionCount = positions is List ? positions.length : 0;
      final heatmap = metrics['heatmap'] as Map<String, dynamic>?;
      if (heatmap != null) {
        _heatmapCounts = heatmap['counts'] as List<dynamic>?;
        _heatGridW = _intVal(heatmap['grid_w']);
        _heatGridH = _intVal(heatmap['grid_h']);
        final coordSpace = (heatmap['coord_space'] as String?) ?? 'image';
        _isCalibrated = coordSpace == 'pitch' ||
            (metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null);
      }

      // Extended metrics
      _workRate = _dblOrNull(metrics['workRateMetersPerMin']);
      _movingRatio = _dblOrNull(metrics['movingRatio']);
      _directionChanges = _dblOrNull(metrics['directionChangesPerMin']);
      final zones = metrics['movementZones'] as Map<String, dynamic>?;
      if (zones != null) _movementZones = zones;

      // Speed samples from positions
      if (positions is List && positions.length >= 2) {
        final debug = args['debug'] as Map<String, dynamic>?;
        final meterPerPx = _dbl(debug?['meterPerPx']);
        const maxHumanSpeedKmh = 45.0;
        for (int i = 1; i < positions.length; i++) {
          final cur = positions[i] as Map<String, dynamic>;
          final prev = positions[i - 1] as Map<String, dynamic>;
          final dt = _dbl(cur['t']) - _dbl(prev['t']);
          if (dt <= 0) continue;
          final dx = _dbl(cur['cx']) - _dbl(prev['cx']);
          final dy = _dbl(cur['cy']) - _dbl(prev['cy']);
          final distPx = math.sqrt(dx * dx + dy * dy);
          double speedKmh;
          if (meterPerPx > 0) {
            speedKmh = (distPx * meterPerPx / dt) * 3.6;
          } else {
            speedKmh = (distPx / dt) * 0.1 * 3.6;
          }
          speedKmh = speedKmh.clamp(0.0, maxHumanSpeedKmh);
          _speedSamples.add(_SpeedSample(t: _dbl(cur['t']), kmh: speedKmh));
        }
      }

      // Card stats
      _cardStats = computeCardStats(
        metrics,
        positions is List ? positions : [],
        posLabel: _position,
      );
      _videoId = (args['_videoId'] ?? args['_id'] ?? args['id'])?.toString();
      _ownerId = (args['ownerId'] ?? args['playerId'])?.toString();
    } else {
      // Legacy PlayerAnalysis model
      final PlayerAnalysis item = args is PlayerAnalysis
          ? args
          : mockAnalyses.firstWhere((e) => e.status == AnalysisStatus.done);
      _distanceKm = item.distanceKm;
      _maxSpeedKmh = item.maxSpeedKmh;
      _sprints = item.sprints;
      _avgSpeedKmh = _maxSpeedKmh * 0.55;
    }
  }

  Future<void> _loadProfile() async {
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (res.statusCode < 400) {
        final me = jsonDecode(res.body) as Map<String, dynamic>;
        final dn = (me['displayName'] as String?)?.trim();
        final email = (me['email'] as String?) ?? '';
        final at = email.indexOf('@');
        setState(() {
          _playerName = (dn != null && dn.isNotEmpty) ? dn : (at > 0 ? email.substring(0, at) : 'Player');
          _position = ((me['position'] as String?) ?? 'CM').toUpperCase();
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
      }
    } catch (_) {}
    // Load portrait
    try {
      final token2 = await AuthStorage.loadToken();
      if (token2 == null || !mounted) return;
      final pUri = Uri.parse('${ApiConfig.baseUrl}/me/portrait?ts=${DateTime.now().millisecondsSinceEpoch}');
      final pRes = await http.get(pUri, headers: {'Authorization': 'Bearer $token2'});
      if (!mounted) return;
      final ct = (pRes.headers['content-type'] ?? '').toLowerCase();
      if (pRes.statusCode < 400 && pRes.bodyBytes.isNotEmpty && ct.startsWith('image/')) {
        setState(() => _portraitBytes = pRes.bodyBytes);
      }
    } catch (_) {}
    // Load player's videos
    try {
      final token3 = await AuthStorage.loadToken();
      if (token3 == null || !mounted) return;
      final vUri = Uri.parse('${ApiConfig.baseUrl}/me/videos');
      final vRes = await http.get(vUri, headers: {'Authorization': 'Bearer $token3'});
      if (!mounted) return;
      if (vRes.statusCode < 400) {
        final parsed = jsonDecode(vRes.body);
        if (parsed is List) setState(() => _playerVideos = parsed);
      }
    } catch (_) {}
    if (mounted) setState(() => _videosLoading = false);
  }

  @override
  Widget build(BuildContext context) {
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
          if (_videoId != null && _videoId!.isNotEmpty)
            IconButton(
              tooltip: 'Generate Highlight Reel',
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppRoutes.montage,
                  arguments: {
                    'videoId': _videoId,
                    'title': _playerName.isNotEmpty ? _playerName : 'Highlight Reel',
                    if (_ownerId != null) 'playerId': _ownerId,
                  },
                );
              },
              icon: const Icon(Icons.movie_creation_outlined, size: 22),
            ),
          IconButton(
            tooltip: 'Share / Download PDF',
            onPressed: _shareLoading ? null : _onShare,
            icon: _shareLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
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
                  '$_positionCount tracking points detected across the video. '
                  'Below are the computed performance metrics.',
                  style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
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
                value: '$_positionCount',
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

          // ── Speed chart ──
          Text(
            S.of(context).speedTimeline,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _speedSamples.length >= 2
                    ? Screenshot(
                        controller: _speedChartCtrl,
                        child: _RealSpeedChart(samples: _speedSamples, height: 130),
                      )
                    : SizedBox(
                        height: 130,
                        child: Center(
                          child: Text(S.of(context).notEnoughData,
                              style: const TextStyle(color: AppColors.textMuted)),
                        ),
                      ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${S.of(context).peakVelocity}\n${_maxSpeedKmh.toStringAsFixed(1)} km/h',
                        style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${S.of(context).averageVelocity}\n${_avgSpeedKmh.toStringAsFixed(1)} km/h',
                        style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Player Videos ──
          Text(
            S.of(context).myVideos,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          if (_videosLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (_playerVideos.isEmpty)
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Text(S.of(context).noVideosUploaded,
                  style: const TextStyle(color: AppColors.textMuted)),
            )
          else
            for (final v in _playerVideos) ...[
              _VideoTile(
                video: v is Map ? Map<String, dynamic>.from(v) : {},
                onTap: () {
                  final vMap = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
                  final vid = (vMap['_id'] ?? vMap['id'])?.toString();
                  if (vid == null) return;
                  Navigator.of(context).pushNamed(AppRoutes.scouterVideoPlayer, arguments: vMap);
                },
              ),
              const SizedBox(height: 8),
            ],

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

  Future<void> _onShare() async {
    setState(() => _shareLoading = true);
    try {
      // Capture heatmap and speed chart as images for PDF embedding
      Uint8List? heatmapImage;
      Uint8List? speedChartImage;
      if (_heatmapCounts != null && _heatGridW > 0) {
        try { heatmapImage = await _heatmapCtrl.capture(pixelRatio: 2.0); } catch (_) {}
      }
      if (_speedSamples.length >= 2) {
        try { speedChartImage = await _speedChartCtrl.capture(pixelRatio: 2.0); } catch (_) {}
      }

      await ShareService.sharePdf(
        context: context,
        playerName: _playerName,
        position: _position,
        cardStats: _cardStats,
        distanceKm: _distanceKm,
        maxSpeedKmh: _maxSpeedKmh,
        avgSpeedKmh: _avgSpeedKmh,
        sprints: _sprints,
        accelPeaks: _accelPeaks,
        positionCount: _positionCount,
        portraitBytes: _portraitBytes,
        heatmapImage: heatmapImage,
        speedChartImage: speedChartImage,
        workRate: _workRate,
        movingRatio: _movingRatio,
        directionChanges: _directionChanges,
        movementZones: _movementZones,
        isCalibrated: _isCalibrated,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _shareLoading = false);
    }
  }

  static double _dbl(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static double? _dblOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 105 / 68,
        child: CustomPaint(
          painter: _PitchHeatmapPainter(counts: counts, gridW: gridW, gridH: gridH),
        ),
      ),
    );
  }
}

class _PitchHeatmapPainter extends CustomPainter {
  _PitchHeatmapPainter({
    required this.counts,
    required this.gridW,
    required this.gridH,
  });

  final List<dynamic> counts;
  final int gridW;
  final int gridH;

  static const _spectrum = [
    Color(0xFF1B8A2F),
    Color(0xFF2DB84B),
    Color(0xFF7FD858),
    Color(0xFFCCF03D),
    Color(0xFFFFFF00),
    Color(0xFFFFD200),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFFE91E1E),
    Color(0xFFB71C1C),
    Color(0xFF880E0E),
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

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E7D32));
    const stripeCount = 12;
    for (var i = 0; i < stripeCount; i++) {
      if (i.isEven) continue;
      final sw = w / stripeCount;
      canvas.drawRect(Rect.fromLTWH(i * sw, 0, sw, h),
          Paint()..color = const Color(0xFF388E3C));
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
      -0.6, 1.2, false, lp,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w - w * 0.17 - 3, h / 2), width: h * 0.16, height: h * 0.16),
      math.pi - 0.6, 1.2, false, lp,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchHeatmapPainter old) => false;
}

// ── Speed sample model ──
class _SpeedSample {
  final double t;
  final double kmh;
  const _SpeedSample({required this.t, required this.kmh});
}

class _RealSpeedChart extends StatelessWidget {
  const _RealSpeedChart({required this.samples, this.height = 130});

  final List<_SpeedSample> samples;
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

  final List<_SpeedSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final smoothed = <_SpeedSample>[];
    const window = 3;
    for (int i = 0; i < samples.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = math.max(0, i - window); j <= math.min(samples.length - 1, i + window); j++) {
        sum += samples[j].kmh;
        count++;
      }
      smoothed.add(_SpeedSample(t: samples[i].t, kmh: sum / count));
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
    for (final p in points) fillPath.lineTo(p.dx, p.dy);
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

    canvas.drawPath(linePath, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = AppColors.primary.withValues(alpha: 0.18));
    canvas.drawPath(linePath, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.primary
      ..strokeCap = StrokeCap.round);

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

/// Tile for a player video in the list.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, this.onTap});

  final Map<String, dynamic> video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = (video['originalName'] ?? video['filename'] ?? 'Video').toString();
    final hasAnalysis = video['lastAnalysis'] is Map;
    final isTagged = video['isTagged'] == true;
    final uploaderName = (video['uploaderName'] ?? '').toString();
    final size = video['size'];
    final sizeMb = size is num ? (size / (1024 * 1024)).toStringAsFixed(1) : '?';

    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppColors.surf2(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.6)),
              ),
              child: Icon(
                hasAnalysis ? Icons.analytics_outlined : Icons.videocam,
                color: hasAnalysis ? AppColors.success : AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
                  const SizedBox(height: 4),
                  Text('$sizeMb MB',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isTagged)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.person_pin, color: AppColors.primary, size: 18),
              ),
            Pill(
              label: hasAnalysis ? 'Analyzed' : 'Not analyzed',
              color: hasAnalysis ? AppColors.success : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            const Icon(Icons.play_circle_outline, color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
