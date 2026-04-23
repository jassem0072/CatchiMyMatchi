import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'fifa_card_stats.dart';

class SimplePlayerCard extends StatelessWidget {
  const SimplePlayerCard({
    super.key,
    required this.name,
    required this.stats,
    this.position = 'CM',
    this.portraitBytes,
    this.isVerified,
    this.onTap,
  });

  final String name;
  final FifaCardStats stats;
  final String position;
  final Uint8List? portraitBytes;
  final bool? isVerified;
  final VoidCallback? onTap;

  Color _getTierColor() {
    if (stats.ovr >= 80) return const Color(0xFFFFD700); // Gold
    if (stats.ovr >= 65) return const Color(0xFFC0C0C0); // Silver
    return const Color(0xFFCD7F32); // Bronze
  }

  String _getTierLabel() {
    if (stats.ovr >= 80) return 'LEGEND';
    if (stats.ovr >= 65) return 'RARE';
    return 'COMMON';
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor();
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 240,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1f3a), Color(0xFF0d1117)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: tierColor,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: tierColor.withValues(alpha: 0.3),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // Particles background
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParticlePainter(),
                ),
              ),

              // Content
              Column(
                children: [
                  const SizedBox(height: 8),
                  
                  // Tier badge
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: tierColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getTierLabel(),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1a1f3a),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Verification chip
                  if (isVerified != null)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isVerified == true
                              ? const Color(0xFF00E676).withValues(alpha: 0.18)
                              : const Color(0xFFFFB300).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isVerified == true
                                ? const Color(0xFF00E676)
                                : const Color(0xFFFFB300),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVerified == true ? Icons.verified_rounded : Icons.pending_rounded,
                              size: 10,
                              color: isVerified == true
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFFB300),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVerified == true ? 'VERIFIED' : 'PENDING',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                                color: isVerified == true
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFFFFB300),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Portrait with tier halo
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tierColor,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tierColor.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: portraitBytes != null
                          ? Image.memory(
                              portraitBytes!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: const Color(0xFF2a2f4a),
                              child: const Icon(
                                Icons.person,
                                size: 50,
                                color: Color(0xFF4a5f7a),
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Player name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: tierColor,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const Spacer(),

                  // OVR in blue bar
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00BFFF), Color(0xFF1E90FF)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      '${stats.ovr}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 30; i++) {
      final x = (i * 37.5) % size.width;
      final y = (i * 53.7) % size.height;
      canvas.drawCircle(Offset(x, y), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
