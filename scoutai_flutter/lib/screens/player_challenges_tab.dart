import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/locale_notifier.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Player Challenges / Achievements tab — loads live data from GET /challenges.
class PlayerChallengesTab extends StatefulWidget {
  const PlayerChallengesTab({super.key});

  @override
  State<PlayerChallengesTab> createState() => _PlayerChallengesTabState();
}

enum _ChallengeFilter { all, inProgress, completed }

class _PlayerChallengesTabState extends State<PlayerChallengesTab> {
  static final List<Map<String, dynamic>> _challengeCatalog = [
    {
      'key': 'first_upload',
      'icon': 'upload_file',
      'titleEN': 'First Upload',
      'titleFR': 'Premier Upload',
      'descEN': 'Upload your first video for analysis.',
      'descFR': 'Envoyez votre premiere video pour analyse.',
      'target': 1,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Starter Badge + 50 XP',
      'rewardFR': 'Debloque le badge Starter + 50 XP',
      'tipsEN': ['Use a stable camera angle.', 'Upload a full-field clip.'],
      'tipsFR': ['Utilisez un angle stable.', 'Ajoutez un clip terrain complet.'],
    },
    {
      'key': 'speed_demon',
      'icon': 'speed',
      'titleEN': 'Speed Demon',
      'titleFR': 'Demon Vitesse',
      'descEN': 'Reach a top speed of 30 km/h.',
      'descFR': 'Atteignez une vitesse max de 30 km/h.',
      'target': 1,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Speed Crest + 100 XP',
      'rewardFR': 'Debloque le blason vitesse + 100 XP',
      'tipsEN': ['Sprint after a controlled first touch.', 'Warm up before max-speed runs.'],
      'tipsFR': ['Sprintez apres un bon premier controle.', 'Echauffez-vous avant les sprints max.'],
    },
    {
      'key': 'marathon_runner',
      'icon': 'directions_run',
      'titleEN': 'Marathon Runner',
      'titleFR': 'Coureur Marathon',
      'descEN': 'Cover 50 km total across all matches.',
      'descFR': 'Parcourez 50 km au total sur tous les matchs.',
      'target': 50,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Endurance Medal + 130 XP',
      'rewardFR': 'Debloque medaille endurance + 130 XP',
      'tipsEN': ['Keep pace consistent.', 'Track distance every match.'],
      'tipsFR': ['Gardez un rythme constant.', 'Suivez la distance a chaque match.'],
    },
    {
      'key': 'sprint_king',
      'icon': 'bolt',
      'titleEN': 'Sprint King',
      'titleFR': 'Roi du Sprint',
      'descEN': 'Complete 100 sprints total.',
      'descFR': 'Realisez 100 sprints au total.',
      'target': 100,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Turbo Frame + 160 XP',
      'rewardFR': 'Debloque cadre turbo + 160 XP',
      'tipsEN': ['Use short explosive runs.', 'Recover well between efforts.'],
      'tipsFR': ['Faites des courses explosives courtes.', 'Recuperez bien entre les efforts.'],
    },
    {
      'key': 'analyst',
      'icon': 'videocam',
      'titleEN': 'Analyst',
      'titleFR': 'Analyste',
      'descEN': 'Analyze 10 match videos.',
      'descFR': 'Analysez 10 videos de match.',
      'target': 10,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Insight Badge + 120 XP',
      'rewardFR': 'Debloque badge Insight + 120 XP',
      'tipsEN': ['Upload videos with clear visibility.', 'Review key moments after each report.'],
      'tipsFR': ['Envoyez des videos bien visibles.', 'Revoyez les moments cle apres chaque rapport.'],
    },
    {
      'key': 'rising_star',
      'icon': 'star',
      'titleEN': 'Rising Star',
      'titleFR': 'Etoile Montante',
      'descEN': 'Get favorited by 5 scouts.',
      'descFR': 'Soyez ajoute en favori par 5 scouts.',
      'target': 5,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Star Banner + 150 XP',
      'rewardFR': 'Debloque banniere star + 150 XP',
      'tipsEN': ['Keep profile highlights updated.', 'Share your best clips first.'],
      'tipsFR': ['Mettez a jour vos highlights.', 'Partagez vos meilleurs clips en premier.'],
    },
    {
      'key': 'precision_passer',
      'icon': 'tune',
      'titleEN': 'Precision Passer',
      'titleFR': 'Passeur Precision',
      'descEN': 'Complete 250 accurate passes.',
      'descFR': 'Reussissez 250 passes precises.',
      'target': 250,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Control Crest + 170 XP',
      'rewardFR': 'Debloque blason controle + 170 XP',
      'tipsEN': ['Open your body before passing.', 'Play one-touch in tight spaces.'],
      'tipsFR': ['Ouvrez le corps avant la passe.', 'Jouez en une touche sous pression.'],
    },
    {
      'key': 'playmaker_vision',
      'icon': 'visibility',
      'titleEN': 'Playmaker Vision',
      'titleFR': 'Vision Playmaker',
      'descEN': 'Deliver 30 key passes.',
      'descFR': 'Realisez 30 passes decisives.',
      'target': 30,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Vision Aura + 180 XP',
      'rewardFR': 'Debloque aura vision + 180 XP',
      'tipsEN': ['Scan before receiving.', 'Find diagonal passing lanes.'],
      'tipsFR': ['Scannez avant de recevoir.', 'Cherchez les lignes diagonales.'],
    },
    {
      'key': 'iron_wall',
      'icon': 'shield',
      'titleEN': 'Iron Wall',
      'titleFR': 'Mur de Fer',
      'descEN': 'Win 20 defensive duels.',
      'descFR': 'Gagnez 20 duels defensifs.',
      'target': 20,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Guard Badge + 165 XP',
      'rewardFR': 'Debloque badge garde + 165 XP',
      'tipsEN': ['Stay side-on in 1v1.', 'Delay before committing to tackle.'],
      'tipsFR': ['Restez de profil en duel.', 'Attendez le bon moment avant tacle.'],
    },
    {
      'key': 'long_shot_hero',
      'icon': 'sports_soccer',
      'titleEN': 'Long Shot Hero',
      'titleFR': 'Hero Tir Lointain',
      'descEN': 'Score 10 goals from outside the box.',
      'descFR': 'Marquez 10 buts hors surface.',
      'target': 10,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Sniper Emblem + 200 XP',
      'rewardFR': 'Debloque embleme sniper + 200 XP',
      'tipsEN': ['Strike through the ball cleanly.', 'Shoot after creating half a yard.'],
      'tipsFR': ['Frappez la balle proprement.', 'Tirez des que vous creez un espace.'],
    },
    {
      'key': 'endurance_beast',
      'icon': 'terrain',
      'titleEN': 'Endurance Beast',
      'titleFR': 'Beast Endurance',
      'descEN': 'Run 100 km in tracked matches.',
      'descFR': 'Courez 100 km sur matchs suivis.',
      'target': 100,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Iron Lung Title + 220 XP',
      'rewardFR': 'Debloque titre Iron Lung + 220 XP',
      'tipsEN': ['Balance intensity and recovery.', 'Hydrate well before each game.'],
      'tipsFR': ['Equilibrez intensite et recuperation.', 'Hydratez-vous avant chaque match.'],
    },
    {
      'key': 'defensive_brain',
      'icon': 'psychology',
      'titleEN': 'Defensive Brain',
      'titleFR': 'Cerveau Defensif',
      'descEN': 'Make 15 interceptions.',
      'descFR': 'Faites 15 interceptions.',
      'target': 15,
      'progress': 0,
      'completed': false,
      'rewardEN': 'Unlock Tactician Mark + 175 XP',
      'rewardFR': 'Debloque marque tacticien + 175 XP',
      'tipsEN': ['Read passing lanes early.', 'Step in only when angle is closed.'],
      'tipsFR': ['Lisez les lignes de passe tot.', 'Intervenez quand l angle est ferme.'],
    },
  ];

  List<Map<String, dynamic>> _challenges = [];
  List<dynamic> _videos = [];
  bool _loading = true;
  String? _error;
  _ChallengeFilter _filter = _ChallengeFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) throw Exception('Not logged in');

      final challengeUri = Uri.parse('${ApiConfig.baseUrl}/challenges');
      final challengeRes =
          await http.get(challengeUri, headers: {'Authorization': 'Bearer $token'});
      if (challengeRes.statusCode != 200) {
        throw Exception('Server error ${challengeRes.statusCode}');
      }
      final challengeList = jsonDecode(challengeRes.body) as List;

      List<dynamic> videos = [];
      try {
        final videoUri = Uri.parse('${ApiConfig.baseUrl}/me/videos');
        final videoRes = await http.get(videoUri, headers: {'Authorization': 'Bearer $token'});
        if (videoRes.statusCode < 400) {
          final parsed = jsonDecode(videoRes.body);
          if (parsed is List) videos = parsed;
        }
      } catch (_) {}

      setState(() {
        _challenges = challengeList.cast<Map<String, dynamic>>();
        _videos = videos;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value > 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is num) {
      final asInt = raw.toInt();
      final ms = asInt > 1000000000000 ? asInt : asInt * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  DateTime? _videoDate(Map<String, dynamic> video) {
    final candidates = [
      video['uploadedAt'],
      video['createdAt'],
      video['date'],
      video['updatedAt'],
      video['lastAnalysisAt'],
    ];
    for (final candidate in candidates) {
      final parsed = _parseTimestamp(candidate);
      if (parsed != null) return parsed;
    }

    final analysis = video['lastAnalysis'];
    if (analysis is Map) {
      final nested = _parseTimestamp(analysis['createdAt']) ??
          _parseTimestamp(analysis['updatedAt']) ??
          _parseTimestamp(analysis['date']);
      if (nested != null) return nested;
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _videosUploadedTodayCount() {
    final now = DateTime.now();
    var count = 0;
    for (final item in _videos) {
      if (item is! Map) continue;
      final video = Map<String, dynamic>.from(item);
      final dt = _videoDate(video);
      if (dt != null && _sameDay(dt, now)) {
        count++;
      }
    }
    return count;
  }

  double _todayBestMaxSpeed() {
    final now = DateTime.now();
    var best = 0.0;
    for (final item in _videos) {
      if (item is! Map) continue;
      final video = Map<String, dynamic>.from(item);
      final dt = _videoDate(video);
      if (dt == null || !_sameDay(dt, now)) continue;

      final analysis = video['lastAnalysis'];
      if (analysis is! Map) continue;
      final metrics = analysis['metrics'] is Map
          ? Map<String, dynamic>.from(analysis['metrics'] as Map)
          : Map<String, dynamic>.from(analysis);

      final speed = _asDouble(
        metrics['maxSpeedKmh'] ?? metrics['max_speed_kmh'] ?? metrics['maxSpeed'],
      ).clamp(0.0, 45.0);
      if (speed > best) best = speed;
    }
    return best;
  }

  int _completedChallengesCount(List<Map<String, dynamic>> allChallenges) {
    return allChallenges.where((item) => _asBool(item['completed'])).length;
  }

  String _challengeKey(Map<String, dynamic> challenge) {
    final raw = (challenge['key'] ??
            challenge['challengeId'] ??
            challenge['titleEN'] ??
            challenge['title'] ??
            challenge['name'] ??
            challenge['icon'] ??
            '')
        .toString();
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _text(bool isFr, String en, String fr) => isFr ? fr : en;

  String _titleFor(Map<String, dynamic> challenge, bool isFr) {
    return isFr
        ? (challenge['titleFR'] ?? challenge['titleEN'] ?? challenge['title'] ?? '')
            .toString()
        : (challenge['titleEN'] ?? challenge['title'] ?? '').toString();
  }

  String _descriptionFor(Map<String, dynamic> challenge, bool isFr) {
    return isFr
        ? (challenge['descFR'] ?? challenge['descEN'] ?? challenge['description'] ?? '')
            .toString()
        : (challenge['descEN'] ?? challenge['description'] ?? '').toString();
  }

  String _rewardFor(Map<String, dynamic> challenge, bool isFr) {
    return isFr
        ? (challenge['rewardFR'] ?? challenge['rewardEN'] ?? 'Badge + XP').toString()
        : (challenge['rewardEN'] ?? 'Badge + XP').toString();
  }

  List<String> _tipsFor(Map<String, dynamic> challenge, bool isFr) {
    final raw = isFr
        ? (challenge['tipsFR'] ?? challenge['tipsEN'])
        : (challenge['tipsEN'] ?? challenge['tipsFR']);
    if (raw is! List) return const [];
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _resolvedChallenges() {
    final merged = <String, Map<String, dynamic>>{};

    for (final seed in _challengeCatalog) {
      final item = Map<String, dynamic>.from(seed);
      final key = _challengeKey(item);
      item['key'] = key;
      merged[key] = item;
    }

    for (final challenge in _challenges) {
      final key = _challengeKey(challenge);
      final previous = merged[key] ?? <String, dynamic>{'key': key};
      merged[key] = {
        ...previous,
        ...challenge,
        'key': key,
      };
    }

    final resolved = merged.values.map((challenge) {
      var target = _asInt(challenge['target'], fallback: 1);
      if (target <= 0) target = 1;

      var progress = _asInt(challenge['progress']);
      if (progress < 0) progress = 0;
      if (progress > target) progress = target;

      final completed = _asBool(challenge['completed']) || progress >= target;

      return {
        ...challenge,
        'target': target,
        'progress': progress,
        'completed': completed,
      };
    }).toList();

    double ratio(Map<String, dynamic> item) {
      final total = _asInt(item['target'], fallback: 1);
      if (total <= 0) return 0;
      return _asInt(item['progress']) / total;
    }

    resolved.sort((a, b) {
      final aDone = _asBool(a['completed']);
      final bDone = _asBool(b['completed']);
      if (aDone != bDone) return aDone ? 1 : -1;
      return ratio(b).compareTo(ratio(a));
    });

    return resolved;
  }

  List<Map<String, dynamic>> _filteredChallenges(
    List<Map<String, dynamic>> challenges,
  ) {
    switch (_filter) {
      case _ChallengeFilter.completed:
        return challenges.where((item) => _asBool(item['completed'])).toList();
      case _ChallengeFilter.inProgress:
        return challenges
            .where((item) =>
                !_asBool(item['completed']) && _asInt(item['progress']) > 0)
            .toList();
      case _ChallengeFilter.all:
        return challenges;
    }
  }

  void _openDetails(Map<String, dynamic> challenge, bool isFr) {
    final title = _titleFor(challenge, isFr);
    final description = _descriptionFor(challenge, isFr);
    final reward = _rewardFor(challenge, isFr);
    final tips = _tipsFor(challenge, isFr);
    final progress = _asInt(challenge['progress']);
    final total = _asInt(challenge['target'], fallback: 1);
    final completed = _asBool(challenge['completed']);
    final icon = _iconForKey((challenge['icon'] ?? '').toString());

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChallengeDetailsSheet(
        icon: icon,
        title: title,
        description: description,
        reward: reward,
        progress: progress,
        total: total,
        completed: completed,
        tips: tips,
        isFr: isFr,
      ),
    );
  }

  Widget _dailyMissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required double progress,
    required String trailing,
    required bool done,
  }) {
    final clamped = progress.clamp(0.0, 1.0);
    final tone = done ? AppColors.success : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surf2(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.tx(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              if (done)
                const Icon(Icons.check_circle, size: 18, color: AppColors.success)
              else
                Text(
                  trailing,
                  style: TextStyle(
                    color: AppColors.txMuted(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.txMuted(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 6,
              backgroundColor: AppColors.bdr(context),
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForKey(String icon) {
    switch (icon) {
      case 'upload_file':
        return Icons.upload_file;
      case 'speed':
        return Icons.speed;
      case 'directions_run':
        return Icons.directions_run;
      case 'bolt':
        return Icons.bolt;
      case 'videocam':
        return Icons.videocam;
      case 'star':
        return Icons.star;
      case 'tune':
        return Icons.tune;
      case 'visibility':
        return Icons.visibility;
      case 'shield':
        return Icons.shield;
      case 'sports_soccer':
        return Icons.sports_soccer;
      case 'terrain':
        return Icons.terrain;
      case 'psychology':
        return Icons.psychology;
      default:
        return Icons.emoji_events;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isFr = LocaleNotifier.instance.isFrench;
    final allChallenges = _resolvedChallenges();
    final challenges = _filteredChallenges(allChallenges);
    final completedCount =
        allChallenges.where((item) => _asBool(item['completed'])).length;
    final activeCount = allChallenges
        .where((item) => !_asBool(item['completed']) && _asInt(item['progress']) > 0)
        .length;
    final completionRate =
        allChallenges.isEmpty ? 0.0 : (completedCount / allChallenges.length);
    final uploadsToday = _videosUploadedTodayCount();
    final completedChallenges = _completedChallengesCount(allChallenges);
    final todayBestSpeed = _todayBestMaxSpeed();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Text(
            s.challengesTitle,
            style: TextStyle(
              color: AppColors.tx(context),
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _text(
              isFr,
              'Tap a challenge to view full details, rewards, and tips.',
              'Touchez un defi pour voir les details, recompenses et conseils.',
            ),
            style: TextStyle(
              color: AppColors.txMuted(context),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.24),
                  AppColors.accent.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(isFr, 'Season Challenge Board', 'Tableau Defis Saison'),
                        style: TextStyle(
                          color: AppColors.tx(context),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _text(
                          isFr,
                          '$completedCount completed • $activeCount active now',
                          '$completedCount termines • $activeCount actifs',
                        ),
                        style: TextStyle(
                          color: AppColors.txMuted(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MiniStatPill(
                            label: _text(isFr, 'Total', 'Total'),
                            value: '${allChallenges.length}',
                          ),
                          _MiniStatPill(
                            label: _text(isFr, 'Done', 'Finis'),
                            value: '$completedCount',
                            color: AppColors.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _CircularCompletion(
                  progress: completionRate,
                  label: '${(completionRate * 100).round()}%',
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _text(
                        isFr,
                        'Live sync failed. Showing local challenge board.',
                        'Sync live echoue. Affichage des defis locaux.',
                      ),
                      style: TextStyle(
                        color: AppColors.txMuted(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      s.retry,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(isFr, 'Daily Missions', 'Missions du jour'),
                  style: TextStyle(
                    color: AppColors.tx(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _text(
                    isFr,
                    'Refresh each day and complete all 3 objectives.',
                    'Reviennent chaque jour. Terminez les 3 objectifs.',
                  ),
                  style: TextStyle(
                    color: AppColors.txMuted(context),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                _dailyMissionRow(
                  icon: Icons.upload_file,
                  title: _text(isFr, 'Upload 1 video', 'Uploader 1 video'),
                  subtitle: _text(
                    isFr,
                    'Post at least one match clip today.',
                    'Publiez au moins un clip de match aujourd hui.',
                  ),
                  progress: uploadsToday >= 1 ? 1 : uploadsToday.toDouble(),
                  trailing: '$uploadsToday / 1',
                  done: uploadsToday >= 1,
                ),
                const SizedBox(height: 10),
                _dailyMissionRow(
                  icon: Icons.emoji_events_outlined,
                  title: _text(isFr, 'Complete 1 challenge', 'Completer 1 defi'),
                  subtitle: _text(
                    isFr,
                    'Finish a challenge milestone.',
                    'Terminez un palier de defi.',
                  ),
                  progress: completedChallenges >= 1 ? 1 : completedChallenges.toDouble(),
                  trailing: '$completedChallenges / 1',
                  done: completedChallenges >= 1,
                ),
                const SizedBox(height: 10),
                _dailyMissionRow(
                  icon: Icons.speed,
                  title: _text(isFr, 'Reach 25 km/h', 'Atteindre 25 km/h'),
                  subtitle: _text(
                    isFr,
                    'Hit sprint speed in an analyzed match today.',
                    'Atteignez cette vitesse sur un match analyse aujourd hui.',
                  ),
                  progress: (todayBestSpeed / 25.0).clamp(0.0, 1.0),
                  trailing: '${todayBestSpeed.toStringAsFixed(1)} / 25.0 km/h',
                  done: todayBestSpeed >= 25,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChallengeFilterChip(
                label: _text(isFr, 'All', 'Tous'),
                selected: _filter == _ChallengeFilter.all,
                onTap: () => setState(() => _filter = _ChallengeFilter.all),
              ),
              _ChallengeFilterChip(
                label: _text(isFr, 'In Progress', 'En cours'),
                selected: _filter == _ChallengeFilter.inProgress,
                onTap: () => setState(() => _filter = _ChallengeFilter.inProgress),
              ),
              _ChallengeFilterChip(
                label: _text(isFr, 'Completed', 'Termines'),
                selected: _filter == _ChallengeFilter.completed,
                onTap: () => setState(() => _filter = _ChallengeFilter.completed),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (challenges.isEmpty)
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 32,
                      color: AppColors.txMuted(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _text(
                        isFr,
                        'No challenges in this filter yet.',
                        'Aucun defi dans ce filtre.',
                      ),
                      style: TextStyle(
                        color: AppColors.txMuted(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < challenges.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 260 + (i * 45)),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              child: _AchievementTile(
                icon: _iconForKey((challenges[i]['icon'] ?? '').toString()),
                title: _titleFor(challenges[i], isFr),
                description: _descriptionFor(challenges[i], isFr),
                progress: _asInt(challenges[i]['progress']),
                total: _asInt(challenges[i]['target'], fallback: 1),
                unlocked: _asBool(challenges[i]['completed']),
                onTap: () => _openDetails(challenges[i], isFr),
                detailsLabel: _text(isFr, 'Tap for details', 'Toucher pour details'),
              ),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: child,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.progress,
    required this.total,
    required this.unlocked,
    required this.onTap,
    required this.detailsLabel,
  });

  final IconData icon;
  final String title;
  final String description;
  final int progress;
  final int total;
  final bool unlocked;
  final VoidCallback onTap;
  final String detailsLabel;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (progress / total).clamp(0.0, 1.0) : 0.0;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: unlocked
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.surf2(context),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: unlocked
                          ? AppColors.primary
                          : AppColors.bdr(context).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: unlocked ? AppColors.primary : AppColors.txMuted(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 0.2,
                                color: unlocked ? null : AppColors.tx(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (unlocked)
                            const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                          else
                            Text(
                              '$progress/$total',
                              style: TextStyle(
                                color: AppColors.txMuted(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: AppColors.txMuted(context),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: AppColors.bdr(context)),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: pct,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: unlocked
                                          ? [
                                              AppColors.success,
                                              AppColors.success.withValues(alpha: 0.85),
                                            ]
                                          : [
                                              AppColors.primary,
                                              AppColors.accent.withValues(alpha: 0.8),
                                            ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              detailsLabel,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeFilterChip extends StatelessWidget {
  const _ChallengeFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.surf2(context),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.8)
                  : AppColors.bdr(context).withValues(alpha: 0.8),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.txMuted(context),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStatPill extends StatelessWidget {
  const _MiniStatPill({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tone.withValues(alpha: 0.15),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: tone,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CircularCompletion extends StatelessWidget {
  const _CircularCompletion({
    required this.progress,
    required this.label,
  });

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 7,
            backgroundColor: AppColors.bdr(context),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
          ),
          Center(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.tx(context),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeDetailsSheet extends StatelessWidget {
  const _ChallengeDetailsSheet({
    required this.icon,
    required this.title,
    required this.description,
    required this.reward,
    required this.progress,
    required this.total,
    required this.completed,
    required this.tips,
    required this.isFr,
  });

  final IconData icon;
  final String title;
  final String description;
  final String reward;
  final int progress;
  final int total;
  final bool completed;
  final List<String> tips;
  final bool isFr;

  String _text(String en, String fr) => isFr ? fr : en;

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (progress / total).clamp(0.0, 1.0) : 0.0;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(top: 48, bottom: bottomPad),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.bdr(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 50,
                            width: 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: AppColors.primary.withValues(alpha: 0.2),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.8),
                              ),
                            ),
                            child: Icon(icon, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: AppColors.tx(context),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  completed
                                      ? _text('Completed', 'Termine')
                                      : _text('In Progress', 'En cours'),
                                  style: TextStyle(
                                    color: completed
                                        ? AppColors.success
                                        : AppColors.warning,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        description,
                        style: TextStyle(
                          color: AppColors.txMuted(context),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _text('Progress', 'Progression'),
                        style: TextStyle(
                          color: AppColors.tx(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: AppColors.surf2(context),
                          border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$progress / $total',
                                  style: TextStyle(
                                    color: AppColors.tx(context),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${(ratio * 100).round()}%',
                                  style: TextStyle(
                                    color: AppColors.txMuted(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                height: 7,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(color: AppColors.bdr(context)),
                                    FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: ratio,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              completed ? AppColors.success : AppColors.primary,
                                              completed
                                                  ? AppColors.success.withValues(alpha: 0.85)
                                                  : AppColors.accent.withValues(alpha: 0.85),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _text('Reward', 'Recompense'),
                        style: TextStyle(
                          color: AppColors.tx(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: AppColors.success.withValues(alpha: 0.14),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          reward,
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _text('How to complete faster', 'Comment terminer plus vite'),
                        style: TextStyle(
                          color: AppColors.tx(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...tips.map(
                        (tip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(Icons.check_circle_outline,
                                    size: 16, color: AppColors.primary),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tip,
                                  style: TextStyle(
                                    color: AppColors.txMuted(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: _GradientActionButton(
                          label: _text('Close', 'Fermer'),
                          icon: Icons.check_circle_outline,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
