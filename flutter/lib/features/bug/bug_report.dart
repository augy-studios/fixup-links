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
import 'package:image/image.dart' as image_library;
import 'package:url_launcher/url_launcher.dart';

import '../../api/resolve.dart';
import '../../app/nav.dart';
import '../../data/store.dart';
import '../../native/native_bridge.dart';
import '../../theme/theme.dart';
import '../../widgets/glass.dart';

const _email = 'augy@augystudios.com';
const _maxPictures = 3;
const _pageNames = {'home': 'Home', 'history': 'History', 'sync': 'Share history', 'look': 'Look'};

/// Opens it, from the Edge Tray, the desktop's rail, command bar and Help menu.
void openBugReport() {
  AppNav.push(const BugReport(), name: 'bug');
}

/// A report's pictures, which outlive its screen while you go and find a page to take.
class _Pictures {
  _Pictures._();
  static final List<String> shots = []; // JPEG data URLs
  static final Set<int> wholePages = {}; // whole pages among them: each also goes as a file, at its full size

  static void clear() {
    shots.clear();
    wholePages.clear();
  }

  /// Removes the picture at [index], and moves the whole-page marks after it down by one.
  static void removeAt(int index) {
    shots.removeAt(index);
    final moved = <int>{};
    for (final pageIndex in wholePages) {
      if (pageIndex == index) {
        continue;
      }
      if (pageIndex > index) {
        moved.add(pageIndex - 1);
      } else {
        moved.add(pageIndex);
      }
    }
    wholePages.clear();
    wholePages.addAll(moved);
  }
}

/// The Report a bug page: what went wrong, how to reach you, pictures, and the details sent with it.
class BugReport extends StatefulWidget {
  const BugReport({super.key});

  static const draftKey = 'uwufix.bugDraft';

  /// The whole page, as a JPEG data URL that Telegram takes as a photo: no wider than pageWidth,
  /// no taller than pageRatio times its width, with its sides adding up to at most pageSum, and
  /// about 900 KB, rougher and then smaller till it is.
  static const pageWidth = 1080;
  static const pageRatio = 20;
  static const pageSum = 9998;

  /// See [pageWidth]: the whole page's picture, shrunk and compressed till Telegram takes it.
  static String? pageJpeg(Uint8List bytes) {
    final image = image_library.decodeImage(bytes);
    if (image == null) {
      return null;
    }
    final width = image.width;
    final height = math.min(image.height, width * pageRatio);
    var scale = math.min(1.0, math.min(pageWidth / width, pageSum / (width + height)));
    image_library.Image page;
    if (height == image.height) {
      page = image;
    } else {
      page = image_library.copyCrop(image, x: 0, y: 0, width: width, height: height);
    }
    for (var tries = 0; tries < 8; tries++) {
      // The height from the rounded-down width, so it stays within pageRatio.
      final scaledWidth = math.max(1, (width * scale).floor());
      final scaledHeight = math.max(1, math.min((height * scale).floor(), scaledWidth * pageRatio));
      image_library.Image resized;
      if (scale >= 1) {
        resized = page;
      } else {
        resized = image_library.copyResize(page, width: scaledWidth, height: scaledHeight);
      }
      int quality;
      if (tries < 2) {
        quality = 80;
      } else {
        quality = 68;
      }
      final encoded = image_library.encodeJpg(resized, quality: quality);
      if (encoded.length <= 900 * 1024 || tries == 7) {
        return 'data:image/jpeg;base64,${base64Encode(encoded)}';
      }
      if (tries >= 1) {
        scale *= 0.82;
      }
    }
    return null;
  }

  /// A picture as a JPEG data URL, at most 1600 px a side and about 900 KB.
  static String? pictureJpeg(Uint8List bytes) {
    var image = image_library.decodeImage(bytes);
    if (image == null) {
      return null;
    }
    final side = math.max(image.width, image.height);
    if (side > 1600) {
      image = image_library.copyResize(image, width: (image.width * 1600 / side).round());
    }
    for (final quality in [80, 65, 50, 35]) {
      final encoded = image_library.encodeJpg(image, quality: quality);
      if (encoded.length <= 900 * 1024 || quality == 35) {
        return 'data:image/jpeg;base64,${base64Encode(encoded)}';
      }
    }
    return null;
  }

  /// What's sent with it, to help find the bug.
  static Map<String, String> details() {
    final info = Native.info;
    final String device;
    if (onDesktop) {
      String systemName;
      final rawSystem = info?['os'];
      if (rawSystem != null) {
        systemName = '$rawSystem';
      } else {
        systemName = Platform.operatingSystem;
      }
      String system;
      switch (systemName) {
        case 'windows':
          system = 'Windows';
        case 'macos':
          system = 'macOS';
        case 'linux':
          system = 'Linux';
        default:
          system = systemName;
      }
      String systemVersion = '';
      final rawSystemVersion = info?['osVersion'];
      if (rawSystemVersion != null) {
        systemVersion = '$rawSystemVersion';
      }
      device = ['$system $systemVersion'.trim(), 'Flutter'].join(' · ');
    } else {
      Object? release;
      final directRelease = info?['release'];
      if (directRelease != null) {
        release = directRelease;
      } else {
        release = info?['android'];
      }
      final parts = <String>[];
      if (release == null) {
        parts.add('Android');
      } else {
        parts.add('Android $release');
      }
      if (info?['model'] != null) {
        parts.add('${info!['model']}');
      }
      parts.add('Flutter');
      device = parts.join(' · ');
    }
    String version = '';
    final nativeVersion = Native.version;
    if (nativeVersion != null) {
      version = nativeVersion;
    }
    String platform;
    if (onDesktop) {
      platform = 'desktop';
    } else {
      platform = 'android';
    }
    final pageId = AppNav.page.value;
    String pageName = pageId;
    final knownName = _pageNames[pageId];
    if (knownName != null) {
      pageName = knownName;
    }
    return {
      'version': version,
      'platform': platform,
      'device': device,
      'page': pageName,
      'lang': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    };
  }

  /// The details as one line, for the page and for an email: "Android app · 1.2.0 · ...".
  static String detailsText(Map<String, String> details) {
    String appName;
    if (onDesktop) {
      appName = 'Desktop app';
    } else {
      appName = 'Android app';
    }
    final parts = <String>[];
    for (final part in [appName, details['version'], details['device'], details['page']]) {
      if (part != null && part.isNotEmpty) {
        parts.add(part);
      }
    }
    return parts.join(' · ');
  }

  @override
  State<BugReport> createState() {
    return _BugReportState();
  }
}

/// What floats over the app while you find the page to take.
class ShotBar extends StatefulWidget {
  const ShotBar({super.key});

  @override
  State<ShotBar> createState() {
    return _ShotBarState();
  }
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
  static ScrollableState? _pageScroll(BuildContext startContext) {
    ScrollableState? best;
    var largestArea = 0.0;
    final minimumWidth = MediaQuery.sizeOf(startContext).width / 3;

    // Looks at [element] and everything on show under it, keeping the biggest list found.
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        final box = element.findRenderObject();
        final position = scrollable.position;
        // Not the Edge Tray's column, or anything else down one side.
        if (position.axis == Axis.vertical &&
            box is RenderBox &&
            box.hasSize &&
            box.size.width >= minimumWidth &&
            position.hasContentDimensions &&
            position.maxScrollExtent > 8) {
          final area = box.size.width * box.size.height;
          if (area > largestArea) {
            largestArea = area;
            best = scrollable;
          }
        }
      }
      element.debugVisitOnstageChildren(visit);
    }

    (startContext as Element).debugVisitOnstageChildren(visit);
    return best;
  }

  static const _pixelRatio = 1.5;

  /// What can be drawn in one picture, in pixels.
  static const _tallestPicture = 8000.0;

  /// The page from top to bottom: the screen with its list at the top, then each further
  /// screenful of the list, and the rest of the screen under them.
  static Future<ui.Image?> _wholePage() async {
    final shotContext = AppNav.shotKey.currentContext;
    final boundary = shotContext?.findRenderObject() as RenderRepaintBoundary?;
    if (shotContext == null || boundary == null) {
      return null;
    }
    final scroll = _pageScroll(shotContext);
    if (scroll == null) {
      return boundary.toImage(pixelRatio: _pixelRatio);
    }
    final position = scroll.position;
    final startPixels = position.pixels;
    final box = scroll.context.findRenderObject()! as RenderBox;
    final listBottom = (box.localToGlobal(Offset.zero, ancestor: boundary).dy + box.size.height) * _pixelRatio;
    // Each further screenful, with how much new height it brings.
    final slices = <(ui.Image, double)>[];
    ui.Image firstImage;
    try {
      position.jumpTo(position.minScrollExtent);
      await _settled();
      firstImage = await boundary.toImage(pixelRatio: _pixelRatio);
      var scrolled = position.minScrollExtent;
      var height = firstImage.height.toDouble();
      while (scrolled < position.maxScrollExtent - 0.5 && height < _tallestPicture) {
        final nextOffset = math.min(scrolled + position.viewportDimension, position.maxScrollExtent);
        position.jumpTo(nextOffset);
        await _settled();
        final sliceHeight = (nextOffset - scrolled) * _pixelRatio;
        slices.add((await boundary.toImage(pixelRatio: _pixelRatio), sliceHeight));
        height += sliceHeight;
        scrolled = nextOffset;
      }
    } finally {
      position.jumpTo(startPixels);
    }
    final width = firstImage.width.toDouble();
    var total = firstImage.height.toDouble();
    for (final slice in slices) {
      total += slice.$2;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    canvas.drawImageRect(firstImage, Rect.fromLTWH(0, 0, width, listBottom), Rect.fromLTWH(0, 0, width, listBottom), paint);
    var drawnTo = listBottom;
    for (final (image, sliceHeight) in slices) {
      canvas.drawImageRect(
          image, Rect.fromLTWH(0, listBottom - sliceHeight, width, sliceHeight), Rect.fromLTWH(0, drawnTo, width, sliceHeight), paint);
      drawnTo += sliceHeight;
    }
    final belowList = firstImage.height - listBottom;
    if (belowList > 0) {
      canvas.drawImageRect(firstImage, Rect.fromLTWH(0, listBottom, width, belowList), Rect.fromLTWH(0, drawnTo, width, belowList), paint);
    }
    final wholePage = await recorder.endRecording().toImage(width.round(), total.round());
    firstImage.dispose();
    for (final (image, _) in slices) {
      image.dispose();
    }
    return wholePage;
  }

  void _back() {
    AppNav.shooting.value = false;
    openBugReport();
  }

  /// Takes the whole page, adds it to the report's pictures, and goes back to the report.
  Future<void> _take() async {
    setState(() {
      _busy = true;
    });
    try {
      final palette = context.fx;
      var shot = await _wholePage();
      if (shot != null && palette.glass != null) {
        shot = await flattenShot(shot, palette.bg);
      }
      final png = await shot?.toByteData(format: ui.ImageByteFormat.png);
      shot?.dispose();
      String? jpeg;
      if (png != null) {
        jpeg = await compute(BugReport.pageJpeg, png.buffer.asUint8List());
      }
      if (jpeg == null) {
        throw StateError('no picture');
      }
      _Pictures.shots.add(jpeg);
      _Pictures.wholePages.add(_Pictures.shots.length - 1);
    } catch (_) {
      AppNav.say("Couldn't take a screenshot here. Take one with your device and add it instead.");
    }
    if (mounted) {
      _busy = false;
    }
    _back();
  }

  @override
  Widget build(BuildContext context) {
    VoidCallback? onTake;
    VoidCallback? onCancel;
    Widget icon;
    String label;
    if (_busy) {
      icon = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
      label = 'Taking a screenshot…';
    } else {
      onTake = _take;
      onCancel = _back;
      icon = const Icon(Icons.screenshot_outlined);
      label = 'Screenshot this page';
    }
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
                  onPressed: onTake,
                  icon: icon,
                  label: Text(label),
                ),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.small(
                heroTag: null,
                onPressed: onCancel,
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
  late final _textController = TextEditingController(text: _draftField('text'));
  late final _contactController = TextEditingController(text: _draftField('contact'));
  late final Map<String, String> _details = BugReport.details();

  List<String> get _shots {
    return _Pictures.shots;
  }

  bool _sending = false;
  String _status = '';
  bool _offerEmail = false;

  /// A field of the kept draft, or empty if there's none.
  String _draftField(String key) {
    final value = _draft[key] as String?;
    if (value == null) {
      return '';
    }
    return value;
  }

  @override
  void dispose() {
    _textController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  /// Keeps what's typed, so it's still there next time.
  void _keepDraft() {
    Store.I.putJson(BugReport.draftKey, {'text': _textController.text, 'contact': _contactController.text});
  }

  /// Adds pictures from the device, as many as there's room for.
  Future<void> _pickPictures() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', mimeTypes: ['image/*'], extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'])
    ]);
    for (final file in files.take(_maxPictures - _shots.length)) {
      final picture = await compute(BugReport.pictureJpeg, await file.readAsBytes());
      if (picture != null) {
        _shots.add(picture);
      } else {
        AppNav.say("Couldn't add that picture.");
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Off to the app to find the page to take; what's typed is kept (_keepDraft).
  void _screenshot() {
    _keepDraft();
    AppNav.shooting.value = true;
    AppNav.navigatorKey.currentState?.popUntil((route) {
      return route.isFirst;
    });
  }

  /// Sends the report to the site, and says how it went.
  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.length < 5) {
      setState(() {
        _status = 'Please say what went wrong first.';
      });
      return;
    }
    setState(() {
      _sending = true;
      _status = 'Sending…';
      _offerEmail = false;
    });
    try {
      final response = await Api.post('/api/bug-report', {
        ..._details,
        'text': text,
        'contact': _contactController.text.trim(),
        'website': '',
        'images': _shots,
        'full': _Pictures.wholePages.toList(),
      });
      String? id;
      if (response?['id'] is String) {
        id = response!['id'] as String;
      }
      _textController.clear();
      _contactController.clear();
      _Pictures.clear();
      Store.I.remove(BugReport.draftKey);
      if (id != null) {
        _status = 'Sent as report $id. Thank you! Augy will look into it.';
      } else {
        _status = 'Sent. Thank you! Augy will look into it.';
      }
    } on ApiError catch (error) {
      if (error.status == 400 || error.status == 413 || error.status == 429) {
        if (error.message.isNotEmpty) {
          _status = error.message;
        } else {
          _status = "Couldn't send it right now.";
        }
      } else {
        if (error.status == 503) {
          _status = "Bug reports can't be sent from the app yet.";
        } else {
          _status = "Couldn't send it right now.";
        }
        _offerEmail = true;
      }
    } on SocketException {
      _status = "You're offline. It's kept here: send it once you're back online.";
    } catch (_) {
      _status = "Couldn't send it right now.";
      _offerEmail = true;
    }
    if (mounted) {
      setState(() {
        _sending = false;
      });
    }
  }

  /// Opens an email to Augy with the report in it, for when the site can't take it.
  void _emailIt() {
    final body = '${_textController.text.trim()}\n\n${BugReport.detailsText(_details)}';
    launchUrl(Uri.parse('mailto:$_email?subject=${Uri.encodeComponent('uwuFix bug report')}&body=${Uri.encodeComponent(body)}'))
        .catchError((_) {
      return false;
    });
  }

  /// One picture's thumbnail, with a button to remove it.
  Widget _buildThumbnail(int index, String picture) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(base64Decode(picture.split(',').last),
            width: 90, height: 140, fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: 'Picture ${index + 1}'),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove picture ${index + 1}',
          onPressed: () {
            setState(() {
              _Pictures.removeAt(index);
            });
          },
          icon: const Icon(Icons.close, size: 16),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    final noteStyle = TextStyle(color: palette.muted, fontSize: 13);
    final hasAllPictures = _shots.length >= _maxPictures;
    VoidCallback? onPickPictures;
    VoidCallback? onScreenshot;
    if (!hasAllPictures) {
      onPickPictures = _pickPictures;
      onScreenshot = _screenshot;
    }
    VoidCallback? onSend;
    if (!_sending) {
      onSend = _send;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Report a bug')),
      body: ListView(padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 32), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const ValueKey('bug.text'),
                controller: _textController,
                minLines: 4,
                maxLines: 10,
                maxLength: 2000,
                onChanged: (_) {
                  _keepDraft();
                },
                decoration: const InputDecoration(labelText: 'What went wrong?', hintText: 'What you did, what happened, and what you expected', alignLabelWithHint: true),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('bug.contact'),
                controller: _contactController,
                maxLength: 200,
                onChanged: (_) {
                  _keepDraft();
                },
                decoration: const InputDecoration(labelText: 'How to reach you (optional)', hintText: 'Telegram @name or email, for an answer'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text('Pictures (optional)', style: TextStyle(color: palette.muted, fontSize: 14)),
              ),
              if (_shots.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (index, picture) in _shots.indexed) _buildThumbnail(index, picture),
                  ]),
                ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: onPickPictures, icon: const Icon(Icons.image_outlined), label: const Text('Add pictures')),
                OutlinedButton.icon(key: const ValueKey('bug.screenshot'), onPressed: onScreenshot, icon: const Icon(Icons.screenshot_outlined), label: const Text('Screenshot a page')),
              ]),
              const SizedBox(height: 8),
              Text('Up to 3. Screenshot a page takes you to the app: go to the page you want, then tap Screenshot this page. It takes the whole page, top to bottom, and brings you back here.',
                  style: noteStyle),
              const SizedBox(height: 12),
              Text('Sent with it, to help find the bug: ${BugReport.detailsText(_details)}.', style: noteStyle),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(key: const ValueKey('bug.send'), onPressed: onSend, icon: const Icon(Icons.send), label: const Text('Send')),
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
