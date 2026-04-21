import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Comparator screen — select two players and compare their AI‑analysed
/// football performance metrics side by side (radar chart, bar stats, AI insights).
class ComparatorScreen extends StatefulWidget {
  const ComparatorScreen({super.key});

  @override
  State<ComparatorScreen> createState() => _ComparatorScreenState();
}

class _ComparatorScreenState extends State<ComparatorScreen> {
  // ── Player selection ──
  Map<String, dynamic>? _playerA;
  Map<String, dynamic>? _playerB;

  // ── Comparison result ──
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result; // full compare response

  // ── Helpers ──
  String _name(Map<String, dynamic>? p) =>
      (p?['displayName'] ?? p?['email'] ?? 'Player').toString();

  String _id(Map<String, dynamic> p) =>
      (p['_id'] ?? p['id'])?.toString() ?? '';

  // ────────────────────────── API calls ──────────────────────────

  Future<void> _compare() async {
    if (_playerA == null || _playerB == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/players/compare');
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'playerIdA': _id(_playerA!),
          'playerIdB': _id(_playerB!),
        }),
      );
      if (res.statusCode >= 400) throw Exception('Compare failed (${res.statusCode})');
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        _result = data is Map<String, dynamic> ? data : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ────────────────────────── Player picker ──────────────────────────

  Future<void> _pickPlayer(bool isSlotA) async {
    final token = await AuthStorage.loadToken();
    if (token == null) return;
    final uri = Uri.parse('${ApiConfig.baseUrl}/players');
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode >= 400) return;
    final list = (jsonDecode(res.body) as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PlayerPickerSheet(
        players: list,
        excludeId: isSlotA ? _id(_playerB ?? {}) : _id(_playerA ?? {}),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isSlotA) {
        _playerA = picked;
      } else {
        _playerB = picked;
      }
      _result = null; // reset comparison when selection changes
    });
  }

  // ────────────────────────── Build ──────────────────────────

  @override
  Widget build(BuildContext context) {
    final canCompare = _playerA != null && _playerB != null && !_loading;

    return GradientScaffold(
      appBar: AppBar(title: Text(S.of(context).compareTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const SizedBox(height: 12),
          // ── Header ──
          const GlassCard(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.compare_arrows, size: 40, color: AppColors.primary),
                SizedBox(height: 10),
                Text('Player Comparator',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                SizedBox(height: 6),
                Text(
                  'Select two players and compare their AI‑analysed football performance side by side.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Selection row ──
          Row(
            children: [
              Expanded(
                child: _PlayerSlotCard(
                  label: S.of(context).player1,
                  player: _playerA,
                  color: const Color(0xFF1D63FF),
                  onSelect: () => _pickPlayer(true),
                ),
              ),
              const SizedBox(width: 12),
              const Text('VS',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: _PlayerSlotCard(
                  label: S.of(context).player2,
                  player: _playerB,
                  color: const Color(0xFFB7F408),
                  onSelect: () => _pickPlayer(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Compare button ──
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canCompare ? _compare : null,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.analytics_outlined),
              label: Text(_loading ? S.of(context).analyzing : S.of(context).compare),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
          ],

          // ── Results ──
          if (_result != null) ..._buildResults(),
        ],
      ),
    );
  }

  // ────────────────────────── Comparison results ──────────────────────────

  List<Widget> _buildResults() {
    final a = _result!['playerA'] as Map<String, dynamic>;
    final b = _result!['playerB'] as Map<String, dynamic>;
    final aggA = a['aggregated'] as Map<String, dynamic>;
    final aggB = b['aggregated'] as Map<String, dynamic>;

    return [
      const SizedBox(height: 28),
      Text(S.current.aiPerformanceAnalysis,
          style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8)),
      const SizedBox(height: 16),

      // ── Radar chart ──
      GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: const Color(0xFF1D63FF), label: _name(_playerA)),
                const SizedBox(width: 20),
                _LegendDot(color: const Color(0xFFB7F408), label: _name(_playerB)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: _RadarChart(metricsA: aggA, metricsB: aggB),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),

      // ── Bar comparisons ──
      _ComparisonBar(
        label: S.current.totalDistance,
        valueA: _d(aggA['totalDistanceMeters']),
        valueB: _d(aggB['totalDistanceMeters']),
        unit: 'm',
        icon: Icons.straighten,
      ),
      const SizedBox(height: 10),
      _ComparisonBar(
        label: S.current.avgSpeed,
        valueA: _d(aggA['avgSpeedKmh']),
        valueB: _d(aggB['avgSpeedKmh']),
        unit: 'km/h',
        icon: Icons.speed,
      ),
      const SizedBox(height: 10),
      _ComparisonBar(
        label: S.current.maxSpeed,
        valueA: _d(aggA['maxSpeedKmh']),
        valueB: _d(aggB['maxSpeedKmh']),
        unit: 'km/h',
        icon: Icons.flash_on,
      ),
      const SizedBox(height: 10),
      _ComparisonBar(
        label: S.current.sprints,
        valueA: _d(aggA['totalSprints']),
        valueB: _d(aggB['totalSprints']),
        unit: '',
        icon: Icons.directions_run,
      ),
      const SizedBox(height: 10),
      _ComparisonBar(
        label: S.current.accelPeaks,
        valueA: _d(aggA['totalAccelPeaks']),
        valueB: _d(aggB['totalAccelPeaks']),
        unit: '',
        icon: Icons.trending_up,
      ),
      const SizedBox(height: 10),
      _ComparisonBar(
        label: S.current.analyzedVideos,
        valueA: _d(aggA['analyzedVideos']),
        valueB: _d(aggB['analyzedVideos']),
        unit: '',
        icon: Icons.videocam,
      ),
      const SizedBox(height: 24),

      // ── AI Insight card ──
      _AiInsightCard(
        nameA: _name(_playerA),
        nameB: _name(_playerB),
        aggA: aggA,
        aggB: aggB,
      ),
      const SizedBox(height: 20),

      // ── Per‑video breakdown ──
      _VideoBreakdown(
        titleA: _name(_playerA),
        titleB: _name(_playerB),
        videosA: (a['videos'] as List?) ?? [],
        videosB: (b['videos'] as List?) ?? [],
      ),
    ];
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PLAYER SLOT CARD
// ═══════════════════════════════════════════════════════════════════════════

class _PlayerSlotCard extends StatelessWidget {
  const _PlayerSlotCard({
    required this.label,
    required this.player,
    required this.color,
    required this.onSelect,
  });

  final String label;
  final Map<String, dynamic>? player;
  final Color color;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final name = (player?['displayName'] ?? player?['email'])?.toString();
    final position = (player?['position'] ?? '').toString();

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
            ),
            child: player == null
                ? Icon(Icons.person_add, color: color, size: 26)
                : Center(
                    child: Text(
                      (name != null && name.isNotEmpty ? name[0] : '?').toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 24),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            name ?? label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: player != null ? AppColors.tx(context) : AppColors.txMuted(context),
            ),
          ),
          if (position.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(position,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onSelect,
              child: Text(
                player == null ? S.current.selectPlayer : S.current.change,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PLAYER PICKER BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _PlayerPickerSheet extends StatefulWidget {
  const _PlayerPickerSheet({required this.players, required this.excludeId});

  final List<Map<String, dynamic>> players;
  final String excludeId;

  @override
  State<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends State<_PlayerPickerSheet> {
  String _search = '';

  List<Map<String, dynamic>> get _filtered {
    var list = widget.players;
    if (widget.excludeId.isNotEmpty) {
      list = list
          .where((p) =>
              (p['_id'] ?? p['id'])?.toString() != widget.excludeId)
          .toList();
    }
    if (_search.isEmpty) return list;
    final q = _search.toLowerCase();
    return list.where((p) {
      final n = (p['displayName'] ?? p['email'] ?? '').toString().toLowerCase();
      final pos = (p['position'] ?? '').toString().toLowerCase();
      return n.contains(q) || pos.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final players = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text(S.current.selectAPlayer,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by name or position…',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.surf2(context),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: players.isEmpty
                ? Center(
                    child: Text(S.current.noPlayersFound,
                        style: const TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    controller: controller,
                    itemCount: players.length,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (_, i) {
                      final p = players[i];
                      final name =
                          (p['displayName'] ?? p['email'] ?? 'Player')
                              .toString();
                      final pos = (p['position'] ?? '').toString();
                      final nation = (p['nation'] ?? '').toString();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary)),
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [if (pos.isNotEmpty) pos, if (nation.isNotEmpty) nation]
                              .join(' • '),
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.textMuted),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  RADAR CHART (custom painted)
// ═══════════════════════════════════════════════════════════════════════════

class _RadarChart extends StatelessWidget {
  const _RadarChart({required this.metricsA, required this.metricsB});

  final Map<String, dynamic> metricsA;
  final Map<String, dynamic> metricsB;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarPainter(metricsA: metricsA, metricsB: metricsB),
      size: const Size(260, 260),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.metricsA, required this.metricsB});

  final Map<String, dynamic> metricsA;
  final Map<String, dynamic> metricsB;

  static const _labels = ['Distance', 'Avg Speed', 'Max Speed', 'Sprints', 'Accel'];
  static const _keys = [
    'totalDistanceMeters',
    'avgSpeedKmh',
    'maxSpeedKmh',
    'totalSprints',
    'totalAccelPeaks',
  ];

  double _v(Map<String, dynamic> m, String k) {
    final val = m[k];
    if (val is num) return val.toDouble();
    return 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 30;
    final n = _labels.length;
    final angleStep = 2 * math.pi / n;

    // Compute max for normalisation
    final maxVals = List.generate(n, (i) {
      final va = _v(metricsA, _keys[i]);
      final vb = _v(metricsB, _keys[i]);
      return math.max(va, vb) == 0 ? 1.0 : math.max(va, vb);
    });

    // Draw grid rings
    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border.withValues(alpha: 0.5);
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + i * angleStep;
        final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, ringPaint);
    }

    // Draw axes & labels
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * angleStep;
      final axisEnd = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.drawLine(
        center,
        axisEnd,
        Paint()
          ..color = AppColors.border.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      // label
      final labelOffset = Offset(
        center.dx + (radius + 18) * math.cos(angle),
        center.dy + (radius + 18) * math.sin(angle),
      );
      final tp = TextPainter(
        text: TextSpan(text: _labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(labelOffset.dx - tp.width / 2, labelOffset.dy - tp.height / 2));
    }

    // Draw data polygons
    void drawPoly(Map<String, dynamic> metrics, Color color) {
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.18);
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 2.5;

      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + i * angleStep;
        final norm = _v(metrics, _keys[i]) / maxVals[i];
        final r = radius * norm.clamp(0, 1);
        final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      // dots
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + i * angleStep;
        final norm = _v(metrics, _keys[i]) / maxVals[i];
        final r = radius * norm.clamp(0, 1);
        final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
        canvas.drawCircle(p, 4, Paint()..color = color);
      }
    }

    drawPoly(metricsA, const Color(0xFF1D63FF));
    drawPoly(metricsB, const Color(0xFFB7F408));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  COMPARISON BAR
// ═══════════════════════════════════════════════════════════════════════════

class _ComparisonBar extends StatelessWidget {
  const _ComparisonBar({
    required this.label,
    required this.valueA,
    required this.valueB,
    required this.unit,
    required this.icon,
  });

  final String label;
  final double valueA;
  final double valueB;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final maxVal = math.max(valueA, valueB);
    final ratioA = maxVal == 0 ? 0.5 : valueA / maxVal;
    final ratioB = maxVal == 0 ? 0.5 : valueB / maxVal;
    final aWins = valueA > valueB;
    final bWins = valueB > valueA;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  '${valueA % 1 == 0 ? valueA.toInt() : valueA.toStringAsFixed(1)}${unit.isNotEmpty ? ' $unit' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: aWins ? const Color(0xFF1D63FF) : AppColors.tx(context),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: (ratioA * 100).round().clamp(1, 100),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D63FF).withValues(alpha: aWins ? 0.8 : 0.35),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      flex: (ratioB * 100).round().clamp(1, 100),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFB7F408).withValues(alpha: bWins ? 0.8 : 0.35),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${valueB % 1 == 0 ? valueB.toInt() : valueB.toStringAsFixed(1)}${unit.isNotEmpty ? ' $unit' : ''}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: bWins ? const Color(0xFFB7F408) : AppColors.tx(context),
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

// ═══════════════════════════════════════════════════════════════════════════
//  AI INSIGHT CARD
// ═══════════════════════════════════════════════════════════════════════════

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({
    required this.nameA,
    required this.nameB,
    required this.aggA,
    required this.aggB,
  });

  final String nameA;
  final String nameB;
  final Map<String, dynamic> aggA;
  final Map<String, dynamic> aggB;

  double _v(Map<String, dynamic> m, String k) {
    final val = m[k];
    if (val is num) return val.toDouble();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Generate AI-style insights based on actual metrics
    final insights = <_Insight>[];

    // Distance
    final distA = _v(aggA, 'totalDistanceMeters');
    final distB = _v(aggB, 'totalDistanceMeters');
    if (distA > 0 || distB > 0) {
      if (distA > distB * 1.1) {
        insights.add(_Insight(
          Icons.straighten,
          '$nameA covers ${((distA - distB) / (distB == 0 ? 1 : distB) * 100).toStringAsFixed(0)}% more distance, indicating higher work rate and stamina.',
          AppColors.primary,
        ));
      } else if (distB > distA * 1.1) {
        insights.add(_Insight(
          Icons.straighten,
          '$nameB covers ${((distB - distA) / (distA == 0 ? 1 : distA) * 100).toStringAsFixed(0)}% more distance, indicating higher work rate and stamina.',
          AppColors.primary,
        ));
      } else {
        insights.add(_Insight(
          Icons.straighten,
          'Both players show comparable total distance coverage, suggesting similar work-rate levels.',
          AppColors.textMuted,
        ));
      }
    }

    // Speed
    final maxA = _v(aggA, 'maxSpeedKmh');
    final maxB = _v(aggB, 'maxSpeedKmh');
    if (maxA > 0 || maxB > 0) {
      if (maxA > maxB) {
        insights.add(_Insight(
          Icons.flash_on,
          '$nameA has a higher top speed (${maxA.toStringAsFixed(1)} km/h vs ${maxB.toStringAsFixed(1)} km/h), giving an advantage in breakaway situations.',
          const Color(0xFF1D63FF),
        ));
      } else if (maxB > maxA) {
        insights.add(_Insight(
          Icons.flash_on,
          '$nameB has a higher top speed (${maxB.toStringAsFixed(1)} km/h vs ${maxA.toStringAsFixed(1)} km/h), giving an advantage in breakaway situations.',
          const Color(0xFFB7F408),
        ));
      }
    }

    // Sprints
    final spA = _v(aggA, 'totalSprints');
    final spB = _v(aggB, 'totalSprints');
    if (spA > 0 || spB > 0) {
      if (spA > spB) {
        insights.add(_Insight(
          Icons.directions_run,
          '$nameA makes ${spA.toInt()} sprints vs ${spB.toInt()}, demonstrating higher intensity off-the-ball movement.',
          AppColors.success,
        ));
      } else if (spB > spA) {
        insights.add(_Insight(
          Icons.directions_run,
          '$nameB makes ${spB.toInt()} sprints vs ${spA.toInt()}, demonstrating higher intensity off-the-ball movement.',
          AppColors.success,
        ));
      }
    }

    // Acceleration
    final acA = _v(aggA, 'totalAccelPeaks');
    final acB = _v(aggB, 'totalAccelPeaks');
    if (acA > 0 || acB > 0) {
      if (acA > acB) {
        insights.add(_Insight(
          Icons.trending_up,
          '$nameA shows ${acA.toInt()} acceleration peaks, indicating explosive bursts suitable for pressing play.',
          AppColors.warning,
        ));
      } else if (acB > acA) {
        insights.add(_Insight(
          Icons.trending_up,
          '$nameB shows ${acB.toInt()} acceleration peaks, indicating explosive bursts suitable for pressing play.',
          AppColors.warning,
        ));
      }
    }

    // Overall verdict
    int winsA = 0, winsB = 0;
    if (distA > distB) winsA++;
    if (distB > distA) winsB++;
    if (maxA > maxB) winsA++;
    if (maxB > maxA) winsB++;
    if (spA > spB) winsA++;
    if (spB > spA) winsB++;
    if (acA > acB) winsA++;
    if (acB > acA) winsB++;
    final avgA = _v(aggA, 'avgSpeedKmh');
    final avgB = _v(aggB, 'avgSpeedKmh');
    if (avgA > avgB) winsA++;
    if (avgB > avgA) winsB++;

    String verdict;
    if (winsA > winsB) {
      verdict =
          '$nameA leads in $winsA of 5 categories. Overall, $nameA currently shows stronger physical performance metrics based on AI video analysis.';
    } else if (winsB > winsA) {
      verdict =
          '$nameB leads in $winsB of 5 categories. Overall, $nameB currently shows stronger physical performance metrics based on AI video analysis.';
    } else {
      verdict =
          'Both players are evenly matched across all categories. Consider tactical fit and positional needs for your final assessment.';
    }

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(S.current.aiScoutingInsights,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: AppColors.primary,
                        letterSpacing: 1.2)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final ins in insights) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ins.icon, size: 16, color: ins.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(ins.text,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Divider(color: AppColors.border),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.emoji_events, size: 18, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(verdict,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Insight {
  const _Insight(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;
}

// ═══════════════════════════════════════════════════════════════════════════
//  VIDEO BREAKDOWN
// ═══════════════════════════════════════════════════════════════════════════

class _VideoBreakdown extends StatelessWidget {
  const _VideoBreakdown({
    required this.titleA,
    required this.titleB,
    required this.videosA,
    required this.videosB,
  });

  final String titleA;
  final String titleB;
  final List<dynamic> videosA;
  final List<dynamic> videosB;

  @override
  Widget build(BuildContext context) {
    if (videosA.isEmpty && videosB.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.current.perVideoBreakdown,
            style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8)),
        const SizedBox(height: 12),
        if (videosA.isNotEmpty) ...[
          _SectionLabel(titleA, const Color(0xFF1D63FF)),
          const SizedBox(height: 6),
          for (final v in videosA)
            _VideoMetricRow(video: v is Map ? Map<String, dynamic>.from(v) : {}),
          const SizedBox(height: 16),
        ],
        if (videosB.isNotEmpty) ...[
          _SectionLabel(titleB, const Color(0xFFB7F408)),
          const SizedBox(height: 6),
          for (final v in videosB)
            _VideoMetricRow(video: v is Map ? Map<String, dynamic>.from(v) : {}),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color))),
      ],
    );
  }
}

class _VideoMetricRow extends StatelessWidget {
  const _VideoMetricRow({required this.video});
  final Map<String, dynamic> video;

  @override
  Widget build(BuildContext context) {
    final name = (video['originalName'] ?? 'Video').toString();
    final m = video['metrics'] is Map ? Map<String, dynamic>.from(video['metrics'] as Map) : <String, dynamic>{};
    final dist = _d(m['distanceMeters']);
    final avg = _d(m['avgSpeedKmh']);
    final max = _d(m['maxSpeedKmh']);
    final sprints = _i(m['sprintCount']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _mini('Dist', '${dist.toStringAsFixed(0)}m'),
                _mini('Avg', '${avg.toStringAsFixed(1)} km/h'),
                _mini('Max', '${max.toStringAsFixed(1)} km/h'),
                _mini('Sprints', '$sprints'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11),
        children: [
          TextSpan(text: '$label ', style: const TextStyle(color: AppColors.textMuted)),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return 0;
  }

  int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LEGEND DOT
// ═══════════════════════════════════════════════════════════════════════════

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
