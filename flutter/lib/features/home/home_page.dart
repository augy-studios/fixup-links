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

/// The home page: the brand line, the cleaner, the platforms it knows, and the History button.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    this.trailingSpace = 0,
    this.showHistoryButton = true,
    this.long = false,
  });

  /// How far the brand line steps in from the right, clear of the Edge Tray's tab, on a phone.
  final double trailingSpace;

  /// The page's own padding at each side.
  static const sidePadding = 16.0;
  final bool showHistoryButton;

  /// The whole page in one column, not scrolling: the desktop's long screenshot.
  final bool long;

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    final safePadding = MediaQuery.paddingOf(context);
    Duration stepDuration;
    if (MediaQuery.of(context).disableAnimations) {
      stepDuration = Duration.zero;
    } else {
      stepDuration = const Duration(milliseconds: 340);
    }
    FontWeight? headlineWeight;
    if (!palette.uwu) {
      headlineWeight = FontWeight.w800;
    }
    final children = [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Steps in and out with the tray, at its pace.
              AnimatedPadding(
                duration: stepDuration,
                curve: const Cubic(0.2, 0.8, 0.2, 1),
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
                  fontWeight: headlineWeight,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Remove trackers & convert links for Discord, Telegram, and more!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: palette.muted),
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
                  style: TextStyle(color: palette.muted),
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
    final padding = EdgeInsets.fromLTRB(
      sidePadding,
      safePadding.top + 14,
      sidePadding,
      safePadding.bottom + 24,
    );
    if (long) {
      return Padding(
        padding: padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    }
    return ListView(padding: padding, children: children);
  }
}

/// The logo and the app's name, at the top of the page.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    FontWeight? nameWeight;
    if (!context.fx.uwu) {
      nameWeight = FontWeight.w700;
    }
    return Row(
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
            fontWeight: nameWeight,
            color: context.fx.ink,
          ),
        ),
      ],
    );
  }
}

/// The cleaner: the box, Clean URL, and the result. [quick] adds the quick screen's Replace.
class CleanerCard extends StatelessWidget {
  const CleanerCard({super.key, this.onReplace});
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final fixer = Fixer.I;
    return GlassCard(
      child: ListenableBuilder(
        listenable: fixer,
        builder: (context, _) {
          return _buildContent(context, fixer);
        },
      ),
    );
  }

  /// What's on the card, drawn again each time the cleaner changes.
  Widget _buildContent(BuildContext context, Fixer fixer) {
    final palette = context.fx;
    final cleaned = fixer.cleaned;
    final error = fixer.error;
    Color resultColor;
    BoxBorder? resultBorder;
    if (palette.glassy) {
      resultColor = palette.surfaceStrong;
      resultBorder = Border.all(color: palette.border);
    } else {
      resultColor = Theme.of(context).colorScheme.surfaceContainerHighest;
      resultBorder = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TourTarget(
          id: 'home.input',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.link, size: 18, color: palette.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Paste your URL',
                      style: TextStyle(color: palette.muted, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: fixer.input,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) {
                        fixer.fix();
                      },
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
                      fixer.input.text = text;
                      AppNav.say('Pasted from clipboard');
                    },
                    icon: const Icon(Icons.content_paste),
                  ),
                  IconButton(
                    tooltip: 'Clear input',
                    onPressed: fixer.clear,
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
            onPressed: () {
              fixer.fix();
            },
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Clean URL'),
          ),
        ),
        if (cleaned != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.check, size: 18, color: palette.ok),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Cleaned URL', style: TextStyle(color: palette.ok)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TourTarget(
            id: 'home.result',
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: resultColor,
                borderRadius: BorderRadius.circular(12),
                border: resultBorder,
              ),
              child: SelectableText(
                cleaned,
                style: TextStyle(color: palette.brandInk, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TourTarget(
            id: 'home.changes',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final change in fixer.changes) _ChangeTag(change),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TourTarget(
            id: 'home.actions',
            child: _Actions(url: cleaned),
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
        if (error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: palette.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(error, style: TextStyle(color: palette.error)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One change cleaning made, as a small tag: trackers removed, an embed fix, or a redirect.
class _ChangeTag extends StatelessWidget {
  const _ChangeTag(this.change);
  final Change change;

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    IconData icon;
    switch (change.type) {
      case 'trackers':
        icon = Icons.delete_outline;
      case 'embed':
        icon = Icons.code;
      case 'redirect':
        icon = Icons.arrow_forward;
      default:
        icon = Icons.check;
    }
    String tooltip;
    if (change.params.isEmpty) {
      tooltip = '';
    } else {
      tooltip = change.params.join(', ');
    }
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.brandFill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.onBrand),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                change.label,
                style: TextStyle(color: palette.onBrand, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy, Open, Share and QR for the cleaned link: in a row, or a column on a narrow card.
class _Actions extends StatelessWidget {
  const _Actions({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      (
        'Copy',
        Icons.copy,
        () {
          copyText(url);
        },
      ),
      (
        'Open',
        Icons.open_in_new,
        () {
          openLink(url);
        },
      ),
      (
        'Share',
        Icons.share,
        () {
          shareLink(url);
        },
      ),
      (
        'QR',
        Icons.qr_code_2,
        () {
          showQr(context, url);
        },
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final children = <Widget>[];
        for (final (label, icon, onTap) in buttons) {
          final button = OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
          if (narrow) {
            children.add(button);
          } else {
            children.add(Expanded(child: button));
          }
        }
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: child,
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              children[index],
            ],
          ],
        );
      },
    );
  }
}

/// The card listing every platform the cleaner knows, each as a chip.
class PlatformsCard extends StatelessWidget {
  const PlatformsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    FontWeight? titleWeight;
    if (!palette.uwu) {
      titleWeight = FontWeight.w700;
    }
    Color chipColor;
    BoxBorder? chipBorder;
    if (palette.glassy) {
      chipColor = palette.surfaceStrong;
      chipBorder = Border.all(color: palette.border);
    } else {
      chipColor = Theme.of(context).colorScheme.surfaceContainerHighest;
      chipBorder = null;
    }
    return TourTarget(
      id: 'home.platforms',
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.desktop_windows_outlined,
                  size: 20,
                  color: palette.ink,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Supported Platforms',
                    style: TextStyle(
                      fontSize: 18,
                      color: palette.ink,
                      fontWeight: titleWeight,
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
                for (final platform in platformChips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(999),
                      border: chipBorder,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgIcon(platform.svg, size: 15, color: palette.ink),
                        const SizedBox(width: 6),
                        // A long one ("URL Shorteners (redirect to final URL)") wraps inside its chip on a
                        // narrow phone rather than running off it.
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: platform.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: palette.ink,
                                  ),
                                ),
                                if (platform.note.isNotEmpty)
                                  TextSpan(
                                    text: ' ${platform.note}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.muted,
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

/// View History, with how many links are in it.
class HistoryButton extends StatelessWidget {
  const HistoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    return TourTarget(
      id: 'home.history',
      child: ValueListenableBuilder(
        valueListenable: History.changed,
        builder: (context, _, _) {
          final entryCount = History.load().length;
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: () {
              AppNav.showPage('history');
            },
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
                    color: palette.brandFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$entryCount',
                    style: TextStyle(color: palette.onBrand, fontSize: 13),
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
