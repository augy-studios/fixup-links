// BinaryPack, the format PeerJS sends a data channel's messages in by default (js-binarypack, a
// MessagePack-like format), so the app talks to the site's Sync (js/p2p.js) on another device.
//
//   0x00-0x7f positive fixnum   0xe0-0xff negative fixnum
//   0x80-0x8f fixmap            0x90-0x9f fixarray
//   0xa0-0xaf fixraw (bytes)    0xb0-0xbf fixstr
//   0xc0 null  0xc1 undefined  0xc2 false  0xc3 true  0xca float  0xcb double
//   0xcc-0xcf uint8..uint64     0xd0-0xd3 int8..int64
//   0xd8 str16 0xd9 str32  0xda raw16 0xdb raw32  0xdc array16 0xdd array32  0xde map16 0xdf map32
// Big-endian throughout.
import 'dart:convert';
import 'dart:typed_data';

class BinaryPack {
  BinaryPack._();

  static Uint8List pack(Object? value) {
    final b = BytesBuilder(copy: false);
    _pack(b, value);
    return b.takeBytes();
  }

  static void _u8(BytesBuilder b, int v) => b.addByte(v & 0xff);
  static void _u16(BytesBuilder b, int v) => b.add([(v >> 8) & 0xff, v & 0xff]);
  static void _u32(BytesBuilder b, int v) => b.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  static void _i64(BytesBuilder b, int v) {
    final d = ByteData(8)..setInt64(0, v);
    b.add(d.buffer.asUint8List());
  }

  static void _pack(BytesBuilder b, Object? v) {
    if (v == null) return _u8(b, 0xc0);
    if (v is bool) return _u8(b, v ? 0xc3 : 0xc2);
    if (v is int) return _int(b, v);
    if (v is double) {
      if (v == v.truncateToDouble() && v.abs() < 9007199254740992) return _int(b, v.toInt());
      _u8(b, 0xcb);
      final d = ByteData(8)..setFloat64(0, v);
      return b.add(d.buffer.asUint8List());
    }
    if (v is String) {
      final bytes = utf8.encode(v);
      if (bytes.length <= 0x0f) {
        _u8(b, 0xb0 | bytes.length);
      } else if (bytes.length <= 0xffff) {
        _u8(b, 0xd8);
        _u16(b, bytes.length);
      } else {
        _u8(b, 0xd9);
        _u32(b, bytes.length);
      }
      return b.add(bytes);
    }
    if (v is Uint8List) {
      if (v.length <= 0x0f) {
        _u8(b, 0xa0 | v.length);
      } else if (v.length <= 0xffff) {
        _u8(b, 0xda);
        _u16(b, v.length);
      } else {
        _u8(b, 0xdb);
        _u32(b, v.length);
      }
      return b.add(v);
    }
    if (v is List) {
      if (v.length <= 0x0f) {
        _u8(b, 0x90 | v.length);
      } else if (v.length <= 0xffff) {
        _u8(b, 0xdc);
        _u16(b, v.length);
      } else {
        _u8(b, 0xdd);
        _u32(b, v.length);
      }
      for (final x in v) {
        _pack(b, x);
      }
      return;
    }
    if (v is Map) {
      final n = v.length;
      if (n <= 0x0f) {
        _u8(b, 0x80 | n);
      } else if (n <= 0xffff) {
        _u8(b, 0xde);
        _u16(b, n);
      } else {
        _u8(b, 0xdf);
        _u32(b, n);
      }
      v.forEach((k, x) {
        _pack(b, k is String ? k : '$k');
        _pack(b, x);
      });
      return;
    }
    // Anything else as its words, as JSON would have it.
    _pack(b, '$v');
  }

  // In js-binarypack's order, so the same number is packed the same way.
  static void _int(BytesBuilder b, int n) {
    if (-0x20 <= n && n <= 0x7f) return _u8(b, n);
    if (0 <= n && n <= 0xff) {
      _u8(b, 0xcc);
      return _u8(b, n);
    }
    if (-0x80 <= n && n <= 0x7f) {
      _u8(b, 0xd0);
      return _u8(b, n);
    }
    if (0 <= n && n <= 0xffff) {
      _u8(b, 0xcd);
      return _u16(b, n);
    }
    if (-0x8000 <= n && n <= 0x7fff) {
      _u8(b, 0xd1);
      return _u16(b, n);
    }
    if (0 <= n && n <= 0xffffffff) {
      _u8(b, 0xce);
      return _u32(b, n);
    }
    if (-0x80000000 <= n && n <= 0x7fffffff) {
      _u8(b, 0xd2);
      return _u32(b, n);
    }
    _u8(b, 0xd3);
    _i64(b, n);
  }

  static Object? unpack(Uint8List bytes) => _Reader(bytes).value();
}

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int i = 0;

  int _u8() => bytes[i++];
  int _u16() {
    final v = data.getUint16(i);
    i += 2;
    return v;
  }

  int _u32() {
    final v = data.getUint32(i);
    i += 4;
    return v;
  }

  String _str(int n) {
    final s = utf8.decode(bytes.sublist(i, i + n), allowMalformed: true);
    i += n;
    return s;
  }

  Uint8List _raw(int n) {
    final r = Uint8List.fromList(bytes.sublist(i, i + n));
    i += n;
    return r;
  }

  List<Object?> _array(int n) => [for (var k = 0; k < n; k++) value()];
  Map<String, Object?> _map(int n) {
    final out = <String, Object?>{};
    for (var k = 0; k < n; k++) {
      final key = value();
      out['$key'] = value();
    }
    return out;
  }

  Object? value() {
    final t = _u8();
    if (t < 0x80) return t;
    if ((t ^ 0xe0) < 0x20) return (t ^ 0xe0) - 0x20;
    if ((t ^ 0xa0) <= 0x0f) return _raw(t ^ 0xa0);
    if ((t ^ 0xb0) <= 0x0f) return _str(t ^ 0xb0);
    if ((t ^ 0x90) <= 0x0f) return _array(t ^ 0x90);
    if ((t ^ 0x80) <= 0x0f) return _map(t ^ 0x80);
    switch (t) {
      case 0xc0:
      case 0xc1:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xca:
        final v = data.getFloat32(i);
        i += 4;
        return v;
      case 0xcb:
        final v = data.getFloat64(i);
        i += 8;
        return v;
      case 0xcc:
        return _u8();
      case 0xcd:
        return _u16();
      case 0xce:
        return _u32();
      case 0xcf:
        final hi = _u32(), lo = _u32();
        return hi * 4294967296 + lo;
      case 0xd0:
        return data.getInt8(i++);
      case 0xd1:
        final v = data.getInt16(i);
        i += 2;
        return v;
      case 0xd2:
        final v = data.getInt32(i);
        i += 4;
        return v;
      case 0xd3:
        final v = data.getInt64(i);
        i += 8;
        return v;
      case 0xd8:
        return _str(_u16());
      case 0xd9:
        return _str(_u32());
      case 0xda:
        return _raw(_u16());
      case 0xdb:
        return _raw(_u32());
      case 0xdc:
        return _array(_u16());
      case 0xdd:
        return _array(_u32());
      case 0xde:
        return _map(_u16());
      case 0xdf:
        return _map(_u32());
    }
    return null;
  }
}
