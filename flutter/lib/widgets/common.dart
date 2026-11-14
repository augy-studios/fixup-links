// Shared pieces: the site's glass card in the UwU Apps look (a Material card in Material You's),
// a small inline SVG icon, and a button with a tooltip.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme.dart';

/// The site's .card.glass, or a Material You filled card.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    if (!fx.uwu) {
      return Card.filled(
        margin: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(padding: padding, child: child),
      );
    }
    // A Material, not a bare box, so lists and buttons on it show their ink.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Material(
        color: fx.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: fx.border)),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// An icon from an SVG string, drawn in the text's colour (currentColor).
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.svg, {super.key, this.size = 18, this.color});
  final String svg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    return SvgPicture.string(svg, width: size, height: size, theme: SvgTheme(currentColor: c));
  }
}

/// A round icon button with its name as a tooltip, as the site's .glass-btn.
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.label, required this.onPressed, this.badge = false});
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: fx.uwu ? fx.surfaceStrong : Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: CircleBorder(side: fx.uwu ? BorderSide(color: fx.border) : BorderSide.none),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: SizedBox(width: 44, height: 44, child: Center(child: IconTheme(data: IconThemeData(color: fx.ink, size: 20), child: icon))),
          ),
        ),
      ),
    );
  }
}
