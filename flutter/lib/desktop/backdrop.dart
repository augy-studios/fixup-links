// The window's backdrop for a desktop's glass (theme/theme.dart's Glass), asked of the runner over
// the app's channel as "setBackdrop" {on, dark}, which answers whether the system now draws it:
//
//   Windows   Mica, by DWM (Windows 11; Windows 10 has none)   windows/runner/flutter_window.cpp
//   macOS     the window's vibrancy (NSVisualEffectView)      macos/Runner/MainFlutterWindow.swift
//   Linux     the compositor's blur behind the window, on      linux/runner/glass.cc
//             KWin and Deepin's (X11) or by
//             ext-background-effect-v1 (Wayland: COSMIC, KWin)
//
// While it does, the app leaves the window clear (AppLook.backdrop); where it doesn't, the glass is
// drawn over a backdrop of the app's own (widgets/glass.dart). Light or dark follows the app's
// mode, not only the system's, so Mica's and the vibrancy's tint match what's drawn over them.
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'desktop.dart';

/// Asks the window for the system's backdrop whenever the look or the system's light or dark
/// changes, and tells the look whether it got it.
class GlassWindow with WidgetsBindingObserver {
  GlassWindow._();
  static final GlassWindow instance = GlassWindow._();

  bool _started = false;
  (bool, bool)? _asked;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    AppLook.I.addListener(apply);
    apply();
  }

  @override
  void didChangePlatformBrightness() {
    apply();
  }

  bool get _dark {
    switch (AppLook.I.themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  /// Asks the window for the backdrop the look wants. [again] even if that's what it was last
  /// asked: window_manager takes Windows' extended frame away whenever it sets a title bar style
  /// or leaves full screen, so each of those asks again.
  Future<void> apply({bool again = false}) async {
    final on = AppLook.I.glass != null;
    final dark = _dark;
    if (!again && _asked == (on, dark)) {
      return;
    }
    _asked = (on, dark);
    try {
      final drawn = await Desktop.channel.invokeMethod<bool>('setBackdrop', {'on': on, 'dark': dark});
      AppLook.I.backdrop = on && drawn == true;
    } catch (_) {
      AppLook.I.backdrop = false;
    }
  }
}
