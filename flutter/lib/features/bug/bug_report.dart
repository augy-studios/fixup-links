// Report a bug, as SG Bus Timings has it (and the site's js/bug-report.js): what went wrong, a way
// to be reached if they'd like an answer, up to three pictures (from the device, or a screenshot
// of a page of the app), and what helps find it (the app's version, the device, the page on show
// and the language), sent to Augy on Telegram by the site's /api/bug-report. What's typed stays
// until it's sent. Once it's sent, it says the report's ID ("20261114-K7QM"), to quote.
//
// Screenshot a page puts the report away and leaves you in the app, to go to the page you want,
// with a floating Screenshot this page. That takes the whole page, top to bottom, scrolling it a
// screen at a time and joining them up, and brings you back to the report. The button floats
// outside the part of the screen that's taken (app/app.dart), so it isn't in the picture. A whole
// page also goes to Telegram as a file, at its full size (api/bug-report.js).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

import '../../api/resolve.dart';
import '../../app/nav.dart';
import '../../data/store.dart';
import '../../native/native_bridge.dart';
import '../../theme/theme.dart';

const _email = 'augy@augystudios.com';
const _maxShots = 3;
const _pageNames = {'home': 'Home', 'history': 'History', 'sync': 'Share history', 'look': 'Look'};

/// Opens it, from the Edge Tray, the desktop's rail, command bar and Help menu.
void openBugReport() => AppNav.push(const BugReport(), name: 'bug');

/// A report's pictures, which outlive its screen while you go and find a page to take.
class _Pictures {
  _Pictures._();
  static final List<String> shots = []; // JPEG data URLs
  static final Set<int> full = {}; // whole pages among them: each also goes as a file, at its full size

  static void clear() {
    shots.clear();
    full.clear();
  }

  static void removeAt(int i) {
    shots.removeAt(i);
    final moved = {for (final n in full) if (n != i) n > i ? n - 1 : n};
    full
      ..clear()
      ..addAll(moved);
  }
}

class BugReport extends StatefulWidget {
  const BugReport({super.key});

  static const draftKey = 'uwufix.bugDraft';

  /// The whole page, as a JPEG data URL that Telegram takes as a photo: no wider than pageWidth,
  /// no taller than pageRatio times its width, with its sides adding up to at most pageSum, and
  /// about 900 KB, rougher and then smaller till it is.
  static const pageWidth = 1080;
  static const pageRatio = 20;
  static const pageSum = 9998;

  static String? pageJpeg(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final w = image.width;
    final h = math.min(image.height, w * pageRatio);
    var k = math.min(1.0, math.min(pageWidth / w, pageSum / (w + h)));
    final page = h == image.height ? image : img.copyCrop(image, x: 0, y: 0, width: w, height: h);
    for (var tries = 0; tries < 8; tries++) {
      // The height from the rounded-down width, so it stays within pageRatio.
      final sw = math.max(1, (w * k).floor());
      final sh = math.max(1, math.min((h * k).floor(), sw * pageRatio));
      final out = img.encodeJpg(k >= 1 ? page : img.copyResize(page, width: sw, height: sh), quality: tries < 2 ? 80 : 68);
      if (out.length <= 900 * 1024 || tries == 7) return 'data:image/jpeg;base64,${base64Encode(out)}';
      if (tries >= 1) k *= 0.82;
    }
    return null;
  }

  /// A picture as a JPEG data URL, at most 1600 px a side and about 900 KB.
  static String? pictureJpeg(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) return null;
    final side = math.max(image.width, image.height);
    if (side > 1600) image = img.copyResize(image, width: (image.width * 1600 / side).round());
    for (final q in [80, 65, 50, 35]) {
      final out = img.encodeJpg(image, quality: q);
      if (out.length <= 900 * 1024 || q == 35) return 'data:image/jpeg;base64,${base64Encode(out)}';
    }
    return null;
  }

  /// What's sent with it, to help find the bug.
  static Map<String, String> details() {
    final info = Native.info;
    final String device;
    if (onDesktop) {
      final os = switch ('${info?['os'] ?? Platform.operatingSystem}') { 'windows' => 'Windows', 'macos' => 'macOS', 'linux' => 'Linux', final o => o };
      device = ['$os ${info?['osVersion'] ?? ''}'.trim(), 'Flutter'].join(' · ');
    } else {
      final release = info?['release'] ?? info?['android'];
      device = [release == null ? 'Android' : 'Android $release', if (info?['model'] != null) '${info!['model']}', 'Flutter'].join(' · ');
    }
    return {
      'version': Native.version ?? '',
      'platform': onDesktop ? 'desktop' : 'android',
      'device': device,
      'page': _pageNames[AppNav.page.value] ?? AppNav.page.value,
      'lang': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    };
  }

  static String detailsText(Map<String, String> d) =>
      [onDesktop ? 'Desktop app' : 'Android app', d['version'], d['device'], d['page']].where((s) => s != null && s.isNotEmpty).join(' · ');

  @override
  State<BugReport> createState() => _BugReportState();
}

/// What floats over the app while you find the page to take.
class ShotBar extends StatefulWidget {
  const ShotBar({super.key});

  @override
  State<ShotBar> createState() => _ShotBarState();
}

class _ShotBarState extends State<ShotBar> {
  bool _busy = false;

  /// Each screenful settled before it's taken.
  static Future<void> _settled() async {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  /// The biggest list on show that has more than fits on the screen, if there is one.
  static ScrollableState? _pageScroll(BuildContext from) {
    ScrollableState? best;
    var most = 0.0;
    final wide = MediaQuery.sizeOf(from).width / 3;
    void look(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        final box = e.findRenderObject();
        final p = s.position;
        // Not the Edge Tray's column, or anything else down one side.
        if (p.axis == Axis.vertical && box is RenderBox && box.hasSize && box.size.width >= wide && p.hasContentDimensions && p.maxScrollExtent > 8) {
          final area = box.size.width * box.size.height;
          if (area > most) {
            most = area;
            best = s;
          }
        }
      }
      e.debugVisitOnstageChildren(look);
    }

    (from as Element).debugVisitOnstageChildren(look);
    return best;
  }

  static const _ratio = 1.5;

  /// What can be drawn in one picture, in pixels.
  static const _tallest = 8000.0;

  /// The page from top to bottom: the screen with its list at the top, then each further
  /// screenful of the list, and the rest of the screen under them.
  static Future<ui.Image?> _wholePage() async {
    final at = AppNav.shotKey.currentContext;
    final boundary = at?.findRenderObject() as RenderRepaintBoundary?;
    if (at == null || boundary == null) return null;
    final scroll = _pageScroll(at);
    if (scroll == null) return boundary.toImage(pixelRatio: _ratio);
    final p = scroll.position;
    final was = p.pixels;
    final box = scroll.context.findRenderObject()! as RenderBox;
    final bottom = (box.localToGlobal(Offset.zero, ancestor: boundary).dy + box.size.height) * _ratio;
    final slices = <(ui.Image, double)>[];
    ui.Image first;
    try {
      p.jumpTo(p.minScrollExtent);
      await _settled();
      first = await boundary.toImage(pixelRatio: _ratio);
      var y = p.minScrollExtent;
      var height = first.height.toDouble();
      while (y < p.maxScrollExtent - 0.5 && height < _tallest) {
        final next = math.min(y + p.viewportDimension, p.maxScrollExtent);
        p.jumpTo(next);
        await _settled();
        final h = (next - y) * _ratio;
        slices.add((await boundary.toImage(pixelRatio: _ratio), h));
        height += h;
        y = next;
      }
    } finally {
      p.jumpTo(was);
    }
    final w = first.width.toDouble();
    var total = first.height.toDouble();
    for (final s in slices) {
      total += s.$2;
    }
    final record = ui.PictureRecorder();
    final canvas = Canvas(record);
    final paint = Paint();
    canvas.drawImageRect(first, Rect.fromLTWH(0, 0, w, bottom), Rect.fromLTWH(0, 0, w, bottom), paint);
    var y = bottom;
    for (final (image, h) in slices) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, bottom - h, w, h), Rect.fromLTWH(0, y, w, h), paint);
      y += h;
    }
    final under = first.height - bottom;
    if (under > 0) canvas.drawImageRect(first, Rect.fromLTWH(0, bottom, w, under), Rect.fromLTWH(0, y, w, under), paint);
    final out = await record.endRecording().toImage(w.round(), total.round());
    first.dispose();
    for (final (image, _) in slices) {
      image.dispose();
    }
    return out;
  }

  void _back() {
    AppNav.shooting.value = false;
    openBugReport();
  }

  Future<void> _take() async {
    setState(() => _busy = true);
    try {
      final shot = await _wholePage();
      final png = await shot?.toByteData(format: ui.ImageByteFormat.png);
      shot?.dispose();
      final jpeg = png == null ? null : await compute(BugReport.pageJpeg, png.buffer.asUint8List());
      if (jpeg == null) throw StateError('no picture');
      _Pictures.shots.add(jpeg);
      _Pictures.full.add(_Pictures.shots.length - 1);
    } catch (_) {
      AppNav.say("Couldn't take a screenshot here. Take one with your device and add it instead.");
    }
    if (mounted) _busy = false;
    _back();
  }

  @override
  Widget build(BuildContext context) {
    // Over the navigator, outside it: its own Material for the buttons' ink.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            type: MaterialType.transparency,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: _busy ? null : _take,
                  icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.screenshot_outlined),
                  label: Text(_busy ? 'Taking a screenshot…' : 'Screenshot this page'),
                ),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.small(
                heroTag: null,
                onPressed: _busy ? null : _back,
                child: Semantics(label: 'Cancel', child: const Icon(Icons.close)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BugReportState extends State<BugReport> {
  late final Map<String, dynamic> _draft = Store.I.json<Map<String, dynamic>>(BugReport.draftKey, const {});
  late final _text = TextEditingController(text: _draft['text'] as String? ?? '');
  late final _contact = TextEditingController(text: _draft['contact'] as String? ?? '');
  late final Map<String, String> _details = BugReport.details();
  List<String> get _shots => _Pictures.shots;
  bool _sending = false;
  String _status = '';
  bool _offerEmail = false;

  @override
  void dispose() {
    _text.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _keep() => Store.I.putJson(BugReport.draftKey, {'text': _text.text, 'contact': _contact.text});

  Future<void> _pick() async {
    final files = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: 'Images', mimeTypes: ['image/*'], extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'])]);
    for (final f in files.take(_maxShots - _shots.length)) {
      final s = await compute(BugReport.pictureJpeg, await f.readAsBytes());
      if (s != null) {
        _shots.add(s);
      } else {
        AppNav.say("Couldn't add that picture.");
      }
    }
    if (mounted) setState(() {});
  }

  /// Off to the app to find the page to take; what's typed is kept (_keep).
  void _screenshot() {
    _keep();
    AppNav.shooting.value = true;
    AppNav.navigatorKey.currentState?.popUntil((r) => r.isFirst);
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 5) return setState(() => _status = 'Please say what went wrong first.');
    setState(() {
      _sending = true;
      _status = 'Sending…';
      _offerEmail = false;
    });
    try {
      final r = await Api.post('/api/bug-report', {..._details, 'text': text, 'contact': _contact.text.trim(), 'website': '', 'images': _shots, 'full': _Pictures.full.toList()});
      final id = r?['id'] is String ? r!['id'] as String : null;
      _text.clear();
      _contact.clear();
      _Pictures.clear();
      Store.I.remove(BugReport.draftKey);
      _status = id != null ? 'Sent as report $id. Thank you! Augy will look into it.' : 'Sent. Thank you! Augy will look into it.';
    } on ApiError catch (e) {
      if (e.status == 400 || e.status == 413 || e.status == 429) {
        _status = e.message.isNotEmpty ? e.message : "Couldn't send it right now.";
      } else {
        _status = e.status == 503 ? "Bug reports can't be sent from the app yet." : "Couldn't send it right now.";
        _offerEmail = true;
      }
    } on SocketException {
      _status = "You're offline. It's kept here: send it once you're back online.";
    } catch (_) {
      _status = "Couldn't send it right now.";
      _offerEmail = true;
    }
    if (mounted) setState(() => _sending = false);
  }

  void _emailIt() {
    final body = '${_text.text.trim()}\n\n${BugReport.detailsText(_details)}';
    launchUrl(Uri.parse('mailto:$_email?subject=${Uri.encodeComponent('uwuFix bug report')}&body=${Uri.encodeComponent(body)}')).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final note = TextStyle(color: fx.muted, fontSize: 13);
    final full = _shots.length >= _maxShots;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a bug')),
      body: ListView(padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 32), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const ValueKey('bug.text'),
                controller: _text,
                minLines: 4,
                maxLines: 10,
                maxLength: 2000,
                onChanged: (_) => _keep(),
                decoration: const InputDecoration(labelText: 'What went wrong?', hintText: 'What you did, what happened, and what you expected', alignLabelWithHint: true),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('bug.contact'),
                controller: _contact,
                maxLength: 200,
                onChanged: (_) => _keep(),
                decoration: const InputDecoration(labelText: 'How to reach you (optional)', hintText: 'Telegram @name or email, for an answer'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text('Pictures (optional)', style: TextStyle(color: fx.muted, fontSize: 14)),
              ),
              if (_shots.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (i, s) in _shots.indexed)
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(base64Decode(s.split(',').last), width: 90, height: 140, fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: 'Picture ${i + 1}'),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remove picture ${i + 1}',
                            onPressed: () => setState(() => _Pictures.removeAt(i)),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ]),
                  ]),
                ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: full ? null : _pick, icon: const Icon(Icons.image_outlined), label: const Text('Add pictures')),
                OutlinedButton.icon(key: const ValueKey('bug.screenshot'), onPressed: full ? null : _screenshot, icon: const Icon(Icons.screenshot_outlined), label: const Text('Screenshot a page')),
              ]),
              const SizedBox(height: 8),
              Text('Up to 3. Screenshot a page takes you to the app: go to the page you want, then tap Screenshot this page. It takes the whole page, top to bottom, and brings you back here.',
                  style: note),
              const SizedBox(height: 12),
              Text('Sent with it, to help find the bug: ${BugReport.detailsText(_details)}.', style: note),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(key: const ValueKey('bug.send'), onPressed: _sending ? null : _send, icon: const Icon(Icons.send), label: const Text('Send')),
              ),
              if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_status, key: const ValueKey('bug.status'))),
              if (_offerEmail) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _emailIt, child: const Text('Email it instead.'))),
            ]),
          ),
        ),
      ]),
    );
  }
}
