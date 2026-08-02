import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _maxConfigBytes = 1024 * 1024;
final _versionPattern = RegExp(
  r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$',
);

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: read_bundletool_version.dart <BundleConfig.pb>');
    exitCode = 64;
    return;
  }

  try {
    final file = File(arguments.single);
    final length = file.lengthSync();
    if (length <= 0 || length > _maxConfigBytes) {
      throw const FormatException('invalid BundleConfig size');
    }
    final config = _ProtoReader(file.readAsBytesSync());
    Uint8List? bundletool;
    while (!config.isDone) {
      final field = config.readField();
      if (field.number == 1) {
        if (field.wireType != 2 || bundletool != null) {
          throw const FormatException('invalid bundletool field');
        }
        bundletool = config.readBytes();
      } else {
        config.skip(field.wireType);
      }
    }
    if (bundletool == null) {
      throw const FormatException('missing bundletool field');
    }

    final tool = _ProtoReader(bundletool);
    String? version;
    while (!tool.isDone) {
      final field = tool.readField();
      if (field.number == 2) {
        if (field.wireType != 2 || version != null) {
          throw const FormatException('invalid bundletool version field');
        }
        version = utf8.decode(tool.readBytes(), allowMalformed: false);
      } else {
        tool.skip(field.wireType);
      }
    }
    if (version == null || !_versionPattern.hasMatch(version)) {
      throw const FormatException('invalid bundletool version');
    }
    stdout.writeln(version);
  } on Object {
    stderr.writeln('Invalid BundleConfig.pb');
    exitCode = 65;
  }
}

final class _Field {
  const _Field(this.number, this.wireType);

  final int number;
  final int wireType;
}

final class _ProtoReader {
  _ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isDone => _offset == _bytes.length;

  _Field readField() {
    final tag = _readVarint();
    final number = tag >> 3;
    final wireType = tag & 7;
    if (number <= 0) {
      throw const FormatException('invalid protobuf tag');
    }
    return _Field(number, wireType);
  }

  Uint8List readBytes() {
    final length = _readVarint();
    if (length < 0 || length > _bytes.length - _offset) {
      throw const FormatException('invalid protobuf length');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        _readVarint();
        return;
      case 1:
        _advance(8);
        return;
      case 2:
        readBytes();
        return;
      case 5:
        _advance(4);
        return;
      default:
        throw const FormatException('unsupported protobuf wire type');
    }
  }

  int _readVarint() {
    var result = 0;
    for (var index = 0; index < 10; index += 1) {
      if (_offset >= _bytes.length) {
        throw const FormatException('truncated protobuf varint');
      }
      final byte = _bytes[_offset++];
      if (index == 9 && byte > 1) {
        throw const FormatException('protobuf varint overflow');
      }
      result |= (byte & 0x7f) << (index * 7);
      if ((byte & 0x80) == 0) {
        return result;
      }
    }
    throw const FormatException('protobuf varint overflow');
  }

  void _advance(int count) {
    if (count > _bytes.length - _offset) {
      throw const FormatException('truncated protobuf field');
    }
    _offset += count;
  }
}
