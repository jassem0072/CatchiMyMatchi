import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/jwt_utils.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Player Team tab: create teams, manage members, invite players.
class PlayerTeamTab extends StatefulWidget {
  const PlayerTeamTab({super.key});

  @override
  State<PlayerTeamTab> createState() => _PlayerTeamTabState();
}

class _PlayerTeamTabState extends State<PlayerTeamTab> {
  List<Map<String, dynamic>> _teams = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<String?> _token() => AuthStorage.loadToken();

  Future<void> _loadTeams() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await _token();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/teams'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');
      final list = jsonDecode(res.body) as List;
      setState(() {
        _teams = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _createTeam() async {
    final s = S.of(context);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surf(ctx),
        title: Text(s.createTeam),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.enterTeamName,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.bdr(ctx)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(s.create),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      final token = await _token();
      if (token == null) return;
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/teams'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode >= 400) throw Exception('Error ${res.statusCode}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).teamCreated), backgroundColor: AppColors.success),
        );
      }
      _loadTeams();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _openTeamDetails(Map<String, dynamic> team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TeamDetailScreen(
          teamId: (team['_id'] ?? '').toString(),
          teamName: team['name'] ?? '',
          onChanged: _loadTeams,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return RefreshIndicator(
      onRefresh: _loadTeams,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.myTeams,
                  style: TextStyle(
                    color: AppColors.txMuted(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _createTeam,
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.createTeam, style: const TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null)
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(_error!, style: TextStyle(color: AppColors.txMuted(context))),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loadTeams, child: Text(s.retry)),
              ]),
            )
          else if (_teams.isEmpty)
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.groups_outlined, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(s.noTeamsYet, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    s.createTeamHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ..._teams.map((team) {
              final memberCount = (team['members'] as List?)?.length ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _openTeamDetails(team),
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          height: 44, width: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.groups, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                team['name'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$memberCount ${s.members}',
                                style: TextStyle(color: AppColors.txMuted(context), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─── Team Detail Screen ─────────────────────────────────────────

class _TeamDetailScreen extends StatefulWidget {
  const _TeamDetailScreen({
    required this.teamId,
    required this.teamName,
    required this.onChanged,
  });

  final String teamId;
  final String teamName;
  final VoidCallback onChanged;

  @override
  State<_TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<_TeamDetailScreen> {
  Map<String, dynamic>? _team;
  bool _loading = true;
  String? _error;
  String? _myUserId;

  // Invite search
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;

  // Team videos
  List<Map<String, dynamic>> _teamVideos = [];

  @override
  void initState() {
    super.initState();
    _resolveUserId();
    _loadTeam();
    _loadTeamVideos();
  }

  Future<void> _loadTeamVideos() async {
    try {
      final token = await _token();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/teams/${widget.teamId}/videos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        if (mounted) setState(() => _teamVideos = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _resolveUserId() async {
    final token = await _token();
    if (token == null) return;
    final payload = decodeJwtPayload(token);
    if (mounted) setState(() => _myUserId = payload['sub']?.toString());
  }

  Future<String?> _token() => AuthStorage.loadToken();

  Future<void> _loadTeam() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await _token();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/teams/${widget.teamId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');
      setState(() {
        _team = jsonDecode(res.body);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _searchPlayers(String q) async {
    setState(() => _searching = true);
    try {
      final token = await _token();
      if (token == null) return;
      final uri = q.isEmpty
          ? '${ApiConfig.baseUrl}/teams/${widget.teamId}/search-players?q='
          : '${ApiConfig.baseUrl}/teams/${widget.teamId}/search-players?q=${Uri.encodeComponent(q)}';
      final res = await http.get(
        Uri.parse(uri),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        setState(() => _searchResults = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    setState(() => _searching = false);
  }

  Future<void> _loadAllPlayers() async {
    _searchCtrl.clear();
    await _searchPlayers('');
  }

  Future<void> _invitePlayer(String userId) async {
    try {
      final token = await _token();
      if (token == null) return;
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/teams/${widget.teamId}/invite'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      if (res.statusCode >= 400) {
        final body = jsonDecode(res.body);
        throw Exception(body['message'] ?? 'Error');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).inviteSent), backgroundColor: AppColors.success),
        );
      }
      _searchCtrl.clear();
      setState(() => _searchResults = []);
      _loadTeam();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _deleteTeam() async {
    final s = S.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surf(ctx),
        title: Text(s.deleteTeam),
        content: Text('${s.deleteTeam}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(s.deleteTeam),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await _token();
      if (token == null) return;
      await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/teams/${widget.teamId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _leaveTeam() async {
    try {
      final token = await _token();
      if (token == null) return;
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/teams/${widget.teamId}/leave'),
        headers: {'Authorization': 'Bearer $token'},
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
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
    final team = _team;
    final isOwner = team != null && _myUserId != null && team['ownerId'] == _myUserId;
    final memberDetails = (team?['memberDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final pendingDetails = (team?['pendingDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return GradientScaffold(
      appBar: AppBar(
        title: Text(widget.teamName),
        actions: [
          if (team != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _deleteTeam();
                if (v == 'leave') _leaveTeam();
              },
              itemBuilder: (_) => [
                if (isOwner)
                  PopupMenuItem(value: 'delete', child: Text(s.deleteTeam))
                else
                  PopupMenuItem(value: 'leave', child: Text(s.leaveTeam)),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: AppColors.txMuted(context))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: [
                    // ── Invite search (owner only) ──
                    if (isOwner) ...[
                      Text(s.invitePlayers, style: TextStyle(
                        color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8,
                      )),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchCtrl,
                        onChanged: _searchPlayers,
                        decoration: InputDecoration(
                          hintText: s.searchPlayersToInvite,
                          prefixIcon: const Icon(Icons.search),
                          fillColor: AppColors.surf(context).withValues(alpha: 0.7),
                          filled: true,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: AppColors.bdr(context).withValues(alpha: 0.8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _searching ? null : _loadAllPlayers,
                          icon: const Icon(Icons.people_outline, size: 18),
                          label: Text(s.suggestedPlayers, style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      if (_searchResults.isNotEmpty)
                        ..._searchResults.map((p) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                  child: Text(
                                    ((p['displayName'] ?? 'U').toString().isEmpty ? 'U' : (p['displayName'] ?? 'U').toString()).substring(0, 1).toUpperCase(),
                                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p['displayName'] ?? p['email'] ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      if ((p['position'] ?? '').toString().isNotEmpty)
                                        Text(p['position'], style: TextStyle(
                                          color: AppColors.txMuted(context), fontSize: 12)),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                  onPressed: () => _invitePlayer((p['_id'] ?? '').toString()),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  ),
                                  child: Text(s.invite, style: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        )),
                      const SizedBox(height: 24),
                    ],

                    // ── Members ──
                    Text(s.teamMembers, style: TextStyle(
                      color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8,
                    )),
                    const SizedBox(height: 10),
                    if (memberDetails.isEmpty)
                      GlassCard(
                        padding: const EdgeInsets.all(24),
                        child: Text(s.noTeamMembers, textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.txMuted(context))),
                      )
                    else
                      ...memberDetails.map((m) {
                        final memberId = (m['_id'] ?? '').toString();
                        final isTeamOwner = memberId == (team?['ownerId'] ?? '');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isTeamOwner
                                      ? AppColors.primary.withValues(alpha: 0.2)
                                      : AppColors.surf2(context),
                                  child: Text(
                                    ((m['displayName'] ?? 'U').toString().isEmpty ? 'U' : (m['displayName'] ?? 'U').toString()).substring(0, 1).toUpperCase(),
                                    style: TextStyle(
                                      color: isTeamOwner ? AppColors.primary : AppColors.txMuted(context),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m['displayName'] ?? m['email'] ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      if (isTeamOwner)
                                        Text(s.owner, style: const TextStyle(
                                          color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                    // ── Pending Invites ──
                    if (pendingDetails.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(s.pendingInvites, style: TextStyle(
                        color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8,
                      )),
                      const SizedBox(height: 10),
                      ...pendingDetails.map((p) {
                        final name = (p['displayName'] ?? p['email'] ?? '').toString();
                        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                                  child: Text(initial, style: const TextStyle(
                                    color: Colors.orange, fontWeight: FontWeight.w900)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                const Icon(Icons.hourglass_top, color: Colors.orange, size: 16),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],

                    // ── Team Videos ──
                    const SizedBox(height: 20),
                    Text('VIDEOS', style: TextStyle(
                      color: AppColors.txMuted(context), fontWeight: FontWeight.w900, letterSpacing: 1.8,
                    )),
                    const SizedBox(height: 10),
                    if (_teamVideos.isEmpty)
                      GlassCard(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          S.of(context).noDataAvailable,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.txMuted(context)),
                        ),
                      )
                    else
                      ..._teamVideos.map((v) {
                        final videoName = (v['originalName'] ?? 'Video').toString();
                        final uploaderName = (v['uploaderName'] ?? '').toString();
                        final videoId = (v['_id'] ?? '').toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.playback,
                                arguments: videoId,
                              );
                            },
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    height: 40, width: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(videoName,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                        if (uploaderName.isNotEmpty)
                                          Text('Uploaded by $uploaderName',
                                            style: TextStyle(
                                              color: AppColors.txMuted(context), fontSize: 11,
                                              fontStyle: FontStyle.italic)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }

}
