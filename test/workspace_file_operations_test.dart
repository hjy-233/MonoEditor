import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/workspace_file_operations.dart';

void main() {
  test('重命名、删除和撤销恢复真实文件内容', () async {
    final folder = await Directory.systemTemp.createTemp('mono_files_');
    final file = File('${folder.path}/before.txt');
    await file.writeAsString('原内容');
    final operations = WorkspaceFileOperations();
    try {
      final renamed = await operations.rename(file, 'after.txt');
      expect(renamed.kind, WorkspaceOperationKind.rename);
      expect(await File('${folder.path}/after.txt').readAsString(), '原内容');

      final deleted = await operations.delete(File(renamed.currentPath));
      expect(deleted.kind, WorkspaceOperationKind.delete);
      expect(await File(renamed.currentPath).exists(), isFalse);
      expect(await File(deleted.currentPath).readAsString(), '原内容');

      await operations.undo();
      expect(await File(renamed.currentPath).readAsString(), '原内容');
      await operations.undo();
      expect(await file.readAsString(), '原内容');
      expect(operations.canUndo, isFalse);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('撤销时遇到同名文件不会覆盖', () async {
    final folder = await Directory.systemTemp.createTemp('mono_conflict_');
    final file = File('${folder.path}/file.txt');
    await file.writeAsString('旧内容');
    final operations = WorkspaceFileOperations();
    try {
      final deleted = await operations.delete(file);
      await file.writeAsString('新内容');
      await expectLater(operations.undo(), throwsA(isA<FileSystemException>()));
      expect(await file.readAsString(), '新内容');
      expect(await File(deleted.currentPath).readAsString(), '旧内容');
      expect(operations.canUndo, isTrue);
      await file.delete();
      await operations.undo();
      expect(await file.readAsString(), '旧内容');
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('文件夹操作会连同内部文件一起撤销', () async {
    final folder = await Directory.systemTemp.createTemp('mono_folder_');
    final child = await Directory('${folder.path}/before').create();
    await File('${child.path}/nested.txt').writeAsString('保留内容');
    final operations = WorkspaceFileOperations();
    try {
      final renamed = await operations.rename(child, 'after');
      final deleted = await operations.delete(Directory(renamed.currentPath));
      expect(
        await File('${deleted.currentPath}/nested.txt').readAsString(),
        '保留内容',
      );
      await operations.undo();
      await operations.undo();
      expect(await File('${child.path}/nested.txt').readAsString(), '保留内容');
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
