import 'dart:async';

import 'editor_document.dart';
import 'file_service.dart';

class WorkspaceAutoSave {
  WorkspaceAutoSave({required this.onError});

  final void Function(EditorDocument document, Object error) onError;
  final Map<EditorDocument, Timer> _pending = {};
  final Map<EditorDocument, Future<bool>> _running = {};

  void schedule(EditorDocument document) {
    _pending.remove(document)?.cancel();
    if (!document.isDirty || document.path == null) return;
    _pending[document] = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(flush(document)),
    );
  }

  Future<bool> flush(EditorDocument document) async {
    _pending.remove(document)?.cancel();
    final running = _running[document];
    if (running != null) {
      if (!await running) return false;
      return flush(document);
    }
    if (!document.isDirty) return true;
    final path = document.path;
    if (path == null) return false;

    final text = document.text;
    final encoding = document.encoding;
    final lineBreak = document.lineBreak;
    final expectedBytes = document.originalBytes;
    final save = () async {
      try {
        final bytes = await writeTextFile(
          path: path,
          text: text,
          expectedBytes: expectedBytes,
          encoding: encoding,
        );
        document.markSaved(
          bytes: bytes,
          text: text,
          encoding: encoding,
          lineBreak: lineBreak,
        );
        if (document.isDirty) schedule(document);
        return true;
      } catch (error) {
        onError(document, error);
        return false;
      }
    }();
    late final Future<bool> operation;
    operation = save.whenComplete(() {
      if (identical(_running[document], operation)) _running.remove(document);
    });
    _running[document] = operation;
    return operation;
  }

  void cancel(EditorDocument document) => _pending.remove(document)?.cancel();

  void dispose() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
  }
}
