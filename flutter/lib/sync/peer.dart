// Host and guest pairing over PeerJS's public broker, STUN only (the site's js/p2p.js, and
// docs/STUN-p2p-spec.md): the same broker, ids, ICE servers, wire and BinaryPack as PeerJS 1.5's,
// so the app shares history with the site on another device and the other way round. As
// sgbus-timings' (lib/sync/peer.dart), from which it's taken.
//
//   The broker  wss://0.peerjs.com/peerjs?key=peerjs&id=…&token=…: OPEN once registered,
//               ID-TAKEN, EXPIRE (the peer asked for isn't there), and OFFER, ANSWER and
//               CANDIDATE between peers, relayed by `dst` and `src`; a HEARTBEAT every 5 s.
//   A link      one WebRTC data channel, made by the guest (its label the connection's id,
//               "dc_…"), each message BinaryPack-packed, and one over 16300 bytes sent as
//               chunks: { __peerData, n, total, data }, put back together on arrival.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'binarypack.dart';

/// The pairing's constants, its codes, and the broker's address.
class P2P {
  P2P._();
  static const prefix = 'uwufix-sync-';
  static const alphabet = 'BCDFGHJKLMNPQRSTVWXYZ23456789';
  static const codeLength = 6;
  static const protocolVersion = 1;
  static const connectTimeout = Duration(seconds: 15);
  static const _brokerHost = '0.peerjs.com';
  static const _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];
  // The largest message sent whole; anything bigger goes as chunks (PeerJS's own limit).
  static const _maximumMessageSize = 16300;

  static String generateCode() {
    final random = math.Random.secure();
    final code = StringBuffer();
    for (var index = 0; index < codeLength; index++) {
      code.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return code.toString();
  }

  static String normalise(String input) {
    final lettersAndDigits = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (lettersAndDigits.length > codeLength) {
      return lettersAndDigits.substring(0, codeLength);
    }
    return lettersAndDigits;
  }

  static bool isValid(String input) {
    final code = normalise(input);
    if (code.length != codeLength) {
      return false;
    }
    for (final character in code.split('')) {
      if (!alphabet.contains(character)) {
        return false;
      }
    }
    return true;
  }

  static String _token() {
    final firstPart = math.Random.secure().nextInt(1 << 32).toRadixString(36);
    final secondPart = math.Random.secure().nextInt(1 << 32).toRadixString(36);
    return firstPart + secondPart;
  }
}

/// What went wrong, as js/p2p.js's describePeerError says it.
String peerError(String type) {
  switch (type) {
    case 'peer-unavailable':
      return 'Nobody is sharing with that code. Check it and try again.';
    case 'unavailable-id':
      return 'That code is already in use. Make a new one.';
    case 'network':
    case 'server-error':
    case 'socket-error':
    case 'socket-closed':
      return 'Cannot reach the pairing service. Everything else still works.';
    default:
      return 'The connection failed.';
  }
}

/// The broker: registering an id, relaying offers, answers and candidates.
class _Broker {
  _Broker(this.id, this.onMessage, this.onClosed);
  final String id;
  final void Function(Map<String, dynamic> message) onMessage;
  final void Function() onClosed;
  WebSocket? _socket;
  Timer? _heartbeat;
  final _opened = Completer<void>();

  /// Opens the broker's socket and registers [id]: done once the broker says OPEN, failing with
  /// 'unavailable-id', 'server-error' or 'socket-closed'. Sends a heartbeat every 5 seconds.
  Future<void> connect() async {
    final url = 'wss://${P2P._brokerHost}:443/peerjs?key=peerjs&id=${Uri.encodeComponent(id)}&token=${P2P._token()}&version=1.5.4';
    _socket = await WebSocket.connect(url).timeout(const Duration(seconds: 15));
    _socket!.listen((raw) {
      Map<String, dynamic> message;
      try {
        message = Map<String, dynamic>.from(jsonDecode('$raw') as Map);
      } catch (_) {
        return;
      }
      if (message['type'] == 'OPEN' && !_opened.isCompleted) {
        _opened.complete();
      }
      if (message['type'] == 'ID-TAKEN' && !_opened.isCompleted) {
        _opened.completeError('unavailable-id');
      }
      if (message['type'] == 'ERROR' && !_opened.isCompleted) {
        _opened.completeError('server-error');
      }
      onMessage(message);
    }, onDone: () {
      _heartbeat?.cancel();
      if (!_opened.isCompleted) {
        _opened.completeError('socket-closed');
      }
      onClosed();
    }, onError: (_) {});
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      send({'type': 'HEARTBEAT'});
    });
    return _opened.future;
  }

  void send(Map<String, Object?> message) {
    try {
      _socket?.add(jsonEncode(message));
    } catch (_) {}
  }

  void close() {
    _heartbeat?.cancel();
    _socket?.close();
    _socket = null;
  }

  /// A random id from the broker, for a guest.
  static Future<String> newId() async {
    final cacheBuster = '${DateTime.now().millisecondsSinceEpoch}${math.Random().nextDouble()}';
    final response = await http.get(Uri.parse('https://${P2P._brokerHost}:443/peerjs/id?ts=$cacheBuster')).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw 'server-error';
    }
    return response.body.trim();
  }
}

/// One data channel to the other device.
class PeerLink {
  PeerLink._(this.peer, this.connectionId, this.peerConnection);
  final String peer;
  final String connectionId;
  final RTCPeerConnection peerConnection;
  RTCDataChannel? _dataChannel;
  bool open = false;
  // Candidates that came before the remote description, added once it's set.
  final List<RTCIceCandidate> _earlyCandidates = [];
  bool _remoteSet = false;
  final Map<int, List<Uint8List?>> _chunks = {};
  int _chunkId = 0;

  void Function()? onOpen;
  void Function(Map<String, dynamic> message)? onMessage;
  void Function()? onClose;

  void _bind(RTCDataChannel dataChannel) {
    _dataChannel = dataChannel;
    dataChannel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen && !open) {
        open = true;
        onOpen?.call();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _markClosed();
      }
    };
    dataChannel.onMessage = (message) {
      if (message.isBinary) {
        _receive(message.binary);
      } else {
        _receive(Uint8List.fromList(utf8.encode(message.text)));
      }
    };
  }

  bool _alreadyClosed = false;
  void _markClosed() {
    if (_alreadyClosed) {
      return;
    }
    _alreadyClosed = true;
    open = false;
    onClose?.call();
  }

  /// One message off the channel: a chunk is kept until its message is whole, then that is read;
  /// a message with a type is passed on.
  void _receive(Uint8List bytes) {
    Object? value;
    try {
      value = BinaryPack.unpack(bytes);
    } catch (_) {
      return;
    }
    if (value is Map && value['__peerData'] != null) {
      final id = (value['__peerData'] as num).toInt();
      final total = (value['total'] as num).toInt();
      final chunkNumber = (value['n'] as num).toInt();
      var list = _chunks[id];
      if (list == null) {
        list = List<Uint8List?>.filled(total, null);
        _chunks[id] = list;
      }
      if (chunkNumber < total && value['data'] is Uint8List) {
        list[chunkNumber] = value['data'] as Uint8List;
      }
      var allArrived = true;
      for (final chunk in list) {
        if (chunk == null) {
          allArrived = false;
          break;
        }
      }
      if (allArrived) {
        _chunks.remove(id);
        final whole = BytesBuilder(copy: false);
        for (final chunk in list) {
          whole.add(chunk!);
        }
        _receive(whole.takeBytes());
      }
      return;
    }
    if (value is Map && value['type'] is String) {
      onMessage?.call(Map<String, dynamic>.from(value));
    }
  }

  /// Sends a message, packed, and as numbered chunks when it's too big for one.
  void send(Map<String, Object?> message) {
    final dataChannel = _dataChannel;
    if (dataChannel == null || !open) {
      return;
    }
    final bytes = BinaryPack.pack(message);
    if (bytes.length <= P2P._maximumMessageSize) {
      dataChannel.send(RTCDataChannelMessage.fromBinary(bytes));
      return;
    }
    final id = _chunkId++;
    final total = (bytes.length / P2P._maximumMessageSize).ceil();
    for (var chunkNumber = 0; chunkNumber < total; chunkNumber++) {
      final start = chunkNumber * P2P._maximumMessageSize;
      final end = math.min(bytes.length, (chunkNumber + 1) * P2P._maximumMessageSize);
      final part = Uint8List.sublistView(bytes, start, end);
      dataChannel.send(RTCDataChannelMessage.fromBinary(BinaryPack.pack({'__peerData': id, 'n': chunkNumber, 'total': total, 'data': part})));
    }
  }

  Future<void> _setRemoteDescription(Map sdp) async {
    await peerConnection.setRemoteDescription(RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'));
    _remoteSet = true;
    for (final candidate in _earlyCandidates) {
      await peerConnection.addCandidate(candidate);
    }
    _earlyCandidates.clear();
  }

  Future<void> _addCandidate(Map candidateMap) async {
    final candidate = RTCIceCandidate(candidateMap['candidate'] as String?, candidateMap['sdpMid'] as String?, (candidateMap['sdpMLineIndex'] as num?)?.toInt());
    if (_remoteSet) {
      await peerConnection.addCandidate(candidate);
    } else {
      _earlyCandidates.add(candidate);
    }
  }

  Future<void> close() async {
    try {
      await _dataChannel?.close();
    } catch (_) {}
    try {
      await peerConnection.close();
    } catch (_) {}
    _markClosed();
  }

  static Future<RTCPeerConnection> _createPeerConnection() {
    return createPeerConnection({'iceServers': P2P._iceServers, 'sdpSemantics': 'unified-plan'});
  }
}

/// The status a session reports: connecting, waiting, connected, dropped, unreachable, error.
typedef PeerStatus = void Function(String status, {String? message, bool taken});

/// The host: registers sgbus-sync-CODE and takes one guest at a time.
class PeerHost {
  PeerHost(this.onStatus, this.onMessage);
  final PeerStatus onStatus;
  final void Function(Map<String, dynamic> message) onMessage;
  _Broker? _broker;
  PeerLink? link;
  bool _closed = false;

  Future<void> start(String code) async {
    onStatus('connecting');
    _broker = _Broker(P2P.prefix + code, _onBroker, () {
      if (!_closed && link == null) {
        onStatus('error', message: peerError('socket-closed'));
      }
    });
    try {
      await _broker!.connect();
      onStatus('waiting');
    } catch (error) {
      onStatus('error', message: peerError('$error'), taken: error == 'unavailable-id');
    }
  }

  /// A message from the broker: an offer from a guest (answered, replacing any guest before it),
  /// or a candidate for the current guest's connection.
  Future<void> _onBroker(Map<String, dynamic> message) async {
    var payload = const {};
    final messagePayload = message['payload'] as Map?;
    if (messagePayload != null) {
      payload = messagePayload;
    }
    var source = '';
    if (message['src'] != null) {
      source = '${message['src']}';
    }
    if (message['type'] == 'OFFER') {
      // The newcomer replaces the incumbent.
      await link?.close();
      final peerConnection = await PeerLink._createPeerConnection();
      final newLink = PeerLink._(source, '${payload['connectionId']}', peerConnection);
      link = newLink;
      peerConnection.onIceCandidate = (candidate) {
        _broker?.send({
          'type': 'CANDIDATE',
          'payload': {'candidate': candidate.toMap(), 'type': 'data', 'connectionId': newLink.connectionId},
          'dst': source,
        });
      };
      peerConnection.onDataChannel = newLink._bind;
      newLink.onOpen = () {
        onStatus('connected');
      };
      newLink.onMessage = onMessage;
      newLink.onClose = () {
        if (link == newLink) {
          link = null;
          if (!_closed) {
            onStatus('waiting');
          }
        }
      };
      await newLink._setRemoteDescription(payload['sdp'] as Map);
      final answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      _broker?.send({
        'type': 'ANSWER',
        'payload': {'sdp': {'type': answer.type, 'sdp': answer.sdp}, 'type': 'data', 'connectionId': newLink.connectionId, 'browser': 'flutter'},
        'dst': source,
      });
    } else if (message['type'] == 'CANDIDATE' && link?.connectionId == payload['connectionId']) {
      await link!._addCandidate(payload['candidate'] as Map);
    }
  }

  void send(Map<String, Object?> message) {
    link?.send(message);
  }

  Future<void> close() async {
    _closed = true;
    await link?.close();
    link = null;
    _broker?.close();
  }
}

/// The guest: connects to the device showing CODE.
class PeerGuest {
  PeerGuest(this.onStatus, this.onMessage, {this.name});
  final PeerStatus onStatus;
  /// Said to the host in hello, for it to show who's connected.
  final String? name;
  final void Function(Map<String, dynamic> message) onMessage;
  _Broker? _broker;
  PeerLink? link;
  Timer? _timer;
  bool _everOpened = false;
  bool _done = false;

  /// Gets an id from the broker, then offers a data channel to the host showing [code], giving
  /// up as unreachable if it hasn't opened within P2P.connectTimeout.
  Future<void> connect(String code) async {
    onStatus('connecting');
    try {
      final id = await _Broker.newId();
      _broker = _Broker(id, _onBroker, () {});
      await _broker!.connect();
    } catch (error) {
      if (error is String) {
        onStatus('error', message: peerError(error));
      } else {
        onStatus('error', message: peerError('network'));
      }
      return;
    }
    // Nothing errors when ICE can't find a path; it just keeps trying.
    _timer = Timer(P2P.connectTimeout, () {
      if (_everOpened || _done) {
        return;
      }
      hangUp();
      onStatus('unreachable');
    });
    final peerConnection = await PeerLink._createPeerConnection();
    final connectionId = 'dc_${P2P._token()}';
    final destination = P2P.prefix + code;
    final newLink = PeerLink._(destination, connectionId, peerConnection);
    link = newLink;
    peerConnection.onIceCandidate = (candidate) {
      _broker?.send({
        'type': 'CANDIDATE',
        'payload': {'candidate': candidate.toMap(), 'type': 'data', 'connectionId': connectionId},
        'dst': destination,
      });
    };
    final channelOptions = RTCDataChannelInit();
    channelOptions.ordered = true;
    newLink._bind(await peerConnection.createDataChannel(connectionId, channelOptions));
    newLink.onOpen = () {
      _everOpened = true;
      _timer?.cancel();
      onStatus('connected');
      newLink.send({'type': 'hello', 'v': P2P.protocolVersion, 'name': ?name});
    };
    newLink.onMessage = onMessage;
    newLink.onClose = () {
      if (_done || link != newLink) {
        return;
      }
      link = null;
      if (_everOpened) {
        onStatus('dropped');
      } else {
        onStatus('unreachable');
      }
    };
    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    _broker!.send({
      'type': 'OFFER',
      'payload': {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
        'type': 'data',
        'connectionId': connectionId,
        'label': connectionId,
        'reliable': true,
        'serialization': 'binary',
        'browser': 'flutter',
      },
      'dst': destination,
    });
  }

  Future<void> _onBroker(Map<String, dynamic> message) async {
    var payload = const {};
    final messagePayload = message['payload'] as Map?;
    if (messagePayload != null) {
      payload = messagePayload;
    }
    final currentLink = link;
    if (message['type'] == 'EXPIRE' || (message['type'] == 'ERROR' && !_everOpened)) {
      hangUp();
      if (message['type'] == 'EXPIRE') {
        onStatus('error', message: peerError('peer-unavailable'));
      } else {
        onStatus('error', message: peerError('server-error'));
      }
      return;
    }
    if (currentLink == null || payload['connectionId'] != currentLink.connectionId) {
      return;
    }
    if (message['type'] == 'ANSWER') {
      await currentLink._setRemoteDescription(payload['sdp'] as Map);
    }
    if (message['type'] == 'CANDIDATE') {
      await currentLink._addCandidate(payload['candidate'] as Map);
    }
  }

  void send(Map<String, Object?> message) {
    link?.send(message);
  }

  /// Leaving on purpose: bye first, so the host retires its code.
  Future<void> leave() async {
    send({'type': 'bye'});
    _done = true;
    _timer?.cancel();
    final leavingLink = link;
    link = null;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await leavingLink?.close();
    _broker?.close();
  }

  void hangUp() {
    _done = true;
    _timer?.cancel();
    link?.close();
    link = null;
    _broker?.close();
  }
}
