import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../badges.dart';
import '../theme.dart';
import 'clay.dart';

/// Gold star + number, e.g. next to a name or in a profile.
class StarCount extends StatelessWidget {
  const StarCount(this.n, {super.key, this.size = 13});
  final int n;
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: size + 4, color: C.honey),
        const SizedBox(width: 2),
        Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: C.honeyDeep)),
      ]);
}

/// Small pill with the mini medal and the badge name. Shown beside names
/// everywhere so every member's badge is visible to everyone.
class BadgeChip extends StatelessWidget {
  const BadgeChip(this.tier, {super.key, this.onTap, this.compact = false});
  final BadgeTier tier;
  final VoidCallback? onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: EdgeInsets.fromLTRB(3, 2, compact ? 7 : 9, 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tier.light.withValues(alpha: .5), tier.glow.withValues(alpha: .3)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tier.dark.withValues(alpha: .5), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        BadgeEmblem(tier, size: compact ? 17 : 20, animate: false),
        const SizedBox(width: 4),
        Text(
          tier.name,
          style: TextStyle(fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w900, color: Color.lerp(tier.dark, C.ink, .4)),
        ),
      ]),
    );
    return onTap == null ? chip : Press(onTap: onTap, child: chip);
  }
}

/// A person's name with their badge beside it (one line, name shrinks first).
class NameLine extends StatelessWidget {
  const NameLine({super.key, required this.name, required this.stars, this.style, this.compact = true});
  final String name;
  final int stars;
  final TextStyle? style;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final tier = badgeForStars(stars);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      if (tier != null) ...[
        const SizedBox(width: 6),
        BadgeChip(tier, compact: compact),
      ],
    ]);
  }
}

/// The gold "Helpful answer" tag on a starred comment.
class HelpfulTag extends StatelessWidget {
  const HelpfulTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(7, 3, 10, 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFE590), C.honey]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: C.honey.withValues(alpha: .45), blurRadius: 8)],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, size: 15, color: C.ink),
          SizedBox(width: 3),
          Text('Helpful answer', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: C.ink)),
        ]),
      );
}

/// Decoration for a starred comment: warm gold fill, gold edge, soft glow.
BoxDecoration helpfulDeco({double radius = 18}) => BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF4D3), Color(0xFFFFE9B0)]),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: C.honey, width: 1.4),
      boxShadow: [BoxShadow(color: C.honey.withValues(alpha: .35), blurRadius: 14, spreadRadius: 0.5)],
    );

/// A hexagon medal (the hive cell) with a star on it. When [animate] is on it
/// glows, sweeps a glint across and twinkles. Locked medals are grey and still.
/// Animation stops when the system asks for reduced motion.
class BadgeEmblem extends StatefulWidget {
  const BadgeEmblem(this.tier, {super.key, this.size = 64, this.locked = false, this.animate = true});
  final BadgeTier tier;
  final double size;
  final bool locked;
  final bool animate;
  @override
  State<BadgeEmblem> createState() => _BadgeEmblemState();
}

class _BadgeEmblemState extends State<BadgeEmblem> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

  bool get _reduceMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  bool get _shine => widget.animate && !widget.locked && !_reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BadgeEmblem old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_shine) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shine = _shine;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              size: Size.square(widget.size),
              painter: _MedalPainter(tier: widget.tier, v: _c.value, locked: widget.locked, shine: shine),
            ),
          ),
          if (widget.locked) Icon(Icons.lock_rounded, size: widget.size * .3, color: Colors.white.withValues(alpha: .9)),
        ]),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  _MedalPainter({required this.tier, required this.v, required this.locked, required this.shine});
  final BadgeTier tier;
  final double v; // 0..1 loop
  final bool locked;
  final bool shine;

  Path _hex(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final x = c.dx + r * math.cos(a);
      final y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  Path _star(Offset c, double outer, double inner) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = c.dx + r * math.cos(a);
      final y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  Path _sparkle(Offset o, double r) {
    final k = r * .22;
    return Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx + k, o.dy - k, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx + k, o.dy + k, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx - k, o.dy + k, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx - k, o.dy - k, o.dx, o.dy - r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final w = s.width;
    final r = w * .46;
    final light = locked ? const Color(0xFFDAD3C8) : tier.light;
    final dark = locked ? const Color(0xFFA79E91) : tier.dark;
    final rect = Offset.zero & s;

    // soft glow that breathes
    if (shine) {
      final pulse = .5 + .5 * math.sin(v * 2 * math.pi);
      canvas.drawPath(
        _hex(c, r),
        Paint()
          ..color = tier.glow.withValues(alpha: .30 + .30 * pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .1),
      );
    }

    // rim (rounded corners: fill plus a round-joined stroke of the same gradient)
    final outer = _hex(c, r);
    final rimShader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, dark]).createShader(rect);
    canvas.drawPath(outer, Paint()..shader = rimShader);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = rimShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .06
        ..strokeJoin = StrokeJoin.round,
    );

    // inset face
    final inner = _hex(c, r * .76);
    final faceShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.lerp(dark, Colors.black, .12)!, Color.lerp(light, Colors.white, .25)!],
    ).createShader(rect);
    canvas.drawPath(inner, Paint()..shader = faceShader);
    canvas.drawPath(
      inner,
      Paint()
        ..color = Colors.white.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .02
        ..strokeJoin = StrokeJoin.round,
    );

    // star
    if (!locked) {
      final star = _star(c.translate(0, w * .01), r * .5, r * .22);
      canvas.drawPath(star.shift(Offset(0, w * .02)), Paint()..color = Colors.black.withValues(alpha: .18));
      final starShader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color.lerp(Colors.white, light, .4)!],
      ).createShader(star.getBounds());
      canvas.drawPath(star, Paint()..shader = starShader);
      canvas.drawPath(
        star,
        Paint()
          ..shader = starShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .025
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // glint sweeping across the medal, then a pause
    if (shine && v < .5) {
      final t = v / .5;
      final bw = w * .4;
      final p0 = -bw + t * (w + bw);
      canvas.save();
      canvas.clipPath(outer);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(p0, p0),
            Offset(p0 + bw, p0 + bw),
            [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .8), Colors.white.withValues(alpha: 0)],
            [0, .5, 1],
          ),
      );
      canvas.restore();
    }

    // twinkles
    if (shine) {
      void twinkle(Offset o, double rad, double phase) {
        final raw = math.sin((v + phase) * 2 * math.pi);
        final a = raw > 0 ? raw : 0.0;
        if (a < .05) return;
        canvas.drawPath(_sparkle(o, rad * (.6 + .4 * a)), Paint()..color = Colors.white.withValues(alpha: a));
      }

      twinkle(Offset(w * .8, w * .18), w * .08, 0);
      twinkle(Offset(w * .17, w * .32), w * .06, .33);
      twinkle(Offset(w * .74, w * .84), w * .065, .66);
    }
  }

  @override
  bool shouldRepaint(covariant _MedalPainter old) => old.v != v || old.tier != tier || old.locked != locked || old.shine != shine;
}
