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

/// script.js's formatRelativeDate.
String relativeDate(String iso, {DateTime? now}) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  final diff = (now ?? DateTime.now()).difference(then);
  final mins = diff.inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '${mins}m ago';
  final hours = mins ~/ 60;
  if (hours < 24) return '${hours}h ago';
  final days = hours ~/ 24;
  if (days < 7) return '${days}d ago';
  final d = then.toLocal();
  return '${d.day}/${d.month}/${d.year}';
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.pane = false, this.onHide});

  /// The desktop's master pane: no page title bar of its own, and a tap stays put.
  final bool pane;

  /// Beside the cleaner on the desktop: puts the pane away (lib/desktop/chrome.dart).
  final VoidCallback? onHide;

  static void load(HistoryEntry e) {
    Fixer.I.input.text = e.original;
    Fixer.I.fix();
    AppNav.say('URL loaded from history');
  }

  Future<void> _clear(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text('Every link you’ve cleaned on this device goes. Other devices keep theirs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear all')),
        ],
      ),
    );
    if (yes == true) {
      History.clear();
      AppNav.say('History cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final actions = [
      TourTarget(
        id: 'history.share',
        child: Tooltip(
          message: 'Share history with your other devices',
          child: TextButton.icon(onPressed: () => AppNav.showPage('sync'), icon: const Icon(Icons.devices_outlined), label: const Text('Share')),
        ),
      ),
      TourTarget(
        id: 'history.clear',
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: fx.error),
          onPressed: () => _clear(context),
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
                Icon(Icons.info_outline, size: 40, color: fx.muted),
                const SizedBox(height: 10),
                Text('No history yet. Clean a URL to get started.', textAlign: TextAlign.center, style: TextStyle(color: fx.muted)),
              ]),
            ),
          ]);
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.paddingOf(context).bottom + 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = _Row(entry: items[i], onTap: () {
              load(items[i]);
              if (!pane) AppNav.showPage('home');
            });
            return i == 0 ? TourTarget(id: 'history.list', child: row) : row;
          },
        );
      },
    );
    if (pane) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Text('History', style: TextStyle(fontSize: 18, color: fx.ink, fontWeight: fx.uwu ? null : FontWeight.w700)),
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

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.onTap});
  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final e = entry;
    return Material(
      color: fx.uwu ? fx.surfaceStrong : Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: fx.uwu ? BorderSide(color: fx.border) : BorderSide.none),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Load: ${e.cleaned}',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (e.title != null) Text(e.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fx.ink, fontSize: 15, fontWeight: fx.uwu ? null : FontWeight.w600)),
                  Text('Original', style: TextStyle(color: fx.muted, fontSize: 11)),
                  Text(e.original, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fx.muted, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(e.cleaned, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fx.brandInk, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(relativeDate(e.date), style: TextStyle(color: fx.muted, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: fx.brandFill, borderRadius: BorderRadius.circular(999)),
                      child: Text(e.platform, style: TextStyle(color: fx.onBrand, fontSize: 11.5)),
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
                  History.remove(e.id);
                  AppNav.say('Entry deleted');
                },
                icon: Icon(Icons.delete_outline, color: fx.muted),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The row, on its own: the desktop's long screenshot, and tests.
Widget historyRow(HistoryEntry e) => _Row(entry: e, onTap: () {});
