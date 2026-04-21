import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/notification_badge.dart';
import 'scouter_following_tab.dart';
import 'scouter_marketplace_tab.dart';

class ScouterShell extends StatefulWidget {
  const ScouterShell({super.key});

  @override
  State<ScouterShell> createState() => _ScouterShellState();
}

class _ScouterShellState extends State<ScouterShell> {
  int _navIndex = 0;

  void _onNavTap(int idx) {
    if (idx == 2) {
      Navigator.of(context).pushNamed(AppRoutes.profile);
      return;
    }
    setState(() => _navIndex = idx);
  }

  Widget _buildBody() {
    switch (_navIndex) {
      case 0:
        return const ScouterFollowingTab();
      case 1:
        return const ScouterMarketplaceTab();
      default:
        return const ScouterFollowingTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.sports_soccer, color: AppColors.primary, size: 24),
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
          NotificationBadge(
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.notifications),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surf(context).withValues(alpha: 0.95),
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavTap,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.favorite_border), selectedIcon: const Icon(Icons.favorite), label: S.of(context).following),
          NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront), label: S.of(context).marketplace),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: S.of(context).profile),
        ],
      ),
      body: _buildBody(),
    );
  }
}
