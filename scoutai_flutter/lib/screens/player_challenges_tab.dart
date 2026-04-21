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

class _PlayerChallengesTabState extends State<PlayerChallengesTab> {
  List<Map<String, dynamic>> _challenges = [];
  bool _loading = true;
  String? _error;

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
      final uri = Uri.parse('${ApiConfig.baseUrl}/challenges');
      final res =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final list = jsonDecode(res.body) as List;
      setState(() {
        _challenges = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
      default:
        return Icons.emoji_events;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isFr = LocaleNotifier.instance.isFrench;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: AppColors.txMuted(context))),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(s.retry)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Text(
            s.challengesTitle,
            style: TextStyle(
              color: AppColors.txMuted(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _challenges.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _AchievementTile(
              icon: _iconForKey(_challenges[i]['icon'] ?? ''),
              title: isFr
                  ? (_challenges[i]['titleFR'] ?? _challenges[i]['titleEN'] ?? '')
                  : (_challenges[i]['titleEN'] ?? ''),
              description: isFr
                  ? (_challenges[i]['descFR'] ?? _challenges[i]['descEN'] ?? '')
                  : (_challenges[i]['descEN'] ?? ''),
              progress: (_challenges[i]['progress'] ?? 0) as int,
              total: (_challenges[i]['target'] ?? 1) as int,
              unlocked: (_challenges[i]['completed'] ?? false) as bool,
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
  });

  final IconData icon;
  final String title;
  final String description;
  final int progress;
  final int total;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (progress / total).clamp(0.0, 1.0) : 0.0;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: unlocked
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.surf2(context),
              borderRadius: BorderRadius.circular(12),
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
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: unlocked ? null : AppColors.txMuted(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: AppColors.txMuted(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: AppColors.bdr(context),
                    color: unlocked ? AppColors.success : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (unlocked)
            const Icon(Icons.check_circle, color: AppColors.success, size: 22)
          else
            Text(
              '$progress/$total',
              style: TextStyle(
                color: AppColors.txMuted(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
