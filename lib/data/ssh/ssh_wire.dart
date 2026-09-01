import 'dart:typed_data';

/// Minimal SSH binary packet primitives (RFC 4251).
class SshWireWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void writeUint32(int value) {
    _out.add([
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  void writeString(Uint8List bytes) {
    writeUint32(bytes.length);
    _out.add(bytes);
  }

  void writeUtf8(String value) {
    writeString(Uint8List.fromList(value.codeUnits));
  }

  void writeMpint(BigInt value) {
    if (value == BigInt.zero) {
      writeString(Uint8List(0));
      return;
    }
    var bytes = _toUnsigned(value);
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    writeString(bytes);
  }

  Uint8List takeBytes() => _out.takeBytes();

  static Uint8List _toUnsigned(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) {
      hex = '0$hex';
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

class SshWireReader {
  SshWireReader(this.data);

  final Uint8List data;
  int _offset = 0;

  int readUint32() {
    if (_offset + 4 > data.length) {
      throw const FormatException('truncated ssh uint32');
    }
    final v = (data[_offset] << 24) |
        (data[_offset + 1] << 16) |
        (data[_offset + 2] << 8) |
        data[_offset + 3];
    _offset += 4;
    return v;
  }

  Uint8List readString() {
    final len = readUint32();
    if (len < 0 || _offset + len > data.length) {
      throw const FormatException('truncated ssh string');
    }
    final slice = Uint8List.sublistView(data, _offset, _offset + len);
    _offset += len;
    return slice;
  }

  String readUtf8() => String.fromCharCodes(readString());

  BigInt readMpint() {
    final bytes = readString();
    if (bytes.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }
}
