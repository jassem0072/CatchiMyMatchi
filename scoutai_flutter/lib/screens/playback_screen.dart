import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/common.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  int _tab = 1;
  double _value = 0.28;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Match Day Analysis', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            Text(
              'FC Barcelona vs Real Madrid',
              style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.cast)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.share_outlined)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          AspectRatio(
            aspectRatio: 9 / 13,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.0, -0.6),
                        radius: 1.1,
                        colors: [Color(0xFF2C3E50), Color(0xFF0B1220)],
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.12),
                    child: Container(
                      height: 120,
                      width: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.9), width: 3),
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.06),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bolt, color: AppColors.warning, size: 18),
                          SizedBox(width: 10),
                          Text(
                            'MAX SPRINT DETECTED',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 88,
                    child: SegmentedTabs(
                      items: const ['Heatmap', 'HUD', 'Events'],
                      selectedIndex: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 42,
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: _value,
                            onChanged: (v) => setState(() => _value = v),
                            activeColor: AppColors.primary,
                            inactiveColor: AppColors.border,
                          ),
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('14:37', style: TextStyle(color: AppColors.textMuted)),
                            Text('90:00', style: TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.replay_10, color: AppColors.textMuted),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.skip_previous, color: AppColors.textMuted),
                          ),
                          Container(
                            height: 70,
                            width: 70,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(Icons.pause, color: Colors.white, size: 34),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.skip_next, color: AppColors.textMuted),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.forward_10, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'LIVE METRICS',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 2.0),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Current Speed', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text('24.8 km/h', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      SizedBox(height: 6),
                      Text('+2.4% vs Avg', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Distance', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text('8.42 km', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      SizedBox(height: 6),
                      Text('92% of target', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Heart Rate', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text('174 bpm', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      SizedBox(height: 6),
                      Text('Zone 5 (Peak)', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Work Rate', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text('High', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      SizedBox(height: 6),
                      Text('Optimal Performance', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'AI Tactical Insight',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'Mbappé is successfully exploiting space between the\nright-back and center-back. Current positioning\nsuggests a 78% probability of a goal-scoring\nopportunity in the next 5 minutes.',
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
