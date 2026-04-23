import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/scoutai_app.dart';
import '../core/network/api_exception.dart';
import '../features/player/models/player_video.dart';
import '../features/player/providers/player_providers.dart';
import '../models/player_analysis.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.insert_chart_outlined, size: 20),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Player Analysis',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications)),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.profile),
            icon: const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: _navIndex == 0
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.uploadVideo),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surf(context).withValues(alpha: 0.95),
        selectedIndex: _navIndex,
        onDestinationSelected: (v) => setState(() => _navIndex = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Teams'),
          NavigationDestination(icon: Icon(Icons.video_library), label: 'Uploads'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      body: _navIndex == 0 ? const _ExploreTab() : const _PlaceholderTab(),
    );
  }
}

class _ExploreTab extends ConsumerStatefulWidget {
  const _ExploreTab();

  @override
  ConsumerState<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<_ExploreTab> {
  bool _loading = true;
  String? _error;
  List<PlayerAnalysis> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatDate(DateTime? createdAt) {
    if (createdAt == null) return '';
    final d = createdAt.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  PlayerAnalysis _mapVideoToAnalysis(PlayerVideo video) {
    final createdAt = _formatDate(video.createdAt);
    final status = video.lastAnalysis == null ? AnalysisStatus.processing : AnalysisStatus.done;
    final analysis = video.lastAnalysis;

    return PlayerAnalysis(
      id: video.id,
      playerName: 'You',
      playerNumber: 0,
      matchName: createdAt.isNotEmpty ? '${video.originalName} • $createdAt' : video.originalName,
      distanceKm: analysis?.distanceKm ?? 0,
      maxSpeedKmh: analysis?.maxSpeedKmh ?? 0,
      sprints: analysis?.sprints ?? 0,
      status: status,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final videos = await ref.read(playerServiceProvider).getCurrentPlayerVideos();
      final items = videos.map(_mapVideoToAnalysis).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
        return;
      }
      setState(() {
        _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 88),
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Search players or matches',
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
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FilterChip(label: 'All Matches', icon: Icons.keyboard_arrow_down),
            _FilterChip(label: 'Processing', icon: Icons.keyboard_arrow_down),
            _FilterChip(label: 'Position', icon: Icons.keyboard_arrow_down),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Analysis',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                'View Archive',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (items.isEmpty)
          const GlassCard(
            padding: EdgeInsets.all(16),
            child: Text(
              'No uploads yet. Tap + to upload your first video.',
              style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
            ),
          )
        else
          for (final item in items) ...[
            _PlayerCard(item: item),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.item});

  final PlayerAnalysis item;

  @override
  Widget build(BuildContext context) {
    final statusPill = item.status == AnalysisStatus.done
        ? const Pill(label: 'Done', color: AppColors.success)
        : const Pill(label: 'Processing', color: AppColors.warning);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFF1B2A44),
                child: Icon(Icons.person, color: AppColors.tx(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${item.playerName} ',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '#${item.playerNumber}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.matchName,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              statusPill,
            ],
          ),
          const SizedBox(height: 14),
          if (item.status == AnalysisStatus.done) ...[
            Row(
              children: [
                MetricTile(label: 'Distance', value: '${item.distanceKm.toStringAsFixed(1)} km'),
                const SizedBox(width: 10),
                MetricTile(
                  label: 'Max Speed',
                  value: '${item.maxSpeedKmh.toStringAsFixed(1)} km/h',
                  valueColor: AppColors.success,
                ),
                const SizedBox(width: 10),
                MetricTile(label: 'Sprints', value: '${item.sprints}'),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppRoutes.details,
                  arguments: item,
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('View Match Heatmap'),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ] else ...[
            const Text(
              'AI Video Analysis',
              style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: item.progress ?? 0.68,
                      backgroundColor: AppColors.bdr(context),
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${((item.progress ?? 0.68) * 100).round()}%',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Tracking positional data from drone footage...',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.progress),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Analysis in progress'),
                  SizedBox(width: 8),
                  Icon(Icons.sync, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surf(context).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(width: 6),
          Icon(icon, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Static UI only',
        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
      ),
    );
  }
}
