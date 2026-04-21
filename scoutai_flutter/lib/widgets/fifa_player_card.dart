import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'country_picker.dart';
import 'fifa_card_stats.dart';

// ── Tier enum based on OVR ──
enum _CardTier { bronze, silver, gold }

_CardTier _tierFromOvr(int ovr) {
  if (ovr >= 75) return _CardTier.gold;
  if (ovr >= 65) return _CardTier.silver;
  return _CardTier.bronze;
}

// ── Tier colors (EA FC 25 — dark bg + metallic frame) ──
class _TC {
  final Color framePrimary;
  final Color frameSecondary;
  final Color frameDark;
  final Color bg;
  final Color bgInner;
  final Color textLight;
  final Color textGold;
  final String label;

  const _TC({
    required this.framePrimary,
    required this.frameSecondary,
    required this.frameDark,
    required this.bg,
    required this.bgInner,
    required this.textLight,
    required this.textGold,
    required this.label,
  });

  static const gold = _TC(
    framePrimary: Color(0xFFD4A843), frameSecondary: Color(0xFFB8860B),
    frameDark: Color(0xFF6B4F10), bg: Color(0xFF0D1526),
    bgInner: Color(0xFF162036), textLight: Color(0xFFFFE8B0),
    textGold: Color(0xFFFFD700), label: 'GOLD',
  );

  static const silver = _TC(
    framePrimary: Color(0xFFC0C0C0), frameSecondary: Color(0xFF8A8A8A),
    frameDark: Color(0xFF555555), bg: Color(0xFF0D1526),
    bgInner: Color(0xFF162036), textLight: Color(0xFFE0E0E0),
    textGold: Color(0xFFB0B0B0), label: 'SILVER',
  );

  static const bronze = _TC(
    framePrimary: Color(0xFFCD7F32), frameSecondary: Color(0xFF8B5A2B),
    frameDark: Color(0xFF5A3820), bg: Color(0xFF0D1526),
    bgInner: Color(0xFF162036), textLight: Color(0xFFE8C9A0),
    textGold: Color(0xFFCD7F32), label: 'BRONZE',
  );

  static _TC fromTier(_CardTier t) {
    switch (t) {
      case _CardTier.gold: return gold;
      case _CardTier.silver: return silver;
      case _CardTier.bronze: return bronze;
    }
  }
}

/// EA FC 25 style 3D shield card — all sizes proportional to card width.
/// Tap to flip with gold burst. Fire glow on name. 3D tilt + shimmer.
class FifaPlayerCard extends StatefulWidget {
  const FifaPlayerCard({
    super.key,
    required this.name,
    required this.stats,
    this.position = 'CM',
    this.nation = '',
    this.portraitBytes,
    this.compact = false,
  });

  final String name;
  final FifaCardStats stats;
  final String position;
  final String nation;
  final Uint8List? portraitBytes;
  final bool compact;

  @override
  State<FifaPlayerCard> createState() => _FifaPlayerCardState();
}

class _FifaPlayerCardState extends State<FifaPlayerCard>
    with TickerProviderStateMixin {
  double _rotX = 0;
  double _rotY = 0;
  late AnimationController _shimmerCtrl;
  late AnimationController _entranceCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _tapCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _tapFlip;
  late Animation<double> _tapScale;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000),
    )..repeat();

    _entranceCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    )..forward();
    _scaleAnim = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutBack);

    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _tapCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    );
    _tapFlip = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOutBack),
    );
    _tapScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut));

    _tapCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _tapCtrl.reset();
        setState(() { _showBack = !_showBack; });
      }
    });
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _tapCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    setState(() {
      _rotY = (d.localPosition.dx - size.width / 2) / size.width * 0.3;
      _rotX = -(d.localPosition.dy - size.height / 2) / size.height * 0.3;
    });
  }

  void _onPanEnd(DragEndDetails _) => setState(() { _rotX = 0; _rotY = 0; });

  void _onTap() {
    if (!_tapCtrl.isAnimating) _tapCtrl.forward();
  }

  Color _statColor(int val) {
    if (val >= 80) return const Color(0xFF00E676);
    if (val >= 65) return const Color(0xFF69F0AE);
    if (val >= 50) return const Color(0xFFFFC107);
    if (val >= 35) return const Color(0xFFFF9800);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tierFromOvr(widget.stats.ovr);
    final tc = _TC.fromTier(tier);

    return LayoutBuilder(builder: (ctx, constraints) {
      // All sizes relative to s (scale factor from card width)
      final cardW = constraints.maxWidth.clamp(0.0, widget.compact ? 170.0 : 210.0);
      final cardH = cardW * 1.45;
      final s = cardW / 210; // scale factor (1.0 at 210px)

      return Center(
        child: GestureDetector(
          onPanUpdate: (d) => _onPanUpdate(d, Size(cardW, cardH)),
          onPanEnd: _onPanEnd,
          onTap: _onTap,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: AnimatedBuilder(
              animation: _tapCtrl,
              builder: (_, __) {
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(_rotX)
                    ..rotateY(_rotY + _tapFlip.value)
                    ..scale(_tapScale.value, _tapScale.value, 1.0),
                  child: SizedBox(
                    width: cardW,
                    height: cardH,
                    child: _showBack && !_tapCtrl.isAnimating
                        ? _buildBack(cardW, cardH, s, tc)
                        : _buildFront(cardW, cardH, s, tc),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }

  // ── FRONT FACE ──
  Widget _buildFront(double cardW, double cardH, double s, _TC tc) {
    final portraitD = 100 * s;

    return CustomPaint(
      size: Size(cardW, cardH),
      painter: _CardFramePainter(tc: tc),
      child: Stack(
        children: [
          // Shimmer
          AnimatedBuilder(
            animation: _shimmerCtrl,
            builder: (_, __) {
              final t = _shimmerCtrl.value;
              return Positioned.fill(
                child: ClipPath(
                  clipper: _ShieldClipper(inset: 0),
                  child: ShaderMask(
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment(-1.5 + 4 * t, -0.5),
                      end: Alignment(-0.8 + 4 * t, 0.5),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.srcATop,
                    child: Container(color: Colors.white.withValues(alpha: 0.03)),
                  ),
                ),
              );
            },
          ),

          // Content
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(12 * s),
              child: Column(
                children: [
                  // OVR + badge row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${widget.stats.ovr}', style: TextStyle(
                            fontSize: 32 * s, fontWeight: FontWeight.w900,
                            color: tc.textGold, height: 1,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 4, offset: const Offset(1, 1))],
                          )),
                          Text(widget.position.toUpperCase(), style: TextStyle(
                            fontSize: 12 * s, fontWeight: FontWeight.w800,
                            color: tc.textLight, letterSpacing: 1.5,
                          )),
                          if (widget.nation.isNotEmpty && flagForCountry(widget.nation).isNotEmpty)
                            Text(flagForCountry(widget.nation), style: TextStyle(fontSize: 16 * s, height: 1.3)),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [tc.framePrimary, tc.frameDark]),
                          borderRadius: BorderRadius.circular(4 * s),
                          border: Border.all(color: tc.framePrimary.withValues(alpha: 0.7)),
                        ),
                        child: Text(tc.label, style: TextStyle(
                          fontSize: 8 * s, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 1,
                        )),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * s),

                  // Portrait with pulsing glow
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      width: portraitD, height: portraitD,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tc.framePrimary, width: 3 * s),
                        boxShadow: [
                          BoxShadow(
                            color: tc.framePrimary.withValues(alpha: _pulseAnim.value),
                            blurRadius: 18 * s, spreadRadius: 2 * s,
                          ),
                          BoxShadow(color: Colors.black54, blurRadius: 8 * s, offset: Offset(0, 3 * s)),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: tc.frameDark.withValues(alpha: 0.7), width: 1.5 * s),
                          gradient: widget.portraitBytes == null
                              ? LinearGradient(colors: [tc.bgInner, tc.bg]) : null,
                          image: widget.portraitBytes != null
                              ? DecorationImage(image: MemoryImage(widget.portraitBytes!), fit: BoxFit.cover) : null,
                        ),
                        child: widget.portraitBytes == null
                            ? Icon(Icons.person, size: portraitD * 0.45, color: tc.textLight.withValues(alpha: 0.3)) : null,
                      ),
                    ),
                  ),
                  SizedBox(height: 4 * s),

                  // Name with fire glow
                  AnimatedBuilder(
                    animation: _shimmerCtrl,
                    builder: (_, __) {
                      final t = _shimmerCtrl.value;
                      return Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 4 * s),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            const Color(0xFFFF6B00).withValues(alpha: 0.06 + 0.05 * t),
                            Colors.transparent,
                          ]),
                          border: Border(
                            top: BorderSide(color: tc.framePrimary.withValues(alpha: 0.5), width: s),
                            bottom: BorderSide(color: tc.framePrimary.withValues(alpha: 0.5), width: s),
                          ),
                        ),
                        child: Text(
                          widget.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14 * s, fontWeight: FontWeight.w900,
                            letterSpacing: 2 * s, color: tc.textLight,
                            shadows: [
                              Shadow(color: const Color(0xFFFF6B00).withValues(alpha: 0.6 + 0.4 * t), blurRadius: 10 + 6 * t),
                              Shadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4 + 0.3 * t), blurRadius: 5 + 3 * t),
                              Shadow(color: const Color(0xFFFF4500).withValues(alpha: 0.25), blurRadius: 16 + 8 * t),
                              Shadow(color: Colors.black87, blurRadius: 2, offset: const Offset(0, 1)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 3 * s),

                  // Stats grid
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatBar(label: 'PAC', value: widget.stats.pac, color: _statColor(widget.stats.pac), tc: tc, s: s),
                            _StatBar(label: 'SHO', value: widget.stats.sho, color: _statColor(widget.stats.sho), tc: tc, s: s),
                            _StatBar(label: 'PAS', value: widget.stats.pas, color: _statColor(widget.stats.pas), tc: tc, s: s),
                          ],
                        )),
                        SizedBox(width: 8 * s),
                        Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatBar(label: 'DRI', value: widget.stats.dri, color: _statColor(widget.stats.dri), tc: tc, s: s),
                            _StatBar(label: 'DEF', value: widget.stats.def, color: _statColor(widget.stats.def), tc: tc, s: s),
                            _StatBar(label: 'PHY', value: widget.stats.phy, color: _statColor(widget.stats.phy), tc: tc, s: s),
                          ],
                        )),
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

  // ── BACK FACE (shown after tap flip) ──
  Widget _buildBack(double cardW, double cardH, double s, _TC tc) {
    final stats = widget.stats;
    return CustomPaint(
      size: Size(cardW, cardH),
      painter: _CardFramePainter(tc: tc),
      child: ClipPath(
        clipper: _ShieldClipper(inset: 8),
        child: Container(
          padding: EdgeInsets.all(16 * s),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star, color: tc.textGold, size: 28 * s),
              SizedBox(height: 6 * s),
              Text('OVERALL', style: TextStyle(
                fontSize: 10 * s, fontWeight: FontWeight.w700,
                color: tc.textLight.withValues(alpha: 0.6), letterSpacing: 2,
              )),
              Text('${stats.ovr}', style: TextStyle(
                fontSize: 48 * s, fontWeight: FontWeight.w900,
                color: tc.textGold, height: 1.1,
                shadows: [
                  Shadow(color: const Color(0xFFFF6B00).withValues(alpha: 0.7), blurRadius: 16),
                  Shadow(color: const Color(0xFFFFD700).withValues(alpha: 0.5), blurRadius: 8),
                ],
              )),
              SizedBox(height: 8 * s),
              Text(widget.name.toUpperCase(), style: TextStyle(
                fontSize: 13 * s, fontWeight: FontWeight.w900,
                color: tc.textLight, letterSpacing: 2,
              )),
              SizedBox(height: 4 * s),
              Container(height: 1, width: 60 * s, color: tc.framePrimary.withValues(alpha: 0.4)),
              SizedBox(height: 8 * s),
              Text(widget.position.toUpperCase(), style: TextStyle(
                fontSize: 11 * s, fontWeight: FontWeight.w700,
                color: tc.textLight.withValues(alpha: 0.7), letterSpacing: 1.5,
              )),
              SizedBox(height: 4 * s),
              Text('TAP TO FLIP', style: TextStyle(
                fontSize: 8 * s, fontWeight: FontWeight.w600,
                color: tc.textLight.withValues(alpha: 0.3),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shield clip path ──
class _ShieldClipper extends CustomClipper<Path> {
  _ShieldClipper({this.inset = 0});
  final double inset;

  @override
  Path getClip(Size size) => _shieldPath(size, inset);

  @override
  bool shouldReclip(covariant _ShieldClipper old) => old.inset != inset;
}

Path _shieldPath(Size size, double inset) {
  final w = size.width - inset * 2;
  final h = size.height - inset * 2;
  final ox = inset;
  final oy = inset;
  final r = w * 0.05;
  final notch = w * 0.06;
  final bevel = w * 0.05;
  final path = Path();

  path.moveTo(ox + r, oy);
  path.lineTo(ox + w * 0.35, oy);
  path.lineTo(ox + w * 0.42, oy + notch);
  path.lineTo(ox + w * 0.5, oy + notch * 1.2);
  path.lineTo(ox + w * 0.58, oy + notch);
  path.lineTo(ox + w * 0.65, oy);
  path.lineTo(ox + w - r, oy);
  path.quadraticBezierTo(ox + w, oy, ox + w, oy + r);
  path.lineTo(ox + w, oy + h * 0.72);
  path.lineTo(ox + w - bevel, oy + h - bevel);
  path.quadraticBezierTo(ox + w - bevel, oy + h, ox + w - bevel - r, oy + h);
  path.lineTo(ox + bevel + r, oy + h);
  path.quadraticBezierTo(ox + bevel, oy + h, ox + bevel, oy + h - bevel);
  path.lineTo(ox, oy + h * 0.72);
  path.lineTo(ox, oy + r);
  path.quadraticBezierTo(ox, oy, ox + r, oy);
  path.close();
  return path;
}

// ── Multi-layer 3D frame painter ──
class _CardFramePainter extends CustomPainter {
  _CardFramePainter({required this.tc});
  final _TC tc;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPath = _shieldPath(size, 0);
    canvas.drawShadow(outerPath, tc.framePrimary, 12, false);

    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [tc.framePrimary, tc.frameSecondary, tc.framePrimary, tc.frameDark, tc.framePrimary],
        stops: const [0.0, 0.2, 0.45, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(outerPath, outerPaint);

    final innerPath = _shieldPath(size, 8);
    final innerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [tc.bgInner, tc.bg, const Color(0xFF060B16)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(innerPath, innerPaint);

    // Diagonal streaks
    canvas.save();
    canvas.clipPath(innerPath);
    final streakPaint = Paint()
      ..color = tc.framePrimary.withValues(alpha: 0.07)
      ..strokeWidth = 2.0 ..style = PaintingStyle.stroke;
    for (double i = -size.height; i < size.width + size.height; i += 16) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height * 0.7, size.height), streakPaint);
    }
    final accentPaint = Paint()
      ..color = tc.framePrimary.withValues(alpha: 0.12)
      ..strokeWidth = 3.5 ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width * 0.15, 0), Offset(size.width * 0.65, size.height * 0.7), accentPaint);
    canvas.drawLine(Offset(size.width * 0.55, 0), Offset(size.width * 1.05, size.height * 0.7), accentPaint);
    canvas.restore();

    canvas.drawPath(_shieldPath(size, 10), Paint()
      ..color = tc.framePrimary.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke ..strokeWidth = 1.5);

    canvas.drawPath(outerPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [tc.framePrimary.withValues(alpha: 0.8), Colors.transparent],
        stops: const [0.0, 0.15],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke ..strokeWidth = 2.0);

    canvas.drawPath(outerPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
        stops: const [0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _CardFramePainter old) => false;
}

// ── Stat bar — all sizes proportional to s ──
class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.label,
    required this.value,
    required this.color,
    required this.tc,
    required this.s,
  });

  final String label;
  final int value;
  final Color color;
  final _TC tc;
  final double s;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 22 * s,
          child: Text(label, style: TextStyle(
            fontSize: 8 * s, fontWeight: FontWeight.w800,
            color: tc.textGold.withValues(alpha: 0.8), letterSpacing: 0.4,
          )),
        ),
        SizedBox(
          width: 20 * s,
          child: Text('$value', style: TextStyle(
            fontSize: 12 * s, fontWeight: FontWeight.w900,
            color: tc.textLight,
          )),
        ),
        SizedBox(width: 2 * s),
        Expanded(
          child: Container(
            height: 5 * s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3 * s),
              color: Colors.white.withValues(alpha: 0.15),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (value / 99).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3 * s),
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                  ),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6 * s)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
