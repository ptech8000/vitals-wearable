// ignore_for_file: unused_import

import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/vital_reading.dart';
import '../theme/vital_theme.dart';
import '../viewmodels/health_viewmodel.dart';
import '../widgets/components.dart';

// =============================================================================
//  PULSE — history redesign
//  A single trend card (big number, clean chart, range switcher), three stat
//  tiles, and a grouped log where every row leads with the metric you are
//  currently charting. Self-styled; matches the redesigned dashboard.
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
}

const _tabular = [FontFeature.tabularFigures()];

Color _statusColor(VitalStatus s) {
  final n = s.level.name.toLowerCase();
  if (n.contains('norm') || n.contains('good') || n == 'ok') return _Pal.ok;
  if (n.contains('warn') ||
      n.contains('caution') ||
      n.contains('elev') ||
      n.contains('mod') ||
      n.contains('low')) {
    return _Pal.warn;
  }
  return _Pal.bad;
}

// -------------------------------------------------------------------- model --

enum HistoryRange {
  day('24 h', Duration(hours: 24)),
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30)),
  all('All', null);

  const HistoryRange(this.label, this.span);
  final String label;
  final Duration? span;
}

class _Metric {
  const _Metric({
    required this.title,
    required this.shortTitle,
    required this.unit,
    required this.color,
    required this.icon,
    required this.pick,
    this.isTemperature = false,
    this.decimals = 0,
  });

  final String title;
  final String shortTitle;
  final String unit;
  final Color color;
  final IconData icon;
  final double Function(VitalReading) pick;
  final bool isTemperature;
  final int decimals;
}

final List<_Metric> _metrics = [
  _Metric(
    title: 'Heart rate',
    shortTitle: 'Heart rate',
    unit: 'bpm',
    color: _Pal.pulse,
    icon: Icons.favorite_rounded,
    pick: (r) => r.heartRate.toDouble(),
  ),
  _Metric(
    title: 'Blood oxygen',
    shortTitle: 'SpO₂',
    unit: '%',
    color: _Pal.oxygen,
    icon: Icons.water_drop_rounded,
    pick: (r) => r.spo2.toDouble(),
  ),
  _Metric(
    title: 'Systolic pressure',
    shortTitle: 'Pressure',
    unit: 'mmHg',
    color: _Pal.pressure,
    icon: Icons.speed_rounded,
    pick: (r) => r.systolicBP.toDouble(),
  ),
  _Metric(
    title: 'Body temperature',
    shortTitle: 'Temperature',
    unit: '°C',
    color: _Pal.temp,
    icon: Icons.thermostat_rounded,
    pick: (r) => r.temperature,
    isTemperature: true,
    decimals: 1,
  ),
  _Metric(
    title: 'Respiratory rate',
    shortTitle: 'Respiration',
    unit: 'rpm',
    color: _Pal.breath,
    icon: Icons.air_rounded,
    pick: (r) => r.respiratoryRate.toDouble(),
  ),
];

/// Everything the chart needs, computed once per (history, metric, range, unit).
class _ChartData {
  _ChartData({
    required this.spots,
    required this.start,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.yInterval,
    required this.count,
    required this.latest,
    required this.average,
    required this.lowest,
    required this.highest,
    required this.spanMinutes,
  });

  final List<FlSpot> spots;
  final DateTime start;
  final double maxX;
  final double minY;
  final double maxY;
  final double yInterval;
  final int count;
  final double latest;
  final double average;
  final double lowest;
  final double highest;
  final double spanMinutes;
}

const int _maxChartPoints = 150;

sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.title, this.count);
  final String title;
  final int count;
}

class _LogRow extends _Row {
  const _LogRow(this.reading, {required this.first, required this.last});
  final VitalReading reading;
  final bool first, last;
}

// ------------------------------------------------------------------- screen --

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _metricIndex = 0;
  HistoryRange _range = HistoryRange.week;

  // Memoised derived data. Rebuilt only when its inputs change, not on every
  // frame or every live heart-rate packet.
  String? _chartKey;
  _ChartData? _chartData;
  int? _rowsRevision;
  List<_Row> _rows = const [];

  static const List<String> _categoryOrder = [
    'This Morning',
    'This Afternoon',
    'This Evening',
    'Today (Night)',
    'Yesterday',
    'This Week',
    'Last 2 Weeks',
    'Last 30 Days',
    'Last 60 Days',
    'Older Logs',
  ];

  static String _categoryFor(DateTime now, DateTime dateTime) {
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final days = today.difference(logDate).inDays;

    if (days <= 0) {
      final hour = dateTime.hour;
      if (hour >= 5 && hour < 12) return 'This Morning';
      if (hour >= 12 && hour < 17) return 'This Afternoon';
      if (hour >= 17 && hour < 22) return 'This Evening';
      return 'Today (Night)';
    } else if (days == 1) {
      return 'Yesterday';
    } else if (days <= 7) {
      return 'This Week';
    } else if (days <= 14) {
      return 'Last 2 Weeks';
    } else if (days <= 30) {
      return 'Last 30 Days';
    } else if (days <= 60) {
      return 'Last 60 Days';
    }
    return 'Older Logs';
  }

  List<_Row> _buildRows(List<VitalReading> history) {
    final now = DateTime.now();
    final grouped = <String, List<VitalReading>>{};
    for (final reading in history) {
      grouped
          .putIfAbsent(_categoryFor(now, reading.timestamp), () => [])
          .add(reading);
    }
    final rows = <_Row>[];
    for (final category in _categoryOrder) {
      final items = grouped[category];
      if (items == null || items.isEmpty) continue;
      rows.add(_HeaderRow(category, items.length));
      for (var i = 0; i < items.length; i++) {
        rows.add(_LogRow(items[i], first: i == 0, last: i == items.length - 1));
      }
    }
    return rows;
  }

  _ChartData? _buildChart(
    List<VitalReading> history,
    _Metric metric,
    HistoryRange range,
    HealthViewModel vm,
  ) {
    final cutoff = range.span == null
        ? null
        : DateTime.now().subtract(range.span!);

    // History is newest first, so we can stop at the first reading that is
    // too old.
    final picked = <VitalReading>[];
    for (final reading in history) {
      if (cutoff != null && reading.timestamp.isBefore(cutoff)) break;
      picked.add(reading);
    }
    if (picked.isEmpty) return null;

    final chronological = picked.reversed.toList();
    double valueOf(VitalReading r) {
      final raw = metric.pick(r);
      return metric.isTemperature ? vm.formatTemperature(raw) : raw;
    }

    final values = [for (final r in chronological) valueOf(r)];
    var lowest = values.first;
    var highest = values.first;
    var sum = 0.0;
    for (final v in values) {
      lowest = math.min(lowest, v);
      highest = math.max(highest, v);
      sum += v;
    }

    // Thin out long ranges so the chart stays fast and legible.
    final stride = (chronological.length / _maxChartPoints).ceil();
    final start = chronological.first.timestamp;
    final spots = <FlSpot>[];
    for (var i = 0; i < chronological.length; i += math.max(stride, 1)) {
      spots.add(_spot(chronological[i].timestamp, start, values[i]));
    }
    final lastIndex = chronological.length - 1;
    if (spots.isEmpty ||
        spots.last.x != _minutes(chronological[lastIndex].timestamp, start)) {
      spots.add(
        _spot(chronological[lastIndex].timestamp, start, values[lastIndex]),
      );
    }

    final spanMinutes = math.max(spots.last.x, 1.0);
    final minimumPad = metric.isTemperature ? 0.3 : 2.0;
    final pad = math.max((highest - lowest) * 0.25, minimumPad);
    final minY = lowest - pad;
    final maxY = highest + pad;

    return _ChartData(
      spots: spots,
      start: start,
      maxX: spanMinutes,
      minY: minY,
      maxY: maxY,
      yInterval: math.max((maxY - minY) / 4, 0.1),
      count: picked.length,
      latest: values.last,
      average: sum / values.length,
      lowest: lowest,
      highest: highest,
      spanMinutes: spanMinutes,
    );
  }

  static double _minutes(DateTime t, DateTime start) =>
      t.difference(start).inSeconds / 60.0;

  static FlSpot _spot(DateTime t, DateTime start, double value) =>
      FlSpot(_minutes(t, start), value);

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    context.select<HealthViewModel, int>((vm) => vm.historyRevision);
    final isCelsius = context.select<HealthViewModel, bool>(
      (vm) => vm.isCelsius,
    );
    final vm = context.read<HealthViewModel>();
    final history = vm.history;
    final metric = _metrics[_metricIndex];

    final revision = vm.historyRevision;
    final key = '$revision|$_metricIndex|${_range.index}|$isCelsius';
    if (key != _chartKey) {
      _chartKey = key;
      _chartData = _buildChart(history, metric, _range, vm);
    }
    if (_rowsRevision != revision) {
      _rowsRevision = revision;
      _rows = _buildRows(history);
    }

    final unit = metric.isTemperature ? vm.temperatureUnitLabel : metric.unit;
    final side = math.max(20.0, (MediaQuery.of(context).size.width - 720) / 2);

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 14, side, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'History',
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${history.length} readings recorded',
                      style: TextStyle(
                        color: pal.inkSoft,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        children: [
                          for (var i = 0; i < _metrics.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _MetricChip(
                                metric: _metrics[i],
                                selected: i == _metricIndex,
                                onTap: () => setState(() => _metricIndex = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _TrendCard(
                      metric: metric,
                      unit: unit,
                      data: _chartData,
                      range: _range,
                      onRange: (r) => setState(() => _range = r),
                    ),
                    if (_chartData != null) ...[
                      const SizedBox(height: 12),
                      _StatRow(metric: metric, unit: unit, data: _chartData!),
                    ],
                    const SizedBox(height: 30),
                    Text(
                      'Log',
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    if (_rows.isEmpty) const _EmptyLog(),
                  ],
                ),
              ),
            ),
            // Rows are built lazily, so thousands of logs cost nothing until
            // they scroll into view.
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 130),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final row = _rows[index];
                    switch (row) {
                      case _HeaderRow(:final title, :final count):
                        return Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: pal.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$count',
                                style: TextStyle(
                                  color: pal.inkSoft,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      case _LogRow(:final reading, :final first, :final last):
                        return _LogTile(
                          reading: reading,
                          first: first,
                          last: last,
                          selected: _metricIndex,
                          tempValue: vm
                              .formatTemperature(reading.temperature)
                              .toString(),
                          tempUnit: vm.temperatureUnitLabel,
                        );
                    }
                  },
                  childCount: _rows.length,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- metric chip --

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.metric,
    required this.selected,
    required this.onTap,
  });

  final _Metric metric;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        decoration: BoxDecoration(
          color: selected ? metric.color : pal.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? metric.color : pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              metric.icon,
              size: 17,
              color: selected ? Colors.white : metric.color,
            ),
            const SizedBox(width: 8),
            Text(
              metric.shortTitle,
              style: TextStyle(
                color: selected ? Colors.white : pal.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- trend card --

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.metric,
    required this.unit,
    required this.data,
    required this.range,
    required this.onRange,
  });

  final _Metric metric;
  final String unit;
  final _ChartData? data;
  final HistoryRange range;
  final ValueChanged<HistoryRange> onRange;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final d = data;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: metric.color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    metric.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: pal.inkSoft,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (d != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pal.surface2,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${d.count} readings',
                      style: TextStyle(
                        color: pal.inkSoft,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (d != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey(metric.title),
                  tween: Tween<double>(end: d.latest),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text(
                    v.toStringAsFixed(metric.decimals),
                    style: TextStyle(
                      color: pal.ink,
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                      height: 1,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  unit,
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'latest',
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else
            Text(
              '—',
              style: TextStyle(
                color: pal.inkSoft,
                fontSize: 52,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: d == null
                ? SizedBox(
                    key: const ValueKey('empty'),
                    height: 200,
                    child: Center(
                      child: Text(
                        'No readings in this range yet.',
                        style: TextStyle(color: pal.inkSoft, fontSize: 13.5),
                      ),
                    ),
                  )
                : SizedBox(
                    key: const ValueKey('chart'),
                    height: 210,
                    child: _buildChart(context, d),
                  ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 0, right: 4),
            child: _Segmented(value: range, onChanged: onRange),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, _ChartData d) {
    final pal = _Pal.of(context);
    final showTime = d.spanMinutes <= 36 * 60;
    final timeFormat = showTime ? DateFormat('h a') : DateFormat('MMM d');
    final tooltipFormat = DateFormat('MMM d, h:mm a');
    const noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));
    final labelStyle = TextStyle(
      color: pal.inkSoft,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: d.maxX,
        minY: d.minY,
        maxY: d.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: d.yInterval,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: pal.line, strokeWidth: 1, dashArray: [3, 5]),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: d.average,
              color: metric.color.withValues(alpha: .5),
              strokeWidth: 1.2,
              dashArray: [5, 5],
            ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: noTitles,
          rightTitles: noTitles,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: d.yInterval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(metric.decimals),
                style: labelStyle,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: math.max(d.maxX / 3, 1.0),
              getTitlesWidget: (value, meta) {
                final t = d.start.add(Duration(seconds: (value * 60).round()));
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(timeFormat.format(t), style: labelStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                pal.dark ? const Color(0xFF2B3240) : const Color(0xFF14171F),
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  '${spot.y.toStringAsFixed(metric.decimals)} $unit\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: tooltipFormat.format(
                        d.start.add(Duration(seconds: (spot.x * 60).round())),
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: d.spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            color: metric.color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: d.spots.length <= 40,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3.4,
                color: pal.surface,
                strokeWidth: 2.2,
                strokeColor: metric.color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  metric.color.withValues(alpha: 0.26),
                  metric.color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final HistoryRange value;
  final ValueChanged<HistoryRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final thumb = pal.dark ? const Color(0xFF2B3240) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final r in HistoryRange.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == value ? thumb : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: r == value && !pal.dark
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    r.label,
                    style: TextStyle(
                      color: r == value ? pal.ink : pal.inkSoft,
                      fontSize: 13,
                      fontWeight: r == value
                          ? FontWeight.w800
                          : FontWeight.w600,
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

// ---------------------------------------------------------------- stat tiles --

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.metric,
    required this.unit,
    required this.data,
  });

  final _Metric metric;
  final String unit;
  final _ChartData data;

  @override
  Widget build(BuildContext context) {
    String f(double v) => v.toStringAsFixed(metric.decimals);
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Average',
            value: f(data.average),
            unit: unit,
            icon: Icons.drag_handle_rounded,
            color: metric.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Lowest',
            value: f(data.lowest),
            unit: unit,
            icon: Icons.south_rounded,
            color: metric.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Highest',
            value: f(data.highest),
            unit: unit,
            icon: Icons.north_rounded,
            color: metric.color,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String label, value, unit;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: TextStyle(
                    color: pal.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- log --

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE d MMM').format(d);
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.reading,
    required this.first,
    required this.last,
    required this.selected,
    required this.tempValue,
    required this.tempUnit,
  });

  final VitalReading reading;
  final bool first, last;
  final int selected;
  final String tempValue, tempUnit;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final r = reading;

    // Index order matches [_metrics].
    final values = <String>[
      '${r.heartRate}',
      '${r.spo2}',
      '${r.systolicBP}/${r.diastolicBP}',
      tempValue,
      '${r.respiratoryRate}',
    ];
    final units = <String>['bpm', '%', 'mmHg', tempUnit, 'rpm'];
    final labels = <String>['HR', 'SpO₂', 'BP', 'Temp', 'Resp'];
    final secondary = <String>[
      for (var i = 0; i < values.length; i++)
        if (i != selected) '${labels[i]} ${values[i]}',
    ].join('  ·  ');

    final metric = _metrics[selected];
    final hr = VitalStatus.heartRate(r.heartRate);

    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(first ? 24 : 0),
          bottom: Radius.circular(last ? 24 : 0),
        ),
      ),
      child: Column(
        children: [
          if (!first)
            Divider(height: 1, indent: 18, endIndent: 18, color: pal.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.inkSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    secondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: pal.inkSoft,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected == 0) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor(hr),
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      values[selected],
                      style: TextStyle(
                        color: metric.color,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                        fontFeatures: _tabular,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      units[selected],
                      style: TextStyle(
                        color: pal.inkSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLog extends StatelessWidget {
  const _EmptyLog();

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(Icons.history_rounded, size: 30, color: pal.inkSoft),
          const SizedBox(height: 12),
          Text(
            'No readings yet',
            style: TextStyle(
              color: pal.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect a device and your measurements will be logged here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.inkSoft, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}
