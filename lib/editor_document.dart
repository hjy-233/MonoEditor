import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'file_service.dart';

enum EditorMode { lightEdit, workspace }

class EditorViewSession {
  EditorViewSession({
    required this.id,
    required this.mode,
    required this.controller,
    required this.onChanged,
  }) {
    controller.addListener(onChanged);
  }

  final int id;
  final EditorMode mode;
  final CodeLineEditingController controller;
  final CodeScrollController scrollController = CodeScrollController();
  final FocusNode focusNode = FocusNode();
  final VoidCallback onChanged;

  void dispose() {
    controller.removeListener(onChanged);
    controller.dispose();
    scrollController.dispose();
    scrollController.verticalScroller.dispose();
    scrollController.horizontalScroller.dispose();
    focusNode.dispose();
  }
}

class EditorDocument extends ChangeNotifier {
  EditorDocument({
    required this.id,
    String text = '',
    String? path,
    this.originalBytes,
    this.encoding = TextFileEncoding.utf8,
    TextLineBreak lineBreak = TextLineBreak.lf,
  }) : _path = path,
       pathListenable = ValueNotifier(path),
       codeLines = CodeLines.fromText(text),
       savedText = text,
       savedEncoding = encoding,
       lineBreak = lineBreak,
       savedLineBreak = lineBreak;

  final int id;
  CodeLines codeLines;
  final List<EditorViewSession> _views = [];
  final Map<EditorMode, EditorViewSession> _primaryViews = {};
  String? _path;
  final ValueNotifier<String?> pathListenable;
  String? get path => _path;
  set path(String? value) {
    if (_path == value) return;
    _path = value;
    pathListenable.value = value;
    notifyListeners();
  }

  Uint8List? originalBytes;
  TextFileEncoding encoding;
  TextFileEncoding savedEncoding;
  TextLineBreak lineBreak;
  TextLineBreak savedLineBreak;
  String savedText;
  bool isDirty = false;

  String get name {
    final currentPath = path;
    return currentPath == null
        ? '临时文档'
        : Uri.file(currentPath).pathSegments.last;
  }

  String get text => codeLines.asString(lineBreak);
  String get lineEnding => switch (lineBreak) {
    TextLineBreak.crlf => 'CRLF',
    TextLineBreak.cr => 'CR',
    TextLineBreak.lf => 'LF',
  };

  EditorViewSession viewFor(EditorMode mode, int Function() nextId) {
    final existing = _primaryViews[mode];
    if (existing != null) return existing;
    return createView(mode, nextId);
  }

  EditorViewSession createView(EditorMode mode, int Function() nextId) {
    late final EditorViewSession view;
    view = EditorViewSession(
      id: nextId(),
      mode: mode,
      controller: CodeLineEditingController(
        codeLines: codeLines,
        options: CodeLineOptions(lineBreak: lineBreak),
      ),
      onChanged: () => _onViewChanged(view),
    );
    codeLines = view.controller.codeLines;
    _views.add(view);
    _primaryViews.putIfAbsent(mode, () => view);
    return view;
  }

  void _onViewChanged(EditorViewSession source) {
    final nextLines = source.controller.codeLines;
    if (identical(nextLines, codeLines)) return;
    codeLines = nextLines;
    for (final view in _views) {
      if (identical(view, source)) continue;
      final selection = view.controller.selection;
      final lastIndex = codeLines.length - 1;
      final baseIndex = selection.baseIndex.clamp(0, lastIndex);
      final extentIndex = selection.extentIndex.clamp(0, lastIndex);
      view.controller.value = view.controller.value.copyWith(
        codeLines: codeLines,
        selection: selection.copyWith(
          baseIndex: baseIndex,
          baseOffset: selection.baseOffset.clamp(
            0,
            codeLines[baseIndex].length,
          ),
          extentIndex: extentIndex,
          extentOffset: selection.extentOffset.clamp(
            0,
            codeLines[extentIndex].length,
          ),
        ),
        composing: TextRange.empty,
      );
    }
    refreshDirty();
    notifyListeners();
  }

  void refreshDirty() {
    isDirty =
        text != savedText ||
        encoding != savedEncoding ||
        lineBreak != savedLineBreak;
  }

  void markSaved({
    required Uint8List bytes,
    required String text,
    required TextFileEncoding encoding,
    required TextLineBreak lineBreak,
  }) {
    originalBytes = bytes;
    savedText = text;
    savedEncoding = encoding;
    savedLineBreak = lineBreak;
    refreshDirty();
    notifyListeners();
  }

  void disposeView(EditorMode mode) {
    _primaryViews.remove(mode);
    final removed = _views.where((view) => view.mode == mode).toList();
    _views.removeWhere((view) => view.mode == mode);
    for (final view in removed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => view.dispose());
    }
  }

  @override
  void dispose() {
    pathListenable.dispose();
    for (final view in _views) {
      view.dispose();
    }
    _views.clear();
    _primaryViews.clear();
    super.dispose();
  }
}
