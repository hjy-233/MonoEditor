import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

typedef OpenedTextFile = ({
  String text,
  Uint8List bytes,
  TextLineBreak lineBreak,
  TextFileEncoding encoding,
});

enum TextFileEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8 BOM'),
  utf16Le('UTF-16 LE'),
  utf16Be('UTF-16 BE'),
  latin1('Latin-1');

  const TextFileEncoding(this.label);
  final String label;
}

String decodeText(Uint8List bytes, TextFileEncoding encoding) {
  return switch (encoding) {
    TextFileEncoding.utf8 => utf8.decode(bytes),
    TextFileEncoding.utf8Bom => utf8.decode(bytes.sublist(3)),
    TextFileEncoding.utf16Le => _decodeUtf16(bytes.sublist(2), true),
    TextFileEncoding.utf16Be => _decodeUtf16(bytes.sublist(2), false),
    TextFileEncoding.latin1 => latin1.decode(bytes),
  };
}

Uint8List encodeText(String text, TextFileEncoding encoding) {
  if (encoding == TextFileEncoding.latin1 &&
      text.codeUnits.any((unit) => unit > 0xff)) {
    throw const FormatException('当前文本包含 Latin-1 无法表示的字符');
  }
  final data = switch (encoding) {
    TextFileEncoding.utf8 || TextFileEncoding.utf8Bom => utf8.encode(text),
    TextFileEncoding.latin1 => latin1.encode(text),
    TextFileEncoding.utf16Le || TextFileEncoding.utf16Be => [
      for (final unit in text.codeUnits)
        if (encoding == TextFileEncoding.utf16Le) ...[
          unit & 0xff,
          unit >> 8,
        ] else ...[
          unit >> 8,
          unit & 0xff,
        ],
    ],
  };
  return Uint8List.fromList([
    if (encoding == TextFileEncoding.utf8Bom) ...[0xef, 0xbb, 0xbf],
    if (encoding == TextFileEncoding.utf16Le) ...[0xff, 0xfe],
    if (encoding == TextFileEncoding.utf16Be) ...[0xfe, 0xff],
    ...data,
  ]);
}

String _decodeUtf16(Uint8List bytes, bool littleEndian) {
  if (bytes.length.isOdd) throw const FormatException('UTF-16 文件字节数不完整');
  final units = <int>[];
  for (var index = 0; index < bytes.length; index += 2) {
    units.add(
      littleEndian
          ? bytes[index] | bytes[index + 1] << 8
          : bytes[index] << 8 | bytes[index + 1],
    );
  }
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= units.length ||
          units[index] < 0xdc00 ||
          units[index] > 0xdfff) {
        throw const FormatException('UTF-16 文件包含无效字符');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('UTF-16 文件包含无效字符');
    }
  }
  return String.fromCharCodes(units);
}

Future<OpenedTextFile> readTextFile(String path) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.size > 10 * 1024 * 1024) {
    throw const FormatException('暂不支持超过 10 MB 的文件');
  }

  final bytes = await file.readAsBytes();
  final encoding =
      bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? TextFileEncoding.utf8Bom
      : bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe
      ? TextFileEncoding.utf16Le
      : bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff
      ? TextFileEncoding.utf16Be
      : TextFileEncoding.utf8;
  final text = decodeText(bytes, encoding);
  if (text.contains('\x00')) {
    throw const FormatException('这不是受支持的文本文件');
  }

  final withoutCrlf = text.replaceAll('\r\n', '');
  final hasCrlf = text.contains('\r\n');
  final hasCr = withoutCrlf.contains('\r');
  final hasLf = withoutCrlf.contains('\n');
  if ([hasCrlf, hasCr, hasLf].where((value) => value).length > 1) {
    throw const FormatException('暂不支持混合换行符的文件');
  }

  return (
    text: text,
    bytes: bytes,
    lineBreak: hasCrlf
        ? TextLineBreak.crlf
        : hasCr
        ? TextLineBreak.cr
        : TextLineBreak.lf,
    encoding: encoding,
  );
}

Future<Uint8List> writeTextFile({
  required String path,
  required String text,
  required Uint8List? expectedBytes,
  required TextFileEncoding encoding,
}) async {
  final entityType = await FileSystemEntity.type(path, followLinks: false);
  if (entityType == FileSystemEntityType.link) {
    throw const FileSystemException('暂不支持覆盖符号链接，请选择其他路径');
  }
  if (entityType == FileSystemEntityType.directory) {
    throw const FileSystemException('保存位置是文件夹');
  }

  final file = File(path);
  if (expectedBytes == null) {
    if (entityType != FileSystemEntityType.notFound) {
      throw const FileSystemException('目标文件已存在，请重新选择保存位置');
    }
  } else {
    if (entityType == FileSystemEntityType.notFound ||
        !listEquals(await file.readAsBytes(), expectedBytes)) {
      throw const FileSystemException('文件已在外部修改，请另存为其他文件');
    }
  }

  final bytes = encodeText(text, encoding);
  await file.writeAsBytes(bytes, flush: true);
  return bytes;
}
