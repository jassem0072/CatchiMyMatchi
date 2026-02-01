import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../data/mock_data.dart';
import '../models/player_analysis.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class AnalysisDetailsScreen extends StatelessWidget {
  const AnalysisDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final PlayerAnalysis item = args is PlayerAnalysis
        ? args
        : mockAnalyses.firstWhere((e) => e.status == AnalysisStatus.done);

    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Player Analysis'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.share_outlined)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 56,
                      width: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2A44),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.person, color: AppColors.text),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.playerName,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Forward • Manchester United\nEngland | 26 years old',
                            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Pill(label: 'Pro Scout', color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {},
                        child: const Text('Follow'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        child: const Text('...'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI SCOUTING INSIGHT',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '"Exceptional high-intensity bursts in the final\nthird. Positioning heatmap shows heavy\npreference for left-channel exploits during\ntransitions."',
                  style: TextStyle(fontWeight: FontWeight.w600, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              MetricTile(label: 'Distance', value: '${item.distanceKm.toStringAsFixed(1)} km'),
              const SizedBox(width: 10),
              MetricTile(
                label: 'Top Speed',
                value: '${item.maxSpeedKmh.toStringAsFixed(1)} km/h',
                valueColor: AppColors.success,
              ),
              const SizedBox(width: 10),
              MetricTile(label: 'Sprints', value: '${item.sprints}'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Field Heatmap',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Live Tracking', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1D3B3A), Color(0xFF2E5B40), Color(0xFF0F1B2B)],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.playback),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_filled, size: 20),
                      SizedBox(width: 10),
                      Text('Watch Player in Video'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'MAIN ZONE\nLeft Wing',
                      style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        const Text(
                          'BOX ENTRIES\n12 Times',
                          style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () {},
                          child: const Row(
                            children: [
                              Text('View Details', style: TextStyle(color: AppColors.primary)),
                              SizedBox(width: 4),
                              Icon(Icons.open_in_new, size: 16, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Speed Timeline',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FakeLineChart(height: 130),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    Expanded(
                      child: Text(
                        'PEAK VELOCITY\n34.5 km/h at 58\'',
                        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'AVERAGE VELOCITY\n18.2 km/h',
                        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
