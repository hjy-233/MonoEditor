import 'dart:io';

enum WorkspaceOperationKind { rename, delete }

class WorkspaceOperation {
  const WorkspaceOperation({
    required this.kind,
    required this.originalPath,
    required this.currentPath,
  });

  final WorkspaceOperationKind kind;
  final String originalPath;
  final String currentPath;
}

class WorkspaceFileOperations {
  final List<WorkspaceOperation> _history = [];

  bool get canUndo => _history.isNotEmpty;
  WorkspaceOperation? get lastOperation => _history.lastOrNull;

  Future<WorkspaceOperation> rename(FileSystemEntity entry, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.contains('/') ||
        trimmed.contains('\\')) {
      throw const FormatException('名称不能为空，也不能包含路径分隔符');
    }
    final destination = '${entry.parent.path}/$trimmed';
    if (destination == entry.path) {
      throw const FormatException('名称没有变化');
    }
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标名称已存在', destination);
    }
    await entry.rename(destination);
    final operation = WorkspaceOperation(
      kind: WorkspaceOperationKind.rename,
      originalPath: entry.path,
      currentPath: destination,
    );
    _history.add(operation);
    return operation;
  }

  Future<WorkspaceOperation> delete(FileSystemEntity entry) async {
    final holdingDirectory = await Directory.systemTemp.createTemp(
      'mono_editor_undo_',
    );
    final heldPath =
        '${holdingDirectory.path}/${Uri.file(entry.path).pathSegments.last}';
    try {
      await entry.rename(heldPath);
    } catch (_) {
      await holdingDirectory.delete();
      rethrow;
    }
    final operation = WorkspaceOperation(
      kind: WorkspaceOperationKind.delete,
      originalPath: entry.path,
      currentPath: heldPath,
    );
    _history.add(operation);
    return operation;
  }

  Future<WorkspaceOperation?> undo() async {
    if (_history.isEmpty) return null;
    final operation = _history.last;
    if (await FileSystemEntity.type(
          operation.originalPath,
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原位置已有同名文件，无法撤销', operation.originalPath);
    }
    final held = await FileSystemEntity.type(
      operation.currentPath,
      followLinks: false,
    );
    if (held == FileSystemEntityType.notFound) {
      throw FileSystemException('操作记录对应的文件已不存在', operation.currentPath);
    }
    if (held == FileSystemEntityType.directory) {
      await Directory(operation.currentPath).rename(operation.originalPath);
    } else {
      await File(operation.currentPath).rename(operation.originalPath);
    }
    _history.removeLast();
    if (operation.kind == WorkspaceOperationKind.delete) {
      await Directory(operation.currentPath).parent.delete();
    }
    return operation;
  }
}
