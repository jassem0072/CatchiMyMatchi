import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/locale_notifier.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Notifications screen — loads from GET /notifications.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifs = [];
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
      final uri = Uri.parse('${ApiConfig.baseUrl}/notifications');
      final res =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');
      final list = jsonDecode(res.body) as List;
      setState(() {
        _notifs = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/notifications/read-all'),
        headers: {'Authorization': 'Bearer $token'},
      );
      setState(() {
        for (final n in _notifs) {
          n['read'] = true;
        }
      });
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'challenge_completed':
        return Icons.emoji_events;
      case 'player_challenge':
        return Icons.emoji_events_outlined;
      case 'analysis_ready':
        return Icons.analytics;
      case 'favorited':
        return Icons.favorite;
      case 'team_invite':
        return Icons.group_add;
      case 'team_member_joined':
        return Icons.groups;
      case 'video_tag':
        return Icons.videocam;
      case 'video_request':
        return Icons.videocam_outlined;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'challenge_completed':
        return AppColors.success;
      case 'player_challenge':
        return const Color(0xFF1D63FF);
      case 'analysis_ready':
        return AppColors.primary;
      case 'favorited':
        return const Color(0xFFFF6B6B);
      case 'team_invite':
        return const Color(0xFF8B5CF6);
      case 'team_member_joined':
        return AppColors.success;
      case 'video_tag':
        return const Color(0xFFFF9800);
      case 'video_request':
        return const Color(0xFF8B5CF6);
      default:
        return AppColors.primary;
    }
  }

  Future<void> _acceptInvite(Map<String, dynamic> n) async {
    final teamId = (n['data'] ?? {})['teamId']?.toString();
    if (teamId == null || teamId.isEmpty) return;
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/teams/$teamId/accept'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode >= 400) throw Exception('Error ${res.statusCode}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined team!'), backgroundColor: AppColors.success),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _declineInvite(Map<String, dynamic> n) async {
    final teamId = (n['data'] ?? {})['teamId']?.toString();
    if (teamId == null || teamId.isEmpty) return;
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/teams/$teamId/decline'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode >= 400) throw Exception('Error ${res.statusCode}');
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isFr = LocaleNotifier.instance.isFrench;

    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.notificationsTitle),
        actions: [
          if (_notifs.any((n) => n['read'] == false))
            TextButton(
              onPressed: _markAllRead,
              child: Text(s.markAllRead,
                  style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(color: AppColors.txMuted(context))),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text(s.retry)),
                    ],
                  ),
                )
              : _notifs.isEmpty
                  ? _buildEmpty(context, s)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                        itemCount: _notifs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _buildTile(context, _notifs[i], isFr),
                      ),
                    ),
    );
  }

  Widget _buildEmpty(BuildContext context, S s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.notifications_none,
                  size: 48, color: AppColors.txMuted(context)),
              const SizedBox(height: 12),
              Text(s.noNotifications,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                s.allCaughtUp,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.txMuted(context), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTile(
      BuildContext context, Map<String, dynamic> n, bool isFr) {
    final type = n['type'] ?? '';
    final title = isFr ? (n['titleFR'] ?? n['titleEN'] ?? '') : (n['titleEN'] ?? '');
    final body = isFr ? (n['bodyFR'] ?? n['bodyEN'] ?? '') : (n['bodyEN'] ?? '');
    final isRead = n['read'] == true;
    final color = _colorForType(type);

    String timeAgo = '';
    try {
      final created = DateTime.parse(n['createdAt'] ?? '');
      final diff = DateTime.now().difference(created);
      if (diff.inDays > 0) {
        timeAgo = '${diff.inDays}d';
      } else if (diff.inHours > 0) {
        timeAgo = '${diff.inHours}h';
      } else {
        timeAgo = '${diff.inMinutes}m';
      }
    } catch (_) {}

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (type == 'video_tag') {
          final videoId = (n['data'] ?? {})['videoId']?.toString();
          if (videoId != null && videoId.isNotEmpty) {
            // Mark as read then navigate to playback
            _markRead(n);
            Navigator.of(context).pushNamed(
              AppRoutes.playback,
              arguments: videoId,
            );
          }
        }
      },
      child: GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconForType(type), color: color, size: 20),
          ),
          const SizedBox(width: 12),
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
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(
                          color: AppColors.txMuted(context), fontSize: 12)),
                ],
                if (timeAgo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(timeAgo,
                      style: TextStyle(
                          color: AppColors.txMuted(context), fontSize: 11)),
                ],
                if (type == 'team_invite' && !isRead) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _declineInvite(n),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            side: BorderSide(color: AppColors.bdr(context)),
                          ),
                          child: Text(S.of(context).decline,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _acceptInvite(n),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          child: Text(S.of(context).accept,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    final id = (n['_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/notifications/$id/read'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
  }
}
