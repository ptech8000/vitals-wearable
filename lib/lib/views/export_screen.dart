import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vital_reading.dart';
import '../viewmodels/health_viewmodel.dart';

// =============================================================================
//  PULSE — export redesign
//  A summary hero (reading count + 30-day activity bars), a two-option format
//  picker, and one clear action button. The generated PDF is restyled to match.
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
  static const brand = Color(0xFF4F7CFF);
}

const _tabular = [FontFeature.tabularFigures()];

// ------------------------------------------------------------ isolate work --
//
// Building a PDF or CSV for a month of readings is CPU heavy. These run on a
// background isolate via compute(), so the UI keeps animating while they work.

String _buildCsv(List<Map<String, dynamic>> logs) {
  final rows = <List<dynamic>>[
    [
      "Timestamp",
      "Heart Rate (bpm)",
      "SpO2 (%)",
      "Systolic BP (mmHg)",
      "Diastolic BP (mmHg)",
      "Temperature (°C)",
      "Respiratory Rate (rpm)",
    ],
    for (final log in logs)
      [
        log['timestamp'] ?? '',
        log['heartRate'] ?? '',
        log['spo2'] ?? '',
        log['systolicBP'] ?? '',
        log['diastolicBP'] ?? '',
        log['temperature'] ?? '',
        log['respiratoryRate'] ?? '',
      ],
  ];
  return '\uFEFF${csv.encode(rows)}';
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}');
}

String _avg(List<Map<String, dynamic>> logs, String key, {int decimals = 0}) {
  final values = [
    for (final l in logs)
      if (_num(l[key]) != null) _num(l[key])!,
  ];
  if (values.isEmpty) return '-';
  final mean = values.reduce((a, b) => a + b) / values.length;
  return mean.toStringAsFixed(decimals);
}

Future<Uint8List> _buildPdf(List<Map<String, dynamic>> logs) async {
  final pdf = pw.Document();

  const ink = PdfColor.fromInt(0xFF14171F);
  const soft = PdfColor.fromInt(0xFF6B7385);
  const paper = PdfColor.fromInt(0xFFF5F4F0);
  const brand = PdfColor.fromInt(0xFF4F7CFF);

  final dates = [
    for (final l in logs)
      if (DateTime.tryParse(l['timestamp']?.toString() ?? '') != null)
        DateTime.parse(l['timestamp'].toString()),
  ]..sort();
  final range = dates.isEmpty
      ? 'Past 30 days'
      : '${DateFormat('d MMM yyyy').format(dates.first)} – ${DateFormat('d MMM yyyy').format(dates.last)}';

  pw.Widget stat(String label, String value, String unit) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: paper,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8.5, color: soft),
            ),
            pw.SizedBox(height: 4),
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: value,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  pw.TextSpan(
                    text: ' $unit',
                    style: const pw.TextStyle(fontSize: 8.5, color: soft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  pdf.addPage(
    pw.MultiPage(
      maxPages: 1000,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (pw.Context context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Self-recorded wearable data. Not a medical diagnosis.',
              style: const pw.TextStyle(fontSize: 8, color: soft),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: soft),
            ),
          ],
        ),
      ),
      build: (pw.Context context) {
        return [
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: ink,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(14)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Vital Signs Report',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      range,
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey400,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Generated ${DateFormat('d MMM yyyy').format(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey400,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Summary of ${logs.length} recordings, prepared for clinical review.',
            style: const pw.TextStyle(fontSize: 10, color: soft),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              stat('Avg heart rate', _avg(logs, 'heartRate'), 'bpm'),
              pw.SizedBox(width: 8),
              stat('Avg SpO2', _avg(logs, 'spo2'), '%'),
              pw.SizedBox(width: 8),
              stat(
                'Avg blood pressure',
                '${_avg(logs, 'systolicBP')}/${_avg(logs, 'diastolicBP')}',
                'mmHg',
              ),
              pw.SizedBox(width: 8),
              stat(
                'Avg temperature',
                _avg(logs, 'temperature', decimals: 1),
                '°C',
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            context: context,
            border: null,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 9,
            ),
            headerDecoration: const pw.BoxDecoration(color: brand),
            headerHeight: 26,
            cellHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 9, color: ink),
            oddRowDecoration: const pw.BoxDecoration(color: paper),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8),
            headers: <String>[
              'Date & time',
              'Heart rate',
              'SpO2',
              'Blood pressure',
              'Temp',
              'Resp',
            ],
            data: logs.map((log) {
              final dt =
                  DateTime.tryParse(log['timestamp']?.toString() ?? '') ??
                  DateTime.now();
              return [
                DateFormat('d MMM, HH:mm').format(dt),
                '${log['heartRate'] ?? '-'} bpm',
                '${log['spo2'] ?? '-'}%',
                '${log['systolicBP'] ?? '-'}/${log['diastolicBP'] ?? '-'}',
                '${log['temperature'] ?? '-'}°C',
                '${log['respiratoryRate'] ?? '-'} rpm',
              ];
            }).toList(),
          ),
        ];
      },
    ),
  );

  return pdf.save();
}

// ------------------------------------------------------------------ screen --

enum _ExportFormat { csv, pdf }

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  _ExportFormat _selected = _ExportFormat.pdf;
  _ExportFormat? _busy;
  _ExportFormat? _justDone;

  /// Readings from the last 30 days, newest first. The view model already
  /// keeps them in memory, so no database read is needed here.
  List<VitalReading> _last30Days(HealthViewModel vm) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 30));
    final result = vm.history
        .where(
          (reading) =>
              !reading.timestamp.isBefore(cutoff) &&
              !reading.timestamp.isAfter(now),
        )
        .toList();
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  Future<void> _export(_ExportFormat format) async {
    if (_busy != null) return;

    final logs = _last30Days(context.read<HealthViewModel>());
    if (logs.isEmpty) {
      _showSnackBar("No health logs found from the past 30 days.");
      return;
    }

    setState(() {
      _busy = format;
      _justDone = null;
    });

    try {
      final rows = [for (final log in logs) log.toJson()];

      if (format == _ExportFormat.csv) {
        final text = await compute(_buildCsv, rows);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        final origin = box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size;
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                Uint8List.fromList(utf8.encode(text)),
                mimeType: 'text/csv',
                name: 'vital_signs_report.csv',
              ),
            ],
            fileNameOverrides: ['vital_signs_report.csv'],
            sharePositionOrigin: origin,
          ),
        );
        if (result.status == ShareResultStatus.dismissed) return;
      } else {
        final bytes = await compute(_buildPdf, rows);
        final shared = await Printing.sharePdf(
          bytes: bytes,
          filename: 'healthcare_provider_report.pdf',
        );
        if (!shared) return;
      }

      if (!mounted) return;
      setState(() => _justDone = format);
      _showSnackBar(
        format == _ExportFormat.csv
            ? "CSV exported successfully!"
            : "PDF Report generated successfully!",
      );
      Future.delayed(const Duration(milliseconds: 2200), () {
        if (mounted && _justDone == format) setState(() => _justDone = null);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        format == _ExportFormat.csv
            ? "Export failed: $e"
            : "PDF generation failed: $e",
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showSnackBar(String message) {
    final pal = _Pal.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: pal.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(
          message,
          style: TextStyle(color: pal.bg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Readings per day for the last 30 days, oldest first.
  List<int> _dailyCounts(List<VitalReading> logs) {
    final today = DateTime.now();
    final start = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 29));
    final counts = List<int>.filled(30, 0);
    for (final l in logs) {
      final d = DateTime.utc(
        l.timestamp.year,
        l.timestamp.month,
        l.timestamp.day,
      );
      final i = d.difference(start).inDays;
      if (i >= 0 && i < 30) counts[i]++;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    context.select<HealthViewModel, int>((vm) => vm.historyRevision);
    final logs = _last30Days(context.read<HealthViewModel>());
    final empty = logs.isEmpty;
    final busy = _busy != null;
    final done = _justDone == _selected;

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
                  Text(
                    'Export',
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
                    'Share your vitals with your doctor.',
                    style: TextStyle(
                      color: pal.inkSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SummaryHero(logs: logs, counts: _dailyCounts(logs)),
                  const SizedBox(height: 28),
                  Text(
                    'Choose a format',
                    style: TextStyle(
                      color: pal.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _FormatOption(
                            icon: Icons.picture_as_pdf_rounded,
                            color: _Pal.pulse,
                            title: 'PDF report',
                            subtitle: 'Formatted summary with averages',
                            selected: _selected == _ExportFormat.pdf,
                            onTap: busy
                                ? null
                                : () => setState(
                                    () => _selected = _ExportFormat.pdf,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FormatOption(
                            icon: Icons.table_chart_rounded,
                            color: _Pal.ok,
                            title: 'CSV file',
                            subtitle: 'Raw data for Excel or Sheets',
                            selected: _selected == _ExportFormat.csv,
                            onTap: busy
                                ? null
                                : () => setState(
                                    () => _selected = _ExportFormat.csv,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Included in the file',
                    style: TextStyle(
                      color: pal.inkSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Included(color: _Pal.pulse, label: 'Heart rate'),
                      _Included(color: _Pal.oxygen, label: 'SpO₂'),
                      _Included(color: _Pal.pressure, label: 'Blood pressure'),
                      _Included(color: _Pal.temp, label: 'Temperature'),
                      _Included(color: _Pal.breath, label: 'Respiration'),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _ExportButton(
                    format: _selected,
                    busy: _busy == _selected,
                    done: done,
                    disabled: busy || empty,
                    onTap: () => _export(_selected),
                  ),
                  if (empty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(
                        child: Text(
                          'Nothing recorded in the past 30 days yet.',
                          style: TextStyle(
                            color: pal.inkSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
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

// --------------------------------------------------------------------- hero --

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.logs, required this.counts});
  final List<VitalReading> logs;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    final maxCount = counts.fold<int>(0, (a, b) => a > b ? a : b);

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
                      _Pal.brand.withValues(alpha: .32),
                      _Pal.brand.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.description_rounded,
                        color: _Pal.brand,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Provider report',
                        style: TextStyle(
                          color: Color(0xFFB7BECC),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Last 30 days',
                          style: TextStyle(
                            color: Color(0xFFB7BECC),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: logs.length.toDouble()),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => Text(
                          '${v.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            height: .95,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -3,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          logs.length == 1 ? 'reading' : 'readings',
                          style: const TextStyle(
                            color: Color(0xFF8D96A8),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    logs.isEmpty
                        ? 'Nothing to export yet'
                        : '${fmt.format(logs.last.timestamp)} – ${fmt.format(logs.first.timestamp)}',
                    style: const TextStyle(
                      color: Color(0xFF8D96A8),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final c in counts)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1.2,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeOutCubic,
                                height: c == 0 || maxCount == 0
                                    ? 5
                                    : 10 + (c / maxCount) * 38,
                                decoration: BoxDecoration(
                                  color: c == 0
                                      ? Colors.white.withValues(alpha: .14)
                                      : _Pal.brand,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Readings per day',
                    style: TextStyle(
                      color: Color(0xFF8D96A8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ format picker --

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: pal.dark ? .12 : .08)
              : pal.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: selected ? color : pal.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? color : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? color
                          : pal.inkSoft.withValues(alpha: .5),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: pal.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: pal.inkSoft,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Included extends StatelessWidget {
  const _Included({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: pal.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: pal.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- button --

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.format,
    required this.busy,
    required this.done,
    required this.disabled,
    required this.onTap,
  });

  final _ExportFormat format;
  final bool busy, done, disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final isPdf = format == _ExportFormat.pdf;
    final bg = done ? _Pal.ok : pal.ink;
    final fg = done ? Colors.white : pal.bg;

    final Widget content = busy
        ? Row(
            key: const ValueKey('busy'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
              ),
              const SizedBox(width: 12),
              Text(
                'Preparing your file…',
                style: TextStyle(
                  color: fg,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          )
        : done
        ? Row(
            key: const ValueKey('done'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, color: fg, size: 22),
              const SizedBox(width: 10),
              Text(
                'Ready to share',
                style: TextStyle(
                  color: fg,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          )
        : Row(
            key: ValueKey('idle-$format'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.ios_share_rounded, color: fg, size: 20),
              const SizedBox(width: 10),
              Text(
                isPdf ? 'Export PDF report' : 'Export CSV file',
                style: TextStyle(
                  color: fg,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled && !busy ? .4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: disabled ? null : onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              height: 60,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
