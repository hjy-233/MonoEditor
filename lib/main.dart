import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:re_editor/re_editor.dart';

import 'file_service.dart';

void main() => runApp(const MonoEditorApp());

class _DocumentTab {
  _DocumentTab({
    String text = '',
    this.path,
    this.originalBytes,
    this.encoding = TextFileEncoding.utf8,
    TextLineBreak lineBreak = TextLineBreak.lf,
  }) : controller = CodeLineEditingController.fromText(
         text,
         CodeLineOptions(lineBreak: lineBreak),
       ),
       savedText = text,
       savedEncoding = encoding,
       savedLineBreak = lineBreak;

  CodeLineEditingController controller;
  final CodeScrollController scrollController = CodeScrollController();
  final FocusNode editorFocusNode = FocusNode();
  String? path;
  Uint8List? originalBytes;
  TextFileEncoding encoding;
  TextFileEncoding savedEncoding;
  TextLineBreak savedLineBreak;
  String savedText;
  bool isDirty = false;
  String get name => path == null ? '临时文档' : Uri.file(path!).pathSegments.last;
  String get lineEnding => switch (controller.options.lineBreak) {
    TextLineBreak.crlf => 'CRLF',
    TextLineBreak.cr => 'CR',
    TextLineBreak.lf => 'LF',
  };
}

class MonoEditorApp extends StatefulWidget {
  const MonoEditorApp({super.key});

  @override
  State<MonoEditorApp> createState() => _MonoEditorAppState();
}

class _MonoEditorAppState extends State<MonoEditorApp> {
  ThemeMode _themeMode = ThemeMode.system;
  final List<_DocumentTab> _tabs = [];
  int _activeIndex = 0;
  bool _isBusy = false;
  final FlyoutController _goToFlyout = FlyoutController();
  String? _error;
  _DocumentTab get _activeTab => _tabs[_activeIndex];

  @override
  void initState() {
    super.initState();
    _addTab(_DocumentTab());
  }

  void _addTab(_DocumentTab tab) {
    tab.controller.addListener(_onEditorChanged);
    _tabs.add(tab);
  }

  void _onEditorChanged() {
    if (!mounted) return;
    final changed = _tabs.any((tab) {
      final dirty = _isTabDirty(tab);
      if (dirty == tab.isDirty) return false;
      tab.isDirty = dirty;
      return true;
    });
    if (changed) setState(() {});
  }

  bool _isTabDirty(_DocumentTab tab) =>
      tab.controller.text != tab.savedText ||
      tab.encoding != tab.savedEncoding ||
      tab.controller.options.lineBreak != tab.savedLineBreak;

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.controller.removeListener(_onEditorChanged);
      tab.controller.dispose();
      tab.scrollController.dispose();
      tab.scrollController.verticalScroller.dispose();
      tab.scrollController.horizontalScroller.dispose();
      tab.editorFocusNode.dispose();
    }
    _goToFlyout.dispose();
    super.dispose();
  }

  void _newTab() {
    if (_isBusy) return;
    setState(() {
      _addTab(_DocumentTab());
      _activeIndex = _tabs.length - 1;
      _error = null;
    });
  }

  Future<_ReplaceAction?> _confirmDiscard(
    BuildContext context,
    _DocumentTab tab,
  ) {
    return showDialog<_ReplaceAction>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: Text('${tab.name} 尚未保存'),
        content: const Text('关闭这个标签前，要如何处理当前修改？'),
        actions: [
          Button(
            onPressed: () =>
                Navigator.pop(dialogContext, _ReplaceAction.discard),
            child: const Text('放弃修改'),
          ),
          Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _ReplaceAction.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _disposeTab(_DocumentTab tab) {
    tab.controller.removeListener(_onEditorChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tab.controller.dispose();
      tab.scrollController.dispose();
      tab.scrollController.verticalScroller.dispose();
      tab.scrollController.horizontalScroller.dispose();
    });
  }

  Future<void> _closeTab(BuildContext context, _DocumentTab tab) async {
    if (_isBusy) return;
    if (tab.isDirty) {
      final action = await _confirmDiscard(context, tab);
      if (!mounted || !context.mounted || action == null) return;
      if (action == _ReplaceAction.save && !await _saveTab(context, tab)) {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      final index = _tabs.indexOf(tab);
      if (index < 0) return;
      _tabs.removeAt(index);
      _disposeTab(tab);
      if (_tabs.isEmpty) _addTab(_DocumentTab());
      if (_activeIndex > index) _activeIndex--;
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      _error = null;
    });
  }

  void _showError(String action, Object error) {
    if (!mounted) return;
    final detail = error is FormatException ? error.message : error.toString();
    setState(() => _error = '$action失败：$detail');
  }

  Future<void> _openFile() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final selected = await openFile();
      if (selected == null || !mounted) return;
      final existing = _tabs.indexWhere((tab) => tab.path == selected.path);
      if (existing >= 0) {
        setState(() => _activeIndex = existing);
        return;
      }
      final document = await readTextFile(selected.path);
      if (!mounted) return;
      final tab = _DocumentTab(
        text: document.text,
        path: selected.path,
        originalBytes: document.bytes,
        encoding: document.encoding,
        lineBreak: document.lineBreak,
      );
      setState(() {
        if (_tabs.length == 1 &&
            _activeTab.path == null &&
            !_activeTab.isDirty) {
          _disposeTab(_tabs.removeAt(0));
        }
        _addTab(tab);
        _activeIndex = _tabs.length - 1;
      });
    } catch (error) {
      _showError('打开', error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _save(BuildContext context, {bool saveAs = false}) async {
    if (_isBusy) return;
    final tab = _activeTab;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await _saveTab(context, tab, saveAs: saveAs);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _saveTab(
    BuildContext context,
    _DocumentTab tab, {
    bool saveAs = false,
  }) async {
    try {
      var path = tab.path;
      Uint8List? expectedBytes = tab.originalBytes;
      if (path == null || saveAs) {
        final location = await getSaveLocation(
          suggestedName: path == null
              ? '未命名.txt'
              : Uri.file(path).pathSegments.last,
        );
        if (location == null || !mounted) return false;
        path = location.path;
        if (_tabs.any((other) => other != tab && other.path == path)) {
          throw const FileSystemException('这个文件已在其他标签中打开');
        }
        if (path != tab.path) {
          expectedBytes = null;
          if (await File(path).exists()) {
            if (!mounted || !context.mounted) return false;
            final name = Uri.file(path).pathSegments.last;
            final overwrite = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => ContentDialog(
                title: const Text('文件已存在'),
                content: Text('确定覆盖 $name 吗？'),
                actions: [
                  Button(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('覆盖'),
                  ),
                ],
              ),
            );
            if (overwrite != true || !mounted) return false;
            expectedBytes = await File(path).readAsBytes();
          }
        }
      }
      final text = tab.controller.text;
      final bytes = await writeTextFile(
        path: path,
        text: text,
        expectedBytes: expectedBytes,
        encoding: tab.encoding,
      );
      if (!mounted) return false;
      setState(() {
        tab.path = path;
        tab.originalBytes = bytes;
        tab.savedText = text;
        tab.savedEncoding = tab.encoding;
        tab.savedLineBreak = tab.controller.options.lineBreak;
        tab.isDirty = _isTabDirty(tab);
        _error = null;
      });
      return true;
    } catch (error) {
      _showError('保存', error);
      return false;
    }
  }

  void _changeEncoding(_DocumentTab tab, TextFileEncoding encoding) {
    if (tab.encoding == encoding || _isBusy) return;
    try {
      encodeText(tab.controller.text, encoding);
      setState(() {
        tab.encoding = encoding;
        tab.isDirty = _isTabDirty(tab);
        _error = null;
      });
    } catch (error) {
      _showError('切换编码', error);
    }
  }

  void _changeLineBreak(_DocumentTab tab, TextLineBreak lineBreak) {
    if (tab.controller.options.lineBreak == lineBreak || _isBusy) return;
    final previous = tab.controller;
    final next = CodeLineEditingController(
      codeLines: previous.codeLines,
      options: previous.options.copyWith(lineBreak: lineBreak),
    );
    next.selection = previous.selection;
    previous.removeListener(_onEditorChanged);
    next.addListener(_onEditorChanged);
    setState(() {
      tab.controller = next;
      tab.isDirty = _isTabDirty(tab);
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  Future<void> _goToPosition(_DocumentTab tab) async {
    final selection = tab.controller.selection;
    final input = TextEditingController(
      text: '${selection.extentIndex + 1}:${selection.extentOffset + 1}',
    );
    try {
      final position = await _goToFlyout.showFlyout<(int, int)>(
        placementMode: FlyoutPlacementMode.topLeft,
        builder: (flyoutContext) => StatefulBuilder(
          builder: (context, updateFlyout) {
            final parts = input.text.trim().split(':');
            final line = int.tryParse(parts.first);
            final column = parts.length == 2 ? int.tryParse(parts.last) : 1;
            final valid =
                parts.length <= 2 &&
                line != null &&
                line > 0 &&
                line <= tab.controller.codeLines.length &&
                column != null &&
                column > 0;
            return FlyoutContent(
              child: SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('跳转到行列'),
                    const SizedBox(height: 8),
                    TextBox(
                      controller: input,
                      autofocus: true,
                      placeholder: '行 或 行:列',
                      onChanged: (_) => updateFlyout(() {}),
                      onSubmitted: (_) {
                        if (valid) _goToFlyout.close((line, column));
                      },
                    ),
                    if (!valid) ...[
                      const SizedBox(height: 6),
                      const Text('请输入有效的行号和列号'),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (position == null || !mounted || !_tabs.contains(tab)) return;
      final index = position.$1 - 1;
      final offset = (position.$2 - 1).clamp(
        0,
        tab.controller.codeLines[index].length,
      );
      tab.controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: offset,
      );
      tab.scrollController.makeCenterIfInvisible(
        CodeLinePosition(index: index, offset: offset),
      );
      tab.editorFocusNode.requestFocus();
    } finally {
      input.dispose();
    }
  }

  Widget _actionIcon(IconData icon, String label, VoidCallback? action) =>
      Tooltip(
        message: label,
        child: SizedBox(
          width: 34,
          height: 34,
          child: IconButton(icon: Icon(icon, size: 16), onPressed: action),
        ),
      );

  Widget _editor(_DocumentTab tab, FluentThemeData theme) => material.Theme(
    data: material.ThemeData(brightness: theme.brightness),
    child: CodeEditor(
      key: ValueKey(tab.controller),
      controller: tab.controller,
      focusNode: tab.editorFocusNode,
      scrollController: tab.scrollController,
      readOnly: _isBusy,
      hint: '开始输入…',
      wordWrap: false,
      style: CodeEditorStyle(
        fontSize: 15,
        backgroundColor: theme.scaffoldBackgroundColor,
        textColor: theme.typography.body?.color,
        cursorColor: theme.accentColor.normal,
      ),
      indicatorBuilder: (context, controller, chunkController, notifier) =>
          DefaultCodeLineNumber(controller: controller, notifier: notifier),
    ),
  );

  Widget _statusButton(String label, VoidCallback? onPressed) => HoverButton(
    onPressed: onPressed,
    semanticLabel: label,
    builder: (context, states) => Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: states.contains(WidgetState.hovered)
            ? FluentTheme.of(context).inactiveColor.withValues(alpha: 0.2)
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    ),
  );

  Widget _statusSeparator(FluentThemeData theme) => Container(
    height: 14,
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: theme.inactiveColor.withValues(alpha: 0.7),
  );

  Widget _tabBody(
    BuildContext context,
    _DocumentTab tab,
    FluentThemeData theme,
  ) => Column(
    children: [
      Expanded(child: _editor(tab, theme)),
      Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(
            top: BorderSide(color: theme.inactiveColor.withValues(alpha: 0.75)),
          ),
        ),
        child: Row(
          children: [
            DropDownButton(
              placement: FlyoutPlacementMode.topCenter,
              buttonBuilder: (_, onOpen) =>
                  _statusButton(tab.encoding.label, onOpen),
              items: [
                for (final encoding in TextFileEncoding.values)
                  MenuFlyoutItem(
                    text: Text(encoding.label),
                    selected: encoding == tab.encoding,
                    onPressed: () => _changeEncoding(tab, encoding),
                  ),
              ],
            ),
            _statusSeparator(theme),
            DropDownButton(
              placement: FlyoutPlacementMode.topCenter,
              buttonBuilder: (_, onOpen) =>
                  _statusButton(tab.lineEnding, onOpen),
              items: [
                for (final lineBreak in TextLineBreak.values)
                  MenuFlyoutItem(
                    text: Text(switch (lineBreak) {
                      TextLineBreak.lf => 'LF',
                      TextLineBreak.crlf => 'CRLF',
                      TextLineBreak.cr => 'CR',
                    }),
                    selected: lineBreak == tab.controller.options.lineBreak,
                    onPressed: () => _changeLineBreak(tab, lineBreak),
                  ),
              ],
            ),
            _statusSeparator(theme),
            FlyoutTarget(
              controller: _goToFlyout,
              child: AnimatedBuilder(
                animation: tab.controller,
                builder: (context, child) {
                  final selection = tab.controller.selection;
                  return _statusButton(
                    '第 ${selection.extentIndex + 1} 行，第 ${selection.extentOffset + 1} 列',
                    () => _goToPosition(tab),
                  );
                },
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('LightEdit', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'MonoEditor',
      themeMode: _themeMode,
      theme: FluentThemeData(brightness: Brightness.light),
      darkTheme: FluentThemeData(brightness: Brightness.dark),
      home: Builder(
        builder: (context) {
          final theme = FluentTheme.of(context);
          return ScaffoldPage(
            padding: EdgeInsets.zero,
            content: Column(
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.only(left: 84, right: 12),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.inactiveColor.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'MonoEditor',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _actionIcon(
                        FluentIcons.add,
                        '新建',
                        _isBusy ? null : _newTab,
                      ),
                      _actionIcon(
                        FluentIcons.open_file,
                        '打开',
                        _isBusy ? null : _openFile,
                      ),
                      _actionIcon(
                        FluentIcons.save,
                        '保存',
                        _isBusy ? null : () => _save(context),
                      ),
                      DropDownButton(
                        title: const Icon(FluentIcons.more, size: 16),
                        items: [
                          MenuFlyoutItem(
                            text: const Text('另存为'),
                            onPressed: _isBusy
                                ? null
                                : () => _save(context, saveAs: true),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _actionIcon(
                        theme.brightness == Brightness.dark
                            ? FluentIcons.sunny
                            : FluentIcons.clear_night,
                        theme.brightness == Brightness.dark
                            ? '切换亮色模式'
                            : '切换深色模式',
                        () => setState(
                          () => _themeMode = theme.brightness == Brightness.dark
                              ? ThemeMode.light
                              : ThemeMode.dark,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  InfoBar.error(
                    title: const Text('操作未完成'),
                    content: Text(_error!),
                    onClose: () => setState(() => _error = null),
                  ),
                Expanded(
                  child: TabView(
                    currentIndex: _activeIndex,
                    shortcutsEnabled: true,
                    tabWidthBehavior: TabWidthBehavior.sizeToContent,
                    onChanged: (index) => setState(() {
                      _activeIndex = index;
                      _error = null;
                    }),
                    tabs: [
                      for (final item in _tabs)
                        Tab(
                          key: ValueKey(item.controller),
                          text: Text('${item.name}${item.isDirty ? ' ●' : ''}'),
                          body: _tabBody(context, item, theme),
                          onClosed: _isBusy
                              ? null
                              : () => _closeTab(context, item),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _ReplaceAction { save, discard }
