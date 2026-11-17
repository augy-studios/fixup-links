// Make it yours (docs/desktop-features-spec.md §1): the first window a new install opens with, and
// from the tray's menu after that. About 940 x 660, in two columns: a welcome panel in the brand
// colour (hidden below 760 px wide), and the choices, each a card.
//
//   Start when I sign in   switch
//   Follow system theme    switch; off, the Theme row decides
//   Theme                  Light, Dark, Time-based (greyed while Follow system theme is on)
//   Look                   UwU Apps (the default on the desktop) or the desktop's own glass:
//                          Fluent 2, macOS Tahoe or Frosted Glass (theme/theme.dart's Glass)
//   Brand colour           the site's colours, or System accent
//
// It previews as you pick. Get started applies everything through the same settings the app's own
// Look page uses; closing it any other way changes nothing, but it won't open by itself again.
// (uwuFix's site has one language, so there's no language row.)
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'desktop.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<WelcomeScreen> createState() {
    return _WelcomeScreenState();
  }
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final look = AppLook.I;
  late final String _wasMode = look.modePreference;
  late final String _wasSwatch = look.swatchId;
  late final bool _wasDevice = look.deviceLook;
  late final bool _wasAccent = look.useSystemAccent;
  bool _login = true;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    startsAtSignIn().then((startsNow) {
      if (mounted) {
        setState(() {
          _login = startsNow || Desktop.fromSource;
        });
      }
    });
  }

  @override
  void dispose() {
    // Closed without Get started: everything as it was.
    if (!_applied) {
      look.modePreference = _wasMode;
      look.swatchId = _wasSwatch;
      look.deviceLook = _wasDevice;
      look.useSystemAccent = _wasAccent;
    }
    super.dispose();
  }

  Future<void> _start() async {
    _applied = true;
    await setStartAtSignIn(_login);
    await widget.onDone();
  }

  /// One choice's card: its icon in the brand colour, its name, and its control, greyed out and
  /// inert when not [enabled].
  Widget _row(Fx palette, IconData icon, String label, Widget control, {bool enabled = true}) {
    double opacity;
    if (enabled) {
      opacity = 1;
    } else {
      opacity = 0.45;
    }
    return Opacity(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: palette.surfaceStrong, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: palette.brandFill, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: palette.onBrand),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: palette.ink, fontSize: 15))),
          IgnorePointer(ignoring: !enabled, child: control),
        ]),
      ),
    );
  }

  /// The welcome panel in the brand colour, with the app's icon and what it does.
  Widget _panel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [look.swatch.color, Color.lerp(look.swatch.color, Colors.white, 0.45)!]),
      ),
      child: Stack(children: [
        Positioned(top: -60, right: -60, child: _circle(180)),
        Positioned(bottom: -40, left: -40, child: _circle(140)),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/desktop/icon.png', width: 72, height: 72)),
            const SizedBox(height: 18),
            const Text('Welcome to uwuFix', style: TextStyle(fontSize: 26, color: Color(0xFF121815), fontFamily: 'Jua')),
            const SizedBox(height: 6),
            const Text('Clean URLs. Fix embeds.', style: TextStyle(fontSize: 16, color: Color(0xCC121815))),
            const SizedBox(height: 28),
            for (final (icon, text) in const [
              (Icons.cleaning_services_outlined, 'Trackers stripped from any link'),
              (Icons.preview_outlined, 'Links that preview in Discord and Telegram'),
              (Icons.devices_outlined, 'Your history on all your devices'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  Icon(icon, size: 22, color: const Color(0xFF121815)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF121815), fontSize: 14.5))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  /// One of the site's brand colours, as a round button; ringed while it's the one picked.
  Widget _swatchButton(Fx palette, Swatch swatch) {
    final picked = !look.useSystemAccent && look.swatchId == swatch.id;
    Color ringColor;
    double ringWidth;
    if (picked) {
      ringColor = palette.brandInk;
      ringWidth = 3;
    } else {
      ringColor = palette.border;
      ringWidth = 1;
    }
    return Tooltip(
      message: swatch.label,
      child: Semantics(
        selected: picked,
        label: swatch.label,
        button: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            look.useSystemAccent = false;
            look.swatchId = swatch.id;
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: swatch.color,
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: ringWidth),
            ),
          ),
        ),
      ),
    );
  }

  /// The system's accent colour, as a round button with a computer on it; ringed while picked.
  Widget _systemAccentButton(Fx palette) {
    Color ringColor;
    double ringWidth;
    if (look.useSystemAccent) {
      ringColor = palette.ink;
      ringWidth = 3;
    } else {
      ringColor = palette.border;
      ringWidth = 1;
    }
    return Tooltip(
      message: 'System accent',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          look.useSystemAccent = true;
        },
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: look.systemAccent,
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: ringWidth),
          ),
          child: const Icon(Icons.computer, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  /// The choices, each a card: sign-in, theme, look and brand colour.
  Widget _choices(BuildContext context, Fx palette) {
    final followSystem = look.modePreference == 'system';
    FontWeight? titleWeight;
    if (!palette.uwu) {
      titleWeight = FontWeight.w700;
    }
    String shownMode;
    if (followSystem) {
      shownMode = 'light';
    } else {
      shownMode = look.modePreference;
    }
    return ListView(padding: const EdgeInsets.fromLTRB(32, 40, 32, 16), children: [
      Text('Make uwuFix yours', style: TextStyle(fontSize: 26, color: palette.ink, fontWeight: titleWeight)),
      const SizedBox(height: 4),
      Text('Choose how the app should look and feel.', style: TextStyle(color: palette.muted)),
      const SizedBox(height: 20),
      _row(
        palette,
        Icons.login,
        'Start when I sign in',
        Switch(
          value: _login,
          onChanged: (startAtSignIn) {
            setState(() {
              _login = startAtSignIn;
            });
          },
        ),
      ),
      _row(
        palette,
        Icons.brightness_auto_outlined,
        'Follow system theme',
        Switch(
          value: followSystem,
          onChanged: (follow) {
            // Turned off, it keeps whichever of light or dark is on show now.
            if (follow) {
              look.modePreference = 'system';
            } else if (Theme.of(context).brightness == Brightness.dark) {
              look.modePreference = 'dark';
            } else {
              look.modePreference = 'light';
            }
          },
        ),
      ),
      _row(
        palette,
        Icons.contrast,
        'Theme',
        DropdownButton<String>(
          value: shownMode,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 'light', child: Text('Light')),
            DropdownMenuItem(value: 'dark', child: Text('Dark')),
            DropdownMenuItem(value: 'time', child: Text('Time-based')),
          ],
          onChanged: (mode) {
            look.modePreference = mode!;
          },
        ),
        enabled: !followSystem,
      ),
      _row(
        palette,
        Icons.palette_outlined,
        'Look',
        DropdownButton<bool>(
          value: look.deviceLook,
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem(value: false, child: Text('UwU Apps')),
            DropdownMenuItem(value: true, child: Text(look.deviceLookName)),
          ],
          onChanged: (deviceLook) {
            look.deviceLook = deviceLook!;
          },
        ),
      ),
      _row(
        palette,
        Icons.circle,
        'Brand colour',
        Semantics(
          label: 'Brand colour',
          child: Wrap(spacing: 6, children: [
            for (final swatch in swatches) _swatchButton(palette, swatch),
            if (look.systemAccent != null) _systemAccentButton(palette),
          ]),
        ),
      ),
    ]);
  }

  /// The two columns (the panel only when there's room) over the footer with Get started.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        final palette = context.fx;
        final panel = _panel();
        final choices = _choices(context, palette);
        return Scaffold(
          body: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Column(children: [
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (wide) SizedBox(width: constraints.maxWidth / 3, child: panel),
                  Expanded(child: choices),
                ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(32, 12, 24, 16),
                child: Row(children: [
                  Expanded(child: Text('You can change these any time, from Make it yours in the tray’s menu.', style: TextStyle(color: palette.muted, fontSize: 13))),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Get started'),
                  ),
                ]),
              ),
            ]);
          }),
        );
      },
    );
  }

  Widget _circle(double size) {
    return Container(width: size, height: size, decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle));
  }
}
