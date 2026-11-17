// History, as the site's window has it: every link cleaned, newest first, each with its page's
// title, the link as it was, the clean one, when, and its platform. Tap one to clean it again;
// the bin deletes it. Share sends it to another device (features/sync/), Clear all empties it.
//
// On the desktop's widest windows this list sits beside the cleaner (the master pane), and tapping
// an entry fills the cleaner in place.
import 'package:flutter/material.dart';

import '../../app/nav.dart';
import '../../data/history.dart';
import '../../theme/theme.dart';
import '../home/fixer.dart';
import '../tour/tour.dart';

/// script.js's formatRelativeDate: how long ago [isoDate] was ("just now", "5m ago", "3h ago",
/// "2d ago"), or its day/month/year once it's a week or more.
String relativeDate(String isoDate, {DateTime? now}) {
  final then = DateTime.tryParse(isoDate);
  if (then == null) {
    return '';
  }
  DateTime current;
  if (now != null) {
    current = now;
  } else {
    current = DateTime.now();
  }
  final difference = current.difference(then);
  final minutes = difference.inMinutes;
  if (minutes < 1) {
    return 'just now';
  }
  if (minutes < 60) {
    return '${minutes}m ago';
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return '${hours}h ago';
  }
  final days = hours ~/ 24;
  if (days < 7) {
    return '${days}d ago';
  }
  final localDate = then.toLocal();
  return '${localDate.day}/${localDate.month}/${localDate.year}';
}

/// The History page (or, on the desktop, the pane beside the cleaner): every link cleaned, with
/// buttons to share the history and to clear it.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.pane = false, this.onHide});

  /// The desktop's master pane: no page title bar of its own, and a tap stays put.
  final bool pane;

  /// Beside the cleaner on the desktop: puts the pane away (lib/desktop/chrome.dart).
  final VoidCallback? onHide;

  /// Puts [entry]'s original link in the cleaner and cleans it again.
  static void load(HistoryEntry entry) {
    Fixer.I.input.text = entry.original;
    Fixer.I.fix();
    AppNav.say('URL loaded from history');
  }

  /// Asks first, then empties the history.
  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear all history?'),
          content: const Text('Every link you’ve cleaned on this device goes. Other devices keep theirs.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Clear all'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      History.clear();
      AppNav.say('History cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    final actions = [
      TourTarget(
        id: 'history.share',
        child: Tooltip(
          message: 'Share history with your other devices',
          child: TextButton.icon(
            onPressed: () {
              AppNav.showPage('sync');
            },
            icon: const Icon(Icons.devices_outlined),
            label: const Text('Share'),
          ),
        ),
      ),
      TourTarget(
        id: 'history.clear',
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: palette.error),
          onPressed: () {
            _clear(context);
          },
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Clear all'),
        ),
      ),
    ];
    final list = ValueListenableBuilder(
      valueListenable: History.changed,
      builder: (context, _, _) {
        final items = History.load();
        if (items.isEmpty) {
          return ListView(padding: const EdgeInsets.all(24), children: [
            TourTarget(
              id: 'history.empty',
              child: Column(children: [
                Icon(Icons.info_outline, size: 40, color: palette.muted),
                const SizedBox(height: 10),
                Text('No history yet. Clean a URL to get started.', textAlign: TextAlign.center, style: TextStyle(color: palette.muted)),
              ]),
            ),
          ]);
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.paddingOf(context).bottom + 16),
          itemCount: items.length,
          separatorBuilder: (_, _) {
            return const SizedBox(height: 8);
          },
          itemBuilder: (context, index) {
            final row = _Row(
              entry: items[index],
              onTap: () {
                load(items[index]);
                if (!pane) {
                  AppNav.showPage('home');
                }
              },
            );
            // The tour points at the first row.
            if (index == 0) {
              return TourTarget(id: 'history.list', child: row);
            } else {
              return row;
            }
          },
        );
      },
    );
    if (pane) {
      FontWeight? titleWeight;
      if (!palette.uwu) {
        titleWeight = FontWeight.w700;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Text('History', style: TextStyle(fontSize: 18, color: palette.ink, fontWeight: titleWeight)),
            const Spacer(),
            ...actions,
            if (onHide != null) IconButton(tooltip: 'Hide history (Ctrl+Shift+H)', onPressed: onHide, icon: const Icon(Icons.keyboard_double_arrow_left)),
          ]),
        ),
        Expanded(child: list),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('History'), actions: [...actions, const SizedBox(width: 6)]),
      body: list,
    );
  }
}

/// One history entry as a card: its title, the link as it was, the clean one, when, its
/// platform, and a button to delete it.
class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.onTap});
  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    Color cardColor;
    BorderSide cardBorder;
    if (palette.glassy) {
      cardColor = palette.surfaceStrong;
      cardBorder = BorderSide(color: palette.border);
    } else {
      cardColor = Theme.of(context).colorScheme.surfaceContainerLow;
      cardBorder = BorderSide.none;
    }
    FontWeight? titleWeight;
    if (!palette.uwu) {
      titleWeight = FontWeight.w600;
    }
    final title = entry.title;
    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: cardBorder),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Load: ${entry.cleaned}',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title != null)
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.ink, fontSize: 15, fontWeight: titleWeight)),
                  Text('Original', style: TextStyle(color: palette.muted, fontSize: 11)),
                  Text(entry.original, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.muted, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(entry.cleaned, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.brandInk, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(relativeDate(entry.date), style: TextStyle(color: palette.muted, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: palette.brandFill, borderRadius: BorderRadius.circular(999)),
                      child: Text(entry.platform, style: TextStyle(color: palette.onBrand, fontSize: 11.5)),
                    ),
                  ]),
                ]),
              ),
            ),
            TourTarget(
              id: 'history.delete',
              child: IconButton(
                tooltip: 'Delete entry',
                onPressed: () {
                  History.remove(entry.id);
                  AppNav.say('Entry deleted');
                },
                icon: Icon(Icons.delete_outline, color: palette.muted),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The row, on its own: the desktop's long screenshot, and tests.
Widget historyRow(HistoryEntry entry) {
  return _Row(entry: entry, onTap: () {});
}
