// The app's two looks, switchable in Look (features/look/look_page.dart):
//
//   the device's   on a phone, Material You: the phone's own palette from its wallpaper (Android
//                  12 and later) and its own font, as Android's own apps have it. The default on
//                  Android. On a computer, its desktop's own glass instead (Glass), as near to
//                  iOS's Liquid Glass as each desktop's own design language goes:
//                    Windows   Fluent 2: Mica behind the window, Acrylic on what floats over it
//                    macOS     macOS Tahoe: the window's vibrancy, and rounder, clearer glass on it
//                    Linux     Frosted Glass, after Deepin's DDE and COSMIC: a blurred backdrop
//                              where the desktop blurs behind windows, frosted panes on it
//                  each with the computer's accent colour and its own font.
//   UwU Apps       the site's look: its seven brand colours, its pale surfaces, Jua, and light,
//                  dark or by the clock. The default on the desktop, which can take the computer's
//                  accent colour for its highlights instead (useSystemAccent).
//
// Either way, light or dark is the site's setting (uwufix.mode: light, dark, time, and here also
// system), and the brand colour the site's (uwufix.colorTheme), so the WebView app's choices come
// across. Widgets read colours from context.fx, never literals.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
    this.glass,
  });

  final Color bg, surface, surfaceStrong, border, ink, muted, brandInk, brandFill, brandFillStrong, onBrand, ok, warn, error;

  /// The UwU Apps look (glass cards and Jua), rather than Material You's.
  final bool uwu;

  /// The desktop's own glass, when that's the look (bg is then the opaque colour behind it, for
  /// screenshots and where the system draws no backdrop).
  final Glass? glass;

  /// See-through surfaces with an edge, the UwU Apps look's or a desktop's glass, rather than
  /// Material You's flat tonal ones.
  bool get glassy => uwu || glass != null;

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
      glass: t < 0.5 ? glass : other.glass,
    );
  }
}

extension FxContext on BuildContext {
  Fx get fx => Theme.of(this).extension<Fx>()!;
}

/// Whether this is the desktop app (Windows, macOS, Linux), not a phone or a test.
bool get onDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux) && !Platform.environment.containsKey('FLUTTER_TEST');

/// A desktop's own glass: the second look on a computer, in place of Material You. Each as its
/// desktop's design language draws it, and each pushed as far towards iOS's Liquid Glass as that
/// language goes: clear panes that blur what's behind them, a bright edge where light catches
/// them, the accent colour for what's pressed.
enum Glass {
  /// Windows 11's Fluent 2: Mica behind the window (the wallpaper, blurred and tinted), Acrylic on
  /// what floats over it, 8 px corners on the window and a little rounder on cards here.
  fluent(
    label: 'Fluent 2',
    about: 'Windows 11’s own look: Mica behind the window, Acrylic on what floats over it, and your accent colour.',
    card: 12,
    control: 8,
    blur: 30,
    light: Color(0xFFF3F3F3),
    dark: Color(0xFF202020),
    paneLight: 0.62,
    paneDark: 0.055,
    edge: 0.5,
    veil: 0.0, // Mica is tinted already
    accent: Color(0xFF005FB8),
    font: 'Segoe UI Variable Text',
  ),

  /// macOS Tahoe's Liquid Glass: the window's vibrancy behind, and on it clear, deeply rounded
  /// panes with a bright rim, capsule buttons.
  tahoe(
    label: 'macOS Tahoe',
    about: 'macOS Tahoe’s Liquid Glass: the desktop through the window, clear rounded panes, and your accent colour.',
    card: 22,
    control: 999,
    blur: 24,
    light: Color(0xFFF2F2F7),
    dark: Color(0xFF1C1C1E),
    paneLight: 0.45,
    paneDark: 0.07,
    edge: 0.9,
    veil: 0.2,
    accent: Color(0xFF007AFF),
    font: null, // the system's (San Francisco)
  ),

  /// Deepin's DDE and COSMIC's frosted glass: the desktop blurred behind the window where its
  /// compositor does that (KWin and Deepin's, by X11's blur hint), frosted panes on it.
  frosted(
    label: 'Frosted Glass',
    about: 'Deepin’s and COSMIC’s frosted glass: the desktop blurred behind the window, frosted panes, and your accent colour.',
    card: 16,
    control: 10,
    blur: 26,
    light: Color(0xFFF0F2F5),
    dark: Color(0xFF1D2024),
    paneLight: 0.55,
    paneDark: 0.06,
    edge: 0.7,
    veil: 0.5, // a compositor's blur is untinted
    accent: Color(0xFF0081FF),
    font: null, // the system's
  );

  const Glass({
    required this.label,
    required this.about,
    required this.card,
    required this.control,
    required this.blur,
    required this.light,
    required this.dark,
    required this.paneLight,
    required this.paneDark,
    required this.edge,
    required this.veil,
    required this.accent,
    required this.font,
  });

  /// Its name in Look, and what it is.
  final String label, about;

  /// Corner radii: cards and panes, and buttons and fields (999: a capsule).
  final double card, control;

  /// How far a pane blurs what's behind it (a Gaussian sigma).
  final double blur;

  /// The window's colour where nothing's behind it, light and dark.
  final Color light, dark;

  /// How much white a pane is, light and dark: lower is clearer.
  final double paneLight, paneDark;

  /// How bright a pane's rim catches the light, 0 to 1.
  final double edge;

  /// How much of the window's colour lies over the system's backdrop, so text reads on it.
  final double veil;

  /// The accent when the computer gives none.
  final Color accent;

  /// Its font, or null for the system's.
  final String? font;

  /// This computer's, if it's a computer.
  static Glass? get current {
    if (override != null) return override;
    if (!onDesktop) return null;
    if (Platform.isWindows) return fluent;
    if (Platform.isMacOS) return tahoe;
    return frosted;
  }

  /// For tests and screenshots: a desktop's glass where there's no desktop.
  static Glass? override;
}

/// The accent, as ink that reads on glass: deep enough on light, light enough on dark (as Fluent
/// 2 shades the Windows accent, and macOS its controls').
Color accentInk(Color accent, bool dark) {
  final h = HSLColor.fromColor(accent);
  final l = dark ? math.max(h.lightness, 0.68) : math.min(h.lightness, 0.42);
  return h.withLightness(l).withSaturation(math.min(h.saturation, 0.95)).toColor();
}

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

  /// The device's own look rather than the UwU Apps look: Material You on a phone, its desktop's
  /// glass on a computer. Kept as the site keeps it ('you' or 'uwu'), and 'glass' for a desktop's,
  /// which a phone reads as Material You; a computer reads 'you' (its Material You, from before it
  /// had glass) as glass.
  bool get deviceLook {
    final v = Store.I.get(lookKey);
    if (v == 'you' || v == 'glass') return true;
    if (v == 'uwu') return false;
    return !onDesktop; // Material You on Android, the UwU Apps look on the desktop
  }

  set deviceLook(bool on) {
    Store.I.put(lookKey, on ? (Glass.current != null ? 'glass' : 'you') : 'uwu');
    notifyListeners();
  }

  /// Material You, the phone's look.
  bool get materialYou => deviceLook && Glass.current == null;

  /// The desktop's glass, when that's the look.
  Glass? get glass => deviceLook ? Glass.current : null;

  /// The device's own look's name: Material You, Fluent 2, macOS Tahoe or Frosted Glass.
  String get deviceLookName => Glass.current?.label ?? 'Material You';

  /// Whether the system draws the window's backdrop (Mica, macOS's vibrancy, the compositor's
  /// blur), told by desktop/backdrop.dart. Without it the glass is drawn over a backdrop of its own.
  bool get backdrop => _backdrop;
  bool _backdrop = false;
  set backdrop(bool on) {
    if (on == _backdrop) return;
    _backdrop = on;
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

  ThemeData theme(Brightness b) {
    final g = glass;
    if (g != null) return _glass(b, g);
    return materialYou ? _you(b) : _uwu(b);
  }

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

  // ---------- A desktop's glass (Fluent 2, macOS Tahoe, Frosted Glass) ----------

  ThemeData _glass(Brightness b, Glass g) {
    final dark = b == Brightness.dark;
    final base = dark ? g.dark : g.light;
    final accent = systemAccent ?? g.accent;
    final brandInk = accentInk(accent, dark);
    // White or near-black on the accent, whichever reads better (Fluent 2's dark accent buttons
    // take black text).
    final lum = brandInk.computeLuminance();
    final onAccent = (lum + 0.05) / 0.05 > 1.05 / (lum + 0.05) ? const Color(0xFF111111) : Colors.white;
    final ink = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E);
    final muted = dark ? const Color(0xFFA1A1A6) : const Color(0xFF5E5E63);
    // Panes are white: plenty over light, a breath of it over dark. Cards are a little stronger.
    final surface = Colors.white.withValues(alpha: dark ? g.paneDark : g.paneLight);
    final surfaceStrong = Colors.white.withValues(alpha: dark ? g.paneDark + 0.06 : math.min(g.paneLight + 0.22, 0.9));
    final border = dark ? const Color(0x1FFFFFFF) : const Color(0x16000000);
    // What's chosen: the accent, see-through.
    final fill = brandInk.withValues(alpha: dark ? 0.30 : 0.16);
    // Menus, dialogs and sheets, over whatever's there: near enough opaque to read.
    final solid = Color.alphaBlend(surfaceStrong, base);
    final fx = Fx(
      bg: base,
      surface: surface,
      surfaceStrong: surfaceStrong,
      border: border,
      ink: ink,
      muted: muted,
      brandInk: brandInk,
      brandFill: fill,
      brandFillStrong: brandInk,
      onBrand: ink,
      ok: dark ? const Color(0xFF4ADE80) : const Color(0xFF0F7234),
      warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
      error: dark ? const Color(0xFFFF6961) : const Color(0xFFC42B1C),
      uwu: false,
      glass: g,
    );
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
      primary: brandInk,
      onPrimary: onAccent,
      primaryContainer: Color.alphaBlend(fill, solid),
      onPrimaryContainer: ink,
      secondaryContainer: fill,
      onSecondaryContainer: ink,
      surface: base,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: Color.alphaBlend(surface, base),
      surfaceContainerLow: Color.alphaBlend(surface, base),
      surfaceContainer: solid,
      surfaceContainerHigh: solid,
      surfaceContainerHighest: solid,
      outlineVariant: border,
      error: fx.error,
    );
    final capsule = g.control >= 999;
    final controlShape = capsule ? const StadiumBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.control)) as OutlinedBorder;
    final fieldRadius = BorderRadius.circular(capsule ? 12 : g.control);
    final font = g.font;
    final fallback = [if (g == Glass.fluent) 'Segoe UI', ...fontFallback];
    // A style of the glass's font, or of the platform's where it's the system's (as Flutter's own
    // typography picks it: San Francisco, Segoe UI, the Linux desktop's sans).
    final body = Typography.material2021(platform: defaultTargetPlatform).black.bodyMedium!;
    TextStyle text([double? size, Color? color]) => body.copyWith(fontFamily: font ?? body.fontFamily, fontFamilyFallback: fallback, fontSize: size, color: color);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: font,
      fontFamilyFallback: fallback,
      // The window shows through: the system's backdrop, or the glass's own (GlassBackdrop).
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: solid,
      visualDensity: onDesktop ? VisualDensity.compact : VisualDensity.standard,
      // Highlights on hover and press, as the desktops have, not Android's ripple.
      splashFactory: NoSplash.splashFactory,
      hoverColor: ink.withValues(alpha: 0.05),
      highlightColor: ink.withValues(alpha: 0.08),
      extensions: [fx],
      dividerTheme: DividerThemeData(color: border, space: 1),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: fill,
        indicatorShape: controlShape,
        selectedIconTheme: IconThemeData(color: brandInk),
        unselectedIconTheme: IconThemeData(color: ink.withValues(alpha: 0.8)),
      ),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: surface, indicatorColor: fill, indicatorShape: controlShape),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: solid,
        contentTextStyle: text(14, ink),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(math.min(g.card, 16)), side: BorderSide(color: border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: brandInk, foregroundColor: onAccent, shape: controlShape, elevation: 0),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(backgroundColor: surfaceStrong, foregroundColor: ink, side: BorderSide(color: border), shape: controlShape),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: brandInk, shape: controlShape)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: capsule ? const CircleBorder() : controlShape)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          selectedBackgroundColor: fill,
          selectedForegroundColor: ink,
          foregroundColor: ink,
          side: BorderSide(color: border),
          shape: controlShape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: fill,
        side: BorderSide(color: border),
        shape: controlShape,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.card), side: BorderSide(color: border)),
      ),
      listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(capsule ? 12 : g.control)), selectedColor: brandInk),
      dialogTheme: DialogThemeData(
        backgroundColor: solid,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(g.card + 4), side: BorderSide(color: border)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: solid),
      popupMenuTheme: PopupMenuThemeData(
        color: solid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(math.min(g.card, 14)), side: BorderSide(color: border)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(capsule ? 10 : g.control), border: Border.all(color: border)),
        textStyle: text(12.5, ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceStrong,
        border: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: brandInk, width: 2)),
      ),
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
