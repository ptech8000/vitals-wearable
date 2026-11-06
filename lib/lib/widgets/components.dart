import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/vital_reading.dart';
import '../theme/vital_theme.dart';
import 'motion.dart';

/// Lets nested screens ask the tab shell to switch tabs.
class AppNavigator extends InheritedWidget {
  const AppNavigator({super.key, required this.goToTab, required super.child});

  final ValueChanged<int> goToTab;

  static AppNavigator? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppNavigator>();

  @override
  bool updateShouldNotify(AppNavigator oldWidget) => false;
}

/// The standard surface: one radius family, one border, one soft shadow.
class VitalCard extends StatelessWidget {
  const VitalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.borderColor,
    this.color,
    this.gradient,
    this.animate,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final Gradient? gradient;

  /// When set, colour and border changes animate over this duration.
  final Duration? animate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final decoration = BoxDecoration(
      color: gradient == null ? (color ?? p.surface) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? p.border),
      boxShadow: p.cardShadow,
    );

    final Widget box = animate == null
        ? Container(padding: padding, decoration: decoration, child: child)
        : AnimatedContainer(
            duration: animate!,
            curve: Curves.easeOutCubic,
            padding: padding,
            decoration: decoration,
            child: child,
          );

    return onTap == null ? box : PressableScale(onTap: onTap, child: box);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VitalText.title(p.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: VitalText.label(p.textSecondary)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Plain-language reading of a vital sign against general adult reference
/// ranges. Informational only; it is not a diagnosis.
enum VitalLevel { normal, watch, alert }

class VitalStatus {
  const VitalStatus(this.label, this.level);

  final String label;
  final VitalLevel level;

  Color get color => switch (level) {
    VitalLevel.normal => VitalColors.good,
    VitalLevel.watch => VitalColors.warn,
    VitalLevel.alert => VitalColors.danger,
  };

  // Heart rate uses the same 50-100 bpm band that triggers the app's alert.
  static VitalStatus heartRate(int bpm) {
    if (bpm > 100) return const VitalStatus('High', VitalLevel.alert);
    if (bpm < 50) return const VitalStatus('Low', VitalLevel.alert);
    return const VitalStatus('Normal', VitalLevel.normal);
  }

  static VitalStatus spo2(int percent) {
    if (percent >= 95) return const VitalStatus('Normal', VitalLevel.normal);
    if (percent >= 90) return const VitalStatus('Low', VitalLevel.watch);
    return const VitalStatus('Very low', VitalLevel.alert);
  }

  static VitalStatus bloodPressure(int systolic, int diastolic) {
    if (systolic >= 140 || diastolic >= 90) {
      return const VitalStatus('High', VitalLevel.alert);
    }
    if (systolic < 90 || diastolic < 60) {
      return const VitalStatus('Low', VitalLevel.watch);
    }
    if (systolic >= 120 || diastolic >= 80) {
      return const VitalStatus('Elevated', VitalLevel.watch);
    }
    return const VitalStatus('Normal', VitalLevel.normal);
  }

  static VitalStatus temperature(double celsius) {
    if (celsius >= 38.0) return const VitalStatus('Fever', VitalLevel.alert);
    if (celsius >= 37.3) return const VitalStatus('Elevated', VitalLevel.watch);
    if (celsius < 35.0) return const VitalStatus('Low', VitalLevel.alert);
    if (celsius < 36.0) return const VitalStatus('Low', VitalLevel.watch);
    return const VitalStatus('Normal', VitalLevel.normal);
  }

  static VitalStatus respiratory(int rpm) {
    if (rpm > 24) return const VitalStatus('High', VitalLevel.alert);
    if (rpm > 20) return const VitalStatus('High', VitalLevel.watch);
    if (rpm < 8) return const VitalStatus('Low', VitalLevel.alert);
    if (rpm < 12) return const VitalStatus('Low', VitalLevel.watch);
    return const VitalStatus('Normal', VitalLevel.normal);
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final VitalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricChip extends StatelessWidget {
  const MetricChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One stored reading as a compact card, shared by the dashboard and history.
class ReadingTile extends StatelessWidget {
  const ReadingTile({
    super.key,
    required this.reading,
    required this.temperatureText,
  });

  final VitalReading reading;

  /// Already converted and labelled, e.g. "98.2°F".
  final String temperatureText;

  static final DateFormat _timeFormat = DateFormat('MMM d, yyyy, h:mm a');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = reading;

    return VitalCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _timeFormat.format(r.timestamp),
                  style: VitalText.label(p.textSecondary),
                ),
              ),
              if (r.alertTriggered)
                const StatusChip(
                  status: VitalStatus('Alert', VitalLevel.alert),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MetricChip(
                icon: Icons.favorite_rounded,
                label: '${r.heartRate} bpm',
                color: VitalColors.pulse,
              ),
              MetricChip(
                icon: Icons.air_rounded,
                label: '${r.spo2}%',
                color: VitalColors.oxygen,
              ),
              MetricChip(
                icon: Icons.speed_rounded,
                label: '${r.systolicBP}/${r.diastolicBP} mmHg',
                color: VitalColors.pressure,
              ),
              MetricChip(
                icon: Icons.thermostat_rounded,
                label: temperatureText,
                color: VitalColors.temperature,
              ),
              MetricChip(
                icon: Icons.waves_rounded,
                label: '${r.respiratoryRate} rpm',
                color: VitalColors.breath,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Smooth miniature line of recent values with a soft fill underneath.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 40,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Trend appears after a few readings',
            style: VitalText.label(p.textSecondary, size: 12),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparklinePainter(values, color)),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) {
      hi += 0.5;
      lo -= 0.5;
    }

    const pad = 4.0;
    final dx = size.width / (n - 1);
    final points = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          i * dx,
          size.height -
              pad -
              ((values[i] - lo) / (hi - lo)) * (size.height - pad * 2),
        ),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < n; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      line.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !listEquals(old.values, values);
}

/// A selectable pill that animates between its resting and selected look.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = VitalColors.primary,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PressableScale(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : p.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.55) : p.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? color : p.textSecondary),
              const SizedBox(width: 6),
            ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : p.textSecondary,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control with a highlight that slides between options.
class VitalSegmented<T> extends StatelessWidget {
  const VitalSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.icons,
  });

  final List<T> values;
  final List<String> labels;
  final List<IconData>? icons;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = values.length;
    final index = values.indexOf(value).clamp(0, n - 1);
    final alignX = n == 1 ? 0.0 : -1.0 + 2.0 * index / (n - 1);

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment(alignX, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                  boxShadow: p.cardShadow,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i == index) return;
                      HapticFeedback.selectionClick();
                      onChanged(values[i]);
                    },
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icons != null) ...[
                            Icon(
                              icons![i],
                              size: 16,
                              color: i == index
                                  ? VitalColors.primary
                                  : p.textSecondary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: i == index
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == index
                                  ? VitalColors.primary
                                  : p.textSecondary,
                            ),
                            child: Text(labels[i]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<T?> showVitalSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
}

/// Drag handle, title and a scrollable body for bottom sheets.
class VitalSheetFrame extends StatelessWidget {
  const VitalSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: VitalText.title(p.textPrimary, size: 20),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: p.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
