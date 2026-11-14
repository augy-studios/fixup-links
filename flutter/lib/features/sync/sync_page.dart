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

String deviceName() {
  if (kIsWeb) return 'uwuFix';
  if (Platform.isAndroid) return 'uwuFix for Android';
  if (Platform.isWindows) return 'uwuFix for Windows';
  if (Platform.isMacOS) return 'uwuFix for Mac';
  if (Platform.isLinux) return 'uwuFix for Linux';
  return 'uwuFix';
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
String _str(Object? v, int n) => v is String ? (v.length > n ? v.substring(0, n) : v) : '';

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
  int _rev = 0;
  bool _retriedTaken = false;
  ({List<Object?> items, int added})? approval;

  // Guest
  PeerGuest? _guest;
  String _guestCode = '';
  List<Object?>? theirs;
  String theirName = '';

  int _lastHeard = 0;
  Timer? _beat;
  StreamSubscription<String>? _historySub;
  bool _active = false;

  String get link => '$site/join?id=$code';

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
      _beat = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _historySub = Store.I.changes.where((k) => k == historyKey).listen((_) => _historyChanged());
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
    if (!_active) return;
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _beat?.cancel();
    _historySub?.cancel();
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
    final items = History.load().take(_maxItems).map((e) => e.toJson()).toList();
    return {'type': 'state', 'v': P2P.protocolVersion, 'rev': _rev, 'name': deviceName(), 'items': items};
  }

  Future<void> _startHosting() async {
    if (_host != null) return;
    final stored = Store.I.get(_hostKey) ?? '';
    code = P2P.isValid(stored) ? P2P.normalise(stored) : P2P.generateCode();
    Store.I.put(_hostKey, code);
    final h = PeerHost((s, {message, taken = false}) => _onHostStatus(s, message: message, taken: taken), (m) => _onHostMessage(m));
    _host = h;
    status = 'connecting';
    _say('Getting a code ready…');
    await h.start(code);
  }

  void _onHostStatus(String s, {String? message, bool taken = false}) {
    if (_host == null) return;
    if (taken && !_retriedTaken) {
      _retriedTaken = true;
      _restartWithFreshCode();
      return;
    }
    if (s == 'waiting') _retriedTaken = false;
    status = s;
    if (s != 'connected') {
      guestName = '';
      approval = null;
    } else {
      _lastHeard = DateTime.now().millisecondsSinceEpoch;
      _host?.send(_snapshot());
    }
    switch (s) {
      case 'connecting':
        _say('Getting a code ready…');
      case 'waiting':
        _say('On the other device, open uwuFix, then History, Share, Enter a code, and type this code. Or scan the QR code, or open the link.');
      case 'connected':
        _say('Connected to ${guestName.isEmpty ? 'the other device' : guestName}. It can see your history, and add yours to its own.', 'ok');
      case 'error':
        _say(message, 'error');
    }
  }

  void _onHostMessage(Map<String, dynamic> m) {
    _lastHeard = DateTime.now().millisecondsSinceEpoch;
    switch (m['type']) {
      case 'hello':
        guestName = _str(m['name'], 60);
        if (guestName.isEmpty) guestName = 'the other device';
        _host?.send(_snapshot());
        _onHostStatus('connected');
      case 'add':
        final items = m['items'];
        if (items is! List) return;
        final list = items.take(_maxItems).toList();
        final preview = mergeHistory(History.load(), list);
        if (preview.added == 0) {
          _host?.send({'type': 'added', 'n': 0});
          note = '${guestName.isEmpty ? 'The other device' : guestName} sent its history: nothing new.';
          notifyListeners();
          return;
        }
        approval = (items: list, added: preview.added);
        notifyListeners();
      case 'took':
        final n = m['n'];
        if (n is num) {
          note = '${guestName.isEmpty ? 'The other device' : guestName} added ${n.round().clamp(0, _maxItems)} of your links to its history.';
          notifyListeners();
        }
      case 'bye':
        _restartWithFreshCode();
        note = '${guestName.isEmpty ? 'The other device' : guestName} left. Here’s a new code for next time.';
        notifyListeners();
      default:
        break; // ping, and anything unknown
    }
  }

  void approve(bool yes) {
    final a = approval;
    approval = null;
    if (a == null || _host == null) return;
    if (!yes) {
      _host!.send({'type': 'refused'});
      notifyListeners();
      return;
    }
    final merged = mergeHistory(History.load(), a.items);
    History.save(merged.items);
    _host!.send({'type': 'added', 'n': merged.added});
    note = 'Added ${_plural(merged.added, 'link', 'links')} from ${guestName.isEmpty ? 'the other device' : guestName}.';
    notifyListeners();
  }

  void _stopHosting() {
    final h = _host;
    _host = null;
    h?.close();
    approval = null;
  }

  Future<void> _restartWithFreshCode() async {
    _stopHosting();
    Store.I.remove(_hostKey);
    if (mode == 'host' && _active) await _startHosting();
  }

  void newCode() {
    note = null;
    _restartWithFreshCode();
  }

  // ---------- guest ----------

  Future<void> join(String input) async {
    final c = P2P.normalise(input);
    if (!P2P.isValid(c)) {
      _say('A code is ${P2P.codeLength} letters and numbers.', 'error');
      return;
    }
    _leaveGuest(quiet: true);
    _guestCode = c;
    theirs = null;
    note = null;
    final g = PeerGuest((s, {message, taken = false}) => _onGuestStatus(s, message), _onGuestMessage, name: deviceName());
    _guest = g;
    status = 'connecting';
    _say('Connecting…');
    await g.connect(c);
    if (_guest == g && status != 'error') Store.I.put(_lastKey, c);
  }

  void _onGuestStatus(String s, String? message) {
    if (_guest == null) return;
    status = s;
    if (s == 'connected') _lastHeard = DateTime.now().millisecondsSinceEpoch;
    if (s != 'connected') {
      theirs = null;
      stale = false;
    }
    switch (s) {
      case 'connecting':
        _say('Connecting…');
      case 'connected':
        _say('Connected. Getting their history…', 'ok');
      case 'dropped':
        _say('The connection dropped.');
      case 'unreachable':
        _say(_sameNetwork, 'error');
      case 'error':
        if (message?.startsWith('Nobody') == true) Store.I.remove(_lastKey);
        _say(message, 'error');
    }
  }

  void _onGuestMessage(Map<String, dynamic> m) {
    _lastHeard = DateTime.now().millisecondsSinceEpoch;
    stale = false;
    switch (m['type']) {
      case 'state':
        final items = m['items'];
        if (items is! List) return;
        theirs = items.take(_maxItems).toList();
        theirName = _str(m['name'], 60);
        _say('Connected to ${theirName.isEmpty ? 'the other device' : theirName}.', 'ok');
      case 'added':
        final n = m['n'];
        note = n is num && n > 0 ? '${theirName.isEmpty ? 'The other device' : theirName} added ${n.round()} of your links.' : 'They had them all already.';
        notifyListeners();
      case 'refused':
        note = '${theirName.isEmpty ? 'The other device' : theirName} said not now.';
        notifyListeners();
      default:
        notifyListeners(); // beat, and anything unknown
    }
  }

  /// How many of theirs are new here, and of mine new there.
  ({int newHere, int newThere}) get counts {
    final t = theirs ?? const [];
    final mine = History.load();
    final here = mergeHistory(mine, t).added;
    final theirsClean = [for (final e in t) sanitizeEntry(e)].whereType<HistoryEntry>().toList();
    final there = mergeHistory(theirsClean, [for (final e in mine) e.toJson()]).added;
    return (newHere: here, newThere: there);
  }

  void take() {
    final t = theirs;
    if (t == null) return;
    final merged = mergeHistory(History.load(), t);
    History.save(merged.items);
    _guest?.send({'type': 'took', 'n': merged.added});
    note = 'Added ${_plural(merged.added, 'link', 'links')} to your history.';
    notifyListeners();
  }

  void send() {
    _guest?.send({'type': 'add', 'items': History.load().take(_maxItems).map((e) => e.toJson()).toList()});
    note = 'Sent. ${theirName.isEmpty ? 'The other device' : theirName} is asked before they’re added.';
    notifyListeners();
  }

  void leave() {
    _leaveGuest();
  }

  void _leaveGuest({bool quiet = false}) {
    final g = _guest;
    _guest = null;
    if (g == null) return;
    if (status == 'connected') {
      g.leave();
    } else {
      g.hangUp();
    }
    theirs = null;
    if (!quiet) {
      Store.I.remove(_lastKey);
      status = 'idle';
      note = null;
      _say(null);
    }
  }

  String get lastCode => Store.I.get(_lastKey) ?? '';

  // ---------- heartbeat and lifecycle ----------

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_host != null && status == 'connected') {
      _host!.send({'type': 'beat', 'rev': _rev});
      if (now - _lastHeard > 6000) {
        _host!.link?.close();
      }
    }
    if (_guest != null && status == 'connected') {
      _guest!.send({'type': 'ping'});
      final was = stale;
      stale = now - _lastHeard >= 3000;
      if (stale != was) notifyListeners();
    }
  }

  void _historyChanged() {
    _rev++;
    if (_host != null && status == 'connected') _host!.send(_snapshot());
    if (theirs != null) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background with a channel that died meanwhile: once more, the same code.
    if (state == AppLifecycleState.resumed && _guest != null && status == 'dropped' && _guestCode.isNotEmpty) join(_guestCode);
  }
}

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, this.joinCode, this.embedded = false});
  final String? joinCode;
  final bool embedded;

  /// For screenshots: draw what SyncController.preview set, and start nothing.
  static bool previewOnly = false;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _codeField = TextEditingController();
  final c = SyncController.I;

  @override
  void initState() {
    super.initState();
    _codeField.text = widget.joinCode != null ? P2P.normalise(widget.joinCode!) : c.lastCode;
    if (!SyncPage.previewOnly) WidgetsBinding.instance.addPostFrameCallback((_) => c.open(joinCode: widget.joinCode));
  }

  @override
  void dispose() {
    if (!SyncPage.previewOnly) c.close();
    _codeField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final body = ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // The host's approval, asked once per offer.
        if (c.approval != null) {
          final a = c.approval!;
          WidgetsBinding.instance.addPostFrameCallback((_) => _ask(a));
        }
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
                      selected: {c.mode},
                      onSelectionChanged: (s) => c.setMode(s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (c.mode == 'host') ..._host(context, fx) else ..._guest(context, fx),
                  if (c.message != null && c.message!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (c.status == 'connecting') ...[
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(c.message!,
                              style: TextStyle(color: c.messageKind == 'error' ? fx.error : c.messageKind == 'ok' ? fx.ok : fx.muted, fontSize: 14.5, height: 1.4)),
                        ),
                      ]),
                    ),
                  ],
                  if (c.stale) ...[
                    const SizedBox(height: 8),
                    Text('The connection looks stale. If nothing changes, check both are still on the same wifi.', style: TextStyle(color: fx.error)),
                  ],
                  if (c.note != null) ...[
                    const SizedBox(height: 10),
                    Semantics(liveRegion: true, child: Text(c.note!, style: TextStyle(color: fx.ok, fontSize: 14.5))),
                  ],
                  const SizedBox(height: 20),
                  TourTarget(
                    id: 'sync.note',
                    child: Text(
                      'Both devices have to be on the same network: the same wifi, or one on the other’s hotspot. Your history goes straight from one to the other, through no server; pairing tells each device the other’s internet address.',
                      style: TextStyle(color: fx.muted, fontSize: 13.5, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Share history')), body: body);
  }

  bool _asking = false;
  Future<void> _ask(({List<Object?> items, int added}) a) async {
    if (_asking || !mounted) return;
    _asking = true;
    final who = c.guestName.isEmpty ? 'the other device' : c.guestName;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('Add their links?'),
        content: Text('Add ${_plural(a.added, 'link', 'links')} from $who to your history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add them')),
        ],
      ),
    );
    _asking = false;
    c.approve(yes == true);
  }

  List<Widget> _host(BuildContext context, Fx fx) => [
        if (c.code.isNotEmpty)
          TourTarget(
            id: 'sync.code',
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                SelectableText(c.code, style: TextStyle(fontSize: 36, letterSpacing: 6, color: fx.ink, fontWeight: fx.uwu ? null : FontWeight.w700)),
                const SizedBox(height: 10),
                // Centred, with its white quiet zone, so a phone pointed at the middle finds it.
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: c.link, size: 168, backgroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(child: Text(c.link, overflow: TextOverflow.ellipsis, style: TextStyle(color: fx.brandInk, fontSize: 13))),
                  IconButton(tooltip: 'Copy the link', onPressed: () => copyText(c.link, said: 'Link copied'), icon: const Icon(Icons.copy, size: 18)),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: c.newCode, icon: const Icon(Icons.refresh), label: const Text('New code')),
        ),
      ];

  List<Widget> _guest(BuildContext context, Fx fx) {
    final connected = c.status == 'connected';
    final busy = c.status == 'connecting' || connected;
    return [
      TourTarget(
        id: 'sync.join',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('The code on the other device', style: TextStyle(color: fx.muted)),
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
                onChanged: (v) {
                  final n = P2P.normalise(v);
                  if (n != v) {
                    _codeField.value = TextEditingValue(text: n, selection: TextSelection.collapsed(offset: n.length));
                  }
                },
                onSubmitted: busy ? null : (v) => c.join(v),
              ),
            ),
            const SizedBox(width: 8),
            if (!busy)
              FilledButton(onPressed: () => c.join(_codeField.text), child: Text(c.status == 'dropped' ? 'Reconnect' : 'Join'))
            else
              OutlinedButton(onPressed: c.leave, child: const Text('Leave')),
          ]),
        ]),
      ),
      if (connected && c.theirs != null) ...[
        const SizedBox(height: 14),
        Builder(builder: (context) {
          final n = c.counts;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: fx.brandFill, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Their history has ${_plural(c.theirs!.length, 'link', 'links')}, ${n.newHere} new to this device. Yours has ${n.newThere} new to them.',
                style: TextStyle(color: fx.onBrand, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: n.newHere == 0 ? null : c.take, icon: const Icon(Icons.download), label: const Text('Add theirs to mine')),
                OutlinedButton.icon(onPressed: n.newThere == 0 ? null : c.send, icon: const Icon(Icons.upload), label: const Text('Send mine to them')),
              ]),
            ]),
          );
        }),
      ],
    ];
  }
}

/// Opening Share history on the Enter a code side, with a code from a link (/join?id=CODE).
void openJoin(String code) => AppNav.showPage('sync', {'join': code});
