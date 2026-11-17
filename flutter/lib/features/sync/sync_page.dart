// Share history: your history between two devices, directly, over STUN-only WebRTC (lib/sync/
// peer.dart, docs/STUN-p2p-spec.md), as the site's js/sync.js does it, message for message, so the
// app pairs with the site, another phone or a computer:
//
//   guest -> host   hello { v, name }, add { items }, took { n }, ping, bye
//   host -> guest   state { v, rev, name, items }, beat { rev }, added { n }, refused
//
// One device shows a code (the host), the other types it, follows its link or scans its QR code
// (the guest). The guest sees the host's history and can Add theirs to mine, or Send mine to them,
// which the host is asked about first. Merging is lib/data/history.dart's, the same as the site's.
//
// Kept: uwufix.sync.hostCode and uwufix.sync.lastCode, as the site keeps them.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/resolve.dart';
import '../../app/actions.dart';
import '../../app/nav.dart';
import '../../data/history.dart';
import '../../data/store.dart';
import '../../sync/peer.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../tour/tour.dart';

const _hostKey = 'uwufix.sync.hostCode';
const _lastKey = 'uwufix.sync.lastCode';
const _maxItems = 200;
const _sameNetwork =
    'Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen.';

/// The name this device goes by when it pairs.
String deviceName() {
  if (kIsWeb) {
    return 'uwuFix';
  }
  if (Platform.isAndroid) {
    return 'uwuFix for Android';
  }
  if (Platform.isWindows) {
    return 'uwuFix for Windows';
  }
  if (Platform.isMacOS) {
    return 'uwuFix for Mac';
  }
  if (Platform.isLinux) {
    return 'uwuFix for Linux';
  }
  return 'uwuFix';
}

/// "1 link", "3 links".
String _plural(int count, String singular, String plural) {
  if (count == 1) {
    return '$count $singular';
  }
  return '$count $plural';
}

/// [value] if it's text, cut to at most [maxLength] characters; otherwise empty.
String _shortText(Object? value, int maxLength) {
  if (value is! String) {
    return '';
  }
  if (value.length > maxLength) {
    return value.substring(0, maxLength);
  }
  return value;
}

/// [name], or [fallback] when it's empty.
String _nameOr(String name, String fallback) {
  if (name.isEmpty) {
    return fallback;
  }
  return name;
}

/// This device's history, newest first, as many as are shared, ready to send.
List<Map<String, Object?>> _myItems() {
  final items = <Map<String, Object?>>[];
  for (final entry in History.load().take(_maxItems)) {
    items.add(entry.toJson());
  }
  return items;
}

/// Share history's connection, as the host (showing a code) or the guest (entering one): its
/// status, what to say about it, and what the other device has sent.
class SyncController extends ChangeNotifier with WidgetsBindingObserver {
  SyncController._();
  static final SyncController I = SyncController._();

  String mode = 'host';
  String status = 'idle';
  String? message; // the status line
  String messageKind = '';
  String? note;
  String code = '';
  bool stale = false;

  // Host
  PeerHost? _host;
  String guestName = '';
  int _revision = 0;
  bool _retriedTaken = false;
  ({List<Object?> items, int added})? approval;

  // Guest
  PeerGuest? _guest;
  String _guestCode = '';
  List<Object?>? theirs;
  String theirName = '';

  int _lastHeard = 0;
  Timer? _heartbeatTimer;
  StreamSubscription<String>? _historySubscription;
  bool _active = false;

  String get link {
    return '$site/join?id=$code';
  }

  /// For screenshots: a code on show, as if it were waiting for the other device, with no network.
  @visibleForTesting
  void preview(String showing) {
    mode = 'host';
    code = showing;
    status = 'waiting';
    message = 'On the other device, open uwuFix, then History, Share, Enter a code, and type this code. Or scan the QR code, or open the link.';
    messageKind = '';
    notifyListeners();
  }

  void _say(String? text, [String kind = '']) {
    message = text;
    messageKind = kind;
    notifyListeners();
  }

  /// The page opened: showing a code, or entering [joinCode].
  void open({String? joinCode}) {
    if (!_active) {
      _active = true;
      WidgetsBinding.instance.addObserver(this);
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _tick();
      });
      _historySubscription = Store.I.changes.where((key) {
        return key == historyKey;
      }).listen((_) {
        _historyChanged();
      });
    }
    if (joinCode != null) {
      setMode('guest');
      join(joinCode);
      return;
    }
    setMode(mode);
  }

  /// The page closed: sharing ends.
  void close() {
    if (!_active) {
      return;
    }
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _historySubscription?.cancel();
    _stopHosting();
    _leaveGuest(quiet: true);
    note = null;
  }

  void setMode(String next) {
    mode = next;
    note = null;
    if (next == 'host') {
      _leaveGuest(quiet: true);
      _startHosting();
    } else {
      _stopHosting();
      _say(null);
    }
    notifyListeners();
  }

  // ---------- host ----------

  Map<String, Object?> _snapshot() {
    return {'type': 'state', 'v': P2P.protocolVersion, 'rev': _revision, 'name': deviceName(), 'items': _myItems()};
  }

  /// Starts showing a code (the one kept from last time, if it's still good) and waits for a guest.
  Future<void> _startHosting() async {
    if (_host != null) {
      return;
    }
    String stored = '';
    final keptCode = Store.I.get(_hostKey);
    if (keptCode != null) {
      stored = keptCode;
    }
    if (P2P.isValid(stored)) {
      code = P2P.normalise(stored);
    } else {
      code = P2P.generateCode();
    }
    Store.I.put(_hostKey, code);
    final host = PeerHost(
      (newStatus, {message, taken = false}) {
        _onHostStatus(newStatus, message: message, taken: taken);
      },
      (incoming) {
        _onHostMessage(incoming);
      },
    );
    _host = host;
    status = 'connecting';
    _say('Getting a code ready…');
    await host.start(code);
  }

  /// The host's connection changed: says so, and sends the history once a guest is connected.
  void _onHostStatus(String newStatus, {String? message, bool taken = false}) {
    if (_host == null) {
      return;
    }
    if (taken && !_retriedTaken) {
      _retriedTaken = true;
      _restartWithFreshCode();
      return;
    }
    if (newStatus == 'waiting') {
      _retriedTaken = false;
    }
    status = newStatus;
    if (newStatus != 'connected') {
      guestName = '';
      approval = null;
    } else {
      _lastHeard = DateTime.now().millisecondsSinceEpoch;
      _host?.send(_snapshot());
    }
    switch (newStatus) {
      case 'connecting':
        _say('Getting a code ready…');
      case 'waiting':
        _say('On the other device, open uwuFix, then History, Share, Enter a code, and type this code. Or scan the QR code, or open the link.');
      case 'connected':
        _say('Connected to ${_nameOr(guestName, 'the other device')}. It can see your history, and add yours to its own.', 'ok');
      case 'error':
        _say(message, 'error');
    }
  }

  /// A message from the guest: its hello, history it offers, how many of ours it took, or bye.
  void _onHostMessage(Map<String, dynamic> incoming) {
    _lastHeard = DateTime.now().millisecondsSinceEpoch;
    switch (incoming['type']) {
      case 'hello':
        guestName = _shortText(incoming['name'], 60);
        if (guestName.isEmpty) {
          guestName = 'the other device';
        }
        _host?.send(_snapshot());
        _onHostStatus('connected');
      case 'add':
        final items = incoming['items'];
        if (items is! List) {
          return;
        }
        final list = items.take(_maxItems).toList();
        final preview = mergeHistory(History.load(), list);
        if (preview.added == 0) {
          _host?.send({'type': 'added', 'n': 0});
          note = '${_nameOr(guestName, 'The other device')} sent its history: nothing new.';
          notifyListeners();
          return;
        }
        approval = (items: list, added: preview.added);
        notifyListeners();
      case 'took':
        final count = incoming['n'];
        if (count is num) {
          note = '${_nameOr(guestName, 'The other device')} added ${count.round().clamp(0, _maxItems)} of your links to its history.';
          notifyListeners();
        }
      case 'bye':
        _restartWithFreshCode();
        note = '${_nameOr(guestName, 'The other device')} left. Here’s a new code for next time.';
        notifyListeners();
      default:
        break; // ping, and anything unknown
    }
  }

  /// The host's answer to the guest's offer: [accepted] adds its links to the history.
  void approve(bool accepted) {
    final offer = approval;
    approval = null;
    if (offer == null || _host == null) {
      return;
    }
    if (!accepted) {
      _host!.send({'type': 'refused'});
      notifyListeners();
      return;
    }
    final merged = mergeHistory(History.load(), offer.items);
    History.save(merged.items);
    _host!.send({'type': 'added', 'n': merged.added});
    note = 'Added ${_plural(merged.added, 'link', 'links')} from ${_nameOr(guestName, 'the other device')}.';
    notifyListeners();
  }

  void _stopHosting() {
    final host = _host;
    _host = null;
    host?.close();
    approval = null;
  }

  Future<void> _restartWithFreshCode() async {
    _stopHosting();
    Store.I.remove(_hostKey);
    if (mode == 'host' && _active) {
      await _startHosting();
    }
  }

  void newCode() {
    note = null;
    _restartWithFreshCode();
  }

  // ---------- guest ----------

  /// Connects to the device showing [input] as its code.
  Future<void> join(String input) async {
    final joinCode = P2P.normalise(input);
    if (!P2P.isValid(joinCode)) {
      _say('A code is ${P2P.codeLength} letters and numbers.', 'error');
      return;
    }
    _leaveGuest(quiet: true);
    _guestCode = joinCode;
    theirs = null;
    note = null;
    final guest = PeerGuest(
      (newStatus, {message, taken = false}) {
        _onGuestStatus(newStatus, message);
      },
      _onGuestMessage,
      name: deviceName(),
    );
    _guest = guest;
    status = 'connecting';
    _say('Connecting…');
    await guest.connect(joinCode);
    if (_guest == guest && status != 'error') {
      Store.I.put(_lastKey, joinCode);
    }
  }

  /// The guest's connection changed: says so.
  void _onGuestStatus(String newStatus, String? message) {
    if (_guest == null) {
      return;
    }
    status = newStatus;
    if (newStatus == 'connected') {
      _lastHeard = DateTime.now().millisecondsSinceEpoch;
    }
    if (newStatus != 'connected') {
      theirs = null;
      stale = false;
    }
    switch (newStatus) {
      case 'connecting':
        _say('Connecting…');
      case 'connected':
        _say('Connected. Getting their history…', 'ok');
      case 'dropped':
        _say('The connection dropped.');
      case 'unreachable':
        _say(_sameNetwork, 'error');
      case 'error':
        if (message?.startsWith('Nobody') == true) {
          Store.I.remove(_lastKey);
        }
        _say(message, 'error');
    }
  }

  /// A message from the host: its history, how many of ours it added, or that it said not now.
  void _onGuestMessage(Map<String, dynamic> incoming) {
    _lastHeard = DateTime.now().millisecondsSinceEpoch;
    stale = false;
    switch (incoming['type']) {
      case 'state':
        final items = incoming['items'];
        if (items is! List) {
          return;
        }
        theirs = items.take(_maxItems).toList();
        theirName = _shortText(incoming['name'], 60);
        _say('Connected to ${_nameOr(theirName, 'the other device')}.', 'ok');
      case 'added':
        final count = incoming['n'];
        if (count is num && count > 0) {
          note = '${_nameOr(theirName, 'The other device')} added ${count.round()} of your links.';
        } else {
          note = 'They had them all already.';
        }
        notifyListeners();
      case 'refused':
        note = '${_nameOr(theirName, 'The other device')} said not now.';
        notifyListeners();
      default:
        notifyListeners(); // beat, and anything unknown
    }
  }

  /// How many of theirs are new here, and of mine new there.
  ({int newHere, int newThere}) get counts {
    List<Object?> theirItems = const [];
    final received = theirs;
    if (received != null) {
      theirItems = received;
    }
    final mine = History.load();
    final newHere = mergeHistory(mine, theirItems).added;
    final theirsClean = <HistoryEntry>[];
    for (final item in theirItems) {
      final entry = sanitizeEntry(item);
      if (entry != null) {
        theirsClean.add(entry);
      }
    }
    final mineAsJson = <Object?>[];
    for (final entry in mine) {
      mineAsJson.add(entry.toJson());
    }
    final newThere = mergeHistory(theirsClean, mineAsJson).added;
    return (newHere: newHere, newThere: newThere);
  }

  /// Adds their history to mine.
  void take() {
    final theirItems = theirs;
    if (theirItems == null) {
      return;
    }
    final merged = mergeHistory(History.load(), theirItems);
    History.save(merged.items);
    _guest?.send({'type': 'took', 'n': merged.added});
    note = 'Added ${_plural(merged.added, 'link', 'links')} to your history.';
    notifyListeners();
  }

  /// Offers my history to them; they're asked before it's added.
  void send() {
    _guest?.send({'type': 'add', 'items': _myItems()});
    note = 'Sent. ${_nameOr(theirName, 'The other device')} is asked before they’re added.';
    notifyListeners();
  }

  void leave() {
    _leaveGuest();
  }

  /// Ends the guest's connection; unless [quiet], also forgets the code and clears what's said.
  void _leaveGuest({bool quiet = false}) {
    final guest = _guest;
    _guest = null;
    if (guest == null) {
      return;
    }
    if (status == 'connected') {
      guest.leave();
    } else {
      guest.hangUp();
    }
    theirs = null;
    if (!quiet) {
      Store.I.remove(_lastKey);
      status = 'idle';
      note = null;
      _say(null);
    }
  }

  String get lastCode {
    final stored = Store.I.get(_lastKey);
    if (stored == null) {
      return '';
    }
    return stored;
  }

  // ---------- heartbeat and lifecycle ----------

  /// Every second: the host's beat (closing a link gone quiet), the guest's ping and its stale check.
  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_host != null && status == 'connected') {
      _host!.send({'type': 'beat', 'rev': _revision});
      if (now - _lastHeard > 6000) {
        _host!.link?.close();
      }
    }
    if (_guest != null && status == 'connected') {
      _guest!.send({'type': 'ping'});
      final wasStale = stale;
      stale = now - _lastHeard >= 3000;
      if (stale != wasStale) {
        notifyListeners();
      }
    }
  }

  void _historyChanged() {
    _revision++;
    if (_host != null && status == 'connected') {
      _host!.send(_snapshot());
    }
    if (theirs != null) {
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background with a channel that died meanwhile: once more, the same code.
    if (state == AppLifecycleState.resumed && _guest != null && status == 'dropped' && _guestCode.isNotEmpty) {
      join(_guestCode);
    }
  }
}

/// The Share history page: Show a code (host) or Enter a code (guest), and what's happening.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key, this.joinCode, this.embedded = false});
  final String? joinCode;
  final bool embedded;

  /// For screenshots: draw what SyncController.preview set, and start nothing.
  static bool previewOnly = false;

  @override
  State<SyncPage> createState() {
    return _SyncPageState();
  }
}

class _SyncPageState extends State<SyncPage> {
  final _codeField = TextEditingController();
  final _controller = SyncController.I;

  @override
  void initState() {
    super.initState();
    final joinCode = widget.joinCode;
    if (joinCode != null) {
      _codeField.text = P2P.normalise(joinCode);
    } else {
      _codeField.text = _controller.lastCode;
    }
    if (!SyncPage.previewOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.open(joinCode: widget.joinCode);
      });
    }
  }

  @override
  void dispose() {
    if (!SyncPage.previewOnly) {
      _controller.close();
    }
    _codeField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return _buildContent(context);
      },
    );
    if (widget.embedded) {
      return body;
    }
    return Scaffold(appBar: AppBar(title: const Text('Share history')), body: body);
  }

  /// The page's content, drawn again each time the connection changes.
  Widget _buildContent(BuildContext context) {
    final palette = context.fx;
    final controller = _controller;
    // The host's approval, asked once per offer.
    final offer = controller.approval;
    if (offer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ask(offer);
      });
    }
    List<Widget> sideWidgets;
    if (controller.mode == 'host') {
      sideWidgets = _host(context, palette);
    } else {
      sideWidgets = _guest(context, palette);
    }
    Color messageColor;
    if (controller.messageKind == 'error') {
      messageColor = palette.error;
    } else if (controller.messageKind == 'ok') {
      messageColor = palette.ok;
    } else {
      messageColor = palette.muted;
    }
    final message = controller.message;
    final note = controller.note;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TourTarget(
                id: 'sync.tabs',
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'host', label: Text('Show a code'), icon: Icon(Icons.qr_code_2)),
                    ButtonSegment(value: 'guest', label: Text('Enter a code'), icon: Icon(Icons.keyboard_outlined)),
                  ],
                  selected: {controller.mode},
                  onSelectionChanged: (selection) {
                    controller.setMode(selection.first);
                  },
                ),
              ),
              const SizedBox(height: 16),
              ...sideWidgets,
              if (message != null && message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (controller.status == 'connecting') ...[
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(message, style: TextStyle(color: messageColor, fontSize: 14.5, height: 1.4)),
                    ),
                  ]),
                ),
              ],
              if (controller.stale) ...[
                const SizedBox(height: 8),
                Text('The connection looks stale. If nothing changes, check both are still on the same wifi.', style: TextStyle(color: palette.error)),
              ],
              if (note != null) ...[
                const SizedBox(height: 10),
                Semantics(liveRegion: true, child: Text(note, style: TextStyle(color: palette.ok, fontSize: 14.5))),
              ],
              const SizedBox(height: 20),
              TourTarget(
                id: 'sync.note',
                child: Text(
                  'Both devices have to be on the same network: the same wifi, or one on the other’s hotspot. Your history goes straight from one to the other, through no server; pairing tells each device the other’s internet address.',
                  style: TextStyle(color: palette.muted, fontSize: 13.5, height: 1.4),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  bool _asking = false;

  /// Asks the host whether to add the guest's offered links, once per offer.
  Future<void> _ask(({List<Object?> items, int added}) offer) async {
    if (_asking || !mounted) {
      return;
    }
    _asking = true;
    final who = _nameOr(_controller.guestName, 'the other device');
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add their links?'),
          content: Text('Add ${_plural(offer.added, 'link', 'links')} from $who to your history?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Add them'),
            ),
          ],
        );
      },
    );
    _asking = false;
    _controller.approve(accepted == true);
  }

  /// The Show a code side: the code, its QR code and link, and New code.
  List<Widget> _host(BuildContext context, Fx palette) {
    final controller = _controller;
    FontWeight? codeWeight;
    if (!palette.uwu) {
      codeWeight = FontWeight.w700;
    }
    return [
      if (controller.code.isNotEmpty)
        TourTarget(
          id: 'sync.code',
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              SelectableText(controller.code, style: TextStyle(fontSize: 36, letterSpacing: 6, color: palette.ink, fontWeight: codeWeight)),
              const SizedBox(height: 10),
              // Centred, with its white quiet zone, so a phone pointed at the middle finds it.
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: controller.link, size: 168, backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(controller.link, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.brandInk, fontSize: 13))),
                IconButton(
                  tooltip: 'Copy the link',
                  onPressed: () {
                    copyText(controller.link, said: 'Link copied');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ]),
            ]),
          ),
        ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: controller.newCode, icon: const Icon(Icons.refresh), label: const Text('New code')),
      ),
    ];
  }

  /// The Enter a code side: the code field with Join or Leave, and once connected, what each
  /// side has that the other hasn't, with Add theirs to mine and Send mine to them.
  List<Widget> _guest(BuildContext context, Fx palette) {
    final controller = _controller;
    final connected = controller.status == 'connected';
    final busy = controller.status == 'connecting' || connected;

    ValueChanged<String>? onSubmitted;
    if (!busy) {
      onSubmitted = (value) {
        controller.join(value);
      };
    }
    Widget joinOrLeave;
    if (!busy) {
      String joinLabel;
      if (controller.status == 'dropped') {
        joinLabel = 'Reconnect';
      } else {
        joinLabel = 'Join';
      }
      joinOrLeave = FilledButton(
        onPressed: () {
          controller.join(_codeField.text);
        },
        child: Text(joinLabel),
      );
    } else {
      joinOrLeave = OutlinedButton(onPressed: controller.leave, child: const Text('Leave'));
    }

    return [
      TourTarget(
        id: 'sync.join',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('The code on the other device', style: TextStyle(color: palette.muted)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _codeField,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 20, letterSpacing: 4),
                decoration: const InputDecoration(hintText: 'BCD234', isDense: true),
                onChanged: (value) {
                  final normalised = P2P.normalise(value);
                  if (normalised != value) {
                    _codeField.value = TextEditingValue(text: normalised, selection: TextSelection.collapsed(offset: normalised.length));
                  }
                },
                onSubmitted: onSubmitted,
              ),
            ),
            const SizedBox(width: 8),
            joinOrLeave,
          ]),
        ]),
      ),
      if (connected && controller.theirs != null) ...[
        const SizedBox(height: 14),
        Builder(builder: (context) {
          return _buildCounts(palette);
        }),
      ],
    ];
  }

  /// Once connected as the guest: how many links each side has new to the other, and the buttons
  /// to swap them.
  Widget _buildCounts(Fx palette) {
    final controller = _controller;
    final counts = controller.counts;
    VoidCallback? onTake;
    if (counts.newHere != 0) {
      onTake = controller.take;
    }
    VoidCallback? onSend;
    if (counts.newThere != 0) {
      onSend = controller.send;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.brandFill, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Their history has ${_plural(controller.theirs!.length, 'link', 'links')}, ${counts.newHere} new to this device. Yours has ${counts.newThere} new to them.',
          style: TextStyle(color: palette.onBrand, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: onTake, icon: const Icon(Icons.download), label: const Text('Add theirs to mine')),
          OutlinedButton.icon(onPressed: onSend, icon: const Icon(Icons.upload), label: const Text('Send mine to them')),
        ]),
      ]),
    );
  }
}

/// Opening Share history on the Enter a code side, with a code from a link (/join?id=CODE).
void openJoin(String code) {
  AppNav.showPage('sync', {'join': code});
}
