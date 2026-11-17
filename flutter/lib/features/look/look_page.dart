// Look: which of the app's two looks (theme/theme.dart), light or dark, and the brand colour, as
// the site's Theme window has the last two. On the desktop, also the computer's accent colour.
// The device's own look is Material You on a phone, and on a computer its desktop's glass: Fluent
// 2 on Windows, macOS Tahoe on a Mac, Frosted Glass on Linux.
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../tour/tour.dart';

/// The Look page: the app's look, its light or dark mode, the accent on the desktop, and the
/// brand colour.
class LookPage extends StatelessWidget {
  const LookPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final look = AppLook.I;
    final body = ListenableBuilder(
      listenable: look,
      builder: (context, _) {
        return _buildSettings(context, look);
      },
    );
    if (embedded) {
      return body;
    }
    return Scaffold(appBar: AppBar(title: const Text('Look')), body: body);
  }

  /// The list of settings, drawn again each time the look changes.
  Widget _buildSettings(BuildContext context, AppLook look) {
    final palette = context.fx;

    // A small heading over a group of settings.
    Widget label(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: TextStyle(color: palette.muted, fontSize: 14)),
      );
    }

    final modePreference = look.modePreference;
    final glass = Glass.current;

    IconData deviceLookIcon;
    if (glass == null) {
      deviceLookIcon = Icons.palette_outlined;
    } else {
      deviceLookIcon = Icons.blur_on;
    }

    String lookDescription;
    if (look.deviceLook) {
      final glassAbout = glass?.about;
      if (glassAbout != null) {
        lookDescription = glassAbout;
      } else {
        lookDescription = 'Colours from your wallpaper and your phone’s own font, as Android’s own apps have them.';
      }
    } else {
      lookDescription = 'The website’s own look: its brand colours, and the Jua font.';
    }

    // Only shown while the mode follows the clock.
    String currentMode = '';
    if (modePreference == 'time') {
      if (AppLook.daylight(AppLook.now())) {
        currentMode = 'light';
      } else {
        currentMode = 'dark';
      }
    }

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
                  segments: [
                    ButtonSegment(value: true, label: Text(look.deviceLookName), icon: Icon(deviceLookIcon)),
                    const ButtonSegment(value: false, label: Text('UwU Apps'), icon: Icon(Icons.favorite_border)),
                  ],
                  selected: {look.deviceLook},
                  onSelectionChanged: (selection) {
                    look.deviceLook = selection.first;
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                lookDescription,
                style: TextStyle(color: palette.muted, fontSize: 13.5),
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
                      selected: modePreference == id,
                      onSelected: (_) {
                        look.modePreference = id;
                      },
                    ),
                ]),
              ),
              if (modePreference == 'time') ...[
                const SizedBox(height: 8),
                Text('Following the clock: light from 09:00 to 18:00. Currently $currentMode.',
                    style: TextStyle(color: palette.muted, fontSize: 13.5)),
              ],
              if (onDesktop && !look.deviceLook) ...[
                label('Accent'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use system accent colour'),
                  subtitle: const Text('Your computer’s accent colour for the UwU Apps look’s highlights.'),
                  value: look.useSystemAccent,
                  onChanged: (value) {
                    look.useSystemAccent = value;
                  },
                ),
              ],
              label('Brand colour'),
              TourTarget(
                id: 'look.colour',
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    for (final swatch in swatches)
                      RadioListTile<String>(
                        value: swatch.id,
                        // ignore: deprecated_member_use
                        groupValue: look.swatchId,
                        // ignore: deprecated_member_use
                        onChanged: (value) {
                          look.swatchId = value!;
                        },
                        contentPadding: EdgeInsets.zero,
                        secondary: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: swatch.color, shape: BoxShape.circle, border: Border.all(color: palette.border, width: 2)),
                        ),
                        title: Text(swatch.label),
                      ),
                  ]),
                ),
              ),
              if (look.deviceLook) ...[
                const SizedBox(height: 8),
                Text('${look.deviceLookName} uses your device’s colours: the brand colour shows in the UwU Apps look.',
                    style: TextStyle(color: palette.muted, fontSize: 13.5)),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}
