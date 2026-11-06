import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/vital_theme.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// One-shot entrance: fades in while rising a few pixels. Used for the first
/// reveal of a screen's content, not for every list row.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 460),
    this.dy = 0.05,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Start offset as a fraction of the child's own height.
  final double dy;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.dy),
    end: Offset.zero,
  ).animate(_curve);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Shrinks slightly while pressed and gives a light haptic tick on tap.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.97,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: () {
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A number that counts up the first time it appears and rolls smoothly from
/// the old value to the new one whenever it changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.decimals = 0,
    this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  final num value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) {
      return Text(value.toStringAsFixed(decimals), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(v.toStringAsFixed(decimals), style: style),
    );
  }
}

/// A heart that beats at the wearer's actual heart rate (lub-dub), with a soft
/// ring that spreads on the first beat. This is the app's signature motion.
class BeatingHeart extends StatefulWidget {
  const BeatingHeart({
    super.key,
    required this.bpm,
    required this.active,
    this.size = 28,
    this.color = VitalColors.pulse,
  });

  final int bpm;
  final bool active;
  final double size;
  final Color color;

  @override
  State<BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<BeatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  Duration? _appliedPeriod;

  Duration get _period =>
      Duration(milliseconds: (60000 / widget.bpm.clamp(40, 180)).round());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.22).chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.22, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 14,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BeatingHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final shouldRun = widget.active && !_reduceMotion(context);
    if (!shouldRun) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
      _appliedPeriod = null;
      return;
    }
    final period = _period;
    if (_appliedPeriod != period || !_controller.isAnimating) {
      _appliedPeriod = period;
      _controller.duration = period;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 1.5;
    return RepaintBoundary(
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = (_controller.value / 0.55).clamp(0.0, 1.0).toDouble();
                if (!widget.active || t >= 1.0 || _controller.value == 0) {
                  return const SizedBox.shrink();
                }
                return Opacity(
                  opacity: (1 - t) * 0.35,
                  child: Transform.scale(
                    scale: 1 + t * 0.9,
                    child: Container(
                      width: widget.size * 1.1,
                      height: widget.size * 1.1,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                );
              },
            ),
            ScaleTransition(
              scale: _scale,
              child: Icon(
                Icons.favorite_rounded,
                color: widget.color,
                size: widget.size,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrolling ECG trace. Beats travel at the real heart rate; the left edge
/// fades out like a hospital monitor. Flat and still when inactive.
class EcgTrace extends StatefulWidget {
  const EcgTrace({
    super.key,
    required this.bpm,
    required this.active,
    this.color = VitalColors.pulse,
  });

  final int bpm;
  final bool active;
  final Color color;

  @override
  State<EcgTrace> createState() => _EcgTraceState();
}

class _EcgTraceState extends State<EcgTrace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Duration? _appliedPeriod;

  Duration get _period =>
      Duration(milliseconds: (60000 / widget.bpm.clamp(40, 180)).round());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EcgTrace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final shouldRun = widget.active && !_reduceMotion(context);
    if (!shouldRun) {
      if (_controller.isAnimating) _controller.stop();
      _appliedPeriod = null;
      return;
    }
    final period = _period;
    if (_appliedPeriod != period || !_controller.isAnimating) {
      _appliedPeriod = period;
      _controller.duration = period;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _EcgPainter(
          animation: _controller,
          color: widget.color,
          active: widget.active,
        ),
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  _EcgPainter({
    required this.animation,
    required this.color,
    required this.active,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final bool active;

  static const double _beatsInView = 3.2;

  // One heartbeat: x is 0..1 across the beat, y is the deflection (up = +).
  static const List<Offset> _beat = [
    Offset(0.00, 0.00),
    Offset(0.08, 0.00),
    Offset(0.13, 0.14),
    Offset(0.18, 0.00),
    Offset(0.28, 0.00),
    Offset(0.31, -0.14),
    Offset(0.35, 1.00),
    Offset(0.39, -0.30),
    Offset(0.43, 0.00),
    Offset(0.55, 0.00),
    Offset(0.62, 0.24),
    Offset(0.70, 0.00),
    Offset(1.00, 0.00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    final baseY = size.height * 0.62;
    final amp = size.height * 0.55;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (!active) {
      paint.color = color.withValues(alpha: 0.25);
      canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), paint);
      return;
    }

    paint.shader = LinearGradient(
      colors: [color.withValues(alpha: 0), color],
      stops: const [0.0, 0.45],
    ).createShader(Offset.zero & size);

    final beatWidth = size.width / _beatsInView;
    final offset = -animation.value * beatWidth;
    final path = Path();
    var started = false;

    for (var b = 0; offset + b * beatWidth < size.width + beatWidth; b++) {
      for (final point in _beat) {
        final x = offset + (b + point.dx) * beatWidth;
        final y = baseY - point.dy * amp;
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EcgPainter old) =>
      old.color != color || old.active != active;
}

/// Rings spreading outward from an icon: "searching".
class ScanRadar extends StatefulWidget {
  const ScanRadar({
    super.key,
    required this.icon,
    required this.color,
    this.size = 150,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  State<ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<ScanRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _controller.value = 0.4;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = widget.size * 0.36;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(widget.size),
              painter: _RadarPainter(
                animation: _controller,
                color: widget.color,
              ),
            ),
            Container(
              width: core,
              height: core,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.16),
              ),
              child: Icon(widget.icon, color: widget.color, size: core * 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final t = (animation.value + i / 3) % 1.0;
      final radius = maxRadius * (0.3 + 0.7 * t);
      final fade = 1 - t;

      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: 0.07 * fade),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.45 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.color != color;
}

/// A status dot with a ring that breathes outward while [active].
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    required this.active,
    this.size = 10,
  });

  final Color color;
  final bool active;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !_reduceMotion(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 2.6;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              if (!widget.active || t == 0) return const SizedBox.shrink();
              return Opacity(
                opacity: (1 - t) * 0.5,
                child: Transform.scale(
                  scale: 1 + t * 1.6,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}
