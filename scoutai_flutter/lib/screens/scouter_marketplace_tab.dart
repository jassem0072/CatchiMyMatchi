import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/country_picker.dart';
import '../widgets/fifa_card_stats.dart';
import '../widgets/simple_player_card.dart';

const _kPositions = [
  'GK', 'CB', 'LB', 'RB', 'LWB', 'RWB',
  'CDM', 'CM', 'CAM', 'LM', 'RM',
  'LW', 'RW', 'CF', 'ST',
];



/// Scouter Marketplace tab — browse all players.

class ScouterMarketplaceTab extends StatefulWidget {

  const ScouterMarketplaceTab({super.key});



  @override

  State<ScouterMarketplaceTab> createState() => _ScouterMarketplaceTabState();

}



class _ScouterMarketplaceTabState extends State<ScouterMarketplaceTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _players = [];
  String _search = '';

  // ── Filter state ──
  int? _minAge;
  int? _maxAge;
  String? _filterCountry;
  String? _filterPosition;
  int? _minOvr;
  int? _maxOvr;
  int? _minHeight;
  int? _maxHeight;

  final _minAgeCtrl = TextEditingController();
  final _maxAgeCtrl = TextEditingController();
  final _minOvrCtrl = TextEditingController();
  final _maxOvrCtrl = TextEditingController();
  final _minHtCtrl = TextEditingController();
  final _maxHtCtrl = TextEditingController();

  @override
  void dispose() {
    _minAgeCtrl.dispose();
    _maxAgeCtrl.dispose();
    _minOvrCtrl.dispose();
    _maxOvrCtrl.dispose();
    _minHtCtrl.dispose();
    _maxHtCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }



  Future<void> _load() async {

    setState(() { _loading = true; _error = null; });

    final token = await AuthStorage.loadToken();

    if (!mounted || token == null) return;

    try {

      final uri = Uri.parse('${ApiConfig.baseUrl}/players');

      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (res.statusCode >= 400) throw Exception('Failed to load players');

      final parsed = jsonDecode(res.body);

      if (parsed is! List) throw Exception('Invalid response');

      final list = parsed

          .whereType<Map>()

          .map((m) => Map<String, dynamic>.from(m))

          .toList();

      if (!mounted) return;

      setState(() { _players = list; _loading = false; });

    } catch (e) {

      if (!mounted) return;

      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });

    }

  }



  Future<void> _toggleFavorite(Map<String, dynamic> player) async {

    final token = await AuthStorage.loadToken();

    if (token == null) return;

    final playerId = (player['_id'] ?? player['id'])?.toString() ?? '';

    if (playerId.isEmpty) return;

    final isFav = player['isFavorite'] == true;

    try {

      if (isFav) {

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

      setState(() => player['isFavorite'] = !isFav);

    } catch (_) {}

  }



  int _playerAge(Map<String, dynamic> p) {
    final dob = p['dateOfBirth'] ?? p['dob'] ?? p['birthDate'];
    if (dob == null) return -1;
    try {
      final dt = DateTime.parse(dob.toString());
      final now = DateTime.now();
      int age = now.year - dt.year;
      if (now.month < dt.month || (now.month == dt.month && now.day < dt.day)) age--;
      return age;
    } catch (_) { return -1; }
  }

  int _playerHeight(Map<String, dynamic> p) {
    final h = p['height'] ?? p['heightCm'];
    if (h == null) return -1;
    if (h is num) return h.round();
    return int.tryParse(h.toString()) ?? -1;
  }

  bool get _hasActiveFilters =>
      _minAge != null || _maxAge != null ||
      _filterCountry != null || _filterPosition != null ||
      _minOvr != null || _maxOvr != null ||
      _minHeight != null || _maxHeight != null;

  void _clearFilters() {
    setState(() {
      _minAge = null; _maxAge = null;
      _filterCountry = null; _filterPosition = null;
      _minOvr = null; _maxOvr = null;
      _minHeight = null; _maxHeight = null;
    });
    _minAgeCtrl.clear(); _maxAgeCtrl.clear();
    _minOvrCtrl.clear(); _maxOvrCtrl.clear();
    _minHtCtrl.clear(); _maxHtCtrl.clear();
  }

  List<Map<String, dynamic>> get _filteredPlayers {
    return _players.where((p) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final name = (p['displayName'] ?? p['email'] ?? '').toString().toLowerCase();
        final pos = (p['position'] ?? '').toString().toLowerCase();
        final nat = (p['nation'] ?? p['country'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !pos.contains(q) && !nat.contains(q)) return false;
      }
      if (_filterPosition != null && _filterPosition!.isNotEmpty) {
        final pos = (p['position'] ?? '').toString().toUpperCase();
        if (pos != _filterPosition!.toUpperCase()) return false;
      }
      if (_filterCountry != null && _filterCountry!.isNotEmpty) {
        final nat = (p['nation'] ?? p['country'] ?? '').toString().toLowerCase();
        if (!nat.contains(_filterCountry!.toLowerCase())) return false;
      }
      final age = _playerAge(p);
      if (_minAge != null && age >= 0 && age < _minAge!) return false;
      if (_maxAge != null && age >= 0 && age > _maxAge!) return false;
      final ht = _playerHeight(p);
      if (_minHeight != null && ht >= 0 && ht < _minHeight!) return false;
      if (_maxHeight != null && ht >= 0 && ht > _maxHeight!) return false;
      final ovr = (p['_cachedOvr'] as int?) ?? -1;
      if (_minOvr != null && ovr >= 0 && ovr < _minOvr!) return false;
      if (_maxOvr != null && ovr >= 0 && ovr > _maxOvr!) return false;
      return true;
    }).toList();
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MarketFilterSheet(
        minAgeCtrl: _minAgeCtrl,
        maxAgeCtrl: _maxAgeCtrl,
        minOvrCtrl: _minOvrCtrl,
        maxOvrCtrl: _maxOvrCtrl,
        minHtCtrl: _minHtCtrl,
        maxHtCtrl: _maxHtCtrl,
        filterCountry: _filterCountry,
        filterPosition: _filterPosition,
        onApply: ({
          required int? minAge, required int? maxAge,
          required String? country, required String? position,
          required int? minOvr, required int? maxOvr,
          required int? minHeight, required int? maxHeight,
        }) {
          setState(() {
            _minAge = minAge; _maxAge = maxAge;
            _filterCountry = country; _filterPosition = position;
            _minOvr = minOvr; _maxOvr = maxOvr;
            _minHeight = minHeight; _maxHeight = maxHeight;
          });
        },
        onClear: _clearFilters,
      ),
    );
  }



  @override

  Widget build(BuildContext context) {

    if (_loading) return const Center(child: CircularProgressIndicator());



    final players = _filteredPlayers;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Text(
            S.of(context).marketplace.toUpperCase(),
            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8),
          ),
          const SizedBox(height: 4),
          Text(
            '${players.length} / ${_players.length} ${S.of(context).player.toLowerCase()}${_players.length == 1 ? '' : 's'} ${S.of(context).available}',
            style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
          ),
          const SizedBox(height: 12),
          // ── Search + Filter row ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: S.of(context).searchByNamePositionNation,
                    prefixIcon: const Icon(Icons.search),
                    fillColor: AppColors.surface.withValues(alpha: 0.7),
                    filled: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                children: [
                  Material(
                    color: _hasActiveFilters ? AppColors.primary : AppColors.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _openFilterSheet,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _hasActiveFilters ? AppColors.primary : AppColors.border.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Icon(
                          Icons.tune,
                          color: _hasActiveFilters ? Colors.white : AppColors.txMuted(context),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  if (_hasActiveFilters)
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.orangeAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_hasActiveFilters) ..._buildActiveFilterChips(context),
          const SizedBox(height: 16),

          if (_error != null)

            GlassCard(

              padding: const EdgeInsets.all(16),

              child: Column(

                children: [

                  Text(_error!, style: const TextStyle(color: AppColors.danger)),

                  const SizedBox(height: 8),

                  OutlinedButton(onPressed: _load, child: Text(S.of(context).retry)),

                ],

              ),

            )

          else if (players.isEmpty)

            GlassCard(

              padding: const EdgeInsets.all(24),

              child: Column(

                children: [

                  const Icon(Icons.person_search, size: 48, color: AppColors.textMuted),

                  const SizedBox(height: 12),

                  Text(S.of(context).noPlayersFound, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),

                  const SizedBox(height: 8),

                  Text(

                    S.of(context).playersWillAppear,

                    textAlign: TextAlign.center,

                    style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),

                  ),

                ],

              ),

            )

          else

            GridView.builder(

              shrinkWrap: true,

              physics: const NeverScrollableScrollPhysics(),

              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(

                crossAxisCount: 2,

                crossAxisSpacing: 12,

                mainAxisSpacing: 12,

                childAspectRatio: 0.62,

              ),

              itemCount: players.length,

              itemBuilder: (ctx, i) {

                final player = players[i];

                return _MarketplaceCardTile(

                  player: player,

                  onFavoriteToggle: () => _toggleFavorite(player),

                  onTap: () {

                    Navigator.of(context).pushNamed(

                      AppRoutes.playerDetail,

                      arguments: player,

                    );

                  },

                );

              },

            ),

        ],
      ),
    );
  }

  List<Widget> _buildActiveFilterChips(BuildContext context) {
    final chips = <Widget>[];
    void addChip(String label, VoidCallback onRemove) {
      chips.add(Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ));
    }
    if (_filterPosition != null) addChip(_filterPosition!, () => setState(() => _filterPosition = null));
    if (_filterCountry != null) addChip('${flagForCountry(_filterCountry!)} $_filterCountry', () => setState(() => _filterCountry = null));
    if (_minAge != null || _maxAge != null) {
      addChip('${_minAge ?? '?'}-${_maxAge ?? '?'} yrs', () { setState(() { _minAge = null; _maxAge = null; }); _minAgeCtrl.clear(); _maxAgeCtrl.clear(); });
    }
    if (_minOvr != null || _maxOvr != null) {
      addChip('OVR ${_minOvr ?? '?'}-${_maxOvr ?? '?'}', () { setState(() { _minOvr = null; _maxOvr = null; }); _minOvrCtrl.clear(); _maxOvrCtrl.clear(); });
    }
    if (_minHeight != null || _maxHeight != null) {
      addChip('${_minHeight ?? '?'}-${_maxHeight ?? '?'} cm', () { setState(() { _minHeight = null; _maxHeight = null; }); _minHtCtrl.clear(); _maxHtCtrl.clear(); });
    }
    if (chips.isEmpty) return [];
    return [
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 4, children: chips),
    ];
  }
}

class _MarketplaceCardTile extends StatefulWidget {

  const _MarketplaceCardTile({

    required this.player,

    required this.onFavoriteToggle,

    required this.onTap,

  });



  final Map<String, dynamic> player;

  final VoidCallback onFavoriteToggle;

  final VoidCallback onTap;



  @override

  State<_MarketplaceCardTile> createState() => _MarketplaceCardTileState();

}



class _MarketplaceCardTileState extends State<_MarketplaceCardTile> {

  Uint8List? _portrait;

  FifaCardStats _stats = FifaCardStats.empty;



  @override

  void initState() {

    super.initState();

    _loadData();

  }



  Future<void> _loadData() async {

    final id = (widget.player['_id'] ?? widget.player['id'])?.toString() ?? '';

    if (id.isEmpty) return;

    final token = await AuthStorage.loadToken();

    if (token == null || !mounted) return;



    // Load portrait and dashboard in parallel

    final portraitFuture = http.get(

      Uri.parse('${ApiConfig.baseUrl}/players/$id/portrait'),

      headers: {'Authorization': 'Bearer $token'},

    );

    final dashboardFuture = http.get(

      Uri.parse('${ApiConfig.baseUrl}/players/$id/dashboard'),

      headers: {'Authorization': 'Bearer $token'},

    );



    try {

      final results = await Future.wait([portraitFuture, dashboardFuture]);

      if (!mounted) return;



      // Portrait

      final pRes = results[0];

      if (pRes.statusCode >= 400 && pRes.statusCode != 204) {

        debugPrint('GET ${ApiConfig.baseUrl}/players/$id/portrait -> ${pRes.statusCode}');

        if (pRes.body.isNotEmpty) debugPrint(pRes.body);

      }

      final ct = (pRes.headers['content-type'] ?? '').toLowerCase();

      if (pRes.statusCode < 400 && pRes.bodyBytes.isNotEmpty && ct.startsWith('image/')) {

        _portrait = pRes.bodyBytes;

      }



      // Dashboard → compute stats

      final dRes = results[1];

      if (dRes.statusCode >= 400) {

        debugPrint('GET ${ApiConfig.baseUrl}/players/$id/dashboard -> ${dRes.statusCode}');

        if (dRes.body.isNotEmpty) debugPrint(dRes.body);

      }

      if (dRes.statusCode < 400) {
        final data = jsonDecode(dRes.body);
        if (data is Map<String, dynamic>) {
          final posLabel = (widget.player['position'] ?? 'CM').toString();
          _stats = _computeStats(data, posLabel);
          widget.player['_cachedOvr'] = _stats.ovr;
        }
      }



      setState(() {});

    } catch (_) {}

  }



  FifaCardStats _computeStats(Map<String, dynamic> dashboard, String posLabel) {

    final videos = dashboard['videos'] is List ? dashboard['videos'] as List : [];

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



  @override

  Widget build(BuildContext context) {

    final name = (widget.player['displayName'] ?? widget.player['email'] ?? 'Player').toString();

    final position = (widget.player['position'] ?? '').toString();

    final nation = (widget.player['nation'] ?? '').toString();

    final isFav = widget.player['isFavorite'] == true;



    return Stack(

        children: [

          SimplePlayerCard(

            name: name,

            stats: _stats,

            position: position.isNotEmpty ? position : '?',

            portraitBytes: _portrait,

            onTap: widget.onTap,

          ),

          // Favorite button overlay

          Positioned(

            top: 4,

            right: 4,

            child: GestureDetector(

              onTap: widget.onFavoriteToggle,

              child: Container(

                padding: const EdgeInsets.all(6),

                decoration: BoxDecoration(

                  color: Colors.black54,

                  shape: BoxShape.circle,

                ),

                child: Icon(

                  isFav ? Icons.favorite : Icons.favorite_border,

                  color: isFav ? Colors.redAccent : Colors.white70,

                  size: 18,

                ),

              ),

            ),

          ),

        ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FILTER BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

typedef _OnApplyMarketFilters = void Function({
  required int? minAge, required int? maxAge,
  required String? country, required String? position,
  required int? minOvr, required int? maxOvr,
  required int? minHeight, required int? maxHeight,
});

class _MarketFilterSheet extends StatefulWidget {
  const _MarketFilterSheet({
    required this.minAgeCtrl, required this.maxAgeCtrl,
    required this.minOvrCtrl, required this.maxOvrCtrl,
    required this.minHtCtrl, required this.maxHtCtrl,
    required this.filterCountry, required this.filterPosition,
    required this.onApply, required this.onClear,
  });
  final TextEditingController minAgeCtrl, maxAgeCtrl;
  final TextEditingController minOvrCtrl, maxOvrCtrl;
  final TextEditingController minHtCtrl, maxHtCtrl;
  final String? filterCountry;
  final String? filterPosition;
  final _OnApplyMarketFilters onApply;
  final VoidCallback onClear;

  @override
  State<_MarketFilterSheet> createState() => _MarketFilterSheetState();
}

class _MarketFilterSheetState extends State<_MarketFilterSheet> {
  late String? _position;
  late String? _country;

  @override
  void initState() {
    super.initState();
    _position = widget.filterPosition;
    _country = widget.filterCountry;
  }

  void _apply() {
    widget.onApply(
      minAge: int.tryParse(widget.minAgeCtrl.text),
      maxAge: int.tryParse(widget.maxAgeCtrl.text),
      country: _country, position: _position,
      minOvr: int.tryParse(widget.minOvrCtrl.text),
      maxOvr: int.tryParse(widget.maxOvrCtrl.text),
      minHeight: int.tryParse(widget.minHtCtrl.text),
      maxHeight: int.tryParse(widget.maxHtCtrl.text),
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onClear();
    setState(() { _position = null; _country = null; });
    Navigator.of(context).pop();
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
                const Icon(Icons.tune, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('FILTERS', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                TextButton(onPressed: _clear, child: const Text('Clear all', style: TextStyle(color: AppColors.primary))),
              ]),
            ),
            Divider(color: borderColor, height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  // ── Position ──
                  _FilterLabel(label: 'POSITION', color: mutedColor),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _FilterChip(label: 'All', selected: _position == null, onTap: () => setState(() => _position = null)),
                    for (final pos in _kPositions)
                      _FilterChip(label: pos, selected: _position == pos,
                        onTap: () => setState(() => _position = _position == pos ? null : pos)),
                  ]),
                  const SizedBox(height: 20),

                  // ── Country ──
                  _FilterLabel(label: 'COUNTRY', color: mutedColor),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showCountryPicker(context, current: _country);
                      if (picked != null && mounted) setState(() => _country = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _country != null
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _country != null ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(children: [
                        if (_country != null) ...[
                          Text(flagForCountry(_country!), style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_country!, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14))),
                          GestureDetector(onTap: () => setState(() => _country = null),
                            child: Icon(Icons.close, size: 18, color: mutedColor)),
                        ] else ...[
                          Icon(Icons.public, size: 20, color: mutedColor),
                          const SizedBox(width: 10),
                          Expanded(child: Text('All Countries', style: TextStyle(color: mutedColor, fontSize: 14))),
                          Icon(Icons.arrow_drop_down, color: mutedColor),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Age ──
                  _FilterLabel(label: 'AGE RANGE', color: mutedColor),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _NumField(ctrl: widget.minAgeCtrl, hint: 'Min age', textColor: textColor, borderColor: borderColor)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('—', style: TextStyle(color: mutedColor))),
                    Expanded(child: _NumField(ctrl: widget.maxAgeCtrl, hint: 'Max age', textColor: textColor, borderColor: borderColor)),
                  ]),
                  const SizedBox(height: 20),

                  // ── OVR ──
                  _FilterLabel(label: 'AVG RATING (OVR)', color: mutedColor),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _NumField(ctrl: widget.minOvrCtrl, hint: 'Min OVR', textColor: textColor, borderColor: borderColor)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('—', style: TextStyle(color: mutedColor))),
                    Expanded(child: _NumField(ctrl: widget.maxOvrCtrl, hint: 'Max OVR', textColor: textColor, borderColor: borderColor)),
                  ]),
                  const SizedBox(height: 20),

                  // ── Height ──
                  _FilterLabel(label: 'HEIGHT (CM)', color: mutedColor),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _NumField(ctrl: widget.minHtCtrl, hint: 'Min cm', textColor: textColor, borderColor: borderColor)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('—', style: TextStyle(color: mutedColor))),
                    Expanded(child: _NumField(ctrl: widget.maxHtCtrl, hint: 'Max cm', textColor: textColor, borderColor: borderColor)),
                  ]),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(label,
    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4));
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(
        color: selected ? Colors.white : AppColors.primary,
        fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );
}

class _NumField extends StatelessWidget {
  const _NumField({required this.ctrl, required this.hint, required this.textColor, required this.borderColor});
  final TextEditingController ctrl;
  final String hint;
  final Color textColor;
  final Color borderColor;
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    style: TextStyle(color: textColor, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: borderColor, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    ),
  );
}
