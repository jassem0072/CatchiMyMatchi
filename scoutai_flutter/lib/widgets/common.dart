import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBodyBehindAppBar = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const RadialGradient(
                center: Alignment(-0.4, -0.9),
                radius: 1.2,
                colors: [
                  Color(0xFF151F33),
                  AppColors.background,
                ],
              )
            : const RadialGradient(
                center: Alignment(-0.4, -0.9),
                radius: 1.2,
                colors: [
                  Color(0xFFFFFFFF),
                  AppColors.backgroundLight,
                ],
              ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: SafeArea(child: body),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF38BDF8),
            AppColors.primary,
            AppColors.accent,
          ],
        ),
      ),
      child: const Icon(Icons.trending_up, color: Colors.black, size: 34),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surf(context).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
      ),
      child: child,
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surf2(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: AppColors.txMuted(context),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: valueColor ?? AppColors.tx(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surf2(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      items[i],
                      style: TextStyle(
                        color: i == selectedIndex
                            ? Colors.white
                            : AppColors.txMuted(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FakeLineChart extends StatelessWidget {
  const FakeLineChart({super.key, this.height = 140});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartPainter(),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = AppColors.primary.withValues(alpha: 0.18);

    final points = <Offset>[];
    for (var i = 0; i <= 6; i++) {
      final t = i / 6.0;
      final y = 0.55 + 0.25 * math.sin(t * math.pi * 3.2);
      points.add(Offset(t * size.width, (1 - y) * size.height));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.quadraticBezierTo(
        (points[i - 1].dx + points[i].dx) / 2,
        points[i - 1].dy,
        points[i].dx,
        points[i].dy,
      );
    }

    canvas.drawPath(path, glow);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = AppColors.primary;
    canvas.drawCircle(points[4], 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
