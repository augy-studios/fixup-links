// Make it yours (docs/desktop-features-spec.md §1): the first window a new install opens with, and
// from the tray's menu after that. About 940 x 660, in two columns: a welcome panel in the brand
// colour (hidden below 760 px wide), and the choices, each a card.
//
//   Start when I sign in   switch
//   Follow system theme    switch; off, the Theme row decides
//   Theme                  Light, Dark, Time-based (greyed while Follow system theme is on)
//   Look                   UwU Apps (the default on the desktop) or Material You
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
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final look = AppLook.I;
  late final String _wasMode = look.modePreference;
  late final String _wasSwatch = look.swatchId;
  late final bool _wasYou = look.materialYou;
  late final bool _wasAccent = look.useSystemAccent;
  bool _login = true;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    startsAtSignIn().then((v) {
      if (mounted) setState(() => _login = v || Desktop.fromSource);
    });
  }

  @override
  void dispose() {
    // Closed without Get started: everything as it was.
    if (!_applied) {
      look.modePreference = _wasMode;
      look.swatchId = _wasSwatch;
      look.materialYou = _wasYou;
      look.useSystemAccent = _wasAccent;
    }
    super.dispose();
  }

  Future<void> _start() async {
    _applied = true;
    await setStartAtSignIn(_login);
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: look,
        builder: (context, _) {
          final fx = context.fx;
          final followSystem = look.modePreference == 'system';
          Widget row(IconData icon, String label, Widget control, {bool enabled = true}) => Opacity(
                opacity: enabled ? 1 : 0.45,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: fx.surfaceStrong, borderRadius: BorderRadius.circular(16), border: Border.all(color: fx.border)),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: fx.brandFill, borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 20, color: fx.onBrand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: TextStyle(color: fx.ink, fontSize: 15))),
                    IgnorePointer(ignoring: !enabled, child: control),
                  ]),
                ),
              );
          final panel = Container(
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
          final choices = ListView(padding: const EdgeInsets.fromLTRB(32, 40, 32, 16), children: [
            Text('Make uwuFix yours', style: TextStyle(fontSize: 26, color: fx.ink, fontWeight: fx.uwu ? null : FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Choose how the app should look and feel.', style: TextStyle(color: fx.muted)),
            const SizedBox(height: 20),
            row(Icons.login, 'Start when I sign in', Switch(value: _login, onChanged: (v) => setState(() => _login = v))),
            row(Icons.brightness_auto_outlined, 'Follow system theme',
                Switch(value: followSystem, onChanged: (v) => look.modePreference = v ? 'system' : (Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'))),
            row(
              Icons.contrast,
              'Theme',
              DropdownButton<String>(
                value: followSystem ? 'light' : look.modePreference,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                  DropdownMenuItem(value: 'time', child: Text('Time-based')),
                ],
                onChanged: (v) => look.modePreference = v!,
              ),
              enabled: !followSystem,
            ),
            row(
              Icons.palette_outlined,
              'Look',
              DropdownButton<bool>(
                value: look.materialYou,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: false, child: Text('UwU Apps')),
                  DropdownMenuItem(value: true, child: Text('Material You')),
                ],
                onChanged: (v) => look.materialYou = v!,
              ),
            ),
            row(
              Icons.circle,
              'Brand colour',
              Semantics(
                label: 'Brand colour',
                child: Wrap(spacing: 6, children: [
                  for (final s in swatches)
                    Tooltip(
                      message: s.label,
                      child: Semantics(
                        selected: !look.useSystemAccent && look.swatchId == s.id,
                        label: s.label,
                        button: true,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            look.useSystemAccent = false;
                            look.swatchId = s.id;
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                              border: Border.all(color: !look.useSystemAccent && look.swatchId == s.id ? fx.brandInk : fx.border, width: !look.useSystemAccent && look.swatchId == s.id ? 3 : 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (look.systemAccent != null)
                    Tooltip(
                      message: 'System accent',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => look.useSystemAccent = true,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: look.systemAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: look.useSystemAccent ? fx.ink : fx.border, width: look.useSystemAccent ? 3 : 1),
                          ),
                          child: const Icon(Icons.computer, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ]);
          return Scaffold(
            body: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 760;
              return Column(children: [
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (wide) SizedBox(width: c.maxWidth / 3, child: panel),
                    Expanded(child: choices),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(32, 12, 24, 16),
                  child: Row(children: [
                    Expanded(child: Text('You can change these any time, from Make it yours in the tray’s menu.', style: TextStyle(color: fx.muted, fontSize: 13))),
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

  Widget _circle(double size) => Container(width: size, height: size, decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle));
}
