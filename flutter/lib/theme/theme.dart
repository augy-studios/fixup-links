// The app's two looks, switchable in Look (features/look/look_page.dart):
//
//   Material You   the phone's own palette from its wallpaper (Android 12 and later) and its own
//                  font, as Android's own apps have it. The default on Android.
//   UwU Apps       the site's look: its seven brand colours, its pale surfaces, Jua, and light,
//                  dark or by the clock. The default on the desktop, which can take the computer's
//                  accent colour for its highlights instead (useSystemAccent).
//
// Either way, light or dark is the site's setting (uwufix.mode: light, dark, time, and here also
// system), and the brand colour the site's (uwufix.colorTheme), so the WebView app's choices come
// across. Widgets read colours from context.fx, never literals.
import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';

class Swatch {
  const Swatch(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

/// The site's brand colours (js/theme.js's COLOR_THEMES), in its order.
const swatches = [
  Swatch('classic', 'Classic', Color(0xFFCCFFCC)),
  Swatch('not-green-1', 'Not green 1', Color(0xFFFFCCCC)),
  Swatch('not-green-2', 'Not green 2', Color(0xFFCCCCFF)),
  Swatch('not-green-3', 'Not green 3', Color(0xFFFFFFCC)),
  Swatch('not-green-4', 'Not green 4', Color(0xFFFFCCFF)),
  Swatch('not-green-5', 'Not green 5', Color(0xFFCCFFFF)),
  Swatch('really-light-green', 'Really really light green', Color(0xFFFFFFFF)),
];

/// The colours every screen draws with, in either look.
@immutable
class Fx extends ThemeExtension<Fx> {
  const Fx({
    required this.bg,
    required this.surface,
    required this.surfaceStrong,
    required this.border,
    required this.ink,
    required this.muted,
    required this.brandInk,
    required this.brandFill,
    required this.brandFillStrong,
    required this.onBrand,
    required this.ok,
    required this.warn,
    required this.error,
    required this.uwu,
  });

  final Color bg, surface, surfaceStrong, border, ink, muted, brandInk, brandFill, brandFillStrong, onBrand, ok, warn, error;

  /// The UwU Apps look (glass cards and Jua), rather than Material You's.
  final bool uwu;

  @override
  Fx copyWith() => this;

  @override
  Fx lerp(Fx? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return Fx(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceStrong: c(surfaceStrong, other.surfaceStrong),
      border: c(border, other.border),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      brandInk: c(brandInk, other.brandInk),
      brandFill: c(brandFill, other.brandFill),
      brandFillStrong: c(brandFillStrong, other.brandFillStrong),
      onBrand: c(onBrand, other.onBrand),
      ok: c(ok, other.ok),
      warn: c(warn, other.warn),
      error: c(error, other.error),
      uwu: t < 0.5 ? uwu : other.uwu,
    );
  }
}

extension FxContext on BuildContext {
  Fx get fx => Theme.of(this).extension<Fx>()!;
}

/// Whether this is the desktop app (Windows, macOS, Linux), not a phone or a test.
bool get onDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux) && !Platform.environment.containsKey('FLUTTER_TEST');

/// What draws the characters a look's font hasn't: an ellipsis or a middle dot in Jua, emoji in
/// page titles. Whichever of these the device has.
const fontFallback = ['Roboto', 'Segoe UI', 'Noto Sans', 'Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji'];

class AppLook extends ChangeNotifier {
  AppLook._();
  static final AppLook I = AppLook._();

  static const lookKey = 'uwufix.look';
  static const modeKey = 'uwufix.mode';
  static const colorKey = 'uwufix.colorTheme';
  static const accentKey = 'uwufix.systemAccent';

  // The site's daylight window (js/theme.js's LIGHT_FROM_HOUR, LIGHT_UNTIL_HOUR).
  static const lightFrom = 9;
  static const lightUntil = 18;

  /// The device's own palette, once read: Android 12's wallpaper colours, or a computer's accent.
  ColorScheme? phoneLight;
  ColorScheme? phoneDark;
  Color? systemAccent;

  /// For tests and screenshots: the clock.
  static DateTime Function() now = DateTime.now;

  bool get materialYou {
    final v = Store.I.get(lookKey);
    if (v == 'you') return true;
    if (v == 'uwu') return false;
    return !onDesktop; // Material You on Android, the UwU Apps look on the desktop
  }

  set materialYou(bool on) {
    Store.I.put(lookKey, on ? 'you' : 'uwu');
    notifyListeners();
  }

  bool get useSystemAccent => Store.I.get(accentKey) == '1';
  set useSystemAccent(bool on) {
    Store.I.put(accentKey, on ? '1' : null);
    notifyListeners();
  }

  /// light, dark, time (by the clock) or system (the device's).
  String get modePreference {
    final v = Store.I.get(modeKey);
    return const ['light', 'dark', 'time', 'system'].contains(v) ? v! : 'system';
  }

  set modePreference(String v) {
    Store.I.put(modeKey, v);
    _schedule();
    notifyListeners();
  }

  String get swatchId {
    final v = Store.I.get(colorKey);
    return swatches.any((s) => s.id == v) ? v! : 'classic';
  }

  set swatchId(String id) {
    Store.I.put(colorKey, id);
    notifyListeners();
  }

  Swatch get swatch => swatches.firstWhere((s) => s.id == swatchId);

  static bool daylight(DateTime t) => t.hour >= lightFrom && t.hour < lightUntil;

  /// What the app is in right now, as Flutter wants it.
  ThemeMode get themeMode => switch (modePreference) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'time' => daylight(now()) ? ThemeMode.light : ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Timer? _timer;

  // A time-based mode left open across 09:00 or 18:00 turns itself over.
  void _schedule() {
    _timer?.cancel();
    if (modePreference != 'time') return;
    final t = now();
    var next = DateTime(t.year, t.month, t.day, t.hour < lightFrom ? lightFrom : (t.hour < lightUntil ? lightUntil : lightFrom));
    if (!next.isAfter(t)) next = next.add(const Duration(days: 1));
    _timer = Timer(next.difference(t) + const Duration(seconds: 1), () {
      notifyListeners();
      _schedule();
    });
  }

  /// The device's palette, read as the app opens and again whenever it comes back to the front
  /// (a new wallpaper, a new accent colour).
  Future<void> readDevice() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (palette != null) {
        // The wallpaper's own primary, tone 40, as Android 12's tonal-spot scheme seeds from.
        final seed = Color(palette.primary.get(40));
        phoneLight = ColorScheme.fromSeed(seedColor: seed);
        phoneDark = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
      }
    } catch (_) {}
    try {
      systemAccent = await DynamicColorPlugin.getAccentColor();
    } catch (_) {}
    _schedule();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  ThemeData theme(Brightness b) => materialYou ? _you(b) : _uwu(b);

  // ---------- Material You ----------

  ThemeData _you(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = (dark ? phoneDark : phoneLight) ??
        ColorScheme.fromSeed(seedColor: systemAccent ?? const Color(0xFF1F6B3D), brightness: b);
    final fx = Fx(
      bg: scheme.surface,
      surface: scheme.surfaceContainerLow,
      surfaceStrong: scheme.surfaceContainerHigh,
      border: scheme.outlineVariant,
      ink: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      brandInk: scheme.primary,
      brandFill: scheme.primaryContainer,
      brandFillStrong: scheme.primary,
      onBrand: scheme.onPrimaryContainer,
      ok: dark ? const Color(0xFF4ADE80) : const Color(0xFF0F7234),
      warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
      error: scheme.error,
      uwu: false,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamilyFallback: fontFallback,
      visualDensity: onDesktop ? VisualDensity.compact : VisualDensity.standard,
      extensions: [fx],
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  // ---------- UwU Apps (the site's style.css) ----------

  ThemeData _uwu(Brightness b) {
    final dark = b == Brightness.dark;
    final brand = swatch.color;
    final bg = dark ? const Color(0xFF0C100E) : const Color(0xFFEEF2F0);
    final page = Color.lerp(bg, brand, 0.10)!;
    final ink = dark ? const Color(0xFFEEF2EF) : const Color(0xFF121815);
    final surfaceStrong = dark ? Color.alphaBlend(const Color(0x1CFFFFFF), page) : Color.alphaBlend(const Color(0xC7FFFFFF), page);
    final surface = dark ? Color.alphaBlend(const Color(0x0FFFFFFF), page) : Color.alphaBlend(const Color(0x8CFFFFFF), page);
    // An accent from the computer, on the desktop, if asked for: its highlights only.
    final accent = onDesktop && useSystemAccent ? systemAccent : null;
    final brandInk = accent ?? (dark ? const Color(0xFFBFF5CF) : const Color(0xFF1F6B3D));
    final fill = accent != null ? Color.lerp(accent, surfaceStrong, 0.55)! : Color.lerp(surfaceStrong, brand, 0.55)!;
    final fillStrong = accent != null ? Color.lerp(accent, surfaceStrong, 0.3)! : Color.lerp(surfaceStrong, brand, 0.75)!;
    final onBrand = fill.computeLuminance() > 0.4 ? const Color(0xFF121815) : Colors.white;
    final fx = Fx(
      bg: page,
      surface: surface,
      surfaceStrong: surfaceStrong,
      border: dark ? const Color(0x24FFFFFF) : const Color(0xA6FFFFFF),
      ink: ink,
      muted: dark ? const Color(0xFF9AA7A0) : const Color(0xFF5B665F),
      brandInk: brandInk,
      brandFill: fill,
      brandFillStrong: fillStrong,
      onBrand: onBrand,
      ok: dark ? const Color(0xFF4ADE80) : const Color(0xFF0F7234),
      warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
      error: dark ? const Color(0xFFFA9696) : const Color(0xFFB91C1C),
      uwu: true,
    );
    final scheme = ColorScheme.fromSeed(seedColor: brandInk, brightness: b).copyWith(
      primary: brandInk,
      onPrimary: dark ? const Color(0xFF0C100E) : Colors.white,
      primaryContainer: fill,
      onPrimaryContainer: onBrand,
      secondaryContainer: fill,
      onSecondaryContainer: onBrand,
      surface: page,
      onSurface: ink,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceStrong,
      surfaceContainerHigh: surfaceStrong,
      surfaceContainerHighest: surfaceStrong,
      onSurfaceVariant: fx.muted,
      error: fx.error,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Jua',
      fontFamilyFallback: fontFallback,
      scaffoldBackgroundColor: page,
      visualDensity: onDesktop ? VisualDensity.compact : VisualDensity.standard,
      extensions: [fx],
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: fillStrong,
        contentTextStyle: TextStyle(color: onBrand, fontFamily: 'Jua', fontFamilyFallback: fontFallback, fontSize: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: onBrand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Jua', fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: surfaceStrong,
          foregroundColor: ink,
          side: BorderSide(color: fx.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: 'Jua', fontSize: 15),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: fx.border)),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surfaceStrong, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surfaceStrong),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceStrong,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: fx.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: fx.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandInk, width: 2)),
      ),
    );
    return base;
  }
}
