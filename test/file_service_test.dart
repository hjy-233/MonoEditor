import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/file_service.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mono_editor_test_');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('打开并保存 UTF-8 BOM 和 CRLF 文件时保持格式', () async {
    final file = File('${directory.path}/example.swift');
    await file.writeAsBytes([0xef, 0xbb, 0xbf, ...utf8.encode('第一行\r\n第二行')]);

    final opened = await readTextFile(file.path);
    expect(opened.text, '第一行\r\n第二行');
    expect(opened.lineBreak, TextLineBreak.crlf);
    expect(opened.encoding, TextFileEncoding.utf8Bom);

    final controller = CodeLineEditingController.fromText(
      opened.text,
      CodeLineOptions(lineBreak: opened.lineBreak),
    );
    expect(controller.text, opened.text);
    controller.text = '第一行\r\n修改后';
    await writeTextFile(
      path: file.path,
      text: controller.text,
      expectedBytes: opened.bytes,
      encoding: opened.encoding,
    );
    expect(await file.readAsBytes(), [
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('第一行\r\n修改后'),
    ]);
    controller.dispose();
  });

  test('文件被外部修改后拒绝覆盖', () async {
    final file = File('${directory.path}/example.txt');
    await file.writeAsString('原内容');
    final opened = await readTextFile(file.path);
    await file.writeAsString('外部修改');

    await expectLater(
      writeTextFile(
        path: file.path,
        text: '编辑器修改',
        expectedBytes: opened.bytes,
        encoding: TextFileEncoding.utf8,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), '外部修改');
  });

  test('新文件不会覆盖已有路径', () async {
    final file = File('${directory.path}/existing.txt');
    await file.writeAsString('已有内容');

    await expectLater(
      writeTextFile(
        path: file.path,
        text: '新内容',
        expectedBytes: null,
        encoding: TextFileEncoding.utf8,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), '已有内容');
  });

  test('混合换行符文件不被静默改写', () async {
    final file = File('${directory.path}/mixed.txt');
    await file.writeAsString('一\r\n二\n三');
    await expectLater(readTextFile(file.path), throwsA(isA<FormatException>()));
  });

  test('UTF-16 LE 和 BE 文件可打开并按原编码保存', () async {
    for (final encoding in [
      TextFileEncoding.utf16Le,
      TextFileEncoding.utf16Be,
    ]) {
      final file = File('${directory.path}/${encoding.name}.txt');
      await file.writeAsBytes(encodeText('第一行\r\n第二行 😀', encoding));
      final opened = await readTextFile(file.path);
      expect(opened.encoding, encoding);
      expect(opened.text, '第一行\r\n第二行 😀');
      expect(opened.lineBreak, TextLineBreak.crlf);
      final saved = await writeTextFile(
        path: file.path,
        text: '修改后 😀',
        expectedBytes: opened.bytes,
        encoding: encoding,
      );
      expect(decodeText(saved, encoding), '修改后 😀');
    }
  });

  test('Latin-1 不会把无法表示的字符静默写坏', () {
    expect(
      () => encodeText('中文', TextFileEncoding.latin1),
      throwsFormatException,
    );
  });
}
