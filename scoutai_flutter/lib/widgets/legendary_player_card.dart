import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fifa_card_stats.dart';

/// Card tier colour palette — determined by OVR rating.
class _CardTier {
  final Color primary;
  final Color light;
  final Color dark;
  final Color deep;
  final Color glow;
  final String label;

  const _CardTier({
    required this.primary,
    required this.light,
    required this.dark,
    required this.deep,
    required this.glow,
    required this.label,
  });

  static const bronze = _CardTier(
    primary: Color(0xFFCD7F32),
    light: Color(0xFFE8A862),
    dark: Color(0xFF8B5A2B),
    deep: Color(0xFF5C3A1A),
    glow: Color(0xFFCD7F32),
    label: 'BRONZE',
  );

  static const silver = _CardTier(
    primary: Color(0xFFA8A8A8),
    light: Color(0xFFE0E0E0),
    dark: Color(0xFF707070),
    deep: Color(0xFF454545),
    glow: Color(0xFFC0C0C0),
    label: 'SILVER',
  );

  static const gold = _CardTier(
    primary: Color(0xFFD4A843),
    light: Color(0xFFFBEC5D),
    dark: Color(0xFF6B4F10),
    deep: Color(0xFF3D2E0A),
    glow: Color(0xFFFFD700),
    label: 'LEGEND',
  );

  static _CardTier fromOvr(int ovr) {
    if (ovr >= 80) return gold;
    if (ovr >= 70) return silver;
    return bronze;
  }
}

/// "Legendary Edition" FIFA-style player card.
///
/// Hyper-realistic 3D gold frame, midnight-blue body, circular portrait with
/// golden halo, metallic embossed name, neon-green stat bars with glass overlay,
/// gold particle effects and god rays.  Drop-in replacement for FifaPlayerCard.
class LegendaryPlayerCard extends StatefulWidget {
  const LegendaryPlayerCard({
    super.key,
    required this.name,
    required this.stats,
    this.position = 'CM',
    this.nation = '',
    this.year = '2020',
    this.portraitBytes,
    this.compact = false,
    this.onTap,
  });

  final String name;
  final FifaCardStats stats;
  final String position;
  final String nation;
  final String year;
  final Uint8List? portraitBytes;
  final bool compact;
  final VoidCallback? onTap;

  @override
  State<LegendaryPlayerCard> createState() => _LegendaryPlayerCardState();
}

class _LegendaryPlayerCardState extends State<LegendaryPlayerCard>
    with TickerProviderStateMixin {
  // ── Interactive 3D tilt ──
  double _rotX = 0;
  double _rotY = 0;

  // ── Animation controllers ──
  late AnimationController _shimmerCtrl;
  late AnimationController _entranceCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _particleCtrl;
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
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _scaleAnim = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutBack);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 0.75).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _tapFlip = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOutBack),
    );
    _tapScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut));

    _tapCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _tapCtrl.reset();
        setState(() => _showBack = !_showBack);
      }
    });
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    _tapCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    setState(() {
      _rotY = (d.localPosition.dx - size.width / 2) / size.width * 0.25;
      _rotX = -(d.localPosition.dy - size.height / 2) / size.height * 0.25;
    });
  }

  void _onPanEnd(DragEndDetails _) => setState(() {
        _rotX = 0;
        _rotY = 0;
      });

  void _onTap() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    if (!_tapCtrl.isAnimating) _tapCtrl.forward();
  }

  /// Current tier based on OVR (bronze / silver / gold).
  _CardTier get _tier => _CardTier.fromOvr(widget.stats.ovr);

  // ── Stat color: visually distinct per tier ──
  Color _statColor(int val) {
    if (val >= 80) return const Color(0xFF00E676); // bright green
    if (val >= 65) return const Color(0xFF76FF03); // lime
    if (val >= 50) return const Color(0xFFFFD600); // vivid yellow
    if (val >= 35) return const Color(0xFFFF6D00); // deep orange
    return const Color(0xFFFF1744); // bright red
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final cardW = constraints.maxWidth.clamp(0.0, widget.compact ? 180.0 : 320.0);
      final cardH = cardW * 1.42;
      final s = cardW / 320;

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
                    ..scaleByDouble(_tapScale.value, _tapScale.value, 1.0, 1.0),
                  child: SizedBox(
                    width: cardW,
                    height: cardH,
                    child: _showBack && !_tapCtrl.isAnimating
                        ? _buildBack(cardW, cardH, s)
                        : _buildFront(cardW, cardH, s),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  FRONT FACE
  // ══════════════════════════════════════════════════════════════
  Widget _buildFront(double cardW, double cardH, double s) {
    final portraitD = widget.compact ? 72 * s : 110 * s;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Layer 0: Outer glow / god rays ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: _tier.primary.withValues(alpha: 0.25 + 0.15 * _pulseAnim.value),
                    blurRadius: 40 * s,
                    spreadRadius: 8 * s,
                  ),
                  BoxShadow(
                    color: _tier.glow.withValues(alpha: 0.1 + 0.08 * _pulseAnim.value),
                    blurRadius: 80 * s,
                    spreadRadius: 16 * s,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Layer 1: Card frame (painted) ──
        Positioned.fill(
          child: CustomPaint(
            painter: _LegendaryFramePainter(shimmer: _shimmerCtrl, tier: _tier),
          ),
        ),

        // ── Layer 2: Holographic shimmer overlay ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _shimmerCtrl,
            builder: (_, __) {
              final t = _shimmerCtrl.value;
              return ClipPath(
                clipper: _LegendaryShieldClipper(inset: cardW * 0.05),
                child: ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment(-2.0 + 5 * t, -1.0),
                    end: Alignment(-1.0 + 5 * t, 1.0),
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.srcATop,
                  child: Container(color: Colors.white.withValues(alpha: 0.02)),
                ),
              );
            },
          ),
        ),

        // ── Layer 3: Particle overlay ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _particleCtrl,
            builder: (_, __) => ClipPath(
              clipper: _LegendaryShieldClipper(inset: cardW * 0.05),
              child: CustomPaint(
                painter: _ParticlePainter(progress: _particleCtrl.value, s: s, tier: _tier),
              ),
            ),
          ),
        ),

        // ── Layer 4: Content ──
        Positioned.fill(
          child: ClipPath(
            clipper: _LegendaryShieldClipper(inset: cardW * 0.05),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14 * s, 8 * s, 14 * s, 16 * s),
              child: Column(
                children: [
                  // ── OVR + Position badge row (top-left) + Crown (top-center) ──
                  SizedBox(height: 6 * s),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // OVR number + position
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [_tier.light, _tier.primary],
                            ).createShader(bounds),
                            child: Text(
                              '${widget.stats.ovr}',
                              style: TextStyle(
                                fontSize: 32 * s,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ),
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [_tier.primary, _tier.light],
                            ).createShader(bounds),
                            child: Text(
                              widget.position.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12 * s,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Crown icon
                      Padding(
                        padding: EdgeInsets.only(top: 2 * s),
                        child: _buildCrownIcon(s),
                      ),
                      const Spacer(),
                      // Edition badge
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_tier.primary, _tier.dark],
                          ),
                          borderRadius: BorderRadius.circular(4 * s),
                          border: Border.all(color: _tier.light.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          _tier.label,
                          style: TextStyle(
                            fontSize: 7 * s,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * s),

                  // ── Portrait with golden halo ──
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => _buildPortrait(portraitD, s),
                  ),
                  SizedBox(height: 8 * s),

                  // ── Name (gold metallic) ──
                  _buildGoldName(s),
                  SizedBox(height: 2 * s),

                  // ── Year ──
                  Text(
                    widget.year,
                    style: TextStyle(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFC0C0C0).withValues(alpha: 0.8),
                      letterSpacing: 3 * s,
                    ),
                  ),
                  SizedBox(height: 5 * s),

                  // ── Divider ──
                  Container(
                    height: 1,
                    margin: EdgeInsets.symmetric(horizontal: 12 * s),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          _tier.primary.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 4 * s),

                  // ── Stats rows ──
                  Expanded(child: _buildStatsSection(s)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCrownIcon(double s) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [_tier.dark, _tier.light, _tier.dark],
      ).createShader(bounds),
      child: Icon(
        Icons.shield,
        size: 26 * s,
        color: Colors.white,
      ),
    );
  }

  Widget _buildPortrait(double diameter, double s) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _tier.primary,
          width: 3.5 * s,
        ),
        boxShadow: [
          BoxShadow(
            color: _tier.glow.withValues(alpha: 0.3 + 0.25 * _pulseAnim.value),
            blurRadius: 24 * s,
            spreadRadius: 4 * s,
          ),
          BoxShadow(
            color: _tier.primary.withValues(alpha: 0.5),
            blurRadius: 12 * s,
            spreadRadius: 1 * s,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 10 * s,
            offset: Offset(0, 4 * s),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _tier.dark.withValues(alpha: 0.8),
            width: 2 * s,
          ),
          gradient: widget.portraitBytes == null
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF162036), Color(0xFF0D1526)],
                )
              : null,
          image: widget.portraitBytes != null
              ? DecorationImage(
                  image: MemoryImage(widget.portraitBytes!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: widget.portraitBytes == null
            ? Icon(Icons.person, size: diameter * 0.45, color: Colors.white24)
            : null,
      ),
    );
  }

  Widget _buildGoldName(double s) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          _tier.dark,
          _tier.light,
          _tier.glow,
          _tier.light,
          _tier.dark,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(bounds),
      child: Text(
        widget.name.toUpperCase(),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          fontSize: widget.compact ? 14 * s : 22 * s,
          fontWeight: FontWeight.w900,
          letterSpacing: 2 * s,
          color: Colors.white,
          height: 1.2,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(double s) {
    final stats = widget.stats;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6 * s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatRow('PAC', stats.pac, 'DRI', stats.dri, s),
          _buildStatRow('SHO', stats.sho, 'DEF', stats.def, s),
          _buildStatRow('PAS', stats.pas, 'PHY', stats.phy, s),
        ],
      ),
    );
  }

  Widget _buildStatRow(String l1, int v1, String l2, int v2, double s) {
    return Row(
      children: [
        Expanded(child: _LegendaryStatBar(label: l1, value: v1, color: _statColor(v1), s: s)),
        SizedBox(width: 8 * s),
        Expanded(child: _LegendaryStatBar(label: l2, value: v2, color: _statColor(v2), s: s)),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  BACK FACE
  // ══════════════════════════════════════════════════════════════
  Widget _buildBack(double cardW, double cardH, double s) {
    final stats = widget.stats;
    return Stack(
      children: [
        // Glow
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: _tier.primary.withValues(alpha: 0.3),
                  blurRadius: 40 * s,
                  spreadRadius: 8 * s,
                ),
              ],
            ),
          ),
        ),
        // Frame
        Positioned.fill(
          child: CustomPaint(
            painter: _LegendaryFramePainter(shimmer: _shimmerCtrl, tier: _tier),
          ),
        ),
        // Content
        Positioned.fill(
          child: ClipPath(
            clipper: _LegendaryShieldClipper(inset: 0),
            child: Container(
              padding: EdgeInsets.all(20 * s),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [_tier.dark, _tier.light, _tier.dark],
                    ).createShader(bounds),
                    child: Icon(Icons.star, size: 36 * s, color: Colors.white),
                  ),
                  SizedBox(height: 8 * s),
                  Text(
                    'OVERALL',
                    style: TextStyle(
                      fontSize: 11 * s,
                      fontWeight: FontWeight.w700,
                      color: _tier.light.withValues(alpha: 0.6),
                      letterSpacing: 3,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [_tier.dark, _tier.light, _tier.dark],
                    ).createShader(bounds),
                    child: Text(
                      '${stats.ovr}',
                      style: TextStyle(
                        fontSize: 56 * s,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(height: 8 * s),
                  _buildGoldName(s),
                  SizedBox(height: 6 * s),
                  Container(
                    height: 1,
                    width: 80 * s,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        _tier.primary.withValues(alpha: 0.5),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                  SizedBox(height: 8 * s),
                  Text(
                    widget.position.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFC0C0C0),
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 6 * s),
                  Text(
                    'TAP TO FLIP',
                    style: TextStyle(
                      fontSize: 9 * s,
                      fontWeight: FontWeight.w600,
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  LEGENDARY SHIELD CLIPPER
// ══════════════════════════════════════════════════════════════════════════════
class _LegendaryShieldClipper extends CustomClipper<Path> {
  _LegendaryShieldClipper({this.inset = 0});
  final double inset;

  @override
  Path getClip(Size size) => _legendaryShieldPath(size, inset);

  @override
  bool shouldReclip(covariant _LegendaryShieldClipper old) => old.inset != inset;
}

Path _legendaryShieldPath(Size size, double inset) {
  final w = size.width - inset * 2;
  final h = size.height - inset * 2;
  final ox = inset;
  final oy = inset;

  // Corner radius
  final r = w * 0.045;
  // Top notch (FIFA-style V-notch at top center)
  final notchW = w * 0.14;
  final notchH = w * 0.08;
  // Bottom point
  final bottomBevel = w * 0.08;
  final bottomPointH = h * 0.06;
  // Side notches near top
  final sideNotch = w * 0.015;

  final path = Path();

  // Start top-left corner
  path.moveTo(ox + r, oy);

  // Top edge left of notch
  path.lineTo(ox + w * 0.5 - notchW, oy);
  // V-notch down
  path.lineTo(ox + w * 0.5 - notchW * 0.35, oy + notchH * 0.7);
  path.lineTo(ox + w * 0.5, oy + notchH);
  path.lineTo(ox + w * 0.5 + notchW * 0.35, oy + notchH * 0.7);
  path.lineTo(ox + w * 0.5 + notchW, oy);

  // Top edge right of notch → top-right corner
  path.lineTo(ox + w - r, oy);
  path.quadraticBezierTo(ox + w, oy, ox + w, oy + r);

  // Right side — slight inward notch
  path.lineTo(ox + w, oy + h * 0.12);
  path.lineTo(ox + w - sideNotch, oy + h * 0.15);
  path.lineTo(ox + w, oy + h * 0.18);

  // Right side down to bottom curve
  path.lineTo(ox + w, oy + h * 0.75);

  // Bottom-right bevel
  path.quadraticBezierTo(
    ox + w, oy + h - bottomPointH,
    ox + w - bottomBevel, oy + h - bottomPointH * 0.5,
  );
  // Bottom point
  path.lineTo(ox + w * 0.5, oy + h);
  // Bottom-left bevel
  path.lineTo(ox + bottomBevel, oy + h - bottomPointH * 0.5);
  path.quadraticBezierTo(
    ox, oy + h - bottomPointH,
    ox, oy + h * 0.75,
  );

  // Left side up
  path.lineTo(ox, oy + h * 0.18);
  path.lineTo(ox + sideNotch, oy + h * 0.15);
  path.lineTo(ox, oy + h * 0.12);

  // Left side → top-left corner
  path.lineTo(ox, oy + r);
  path.quadraticBezierTo(ox, oy, ox + r, oy);

  path.close();
  return path;
}

// ══════════════════════════════════════════════════════════════════════════════
//  LEGENDARY FRAME PAINTER
// ══════════════════════════════════════════════════════════════════════════════
class _LegendaryFramePainter extends CustomPainter {
  _LegendaryFramePainter({required this.shimmer, required this.tier}) : super(repaint: shimmer);
  final Animation<double> shimmer;
  final _CardTier tier;

  static const _bgDark = Color(0xFF0A0F1E);
  static const _bgInner = Color(0xFF0F1628);

  @override
  void paint(Canvas canvas, Size size) {
    final outerPath = _legendaryShieldPath(size, 0);
    final innerPath = _legendaryShieldPath(size, size.width * 0.05);
    final midPath = _legendaryShieldPath(size, size.width * 0.025);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // ── Drop shadow ──
    canvas.drawShadow(outerPath, tier.primary, 18, false);

    // ── Outer frame (thick gradient) ──
    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tier.light, tier.primary, tier.dark, tier.primary, tier.light, tier.dark, tier.primary],
        stops: const [0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0],
      ).createShader(rect);
    canvas.drawPath(outerPath, outerPaint);

    // ── Ornate filigree patterns (etched lines in frame) ──
    canvas.save();
    final framePath = Path.combine(ui.PathOperation.difference, outerPath, innerPath);
    canvas.clipPath(framePath);

    final filigree = Paint()
      ..color = tier.deep.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Corner filigree — top-left
    _drawCornerFiligree(canvas, size, filigree, topLeft: true);
    _drawCornerFiligree(canvas, size, filigree, topLeft: false);

    // Geometric pattern lines along frame
    final patternPaint = Paint()
      ..color = tier.deep.withValues(alpha: 0.45)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final spacing = size.width * 0.025;
    for (double i = 0; i < size.height; i += spacing) {
      // Left edge
      canvas.drawLine(
        Offset(0, i),
        Offset(size.width * 0.05, i + spacing * 0.5),
        patternPaint,
      );
      // Right edge
      canvas.drawLine(
        Offset(size.width, i),
        Offset(size.width * 0.95, i + spacing * 0.5),
        patternPaint,
      );
    }
    canvas.restore();

    // ── Mid stroke (brushed metal highlight) ──
    canvas.drawPath(
      midPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tier.light.withValues(alpha: 0.7),
            tier.dark.withValues(alpha: 0.3),
            tier.light.withValues(alpha: 0.5),
          ],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Inner fill (midnight blue) ──
    final innerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_bgInner, _bgDark, Color(0xFF060A14)],
      ).createShader(rect);
    canvas.drawPath(innerPath, innerPaint);

    // ── Holographic X pattern inside body ──
    canvas.save();
    canvas.clipPath(innerPath);
    final xPaint = Paint()
      ..color = tier.primary.withValues(alpha: 0.04)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (double x = -size.height; x < size.width + size.height; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height * 0.6, size.height), xPaint);
      canvas.drawLine(Offset(x + size.height * 0.6, 0), Offset(x, size.height), xPaint);
    }
    canvas.restore();

    // ── Inner border highlight ──
    canvas.drawPath(
      innerPath,
      Paint()
        ..color = tier.primary.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // ── Top specular highlight ──
    canvas.drawPath(
      outerPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tier.light.withValues(alpha: 0.8),
            Colors.transparent,
          ],
          stops: const [0.0, 0.12],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── Bottom shadow edge ──
    canvas.drawPath(
      outerPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.6),
          ],
          stops: const [0.85, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _drawCornerFiligree(Canvas canvas, Size size, Paint paint, {required bool topLeft}) {
    final cx = topLeft ? size.width * 0.025 : size.width * 0.975;
    final cy = size.height * 0.03;
    final sx = topLeft ? 1.0 : -1.0;
    final step = size.width * 0.015;

    // Concentric arcs
    for (int i = 1; i <= 3; i++) {
      final r = step * i;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        topLeft ? 0 : math.pi,
        math.pi * 0.5,
        false,
        paint,
      );
    }

    // Diamond
    final dPath = Path()
      ..moveTo(cx + sx * step * 0.5, cy + step * 4)
      ..lineTo(cx + sx * step * 1.5, cy + step * 5)
      ..lineTo(cx + sx * step * 0.5, cy + step * 6)
      ..lineTo(cx - sx * step * 0.5, cy + step * 5)
      ..close();
    canvas.drawPath(dPath, paint);

    // Bottom filigree at bottom corners
    final by = size.height * 0.85;
    for (int i = 1; i <= 3; i++) {
      final r = step * i;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, by), radius: r),
        topLeft ? -math.pi * 0.5 : math.pi * 0.5,
        math.pi * 0.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LegendaryFramePainter old) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
//  PARTICLE PAINTER (golden sparkles)
// ══════════════════════════════════════════════════════════════════════════════
class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.progress, required this.s, required this.tier});
  final double progress;
  final double s;
  final _CardTier tier;

  static final _rng = math.Random(42);
  static final _particles = List.generate(18, (_) => _Particle.random(_rng));

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress + p.phase) % 1.0;
      final alpha = (math.sin(t * math.pi) * p.maxAlpha).clamp(0.0, 1.0);
      if (alpha < 0.02) continue;
      final x = p.x * size.width;
      final y = p.y * size.height - t * size.height * 0.15;
      final r = p.radius * s;

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = tier.glow.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8),
      );
      canvas.drawCircle(
        Offset(x, y),
        r * 0.4,
        Paint()..color = tier.light.withValues(alpha: alpha * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.progress != progress;
}

class _Particle {
  final double x, y, phase, maxAlpha, radius;
  const _Particle(this.x, this.y, this.phase, this.maxAlpha, this.radius);

  factory _Particle.random(math.Random rng) {
    return _Particle(
      rng.nextDouble(),
      rng.nextDouble(),
      rng.nextDouble(),
      0.3 + rng.nextDouble() * 0.5,
      2.0 + rng.nextDouble() * 3.0,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAT BAR (neon green + glass morphism)
// ══════════════════════════════════════════════════════════════════════════════
class _LegendaryStatBar extends StatelessWidget {
  const _LegendaryStatBar({
    required this.label,
    required this.value,
    required this.color,
    required this.s,
  });

  final String label;
  final int value;
  final Color color;
  final double s;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Label
        SizedBox(
          width: 30 * s,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11 * s,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFFFE8B0).withValues(alpha: 0.85),
              letterSpacing: 0.8,
            ),
          ),
        ),
        // Progress bar
        Expanded(
          child: Container(
            height: 12 * s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6 * s),
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Fill
                FractionallySizedBox(
                  widthFactor: (value / 99).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6 * s),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.7),
                          color,
                          color.withValues(alpha: 0.9),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8 * s),
                      ],
                    ),
                  ),
                ),
                // Glass overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6 * s),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 5 * s),
        // Value number
        SizedBox(
          width: 28 * s,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14 * s,
              fontWeight: FontWeight.w900,
              color: color,
              shadows: [
                Shadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
