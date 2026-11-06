import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../viewmodels/health_viewmodel.dart';

// =============================================================================
//  PULSE — settings redesign
//  Device hero, visual theme tiles, big unit toggle, a slider for reading
//  frequency, and a cloud backup card. Self-styled; matches the other screens.
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

  static const ok = Color(0xFF22C58B);
  static const warn = Color(0xFFF5A623);
  static const bad = Color(0xFFFF4D5E);
  static const brand = Color(0xFF4F7CFF);
  static const temp = Color(0xFFFF9F2E);
}

const _tabular = [FontFeature.tabularFigures()];

// ------------------------------------------------------------------- screen --

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<String> _frequencies = [
    "5 min",
    "10 min",
    "30 min",
    "1 hour",
    "4 hours",
    "6 hours",
    "12 hours",
    "24 hours",
  ];

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);

    // Each section listens only to the values it shows, so live heart-rate
    // updates never rebuild this screen.
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
                    'Settings',
                    style: TextStyle(
                      color: pal.ink,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _DeviceCard(),
                  const SizedBox(height: 30),
                  const _SectionLabel(
                    title: 'Appearance',
                    caption: 'Choose how the app looks.',
                  ),
                  const _ThemeSection(),
                  const SizedBox(height: 30),
                  const _SectionLabel(
                    title: 'Temperature unit',
                    caption: 'Used for every body temperature reading.',
                  ),
                  const _TemperatureSection(),
                  const SizedBox(height: 30),
                  const _SectionLabel(
                    title: 'Reading frequency',
                    caption: 'How often the watch records and syncs vitals.',
                  ),
                  const _FrequencyCard(frequencies: _frequencies),
                  const SizedBox(height: 30),
                  const _SectionLabel(
                    title: 'Cloud backup',
                    caption: 'Keep your readings safe off this phone.',
                  ),
                  const _SyncSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.caption});
  final String title, caption;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: pal.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(
              color: pal.inkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- device --

class _DeviceCard extends StatelessWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context) {
    final s = context.select<HealthViewModel, (String, String, bool, int)>(
      (vm) =>
          (vm.deviceName, vm.connectionStatus, vm.isConnected, vm.batteryLevel),
    );
    final name = s.$1;
    final status = s.$2;
    final connected = s.$3;
    final battery = s.$4;
    final statusColor = connected ? _Pal.ok : _Pal.warn;

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
              right: -60,
              top: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _Pal.brand.withValues(alpha: connected ? .32 : .14),
                      _Pal.brand.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device status',
                          style: TextStyle(
                            color: Color(0xFFB7BECC),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          connected ? name : 'No device connected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            key: ValueKey(status),
                            padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 7, color: statusColor),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _BatteryRing(level: battery, connected: connected),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryRing extends StatelessWidget {
  const _BatteryRing({required this.level, required this.connected});
  final int level;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    const soft = Color(0xFF8D96A8);
    final color = !connected
        ? soft
        : (level > 50 ? _Pal.ok : (level > 20 ? _Pal.warn : _Pal.bad));

    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: connected ? level.clamp(0, 100) / 100 : 0,
            ),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => SizedBox(
              width: 76,
              height: 76,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: Colors.white.withValues(alpha: .1),
              ),
            ),
          ),
          connected
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$level%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFeatures: _tabular,
                      ),
                    ),
                    const Text(
                      'battery',
                      style: TextStyle(
                        color: soft,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : const Icon(Icons.watch_off_rounded, color: soft, size: 24),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- theme --

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final mode = context.select<HealthViewModel, ThemeMode>(
      (vm) => vm.themeMode,
    );
    void set(ThemeMode m) => context.read<HealthViewModel>().setThemeMode(m);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ThemeTile(
            label: 'System',
            kind: _PreviewKind.system,
            selected: mode == ThemeMode.system,
            onTap: () => set(ThemeMode.system),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ThemeTile(
            label: 'Light',
            kind: _PreviewKind.light,
            selected: mode == ThemeMode.light,
            onTap: () => set(ThemeMode.light),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ThemeTile(
            label: 'Dark',
            kind: _PreviewKind.dark,
            selected: mode == ThemeMode.dark,
            onTap: () => set(ThemeMode.dark),
          ),
        ),
      ],
    );
  }
}

enum _PreviewKind { system, light, dark }

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.label,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final _PreviewKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 92,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected ? _Pal.brand : pal.line,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _Preview(kind: kind),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? _Pal.brand : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? _Pal.brand
                        : pal.inkSoft.withValues(alpha: .5),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? pal.ink : pal.inkSoft,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tiny mock of the app in light, dark, or split (system) colours.
class _Preview extends StatelessWidget {
  const _Preview({required this.kind});
  final _PreviewKind kind;

  static const _lightBg = Color(0xFFF5F4F0);
  static const _darkBg = Color(0xFF0C0E12);

  Widget _mock(bool light) {
    final bg = light ? _lightBg : _darkBg;
    final card = light ? Colors.white : const Color(0xFF1C212B);
    final ink = light ? const Color(0xFF14171F) : const Color(0xFFF2F4F8);
    return Container(
      color: bg,
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 5,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(6),
              child: Container(
                width: 18,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D5E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _PreviewKind.light:
        return _mock(true);
      case _PreviewKind.dark:
        return _mock(false);
      case _PreviewKind.system:
        return Row(
          children: [
            Expanded(
              child: ClipRect(child: _HalfMock(child: _mock(true))),
            ),
            Expanded(
              child: ClipRect(
                child: _HalfMock(alignRight: true, child: _mock(false)),
              ),
            ),
          ],
        );
    }
  }
}

/// Shows one half of a mock (left or right) by overflowing it inside a clip.
class _HalfMock extends StatelessWidget {
  const _HalfMock({required this.child, this.alignRight = false});
  final Widget child;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => OverflowBox(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        minWidth: c.maxWidth * 2,
        maxWidth: c.maxWidth * 2,
        child: child,
      ),
    );
  }
}

// ------------------------------------------------------------- temperature --

class _TemperatureSection extends StatelessWidget {
  const _TemperatureSection();

  @override
  Widget build(BuildContext context) {
    final isCelsius = context.select<HealthViewModel, bool>(
      (vm) => vm.isCelsius,
    );
    void set(bool c) => context.read<HealthViewModel>().setTemperatureUnit(c);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _UnitOption(
              symbol: '°C',
              name: 'Celsius',
              selected: isCelsius,
              onTap: () => set(true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _UnitOption(
              symbol: '°F',
              name: 'Fahrenheit',
              selected: !isCelsius,
              onTap: () => set(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitOption extends StatelessWidget {
  const _UnitOption({
    required this.symbol,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String symbol, name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final fg = selected ? pal.bg : pal.ink;
    final sub = selected ? pal.bg.withValues(alpha: .7) : pal.inkSoft;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? pal.ink : pal.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: selected ? pal.ink : pal.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.thermostat_rounded,
                  size: 20,
                  color: selected ? _Pal.temp : pal.inkSoft,
                ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: fg),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              symbol,
              style: TextStyle(
                color: fg,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                color: sub,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- frequency --

class _FrequencyCard extends StatefulWidget {
  const _FrequencyCard({required this.frequencies});
  final List<String> frequencies;

  @override
  State<_FrequencyCard> createState() => _FrequencyCardState();
}

class _FrequencyCardState extends State<_FrequencyCard> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final freqs = widget.frequencies;
    final selected = context.select<HealthViewModel, String>(
      (vm) => vm.readingFrequency,
    );
    final stored = (freqs.contains(selected) ? freqs.indexOf(selected) : 0)
        .toDouble();
    final value = _drag ?? stored;
    final shown = freqs[value.round()];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _Pal.brand.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.timer_rounded,
                  color: _Pal.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Measure every',
                      style: TextStyle(
                        color: pal.inkSoft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        shown,
                        key: ValueKey(shown),
                        style: TextStyle(
                          color: pal.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: _Pal.brand,
              inactiveTrackColor: pal.surface2,
              thumbColor: Colors.white,
              overlayColor: _Pal.brand.withValues(alpha: .14),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11,
                elevation: 3,
              ),
              activeTickMarkColor: Colors.white.withValues(alpha: .7),
              inactiveTickMarkColor: pal.inkSoft.withValues(alpha: .35),
              tickMarkShape: const RoundSliderTickMarkShape(
                tickMarkRadius: 1.6,
              ),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: (freqs.length - 1).toDouble(),
              divisions: freqs.length - 1,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                final f = freqs[v.round()];
                context.read<HealthViewModel>().setReadingFrequency(f);
                setState(() => _drag = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'More often · ${freqs.first}',
                    maxLines: 2,
                    style: TextStyle(
                      color: pal.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${freqs.last} · Battery saver',
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    style: TextStyle(
                      color: pal.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
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

// -------------------------------------------------------------------- sync --

class _SyncSection extends StatelessWidget {
  const _SyncSection();

  static final DateFormat _timeFormat = DateFormat('MMM d, h:mm a');

  Future<void> _sync(BuildContext context) async {
    final vm = context.read<HealthViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final pal = _Pal.of(context);
    final outcome = await vm.syncNow();
    if (!context.mounted) return;

    final message = switch (outcome) {
      SyncOutcome.success => 'Synced to Firebase.',
      SyncOutcome.offline =>
        'No internet connection. Readings are saved on this phone and will upload later.',
      SyncOutcome.noDevice => 'Connect a device first to sync its readings.',
      SyncOutcome.failed => 'Sync failed. Please try again.',
    };
    messenger.showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context);
    final s = context.select<HealthViewModel, (bool, DateTime?)>(
      (vm) => (vm.isManualSyncing, vm.lastSyncedAt),
    );
    final syncing = s.$1;
    final last = s.$2;

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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (last == null ? pal.inkSoft : _Pal.ok).withValues(
                    alpha: .14,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  last == null
                      ? Icons.cloud_queue_rounded
                      : Icons.cloud_done_rounded,
                  color: last == null ? pal.inkSoft : _Pal.ok,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync to Firebase',
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        last == null
                            ? 'New readings upload automatically when online.'
                            : 'Last synced ${_timeFormat.format(last)}',
                        key: ValueKey(last),
                        style: TextStyle(
                          color: pal.inkSoft,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: syncing ? pal.ink.withValues(alpha: .6) : pal.ink,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: syncing ? null : () => _sync(context),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: syncing
                      ? Row(
                          key: const ValueKey('syncing'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: pal.bg,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Syncing…',
                              style: TextStyle(
                                color: pal.bg,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_upload_rounded,
                              color: pal.bg,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Sync now',
                              style: TextStyle(
                                color: pal.bg,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
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
