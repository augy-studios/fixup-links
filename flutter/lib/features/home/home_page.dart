// The home page, as the site's: the cleaner (paste a link, Clean URL, and what came of it with
// Copy, Open, Share and QR), the platforms it knows, and the History button.
import 'package:flutter/material.dart';

import '../../app/actions.dart';
import '../../app/nav.dart';
import '../../data/history.dart';
import '../../data/linkfix.dart';
import '../../data/platforms.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../tour/tour.dart';
import 'fixer.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    this.trailingSpace = 0,
    this.showHistoryButton = true,
    this.long = false,
  });

  /// Room at the right for the Edge Tray, on a phone.
  final double trailingSpace;
  final bool showHistoryButton;

  /// The whole page in one column, not scrolling: the desktop's long screenshot.
  final bool long;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final pad = MediaQuery.paddingOf(context);
    final children = [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(right: trailingSpace),
                child: const _Brand(),
              ),
              const SizedBox(height: 26),
              Text(
                'Clean URLs.\nFix Embeds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: fx.uwu ? null : FontWeight.w800,
                  color: fx.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Remove trackers & convert links for Discord, Telegram, and more!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: fx.muted),
              ),
              const SizedBox(height: 22),
              const CleanerCard(),
              const SizedBox(height: 16),
              const PlatformsCard(),
              if (showHistoryButton) ...[
                const SizedBox(height: 18),
                const Center(child: HistoryButton()),
              ],
              const SizedBox(height: 22),
              Text.rich(
                TextSpan(
                  style: TextStyle(color: fx.muted),
                  children: const [
                    TextSpan(text: 'Made with '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.favorite,
                        size: 16,
                        color: Color(0xFF34C759),
                      ),
                    ),
                    TextSpan(text: ' by Augy'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ];
    final padding = EdgeInsets.fromLTRB(16, pad.top + 14, 16, pad.bottom + 24);
    if (long)
      return Padding(
        padding: padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    return ListView(padding: padding, children: children);
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset('assets/images/logo.png', width: 40, height: 40),
      ),
      const SizedBox(width: 10),
      Text(
        'uwuFix',
        style: TextStyle(
          fontSize: 22,
          fontWeight: context.fx.uwu ? null : FontWeight.w700,
          color: context.fx.ink,
        ),
      ),
    ],
  );
}

/// The cleaner: the box, Clean URL, and the result. [quick] adds the quick screen's Replace.
class CleanerCard extends StatelessWidget {
  const CleanerCard({super.key, this.onReplace});
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final f = Fixer.I;
    return GlassCard(
      child: ListenableBuilder(
        listenable: f,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TourTarget(
              id: 'home.input',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, size: 18, color: fx.muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Paste your URL',
                          style: TextStyle(color: fx.muted, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: f.input,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => f.fix(),
                          decoration: const InputDecoration(
                            hintText:
                                'https://x.com/user/status/123?utm_source=...',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final text = (await pasteText()).trim();
                          if (text.isEmpty) {
                            AppNav.say('Nothing to paste. Copy a link first.');
                            return;
                          }
                          f.input.text = text;
                          AppNav.say('Pasted from clipboard');
                        },
                        icon: const Icon(Icons.content_paste),
                      ),
                      IconButton(
                        tooltip: 'Clear input',
                        onPressed: f.clear,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TourTarget(
              id: 'home.clean',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => f.fix(),
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Clean URL'),
              ),
            ),
            if (f.cleaned != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.check, size: 18, color: fx.ok),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Cleaned URL', style: TextStyle(color: fx.ok)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TourTarget(
                id: 'home.result',
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fx.uwu
                        ? fx.surfaceStrong
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: fx.uwu ? Border.all(color: fx.border) : null,
                  ),
                  child: SelectableText(
                    f.cleaned!,
                    style: TextStyle(color: fx.brandInk, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TourTarget(
                id: 'home.changes',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final c in f.changes) _ChangeTag(c)],
                ),
              ),
              const SizedBox(height: 12),
              TourTarget(
                id: 'home.actions',
                child: _Actions(url: f.cleaned!),
              ),
              if (onReplace != null) ...[
                const SizedBox(height: 12),
                TourTarget(
                  id: 'quick.replace',
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: onReplace,
                    icon: const Icon(Icons.undo),
                    label: const Text('Replace the highlighted link'),
                  ),
                ),
              ],
            ],
            if (f.error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: fx.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: fx.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f.error!, style: TextStyle(color: fx.error)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChangeTag extends StatelessWidget {
  const _ChangeTag(this.change);
  final Change change;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final icon = switch (change.type) {
      'trackers' => Icons.delete_outline,
      'embed' => Icons.code,
      'redirect' => Icons.arrow_forward,
      _ => Icons.check,
    };
    return Tooltip(
      message: change.params.isEmpty ? '' : change.params.join(', '),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fx.brandFill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fx.onBrand),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                change.label,
                style: TextStyle(color: fx.onBrand, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      ('Copy', Icons.copy, () => copyText(url)),
      ('Open', Icons.open_in_new, () => openLink(url)),
      ('Share', Icons.share, () => shareLink(url)),
      ('QR', Icons.qr_code_2, () => showQr(context, url)),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 360;
        final children = [
          for (final (label, icon, onTap) in buttons)
            narrow
                ? OutlinedButton.icon(
                    onPressed: onTap,
                    icon: Icon(icon, size: 18),
                    label: Text(label),
                  )
                : Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      icon: Icon(icon, size: 18),
                      label: Text(label),
                    ),
                  ),
        ];
        return narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final w in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: w,
                    ),
                ],
              )
            : Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    children[i],
                  ],
                ],
              );
      },
    );
  }
}

class PlatformsCard extends StatelessWidget {
  const PlatformsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    return TourTarget(
      id: 'home.platforms',
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.desktop_windows_outlined, size: 20, color: fx.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Supported Platforms',
                    style: TextStyle(
                      fontSize: 18,
                      color: fx.ink,
                      fontWeight: fx.uwu ? null : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in platformChips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: fx.uwu
                          ? fx.surfaceStrong
                          : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: fx.uwu ? Border.all(color: fx.border) : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgIcon(p.svg, size: 15, color: fx.ink),
                        const SizedBox(width: 6),
                        // A long one ("URL Shorteners (redirect to final URL)") wraps inside its chip on a
                        // narrow phone rather than running off it.
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: p.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: fx.ink,
                                  ),
                                ),
                                if (p.note.isNotEmpty)
                                  TextSpan(
                                    text: ' ${p.note}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: fx.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryButton extends StatelessWidget {
  const HistoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    return TourTarget(
      id: 'home.history',
      child: ValueListenableBuilder(
        valueListenable: History.changed,
        builder: (context, _, _) {
          final n = History.load().length;
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: () => AppNav.showPage('history'),
            icon: const Icon(Icons.history),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('View History')),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: fx.brandFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(color: fx.onBrand, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
