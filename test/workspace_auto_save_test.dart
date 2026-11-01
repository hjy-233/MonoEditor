import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/editor_document.dart';
import 'package:mono_editor/workspace_auto_save.dart';

void main() {
  test('Workspace 编辑后自动保存，并拒绝覆盖外部修改', () async {
    final directory = await Directory.systemTemp.createTemp('mono_workspace_');
    final file = File('${directory.path}/example.txt');
    await file.writeAsString('原内容');
    final document = EditorDocument(
      id: 1,
      text: '原内容',
      path: file.path,
      originalBytes: await file.readAsBytes(),
    );
    final view = document.viewFor(EditorMode.workspace, () => 1);
    final errors = <Object>[];
    final saver = WorkspaceAutoSave(onError: (_, error) => errors.add(error));
    try {
      view.controller.text = '编辑后';
      saver.schedule(document);
      expect(
        await Future.wait([saver.flush(document), saver.flush(document)]),
        [isTrue, isTrue],
      );
      expect(await file.readAsString(), '编辑后');
      expect(document.isDirty, isFalse);

      view.controller.text = '再次编辑';
      await file.writeAsBytes(utf8.encode('外部修改'));
      expect(await saver.flush(document), isFalse);
      expect(await file.readAsString(), '外部修改');
      expect(document.isDirty, isTrue);
      expect(errors.single, isA<FileSystemException>());
    } finally {
      saver.dispose();
      document.dispose();
      await directory.delete(recursive: true);
    }
  });
}
