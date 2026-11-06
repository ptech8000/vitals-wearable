import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/vital_reading.dart';
import '../services/wifi_service.dart';
import '../utils/ble_helper.dart';
import '../viewmodels/health_viewmodel.dart';
import '../widgets/components.dart';

// =============================================================================
//  PULSE — dashboard redesign
//  Concept: one hero (heart rate with a live ECG trace), a compact bento of the
//  remaining vitals, and a quiet timeline of recent records. Fully self-styled:
//  no VitalCard / IconBadge / ScanRadar / showVitalSheet dependencies.
// =============================================================================

// ------------------------------------------------------------------ palette --

class _Pal {
  const _Pal._({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.inkSoft,
    required this.line,
  });

  final bool dark;
  final Color bg, surface, surface2, ink, inkSoft, line;

  factory _Pal.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const _Pal._(
            dark: true,
            bg: Color(0xFF0C0E12),
            surface: Color(0xFF151921),
            surface2: Color(0xFF1C212B),
            ink: Color(0xFFF2F4F8),
            inkSoft: Color(0xFF8D96A8),
            line: Color(0xFF242A36),
          )
        : const _Pal._(
            dark: false,
            bg: Color(0xFFF5F4F0),
            surface: Color(0xFFFFFFFF),
            surface2: Color(0xFFF0EFEA),
            ink: Color(0xFF14171F),
            inkSoft: Color(0xFF6B7385),
            line: Color(0xFFE6E4DD),
          );
  }

  static const pulse = Color(0xFFFF4D5E);
  static const oxygen = Color(0xFF2D9CFF);
  static const breath = Color(0xFF1FC8A6);
  static const pressure = Color(0xFF8B6CFF);
  static const temp = Color(0xFFFF9F2E);
  static const ok = Color(0xFF22C58B);
  static const warn = Color(0xFFF5A623);
  static const bad = Color(0xFFFF4D5E);
  static const brand = Color(0xFF4F7CFF);
}

const _tabular = [FontFeature.tabularFigures()];

/// Maps a [VitalStatus] level onto a traffic-light colour.
Color _statusColor(VitalStatus s) {
  return switch (s.level) {
    VitalLevel.normal => _Pal.ok,
    VitalLevel.watch => _Pal.warn,
    VitalLevel.alert => _Pal.bad,
  };
}

// ------------------------------------------------------------------- screen --

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final vm = context.watch<HealthViewModel>();
    final reading = vm.currentReading;
    final connected = vm.isConnected;
    final recorded = vm.history.length;

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 130),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    connected: connected,
                    name: vm.deviceName,
                    battery: vm.batteryLevel,
                    onTap: () => _showConnectionChoiceSheet(context),
                  ),
                  const SizedBox(height: 22),
                  _HeartHero(
                    reading: reading,
                    connected: connected,
                    status: vm.connectionStatus,
                    onConnect: () => _showConnectionChoiceSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _VitalsBento(reading: reading, vm: vm, connected: connected),
                  const SizedBox(height: 32),
                  _SectionTitle(
                    title: 'Recent records',
                    caption: '$recorded saved',
                    action: recorded > 0 ? 'See all' : null,
                    onAction: () => AppNavigator.maybeOf(context)?.goToTab(1),
                  ),
                  const SizedBox(height: 12),
                  if (recorded == 0)
                    _EmptyRecords(
                      onConnect: () => _showConnectionChoiceSheet(context),
                    )
                  else
                    _RecordList(
                      records: vm.history.take(4).toList(),
                      tempText: (r) =>
                          '${vm.formatTemperature(r.temperature)}${vm.temperatureUnitLabel}',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- header --

class _Header extends StatelessWidget {
  const _Header({
    required this.connected,
    required this.name,
    required this.battery,
    required this.onTap,
  });

  final bool connected;
  final String name;
  final int battery;
  final VoidCallback onTap;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEE, d MMM').format(DateTime.now()),
                style: TextStyle(
                  color: pal.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _greeting,
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: pal.surface,
          shape: StadiumBorder(side: BorderSide(color: pal.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected ? _Pal.ok : pal.inkSoft,
                        boxShadow: connected
                            ? [
                                BoxShadow(
                                  color: _Pal.ok.withValues(alpha: .5),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        connected ? name : 'Connect',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (connected) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$battery%',
                        style: TextStyle(
                          color: pal.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 6),
                      Icon(Icons.add_rounded, size: 16, color: pal.inkSoft),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- hero --

class _HeartHero extends StatelessWidget {
  const _HeartHero({
    required this.reading,
    required this.connected,
    required this.status,
    required this.onConnect,
  });

  final VitalReading? reading;
  final bool connected;
  final String status;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final hasData = r != null;
    final st = hasData ? VitalStatus.heartRate(r.heartRate) : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1E2B), Color(0xFF0F1118)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -70,
              top: -70,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _Pal.pulse.withValues(alpha: connected ? .38 : .16),
                      _Pal.pulse.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: _Pal.pulse,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Heart rate',
                            style: TextStyle(
                              color: Color(0xFFB7BECC),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (connected) const _LivePill(),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hasData ? '${r.heartRate}' : '--',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 84,
                                  height: .95,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -3,
                                  fontFeatures: _tabular,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'bpm',
                              style: TextStyle(
                                color: Color(0xFF8D96A8),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (st != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _StatusBadge(status: st, onDark: true),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasData
                            ? 'Updated ${DateFormat('h:mm a').format(r.timestamp)}'
                            : 'No signal yet',
                        style: const TextStyle(
                          color: Color(0xFF8D96A8),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Column(
                  children: [
                    SizedBox(
                      height: 74,
                      width: double.infinity,
                      child: _EcgWave(
                        live: connected && hasData,
                        bpm: hasData ? r.heartRate : 70,
                      ),
                    ),
                    if (!connected)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: onConnect,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF14171F),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.add_link_rounded, size: 20),
                            label: const Text(
                              'Connect a wearable',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: _Pal.ok.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: _Pal.ok),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: _Pal.ok,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.onDark = false});
  final VitalStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: onDark ? .16 : .13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// --------------------------------------------------------------- ECG painter --

class _EcgWave extends StatefulWidget {
  const _EcgWave({required this.live, required this.bpm});
  final bool live;
  final int bpm;

  @override
  State<_EcgWave> createState() => _EcgWaveState();
}

class _EcgWaveState extends State<_EcgWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  Duration get _beat =>
      Duration(milliseconds: (60000 / widget.bpm.clamp(40, 180)).round());

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _beat);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final shouldAnimate =
        widget.live && !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate && !_c.isAnimating) _c.repeat();
    if (!shouldAnimate && _c.isAnimating) _c.stop();
  }

  @override
  void didUpdateWidget(_EcgWave old) {
    super.didUpdateWidget(old);
    _c.duration = _beat;
    _syncAnimation();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _EcgPainter(phase: _c.value, live: widget.live),
        ),
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  _EcgPainter({required this.phase, required this.live});
  final double phase;
  final bool live;

  static double _g(double t, double c, double s) {
    final d = t - c;
    return math.exp(-(d * d) / (2 * s * s));
  }

  static double _beat(double t) =>
      0.14 * _g(t, .16, .035) -
      0.18 * _g(t, .295, .011) +
      1.0 * _g(t, .32, .010) -
      0.28 * _g(t, .345, .012) +
      0.26 * _g(t, .58, .05);

  @override
  void paint(Canvas canvas, Size size) {
    final beatW = size.width / 2.2;
    final mid = size.height * .62;
    final amp = size.height * .62;
    final path = Path();
    for (double x = 0; x <= size.width; x += 1.5) {
      final t = ((x / beatW) + phase) % 1.0;
      final y = mid - (live ? _beat(t) * amp : 0);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
        colors: [
          _Pal.pulse.withValues(alpha: 0),
          _Pal.pulse.withValues(alpha: live ? 1 : .35),
        ],
        stops: const [0, .55],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EcgPainter old) => old.phase != phase || old.live != live;
}

// -------------------------------------------------------------------- bento --

class _Metric {
  const _Metric(
    this.label,
    this.value,
    this.unit,
    this.icon,
    this.color,
    this.status,
  );
  final String label, value, unit;
  final IconData icon;
  final Color color;
  final VitalStatus? status;
}

class _VitalsBento extends StatelessWidget {
  const _VitalsBento({
    required this.reading,
    required this.vm,
    required this.connected,
  });

  final VitalReading? reading;
  final HealthViewModel vm;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final spo2 = _Metric(
      'Blood oxygen',
      r == null ? '—' : '${r.spo2}',
      '%',
      Icons.water_drop_rounded,
      _Pal.oxygen,
      r == null ? null : VitalStatus.spo2(r.spo2),
    );
    final resp = _Metric(
      'Respiration',
      r == null ? '—' : '${r.respiratoryRate}',
      '/min',
      Icons.air_rounded,
      _Pal.breath,
      r == null ? null : VitalStatus.respiratory(r.respiratoryRate),
    );
    final bp = _Metric(
      'Blood pressure',
      r == null ? '—' : '${r.systolicBP}/${r.diastolicBP}',
      'mmHg',
      Icons.speed_rounded,
      _Pal.pressure,
      r == null ? null : VitalStatus.bloodPressure(r.systolicBP, r.diastolicBP),
    );
    final temp = _Metric(
      'Temperature',
      r == null ? '—' : vm.formatTemperature(r.temperature).toString(),
      vm.temperatureUnitLabel,
      Icons.thermostat_rounded,
      _Pal.temp,
      r == null ? null : VitalStatus.temperature(r.temperature),
    );

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MetricTile(m: spo2)),
              const SizedBox(width: 12),
              Expanded(child: _MetricTile(m: resp)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _MetricTile(m: bp, wide: true),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MetricTile(m: temp)),
              const SizedBox(width: 12),
              Expanded(
                child: _BatteryTile(
                  connected: connected,
                  battery: vm.batteryLevel,
                  status: vm.connectionStatus,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.m, this.wide = false});
  final _Metric m;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final status = m.status;

    final value = FittedBox(
      alignment: Alignment.centerLeft,
      fit: BoxFit.scaleDown,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            m.value,
            style: TextStyle(
              color: pal.ink,
              fontSize: wide ? 40 : 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            m.unit,
            style: TextStyle(
              color: pal.inkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(m.icon, size: 17, color: m.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (wide && status != null) _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 18),
          value,
          if (!wide) ...[
            const SizedBox(height: 10),
            if (status != null)
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _statusColor(status),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                'No data',
                style: TextStyle(
                  color: pal.inkSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BatteryTile extends StatelessWidget {
  const _BatteryTile({
    required this.connected,
    required this.battery,
    required this.status,
  });

  final bool connected;
  final int battery;
  final String status;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final level = (battery.clamp(0, 100)) / 100;
    final color = battery <= 15
        ? _Pal.bad
        : battery <= 30
        ? _Pal.warn
        : _Pal.ok;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: pal.inkSoft.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  connected ? Icons.watch_rounded : Icons.watch_off_rounded,
                  size: 17,
                  color: pal.inkSoft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Device',
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            connected ? '$battery%' : '—',
            style: TextStyle(
              color: pal.ink,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 10),
          if (connected) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: level,
                minHeight: 6,
                color: color,
                backgroundColor: pal.inkSoft.withValues(alpha: .2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: pal.inkSoft,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            Text(
              'Not connected',
              style: TextStyle(
                color: pal.inkSoft,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ records --

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.caption,
    this.action,
    this.onAction,
  });

  final String title, caption;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              color: pal.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            caption,
            style: TextStyle(
              color: pal.inkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        if (action != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                action!,
                style: const TextStyle(
                  color: _Pal.brand,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('d MMM').format(d);
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records, required this.tempText});
  final List<VitalReading> records;
  final String Function(VitalReading) tempText;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 18, endIndent: 18, color: pal.line),
            _RecordRow(reading: records[i], temperature: tempText(records[i])),
          ],
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.reading, required this.temperature});
  final VitalReading reading;
  final String temperature;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final r = reading;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('h:mm a').format(r.timestamp),
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dayLabel(r.timestamp),
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _MiniStat(color: _Pal.pulse, text: '${r.heartRate} bpm'),
                _MiniStat(color: _Pal.oxygen, text: '${r.spo2}%'),
                _MiniStat(
                  color: _Pal.pressure,
                  text: '${r.systolicBP}/${r.diastolicBP}',
                ),
                _MiniStat(color: _Pal.temp, text: temperature),
                _MiniStat(color: _Pal.breath, text: '${r.respiratoryRate}/min'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: pal.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(Icons.timeline_rounded, size: 30, color: pal.inkSoft),
          const SizedBox(height: 12),
          Text(
            'Nothing recorded yet',
            style: TextStyle(
              color: pal.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Readings are saved automatically once a device is connected.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.inkSoft, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onConnect,
            style: OutlinedButton.styleFrom(
              foregroundColor: pal.ink,
              side: BorderSide(color: pal.line),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text(
              'Connect a device',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================== sheets ==

Future<T?> _openSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: builder,
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title, subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .8,
      ),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: pal.inkSoft.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: pal.inkSoft,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          Flexible(child: child),
        ],
      ),
    );
  }
}

void _showConnectionChoiceSheet(BuildContext context) {
  final viewModel = context.read<HealthViewModel>();

  _openSheet<void>(
    context,
    (sheetContext) => _Sheet(
      title: 'Connect a device',
      subtitle: 'Pick how your wearable talks to the app.',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChoiceTile(
              icon: Icons.bluetooth_rounded,
              color: _Pal.brand,
              title: 'Bluetooth',
              subtitle: 'Scan for a wearable nearby',
              onTap: () {
                Navigator.pop(sheetContext);

                // Guard: no point scanning while the Bluetooth adapter is off.
                if (FlutterBluePlus.adapterStateNow !=
                    BluetoothAdapterState.on) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Cannot connect: please turn on your Bluetooth first.',
                      ),
                    ),
                  );
                  return;
                }
                _showBluetoothScannerSheet(context, viewModel);
              },
            ),
            const SizedBox(height: 10),
            _ChoiceTile(
              icon: Icons.wifi_rounded,
              color: _Pal.ok,
              title: 'Wi-Fi network',
              subtitle: 'Find devices on your router',
              onTap: () {
                Navigator.pop(sheetContext);
                _showWifiScannerSheet(context, viewModel);
              },
            ),
            if (viewModel.isConnected) ...[
              const SizedBox(height: 10),
              _ChoiceTile(
                icon: Icons.link_off_rounded,
                color: _Pal.bad,
                title: 'Disconnect',
                subtitle: 'Stop streaming from ${viewModel.deviceName}',
                onTap: () {
                  Navigator.pop(sheetContext);
                  viewModel.disconnectDevice();
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Material(
      color: pal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: pal.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: pal.inkSoft, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: pal.inkSoft, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

void _showBluetoothScannerSheet(
  BuildContext context,
  HealthViewModel viewModel,
) {
  viewModel.startBluetoothScanning();

  _openSheet<void>(
    context,
    (sheetContext) => _Sheet(
      title: 'Nearby devices',
      subtitle: 'Bluetooth wearables in range.',
      trailing: _RescanButton(onTap: viewModel.startBluetoothScanning),
      child: StreamBuilder<bool>(
        stream: viewModel.bluetoothScanning,
        initialData: true,
        builder: (context, scanningSnapshot) {
          final scanning = scanningSnapshot.data ?? false;
          return StreamBuilder<List<ScanResult>>(
            stream: viewModel.scanResults,
            builder: (context, snapshot) {
              final devices = snapshot.data ?? const <ScanResult>[];
              if (devices.isEmpty) {
                return _ScanEmpty(
                  scanning: scanning,
                  icon: Icons.bluetooth_searching_rounded,
                  color: _Pal.brand,
                  searching: 'Looking for Bluetooth wearables…',
                  none:
                      'No wearables found. Make sure the watch is on and nearby.',
                  onRescan: viewModel.startBluetoothScanning,
                );
              }
              return _DeviceList(
                scanning: scanning,
                color: _Pal.brand,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final scanResult = devices[index];
                  return _DeviceRow(
                    key: ValueKey(scanResult.device.remoteId.toString()),
                    icon: Icons.bluetooth_rounded,
                    color: _Pal.brand,
                    name: getDeviceDisplayName(scanResult),
                    detail: '${scanResult.rssi} dBm',
                    rssi: scanResult.rssi,
                    onConnect: () {
                      // Check again right before connecting.
                      if (FlutterBluePlus.adapterStateNow !=
                          BluetoothAdapterState.on) {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Bluetooth is turned off. Cannot connect.',
                            ),
                          ),
                        );
                        return;
                      }
                      viewModel.selectAndConnectBluetoothDevice(
                        scanResult.device,
                      );
                      Navigator.pop(sheetContext);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    ),
  ).whenComplete(viewModel.cancelScanning);
}

void _showWifiScannerSheet(BuildContext context, HealthViewModel viewModel) {
  viewModel.startWifiScanning();

  _openSheet<void>(
    context,
    (sheetContext) => _Sheet(
      title: 'Devices on Wi-Fi',
      subtitle: 'Anything answering on your local network.',
      trailing: _RescanButton(onTap: viewModel.startWifiScanning),
      child: ValueListenableBuilder<bool>(
        valueListenable: viewModel.wifiScanning,
        builder: (context, scanning, _) {
          return StreamBuilder<List<WifiDeviceResult>>(
            stream: viewModel.wifiScanResults,
            builder: (context, snapshot) {
              final devices = snapshot.data ?? const <WifiDeviceResult>[];
              if (devices.isEmpty) {
                return _ScanEmpty(
                  scanning: scanning,
                  icon: Icons.wifi_find_rounded,
                  color: _Pal.ok,
                  searching: 'Scanning your local network…',
                  none:
                      'No devices answered. Check that you are on the same Wi-Fi.',
                  onRescan: viewModel.startWifiScanning,
                );
              }
              return _DeviceList(
                scanning: scanning,
                color: _Pal.ok,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return _DeviceRow(
                    key: ValueKey(device.ipAddress),
                    icon: Icons.wifi_rounded,
                    color: _Pal.ok,
                    name: device.name,
                    detail: '${device.ipAddress}:${device.port}',
                    onConnect: () {
                      viewModel.selectAndConnectWifiDevice(device);
                      Navigator.pop(sheetContext);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    ),
  ).whenComplete(viewModel.cancelScanning);
}

class _RescanButton extends StatelessWidget {
  const _RescanButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Material(
      color: pal.surface,
      shape: CircleBorder(side: BorderSide(color: pal.line)),
      child: IconButton(
        tooltip: 'Scan again',
        onPressed: onTap,
        icon: Icon(Icons.refresh_rounded, color: pal.ink, size: 20),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.scanning,
    required this.color,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool scanning;
  final Color color;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: scanning ? 3 : 0,
          margin: EdgeInsets.only(bottom: scanning ? 12 : 0),
          child: scanning
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    color: color,
                    backgroundColor: color.withValues(alpha: .14),
                  ),
                )
              : null,
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

class _ScanEmpty extends StatelessWidget {
  const _ScanEmpty({
    required this.scanning,
    required this.icon,
    required this.color,
    required this.searching,
    required this.none,
    required this.onRescan,
  });

  final bool scanning;
  final IconData icon;
  final Color color;
  final String searching, none;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseRings(icon: icon, color: color, size: 150, animate: scanning),
          const SizedBox(height: 16),
          Text(
            scanning ? searching : none,
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.inkSoft, fontSize: 14, height: 1.4),
          ),
          if (!scanning) ...[
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: onRescan,
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Scan again',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseRings extends StatefulWidget {
  const _PulseRings({
    required this.icon,
    required this.color,
    required this.size,
    required this.animate,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool animate;

  @override
  State<_PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<_PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final shouldAnimate =
        widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate && !_c.isAnimating) _c.repeat();
    if (!shouldAnimate && _c.isAnimating) _c.stop();
  }

  @override
  void didUpdateWidget(_PulseRings old) {
    super.didUpdateWidget(old);
    _syncAnimation();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _RingsPainter(
                t: _c.value,
                color: widget.color,
                active: widget.animate,
              ),
            ),
          ),
          Container(
            width: widget.size * .38,
            height: widget.size * .38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: .16),
            ),
            child: Icon(
              widget.icon,
              color: widget.color,
              size: widget.size * .18,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t, required this.color, required this.active});
  final double t;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final minR = size.width * .22;
    final maxR = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final p = active ? (t + i / 3) % 1.0 : (i + 1) / 4;
      final radius = minR + (maxR - minR) * p;
      final alpha = active ? (1 - p) * .4 : .12;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.t != t || old.active != active || old.color != color;
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    required this.detail,
    required this.onConnect,
    this.rssi,
  });

  final IconData icon;
  final Color color;
  final String name, detail;
  final int? rssi;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Material(
      color: pal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: pal.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onConnect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (rssi != null) ...[
                          _SignalBars(rssi: rssi!, color: color),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            detail,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: pal.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: pal.ink,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Connect',
                  style: TextStyle(
                    color: pal.bg,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi, required this.color});
  final int rssi;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final level = rssi > -60 ? 4 : (rssi > -70 ? 3 : (rssi > -80 ? 2 : 1));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 3.5,
            height: 4.0 + i * 3,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i <= level ? color : pal.inkSoft.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
      ],
    );
  }
}
