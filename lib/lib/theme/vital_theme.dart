import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colours with a fixed meaning across the app: each vital sign owns one hue,
/// so a colour always tells you which measurement you are looking at.
class VitalColors {
  VitalColors._();

  static const Color primary = Color(0xFF3B82F6);

  static const Color pulse = Color(0xFFFF5A6E); // heart rate
  static const Color oxygen = Color(0xFF38BDF8); // SpO2
  static const Color pressure = Color(0xFFFFB020); // blood pressure
  static const Color temperature = Color(0xFF2DD4A0); // body temperature
  static const Color breath = Color(0xFFA78BFA); // respiratory rate

  static const Color good = Color(0xFF22C55E);
  static const Color warn = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
}

/// Surface and text colours that change between light and dark mode.
@immutable
class VitalPalette {
  const VitalPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.shadow,
  });

  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color shadow;

  static const VitalPalette dark = VitalPalette(
    isDark: true,
    background: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    surfaceAlt: Color(0xFF1E2530),
    border: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF8B96A5),
    shadow: Color(0x40000000),
  );

  static const VitalPalette light = VitalPalette(
    isDark: false,
    background: Color(0xFFF4F6F9),
    surface: Colors.white,
    surfaceAlt: Color(0xFFECEFF4),
    border: Color(0x0F000000),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    shadow: Color(0x120F172A),
  );

  List<BoxShadow> get cardShadow => [
    BoxShadow(color: shadow, blurRadius: 18, offset: const Offset(0, 6)),
  ];
}

extension VitalThemeContext on BuildContext {
  VitalPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? VitalPalette.dark
      : VitalPalette.light;
}

class VitalText {
  VitalText._();

  /// Equal-width digits, so numbers that count up or change do not jitter.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle numeral(
    Color color, {
    double size = 28,
    FontWeight weight = FontWeight.w700,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: -0.8,
    height: 1.0,
    fontFeatures: tabular,
  );

  static TextStyle title(Color color, {double size = 17}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: -0.3,
  );

  static TextStyle label(Color color, {double size = 12.5}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: color);
}

class VitalTheme {
  VitalTheme._();

  static final ThemeData light = _build(VitalPalette.light);
  static final ThemeData dark = _build(VitalPalette.dark);

  static ThemeData _build(VitalPalette p) {
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: VitalColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: VitalColors.primary,
          surface: p.surface,
          onSurface: p.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(fontFamily: 'Roboto'),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: VitalText.title(p.textPrimary, size: 20),
        systemOverlayStyle: p.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark
            ? const Color(0xFF283243)
            : const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // Keeps the message clear of the floating navigation bar.
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    );
  }
}
