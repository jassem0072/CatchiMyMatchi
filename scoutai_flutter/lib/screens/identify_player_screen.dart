import 'package:flutter/material.dart';

import '../app/scoutai_app.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class IdentifyPlayerScreen extends StatefulWidget {
  const IdentifyPlayerScreen({super.key});

  @override
  State<IdentifyPlayerScreen> createState() => _IdentifyPlayerScreenState();
}

class _IdentifyPlayerScreenState extends State<IdentifyPlayerScreen> {
  double _value = 0.36;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Identify Player'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.info_outline)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          const Text(
            'Scrub to the right frame and tap on the player to\nanalyze.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          _VideoMock(value: _value, onChanged: (v) => setState(() => _value = v)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MATCH EVENTS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 12,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'PRECISION SEEK',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
                  ),
                  child: const Icon(Icons.play_arrow, color: AppColors.text),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Match Start', style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(height: 4),
                      Text('00:00', style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.progress),
            child: const Text('Confirm selection'),
          ),
        ],
      ),
    );
  }
}

class _VideoMock extends StatelessWidget {
  const _VideoMock({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF25304A),
                          Color(0xFF0D1424),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '4K HDR • 60 FPS',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 130,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.55)),
                      ),
                      child: const Text(
                        'PLAYER LOCKED',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 11),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RoundIcon(icon: Icons.replay_5, onTap: () {}),
                        const SizedBox(width: 18),
                        Container(
                          height: 76,
                          width: 76,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                        ),
                        const SizedBox(width: 18),
                        _RoundIcon(icon: Icons.forward_5, onTap: () {}),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: value,
                            onChanged: onChanged,
                            activeColor: AppColors.primary,
                            inactiveColor: AppColors.border,
                          ),
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('32:10', style: TextStyle(color: AppColors.textMuted)),
                            Text('90:00', style: TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 46,
        width: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
