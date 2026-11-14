// Look: which of the app's two looks (theme/theme.dart), light or dark, and the brand colour, as
// the site's Theme window has the last two. On the desktop, also the computer's accent colour.
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../tour/tour.dart';

class LookPage extends StatelessWidget {
  const LookPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final look = AppLook.I;
    final body = ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        final fx = context.fx;
        Widget label(String t) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(t, style: TextStyle(color: fx.muted, fontSize: 14)),
            );
        final pref = look.modePreference;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.paddingOf(context).bottom + 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  label('Look'),
                  TourTarget(
                    id: 'look.style',
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Material You'), icon: Icon(Icons.palette_outlined)),
                        ButtonSegment(value: false, label: Text('UwU Apps'), icon: Icon(Icons.favorite_border)),
                      ],
                      selected: {look.materialYou},
                      onSelectionChanged: (s) => look.materialYou = s.first,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    look.materialYou
                        ? (onDesktop ? 'Colours from your computer’s accent colour, as its own apps have them.' : 'Colours from your wallpaper and your phone’s own font, as Android’s own apps have them.')
                        : 'The website’s own look: its brand colours, and the Jua font.',
                    style: TextStyle(color: fx.muted, fontSize: 13.5),
                  ),
                  label('Mode'),
                  TourTarget(
                    id: 'look.mode',
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (id, name, icon) in const [
                        ('system', 'As my device', Icons.brightness_auto_outlined),
                        ('light', 'Light', Icons.light_mode_outlined),
                        ('dark', 'Dark', Icons.dark_mode_outlined),
                        ('time', 'Time-based', Icons.schedule),
                      ])
                        ChoiceChip(
                          showCheckmark: false,
                          avatar: Icon(icon, size: 18),
                          label: Text(name),
                          selected: pref == id,
                          onSelected: (_) => look.modePreference = id,
                        ),
                    ]),
                  ),
                  if (pref == 'time') ...[
                    const SizedBox(height: 8),
                    Text('Following the clock: light from 09:00 to 18:00. Currently ${AppLook.daylight(AppLook.now()) ? 'light' : 'dark'}.',
                        style: TextStyle(color: fx.muted, fontSize: 13.5)),
                  ],
                  if (onDesktop) ...[
                    label('Accent'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use system accent colour'),
                      subtitle: const Text('Your computer’s accent colour for the UwU Apps look’s highlights.'),
                      value: look.useSystemAccent,
                      onChanged: (v) => look.useSystemAccent = v,
                    ),
                  ],
                  label('Brand colour'),
                  TourTarget(
                    id: 'look.colour',
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        for (final s in swatches)
                          RadioListTile<String>(
                            value: s.id,
                            // ignore: deprecated_member_use
                            groupValue: look.swatchId,
                            // ignore: deprecated_member_use
                            onChanged: (v) => look.swatchId = v!,
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle, border: Border.all(color: fx.border, width: 2)),
                            ),
                            title: Text(s.label),
                          ),
                      ]),
                    ),
                  ),
                  if (look.materialYou) ...[
                    const SizedBox(height: 8),
                    Text('Material You uses your device’s colours: the brand colour shows in the UwU Apps look.', style: TextStyle(color: fx.muted, fontSize: 13.5)),
                  ],
                ]),
              ),
            ),
          ],
        );
      },
    );
    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Look')), body: body);
  }
}
