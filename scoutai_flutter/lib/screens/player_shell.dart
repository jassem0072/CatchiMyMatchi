import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/notification_badge.dart';
import 'player_home_tab.dart';
import 'player_team_tab.dart';
import 'player_challenges_tab.dart';

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  static const _brandLogoPath = 'assets/branding/scoutai_logo.png';

  int _navIndex = 0;

  List<String> _labels(BuildContext ctx) {
    final s = S.of(ctx);
    return [s.home, s.team, '+', s.challenges, s.profile];
  }
  static const _icons = [
    Icons.home_outlined,
    Icons.groups_outlined,
    Icons.add_circle_outline,
    Icons.emoji_events_outlined,
    Icons.person_outline,
  ];
  static const _activeIcons = [
    Icons.home,
    Icons.groups,
    Icons.add_circle,
    Icons.emoji_events,
    Icons.person,
  ];

  void _onNavTap(int idx) {
    if (idx == 2) {
      // Upload action — navigate to upload screen
      Navigator.of(context).pushNamed(AppRoutes.uploadVideo);
      return;
    }
    if (idx == 4) {
      // Profile — navigate to profile screen
      Navigator.of(context).pushNamed(AppRoutes.profile);
      return;
    }
    setState(() => _navIndex = idx);
  }

  Widget _buildBody() {
    switch (_navIndex) {
      case 0:
        return const PlayerHomeTab();
      case 1:
        return const PlayerTeamTab();
      case 3:
        return const PlayerChallengesTab();
      default:
        return const PlayerHomeTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  _brandLogoPath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.sports_soccer,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('ScoutAI', overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.comparator),
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Comparator',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.contractWorkflow),
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Contract Workflow',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).pushNamed(
                AppRoutes.aiCoach,
                arguments: <String, dynamic>{
                  'pac': 75, 'sho': 65, 'pas': 70, 'dri': 68,
                  'def': 60, 'phy': 72, 'ovr': 68,
                  'position': 'CM',
                  'maxSpeedKmh': '28.5', 'avgSpeedKmh': '12.3',
                  'distanceKm': '1.85', 'sprints': 4,
                  'trackingPoints': 120,
                },
              );
            },
            icon: const Icon(Icons.smart_toy),
            tooltip: 'AI Coach',
          ),
          NotificationBadge(
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.notifications),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surf(context).withValues(alpha: 0.95),
        selectedIndex: _navIndex < 2 ? _navIndex : (_navIndex == 2 ? 0 : _navIndex),
        onDestinationSelected: _onNavTap,
        destinations: List.generate(5, (i) {
          if (i == 2) {
            // Center "+" button
            return NavigationDestination(
              icon: Icon(_icons[i], color: AppColors.primary, size: 32),
              selectedIcon: Icon(_activeIcons[i], color: AppColors.primary, size: 32),
              label: '',
            );
          }
          return NavigationDestination(
            icon: Icon(_icons[i]),
            selectedIcon: Icon(_activeIcons[i]),
            label: _labels(context)[i],
          );
        }),
      ),
      body: _buildBody(),
    );
  }
}
