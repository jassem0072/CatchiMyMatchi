import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Screen shown after video upload to tag teammates and set visibility.
class TagTeammatesScreen extends StatefulWidget {
  const TagTeammatesScreen({super.key});

  @override
  State<TagTeammatesScreen> createState() => _TagTeammatesScreenState();
}

class _TagTeammatesScreenState extends State<TagTeammatesScreen> {
  String? _videoId;
  bool _editMode = false;
  /// Each entry: { '_id', 'name', 'members': [...ids], 'memberDetails': [...] }
  List<Map<String, dynamic>> _teams = [];
  final Set<String> _selectedIds = {};
  final Set<String> _selectedTeamIds = {};
  bool _isPrivate = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _argsParsed = false;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsParsed) {
      _argsParsed = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _videoId = (args['videoId'] ?? '').toString();
        _editMode = args['editMode'] == true;
        // Preload existing tagged players if provided
        final existing = args['taggedPlayers'];
        if (existing is List) {
          for (final id in existing) {
            _selectedIds.add(id.toString());
          }
        }
      } else if (args is String) {
        _videoId = args;
      }
      if (_editMode && _videoId != null) _loadExistingTags();
    }
  }

  Future<void> _loadExistingTags() async {
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/me/videos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode < 400) {
        final videos = jsonDecode(res.body) as List;
        for (final v in videos) {
          if (v is Map && (v['_id'] ?? v['id'])?.toString() == _videoId) {
            final tagged = v['taggedPlayers'];
            if (tagged is List) {
              for (final id in tagged) {
                _selectedIds.add(id.toString());
              }
            }
            final taggedTeams = v['taggedTeams'];
            if (taggedTeams is List) {
              for (final id in taggedTeams) {
                _selectedTeamIds.add(id.toString());
              }
            }
            if (v['visibility'] == 'private') _isPrivate = true;
            break;
          }
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadTeams() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      // Get list of my teams
      final listRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/teams'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (listRes.statusCode != 200) throw Exception('Error ${listRes.statusCode}');
      final teamList = (jsonDecode(listRes.body) as List).cast<Map<String, dynamic>>();

      // Fetch details (with memberDetails) for each team
      final enriched = <Map<String, dynamic>>[];
      for (final t in teamList) {
        final id = (t['_id'] ?? '').toString();
        try {
          final detailRes = await http.get(
            Uri.parse('${ApiConfig.baseUrl}/teams/$id'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (detailRes.statusCode == 200) {
            enriched.add(jsonDecode(detailRes.body) as Map<String, dynamic>);
          } else {
            enriched.add(t);
          }
        } catch (_) {
          enriched.add(t);
        }
      }
      if (mounted) setState(() { _teams = enriched; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    final videoId = _videoId;
    if (videoId == null || videoId.isEmpty) {
      _goToIdentify();
      return;
    }

    setState(() => _saving = true);
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return;
      await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/me/videos/$videoId/tags'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'taggedPlayers': _selectedIds.toList(),
          'taggedTeams': _selectedTeamIds.toList(),
          'visibility': _isPrivate ? 'private' : 'public',
        }),
      );
      if (mounted) {
        if (_editMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Players tagged successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop();
        } else {
          _goToIdentify();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _goToIdentify() {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.identifyPlayer,
      arguments: _videoId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.tagTeammates),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                Text(
                  s.tagTeammates,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  s.tagTeammatesHint,
                  style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),

                // ── Visibility Toggle ──
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.videoVisibility,
                        style: TextStyle(
                          color: AppColors.txMuted(context),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _VisibilityOption(
                              icon: Icons.public,
                              label: s.publicVideo,
                              hint: s.publicHint,
                              selected: !_isPrivate,
                              onTap: () => setState(() => _isPrivate = false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _VisibilityOption(
                              icon: Icons.lock_outline,
                              label: s.privateVideo,
                              hint: s.privateHint,
                              selected: _isPrivate,
                              onTap: () => setState(() => _isPrivate = true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_error != null)
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: AppColors.txMuted(context))),
                  )
                else if (_teams.isEmpty)
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.groups_outlined, size: 40, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        Text(
                          s.noTeammates,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  // ── Teams with members ──
                  ..._teams.map((team) {
                    final teamId = (team['_id'] ?? '').toString();
                    final teamName = (team['name'] ?? '').toString();
                    final members = (team['memberDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final teamSelected = _selectedTeamIds.contains(teamId);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team header — tap to tag entire team
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            setState(() {
                              if (teamSelected) {
                                _selectedTeamIds.remove(teamId);
                                // Also deselect all members of this team
                                for (final m in members) {
                                  _selectedIds.remove((m['_id'] ?? '').toString());
                                }
                              } else {
                                _selectedTeamIds.add(teamId);
                                // Also select all members
                                for (final m in members) {
                                  _selectedIds.add((m['_id'] ?? '').toString());
                                }
                              }
                            });
                          },
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  height: 36, width: 36,
                                  decoration: BoxDecoration(
                                    color: teamSelected
                                        ? AppColors.primary.withValues(alpha: 0.2)
                                        : AppColors.surf2(context),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.groups, size: 20,
                                    color: teamSelected ? AppColors.primary : AppColors.txMuted(context)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(teamName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                                      Text('${members.length} ${s.members}',
                                        style: TextStyle(color: AppColors.txMuted(context), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: 28, width: 28,
                                  decoration: BoxDecoration(
                                    color: teamSelected ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: teamSelected ? AppColors.primary : AppColors.bdr(context),
                                      width: 2,
                                    ),
                                  ),
                                  child: teamSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Individual members
                        ...members.map((mate) {
                          final id = (mate['_id'] ?? '').toString();
                          final selected = _selectedIds.contains(id);
                          final name = (mate['displayName'] ?? mate['email'] ?? '').toString();
                          final position = (mate['position'] ?? '').toString();
                          return Padding(
                            padding: const EdgeInsets.only(left: 24, bottom: 6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedIds.remove(id);
                                    _selectedTeamIds.remove(teamId);
                                  } else {
                                    _selectedIds.add(id);
                                  }
                                });
                              },
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: selected
                                          ? AppColors.primary.withValues(alpha: 0.2)
                                          : AppColors.surf2(context),
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                        style: TextStyle(
                                          color: selected ? AppColors.primary : AppColors.txMuted(context),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                          if (position.isNotEmpty)
                                            Text(position, style: TextStyle(
                                              color: AppColors.txMuted(context), fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      height: 24, width: 24,
                                      decoration: BoxDecoration(
                                        color: selected ? AppColors.primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: selected ? AppColors.primary : AppColors.bdr(context),
                                          width: 2,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 14),
                      ],
                    );
                  }),

                const SizedBox(height: 24),

                // ── Action Buttons ──
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_editMode ? 'Save Tags' : s.saveAndContinue),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : _editMode
                          ? () => Navigator.of(context).pop()
                          : _goToIdentify,
                  child: Text(_editMode ? 'Cancel' : s.skipTagging),
                ),
              ],
            ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surf2(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.bdr(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.primary : AppColors.txMuted(context), size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected ? AppColors.primary : AppColors.tx(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.txMuted(context),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
