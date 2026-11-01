import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as system;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, MethodChannel;
import 'package:re_editor/re_editor.dart';

import 'file_service.dart';
import 'file_icons.dart';
import 'keyboard_hint.dart';
import 'syntax_highlighting.dart';
import 'editor_document.dart';
import 'workspace_auto_save.dart';
import 'workspace_file_operations.dart';

void main() => runApp(const MonoEditorApp());

class MonoEditorApp extends StatefulWidget {
  const MonoEditorApp({super.key});

  @override
  State<MonoEditorApp> createState() => _MonoEditorAppState();
}

class _MonoEditorAppState extends State<MonoEditorApp> {
  ThemeMode _themeMode = ThemeMode.system;
  EditorMode _mode = EditorMode.lightEdit;
  final List<EditorDocument> _documents = [];
  final List<EditorDocument> _lightTabs = [];
  final List<EditorDocument> _workspaceTabs = [];
  final Map<EditorDocument, VoidCallback> _documentListeners = {};
  final Map<EditorViewSession, Tab> _viewTabs = {};
  int _lightActiveIndex = 0;
  int _workspaceActiveIndex = 0;
  String? _workspaceFolder;
  final TreeViewController _explorerController = TreeViewController();
  static const _explorerMenuChannel = MethodChannel(
    'org.dcstudio.MonoEditor/explorerMenu',
  );
  final WorkspaceFileOperations _fileOperations = WorkspaceFileOperations();
  double _explorerWidth = 250;
  final FocusNode _explorerPanelFocusNode = FocusNode();
  final List<FocusNode> _explorerFocusNodes = [];
  final Set<String> _loadedFolders = {};
  int _explorerVersion = 0;
  bool _showExplorer = true;
  bool _showExcluded = false;
  bool _explorerLoading = false;
  static const _excludedNames = {
    '.DS_Store',
    'Thumbs.db',
    '.git',
    '.build',
    '.dart_tool',
    '.swiftpm',
    '.venv',
    '.pytest_cache',
    '__pycache__',
    'build',
    'dist',
    'node_modules',
    '.next',
    '.gradle',
    'target',
    'DerivedData',
    'Pods',
  };
  int _nextDocumentId = 0;
  int _nextViewId = 0;
  bool _isBusy = false;
  final FlyoutController _goToFlyout = FlyoutController();
  late final AppLifecycleListener _lifecycleListener;
  late final WorkspaceAutoSave _autoSave = WorkspaceAutoSave(
    onError: (document, error) => _showError('自动保存', error),
  );
  String? _error;
  List<EditorDocument> get _tabs =>
      _mode == EditorMode.lightEdit ? _lightTabs : _workspaceTabs;
  int get _activeIndex =>
      _mode == EditorMode.lightEdit ? _lightActiveIndex : _workspaceActiveIndex;
  set _activeIndex(int value) {
    if (_mode == EditorMode.lightEdit) {
      _lightActiveIndex = value;
    } else {
      _workspaceActiveIndex = value;
    }
  }

  EditorDocument get _activeTab => _tabs[_activeIndex];
  EditorViewSession _view(EditorDocument document) =>
      document.viewFor(_mode, () => _nextViewId++);
  Tab _tabFor(BuildContext context, EditorDocument document) {
    final view = _view(document);
    return _viewTabs.putIfAbsent(
      view,
      () => Tab(
        key: ValueKey(view.id),
        icon: ValueListenableBuilder<String?>(
          valueListenable: document.pathListenable,
          builder: (context, _, _) =>
              JetBrainsFileIcon(name: document.name, isDirectory: false),
        ),
        closeIcon: const Icon(system.FluentIcons.dismiss_16_regular, size: 16),
        text: AnimatedBuilder(
          animation: document,
          builder: (context, child) =>
              Text('${document.name}${document.isDirty ? ' ●' : ''}'),
        ),
        body: ValueListenableBuilder<String?>(
          valueListenable: document.pathListenable,
          builder: (context, _, _) =>
              _tabBody(context, document, FluentTheme.of(context)),
        ),
        onClosed: () => _closeTab(context, document),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    _addTab(EditorDocument(id: _nextDocumentId++));
  }

  Future<AppExitResponse> _onExitRequested() async {
    for (final tab in _workspaceTabs) {
      if (tab.isDirty && !await _autoSave.flush(tab)) {
        return AppExitResponse.cancel;
      }
    }
    return AppExitResponse.exit;
  }

  void _addTab(EditorDocument tab) {
    if (!_documents.contains(tab)) {
      void listener() => _onEditorChanged(tab);
      _documentListeners[tab] = listener;
      tab.addListener(listener);
      _documents.add(tab);
    }
    _view(tab);
    _tabs.add(tab);
  }

  void _onEditorChanged(EditorDocument tab) {
    if (_mode == EditorMode.workspace && _workspaceTabs.contains(tab)) {
      _autoSave.schedule(tab);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    for (final tab in _documents) {
      final listener = _documentListeners[tab];
      if (listener != null) tab.removeListener(listener);
      tab.dispose();
    }
    _autoSave.dispose();
    _explorerController.dispose();
    _explorerPanelFocusNode.dispose();
    for (final node in _explorerFocusNodes) {
      node.dispose();
    }
    _goToFlyout.dispose();
    super.dispose();
  }

  void _newTab() {
    if (_isBusy) return;
    setState(() {
      _addTab(EditorDocument(id: _nextDocumentId++));
      _activeIndex = _tabs.length - 1;
      _error = null;
    });
  }

  Future<_ReplaceAction?> _confirmDiscard(
    BuildContext context,
    EditorDocument tab,
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

  void _disposeTab(EditorDocument tab) {
    _autoSave.cancel(tab);
    final listener = _documentListeners.remove(tab);
    if (listener != null) tab.removeListener(listener);
    _documents.remove(tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tab.dispose();
    });
  }

  void _removeTab(EditorDocument tab) {
    _tabs.remove(tab);
    _viewTabs.remove(_view(tab));
    if (_lightTabs.contains(tab) || _workspaceTabs.contains(tab)) {
      tab.disposeView(_mode);
    } else {
      _disposeTab(tab);
    }
  }

  void _switchMode(EditorMode mode) {
    if (_mode == mode || _isBusy) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == EditorMode.workspace) {
      for (final tab in _workspaceTabs) {
        _autoSave.schedule(tab);
      }
    }
  }

  Future<void> _closeTab(BuildContext context, EditorDocument tab) async {
    if (_isBusy) return;
    final closingMode = _mode;
    if (closingMode == EditorMode.workspace && tab.isDirty) {
      if (!await _autoSave.flush(tab)) return;
    }
    if (!mounted || !context.mounted || _mode != closingMode) return;
    final otherTabs = _mode == EditorMode.lightEdit
        ? _workspaceTabs
        : _lightTabs;
    if (tab.isDirty && !otherTabs.contains(tab)) {
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
      _removeTab(tab);
      if (_tabs.isEmpty && _mode == EditorMode.lightEdit) {
        _addTab(EditorDocument(id: _nextDocumentId++));
      }
      if (_activeIndex > index) _activeIndex--;
      if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.isEmpty ? 0 : _tabs.length - 1;
      }
      _error = null;
    });
  }

  void _showError(String action, Object error) {
    if (!mounted) return;
    final detail = error is FormatException ? error.message : error.toString();
    setState(() => _error = '$action失败：$detail');
  }

  Future<void> _selectWorkspaceFolder() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final selected = await getDirectoryPath();
      if (selected == null || !mounted) return;
      final folder = await Directory(selected).resolveSymbolicLinks();
      final entries = await _listWorkspaceEntries(folder);
      final nodes = <FocusNode>[];
      final items = await _createExplorerItems(entries, nodes);
      if (!mounted) return;
      final oldNodes = List<FocusNode>.of(_explorerFocusNodes);
      _explorerFocusNodes.clear();
      _explorerFocusNodes.addAll(nodes);
      _loadedFolders.clear();
      _explorerVersion++;
      _explorerController.items = items;
      setState(() {
        _workspaceFolder = folder;
        _showExplorer = true;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in oldNodes) {
          node.dispose();
        }
        _focusExplorer();
      });
    } catch (error) {
      _showError('选择文件夹', error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<List<FileSystemEntity>> _listWorkspaceEntries(String path) async {
    final entries = await Directory(path)
        .list(followLinks: false)
        .where(
          (entry) =>
              (entry is File || entry is Directory) &&
              (_showExcluded ||
                  !_excludedNames.contains(
                    Uri.file(entry.path).pathSegments.last,
                  )),
        )
        .toList();
    entries.sort((left, right) {
      if (left is Directory && right is! Directory) return -1;
      if (left is! Directory && right is Directory) return 1;
      return left.path.toLowerCase().compareTo(right.path.toLowerCase());
    });
    return entries;
  }

  Future<List<TreeViewItem>> _createExplorerItems(
    List<FileSystemEntity> entries,
    List<FocusNode> nodes, [
    Set<String> expandedPaths = const {},
  ]) => Future.wait(
    entries.map((entry) => _explorerItem(entry, nodes, expandedPaths)),
  );

  Future<TreeViewItem> _explorerItem(
    FileSystemEntity entry,
    List<FocusNode> nodes,
    Set<String> expandedPaths,
  ) async {
    final isDirectory = entry is Directory;
    var displayName = Uri.file(entry.path).pathSegments.last;
    if (entry is Directory) {
      for (var depth = 0; depth < 32; depth++) {
        final List<FileSystemEntity> children;
        try {
          children = await _listWorkspaceEntries(entry.path);
        } on FileSystemException {
          break;
        }
        if (children.length != 1 || children.single is! Directory) break;
        entry = children.single;
        displayName += '/${Uri.file(entry.path).pathSegments.last}';
      }
    }
    final focusNode = FocusNode();
    nodes.add(focusNode);
    final path = entry.path;
    final expanded = isDirectory && expandedPaths.contains(path);
    final children = expanded
        ? await _createExplorerItems(
            await _listWorkspaceEntries(path),
            nodes,
            expandedPaths,
          )
        : <TreeViewItem>[];
    return TreeViewItem(
      key: ValueKey(entry.path),
      value: entry,
      focusNode: focusNode,
      lazy: isDirectory,
      children: children,
      expanded: expanded,
      leading: JetBrainsFileIcon(
        name: Uri.file(entry.path).pathSegments.last,
        isDirectory: isDirectory,
      ),
      content: Tooltip(
        message: displayName,
        child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _expandExplorerItem(TreeViewItem item, bool expanded) async {
    final entry = item.value;
    if (!expanded || entry is! Directory || !_loadedFolders.add(entry.path)) {
      return;
    }
    final version = _explorerVersion;
    try {
      final entries = await _listWorkspaceEntries(entry.path);
      final nodes = <FocusNode>[];
      final items = await _createExplorerItems(entries, nodes);
      if (!mounted || version != _explorerVersion) {
        for (final node in nodes) {
          node.dispose();
        }
        return;
      }
      _explorerFocusNodes.addAll(nodes);
      _explorerController.addItems(items, parent: item);
    } catch (error) {
      if (version == _explorerVersion) {
        _loadedFolders.remove(entry.path);
        _showError('读取文件夹', error);
      }
    }
  }

  Set<String> _expandedExplorerPaths() {
    final paths = <String>{};
    void collect(TreeViewItem item) {
      final entry = item.value;
      if (item.expanded && entry is Directory) paths.add(entry.path);
      for (final child in item.children) {
        collect(child);
      }
    }

    for (final item in _explorerController.items) {
      collect(item);
    }
    return paths;
  }

  Future<void> _refreshExplorer({String? oldPath, String? newPath}) async {
    final folder = _workspaceFolder;
    if (folder == null) return;
    final expanded = _expandedExplorerPaths();
    if (oldPath != null && newPath != null) {
      final moved = expanded
          .where((path) => path == oldPath || path.startsWith('$oldPath/'))
          .toList();
      for (final path in moved) {
        expanded
          ..remove(path)
          ..add('$newPath${path.substring(oldPath.length)}');
      }
    }
    final version = ++_explorerVersion;
    final nodes = <FocusNode>[];
    try {
      final entries = await _listWorkspaceEntries(folder);
      final items = await _createExplorerItems(entries, nodes, expanded);
      if (!mounted || version != _explorerVersion) {
        for (final node in nodes) {
          node.dispose();
        }
        return;
      }
      final oldNodes = List<FocusNode>.of(_explorerFocusNodes);
      _explorerFocusNodes
        ..clear()
        ..addAll(nodes);
      _loadedFolders
        ..clear()
        ..addAll(expanded);
      _explorerController.items = items;
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in oldNodes) {
          node.dispose();
        }
      });
    } catch (error) {
      for (final node in nodes) {
        node.dispose();
      }
      _showError('刷新文件树', error);
    }
  }

  List<EditorDocument> _documentsAt(String path) =>
      _documents.where((document) {
        final documentPath = document.path;
        return documentPath == path ||
            (documentPath?.startsWith('$path/') ?? false);
      }).toList();

  Future<bool> _prepareFileOperation(List<EditorDocument> documents) async {
    for (final document in documents) {
      if (document.isDirty && !_workspaceTabs.contains(document)) {
        _showError('文件操作', const FormatException('请先保存打开文件的修改'));
        return false;
      }
      if (!await _autoSave.flush(document)) return false;
    }
    return mounted;
  }

  void _moveDocumentPaths(String oldPath, String newPath) {
    for (final document in _documentsAt(oldPath)) {
      final path = document.path!;
      document.path = '$newPath${path.substring(oldPath.length)}';
    }
  }

  void _detachDeletedDocuments(List<EditorDocument> documents) {
    setState(() {
      for (final document in documents) {
        for (final mode in EditorMode.values) {
          final tabs = mode == EditorMode.lightEdit
              ? _lightTabs
              : _workspaceTabs;
          if (!tabs.remove(document)) continue;
          _viewTabs.remove(document.viewFor(mode, () => _nextViewId++));
          document.disposeView(mode);
        }
        _disposeTab(document);
      }
      if (_lightTabs.isEmpty) {
        final document = EditorDocument(id: _nextDocumentId++);
        final mode = _mode;
        _mode = EditorMode.lightEdit;
        _addTab(document);
        _mode = mode;
      }
      _lightActiveIndex = _lightActiveIndex.clamp(0, _lightTabs.length - 1);
      _workspaceActiveIndex = _workspaceTabs.isEmpty
          ? 0
          : _workspaceActiveIndex.clamp(0, _workspaceTabs.length - 1);
    });
  }

  Future<void> _renameExplorerItem(
    BuildContext context,
    FileSystemEntity entry,
  ) async {
    final controller = TextEditingController(
      text: Uri.file(entry.path).pathSegments.last,
    );
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          void finish([String? value]) =>
              Navigator.of(dialogContext, rootNavigator: true).pop(value);

          return ContentDialog(
            title: const Text('重命名'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 32,
                  child: TextBox(
                    controller: controller,
                    autofocus: true,
                    onSubmitted: finish,
                  ),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    KeyboardHint(keyLabel: 'Enter', actionLabel: '重命名'),
                    KeyboardHint(keyLabel: 'Esc', actionLabel: '取消'),
                  ],
                ),
              ],
            ),
          );
        },
      );
      if (name == null || !mounted || _isBusy) return;
      final documents = _documentsAt(entry.path);
      setState(() => _isBusy = true);
      if (!await _prepareFileOperation(documents)) return;
      final operation = await _fileOperations.rename(entry, name);
      _moveDocumentPaths(operation.originalPath, operation.currentPath);
      await _refreshExplorer(
        oldPath: operation.originalPath,
        newPath: operation.currentPath,
      );
    } catch (error) {
      _showError('重命名', error);
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _deleteExplorerItem(
    BuildContext context,
    FileSystemEntity entry,
  ) async {
    final name = Uri.file(entry.path).pathSegments.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        void finish(bool value) =>
            Navigator.of(dialogContext, rootNavigator: true).pop(value);

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
              finish(true);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ContentDialog(
            title: Text('删除 $name？'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('文件会移到临时暂存区；本次运行期间可撤销。相关的已打开标签会关闭。'),
                SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    KeyboardHint(keyLabel: 'Enter', actionLabel: '删除'),
                    KeyboardHint(keyLabel: 'Esc', actionLabel: '取消'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted || _isBusy) return;
    final documents = _documentsAt(entry.path);
    setState(() => _isBusy = true);
    try {
      if (!await _prepareFileOperation(documents)) return;
      await _fileOperations.delete(entry);
      _detachDeletedDocuments(documents);
      await _refreshExplorer();
    } catch (error) {
      _showError('删除', error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _undoExplorerOperation() async {
    if (_isBusy || !_fileOperations.canUndo) return;
    setState(() => _isBusy = true);
    try {
      final operation = await _fileOperations.undo();
      if (operation == null) return;
      if (operation.kind == WorkspaceOperationKind.rename) {
        _moveDocumentPaths(operation.currentPath, operation.originalPath);
      }
      await _refreshExplorer(
        oldPath: operation.kind == WorkspaceOperationKind.rename
            ? operation.currentPath
            : null,
        newPath: operation.kind == WorkspaceOperationKind.rename
            ? operation.originalPath
            : null,
      );
    } catch (error) {
      _showError('撤销文件操作', error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showExplorerMenu(
    BuildContext context,
    TreeViewItem item,
    TapDownDetails _,
  ) async {
    final entry = item.value;
    if (entry is! File && entry is! Directory) return;
    try {
      final action = await _explorerMenuChannel.invokeMethod<String>('show', {
        'canUndo': _fileOperations.canUndo,
      });
      if (!mounted || !context.mounted) return;
      switch (action) {
        case 'rename':
          await _renameExplorerItem(context, entry);
        case 'delete':
          await _deleteExplorerItem(context, entry);
        case 'undo':
          await _undoExplorerOperation();
      }
    } catch (error) {
      _showError('文件操作', error);
    }
  }

  Future<void> _toggleExcluded() async {
    if (_isBusy || _explorerLoading) return;
    final folder = _workspaceFolder;
    if (folder == null) {
      setState(() => _showExcluded = !_showExcluded);
      return;
    }
    setState(() {
      _showExcluded = !_showExcluded;
      _explorerLoading = true;
    });
    final version = ++_explorerVersion;
    final nodes = <FocusNode>[];
    try {
      final entries = await _listWorkspaceEntries(folder);
      final items = await _createExplorerItems(entries, nodes);
      if (!mounted || version != _explorerVersion) {
        for (final node in nodes) {
          node.dispose();
        }
        return;
      }
      final oldNodes = List<FocusNode>.of(_explorerFocusNodes);
      _explorerFocusNodes
        ..clear()
        ..addAll(nodes);
      _loadedFolders.clear();
      _explorerController.items = items;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in oldNodes) {
          node.dispose();
        }
      });
    } catch (error) {
      for (final node in nodes) {
        node.dispose();
      }
      if (mounted) {
        setState(() => _showExcluded = !_showExcluded);
        _showError('读取文件夹', error);
      }
    } finally {
      if (mounted) setState(() => _explorerLoading = false);
    }
  }

  void _focusExplorer() {
    if (!mounted || !_showExplorer) return;
    _explorerPanelFocusNode.requestFocus();
  }

  void _toggleExplorer() {
    setState(() => _showExplorer = !_showExplorer);
    if (_showExplorer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusExplorer());
    } else if (_workspaceTabs.isNotEmpty) {
      _view(_activeTab).focusNode.requestFocus();
    }
  }

  void _revealExplorer() {
    setState(() => _showExplorer = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusExplorer());
  }

  void _resizeExplorer(DragUpdateDetails details) {
    final maxWidth = (MediaQuery.sizeOf(context).width - 220).clamp(
      180.0,
      600.0,
    );
    setState(() {
      _explorerWidth = (_explorerWidth + details.delta.dx).clamp(
        180.0,
        maxWidth,
      );
    });
  }

  Future<void> _openWorkspaceFile(String path) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final existing = _workspaceTabs.indexWhere((tab) => tab.path == path);
      if (existing >= 0) {
        setState(() {
          _activeIndex = existing;
        });
        return;
      }
      final shared = _documents.where((tab) => tab.path == path).firstOrNull;
      final opened = shared == null ? await readTextFile(path) : null;
      if (!mounted) return;
      final EditorDocument tab;
      if (shared != null) {
        tab = shared;
      } else if (opened != null) {
        tab = EditorDocument(
          id: _nextDocumentId++,
          text: opened.text,
          path: path,
          originalBytes: opened.bytes,
          encoding: opened.encoding,
          lineBreak: opened.lineBreak,
        );
      } else {
        return;
      }
      setState(() {
        _addTab(tab);
        _activeIndex = _tabs.length - 1;
      });
      _autoSave.schedule(tab);
    } catch (error) {
      _showError('打开', error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
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
      final shared = _documents
          .where((tab) => tab.path == selected.path)
          .firstOrNull;
      final document = shared == null
          ? await readTextFile(selected.path)
          : null;
      if (!mounted) return;
      final EditorDocument tab;
      if (shared != null) {
        tab = shared;
      } else if (document != null) {
        tab = EditorDocument(
          id: _nextDocumentId++,
          text: document.text,
          path: selected.path,
          originalBytes: document.bytes,
          encoding: document.encoding,
          lineBreak: document.lineBreak,
        );
      } else {
        return;
      }
      setState(() {
        if (_tabs.length == 1 &&
            _activeTab.path == null &&
            !_activeTab.isDirty) {
          _removeTab(_activeTab);
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
    EditorDocument tab, {
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
        if (_documents.any((other) => other != tab && other.path == path)) {
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
      final text = tab.text;
      final bytes = await writeTextFile(
        path: path,
        text: text,
        expectedBytes: expectedBytes,
        encoding: tab.encoding,
      );
      if (!mounted) return false;
      tab.path = path;
      tab.markSaved(
        bytes: bytes,
        text: text,
        encoding: tab.encoding,
        lineBreak: tab.lineBreak,
      );
      setState(() => _error = null);
      return true;
    } catch (error) {
      _showError('保存', error);
      return false;
    }
  }

  void _changeEncoding(EditorDocument tab, TextFileEncoding encoding) {
    if (tab.encoding == encoding || _isBusy) return;
    try {
      encodeText(tab.text, encoding);
      setState(() {
        tab.encoding = encoding;
        tab.refreshDirty();
        _error = null;
      });
      if (_mode == EditorMode.workspace) _autoSave.schedule(tab);
    } catch (error) {
      _showError('切换编码', error);
    }
  }

  void _changeLineBreak(EditorDocument tab, TextLineBreak lineBreak) {
    if (tab.lineBreak == lineBreak || _isBusy) return;
    setState(() {
      tab.lineBreak = lineBreak;
      tab.refreshDirty();
      _error = null;
    });
    if (_mode == EditorMode.workspace) _autoSave.schedule(tab);
  }

  Future<void> _goToPosition(EditorDocument tab) async {
    final view = _view(tab);
    final selection = view.controller.selection;
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
                line <= view.controller.codeLines.length &&
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
        view.controller.codeLines[index].length,
      );
      view.controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: offset,
      );
      view.scrollController.makeCenterIfInvisible(
        CodeLinePosition(index: index, offset: offset),
      );
      view.focusNode.requestFocus();
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
          child: Button(
            onPressed: action,
            child: Center(child: Icon(icon, size: 16)),
          ),
        ),
      );

  Widget _actionDropdown(List<MenuFlyoutItemBase> items) => SizedBox(
    height: 34,
    child: DropDownButton(
      title: const Icon(
        system.FluentIcons.more_horizontal_20_regular,
        size: 16,
      ),
      items: items,
    ),
  );

  Widget _actionGroup(List<Widget> actions) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < actions.length; index++) ...[
        if (index > 0) const SizedBox(width: 4),
        actions[index],
      ],
    ],
  );

  Widget _editor(EditorDocument tab, FluentThemeData theme) {
    final view = _view(tab);
    return material.Theme(
      data: material.ThemeData(brightness: theme.brightness),
      child: CodeEditor(
        key: ValueKey(view.id),
        controller: view.controller,
        focusNode: view.focusNode,
        scrollController: view.scrollController,
        readOnly: _isBusy,
        leadingDivider: Container(
          width: 1,
          color: theme.inactiveColor.withValues(alpha: 0.35),
        ),
        hint: '开始输入…',
        wordWrap: false,
        style: CodeEditorStyle(
          fontSize: 15,
          fontFamily: 'JetBrainsMono',
          fontFamilyFallback: const ['JetBrains Mono', 'Menlo'],
          backgroundColor: theme.scaffoldBackgroundColor,
          textColor: theme.typography.body?.color,
          cursorColor: theme.accentColor.normal,
          codeTheme: syntaxThemeFor(tab.path, theme.brightness),
        ),
        indicatorBuilder: (context, controller, chunkController, notifier) =>
            DefaultCodeLineNumber(controller: controller, notifier: notifier),
      ),
    );
  }

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
    EditorDocument tab,
    FluentThemeData theme,
  ) => Column(
    children: [
      Expanded(child: _editor(tab, theme)),
      if (_mode == EditorMode.lightEdit) _statusBar(theme, tab),
    ],
  );

  Widget _statusBar(FluentThemeData theme, EditorDocument? tab) => Container(
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
        if (tab != null) ...[
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
            buttonBuilder: (_, onOpen) => _statusButton(tab.lineEnding, onOpen),
            items: [
              for (final lineBreak in TextLineBreak.values)
                MenuFlyoutItem(
                  text: Text(switch (lineBreak) {
                    TextLineBreak.lf => 'LF',
                    TextLineBreak.crlf => 'CRLF',
                    TextLineBreak.cr => 'CR',
                  }),
                  selected: lineBreak == tab.lineBreak,
                  onPressed: () => _changeLineBreak(tab, lineBreak),
                ),
            ],
          ),
          _statusSeparator(theme),
          FlyoutTarget(
            controller: _goToFlyout,
            child: AnimatedBuilder(
              animation: _view(tab).controller,
              builder: (context, child) {
                final selection = _view(tab).controller.selection;
                return _statusButton(
                  '第 ${selection.extentIndex + 1} 行，第 ${selection.extentOffset + 1} 列',
                  () => _goToPosition(tab),
                );
              },
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _workspaceFolder ?? '未选择文件夹',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            _mode == EditorMode.lightEdit ? 'LightEdit' : 'Workspace',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _workspaceContent(BuildContext context, FluentThemeData theme) {
    final folder = _workspaceFolder;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 44,
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  border: Border(
                    right: BorderSide(
                      color: theme.inactiveColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _actionIcon(
                    _showExplorer
                        ? system.FluentIcons.folder_20_filled
                        : system.FluentIcons.folder_20_regular,
                    _showExplorer ? '隐藏文件浏览器' : '显示文件浏览器',
                    _toggleExplorer,
                  ),
                ),
              ),
              if (_showExplorer)
                Focus(
                  focusNode: _explorerPanelFocusNode,
                  child: Container(
                    width: _explorerWidth.clamp(
                      180.0,
                      (MediaQuery.sizeOf(context).width - 220).clamp(
                        180.0,
                        600.0,
                      ),
                    ),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      border: Border(
                        right: BorderSide(
                          color: theme.inactiveColor.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 42,
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  '文件',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              _actionGroup([
                                _actionIcon(
                                  system.FluentIcons.folder_open_20_regular,
                                  '选择工作文件夹',
                                  _isBusy ? null : _selectWorkspaceFolder,
                                ),
                                _actionDropdown([
                                  MenuFlyoutItem(
                                    text: const Text('显示噪音文件和生成目录'),
                                    selected: _showExcluded,
                                    onPressed: _toggleExcluded,
                                  ),
                                  MenuFlyoutItem(
                                    text: const Text('撤销上次文件操作'),
                                    onPressed: _fileOperations.canUndo
                                        ? _undoExplorerOperation
                                        : null,
                                  ),
                                ]),
                              ]),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                        if (folder != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                Uri.file(folder).pathSegments.last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: theme.inactiveColor),
                              ),
                            ),
                          ),
                        Expanded(
                          child: folder == null
                              ? const Center(child: Text('尚未打开文件夹'))
                              : _explorerController.items.isEmpty
                              ? const Center(child: Text('这个文件夹是空的'))
                              : TreeView(
                                  controller: _explorerController,
                                  selectionMode: TreeViewSelectionMode.single,
                                  narrowSpacing: true,
                                  onSecondaryTap: (item, details) =>
                                      _showExplorerMenu(context, item, details),
                                  onItemExpandToggle: _expandExplorerItem,
                                  onItemInvoked: (item, reason) async {
                                    final entry = item.value;
                                    if (reason !=
                                        TreeViewItemInvokeReason.pressed) {
                                      return;
                                    }
                                    if (entry is File) {
                                      await _openWorkspaceFile(entry.path);
                                    } else if (entry is Directory) {
                                      if (item.expanded) {
                                        _explorerController.collapseItem(item);
                                      } else {
                                        final version = _explorerVersion;
                                        await _expandExplorerItem(item, true);
                                        if (mounted &&
                                            version == _explorerVersion) {
                                          _explorerController.expandItem(item);
                                        }
                                      }
                                    }
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_showExplorer)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    key: const ValueKey('explorer-resize-handle'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: _resizeExplorer,
                    child: const SizedBox(width: 6, height: double.infinity),
                  ),
                ),
              Expanded(
                child: _workspaceTabs.isEmpty
                    ? Center(
                        child: folder == null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('选择文件夹开始 Workspace 工作'),
                                  const SizedBox(height: 14),
                                  Button(
                                    onPressed: _isBusy
                                        ? null
                                        : _selectWorkspaceFolder,
                                    child: const Text('选择文件夹'),
                                  ),
                                ],
                              )
                            : const Text('从左侧文件树选择文件'),
                      )
                    : _editorTabs(context),
              ),
            ],
          ),
        ),
        _statusBar(theme, _workspaceTabs.isEmpty ? null : _activeTab),
      ],
    );
  }

  Widget _editorTabs(BuildContext context) => TabView(
    currentIndex: _activeIndex,
    shortcutsEnabled: true,
    tabWidthBehavior: TabWidthBehavior.sizeToContent,
    onChanged: (index) => setState(() {
      _activeIndex = index;
      _error = null;
    }),
    tabs: [for (final item in _tabs) _tabFor(context, item)],
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
          final workspaceFolder = _workspaceFolder;
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
                      const SizedBox(width: 18),
                      SizedBox(
                        height: 34,
                        child: DropDownButton(
                          title: Text(
                            _mode == EditorMode.lightEdit
                                ? 'LightEdit'
                                : 'Workspace',
                            style: const TextStyle(fontSize: 12),
                          ),
                          items: [
                            MenuFlyoutItem(
                              text: const Text('LightEdit'),
                              selected: _mode == EditorMode.lightEdit,
                              onPressed: () =>
                                  _switchMode(EditorMode.lightEdit),
                            ),
                            MenuFlyoutItem(
                              text: const Text('Workspace'),
                              selected: _mode == EditorMode.workspace,
                              onPressed: () =>
                                  _switchMode(EditorMode.workspace),
                            ),
                          ],
                        ),
                      ),
                      if (_mode == EditorMode.workspace) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 34,
                          child: Button(
                            onPressed: _isBusy
                                ? null
                                : workspaceFolder == null
                                ? _selectWorkspaceFolder
                                : _revealExplorer,
                            child: Text(
                              workspaceFolder == null
                                  ? '选择文件夹'
                                  : Uri.file(workspaceFolder).pathSegments.last,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      _actionGroup([
                        if (_mode == EditorMode.lightEdit) ...[
                          _actionIcon(
                            system.FluentIcons.add_20_regular,
                            '新建',
                            _isBusy ? null : _newTab,
                          ),
                          _actionIcon(
                            system.FluentIcons.folder_open_20_regular,
                            '打开',
                            _isBusy ? null : _openFile,
                          ),
                          _actionIcon(
                            system.FluentIcons.save_20_regular,
                            '保存',
                            _isBusy ? null : () => _save(context),
                          ),
                          _actionDropdown([
                            MenuFlyoutItem(
                              text: const Text('另存为'),
                              onPressed: _isBusy
                                  ? null
                                  : () => _save(context, saveAs: true),
                            ),
                          ]),
                        ],
                        _actionIcon(
                          theme.brightness == Brightness.dark
                              ? system.FluentIcons.weather_sunny_20_regular
                              : system.FluentIcons.weather_moon_20_regular,
                          theme.brightness == Brightness.dark
                              ? '切换亮色模式'
                              : '切换深色模式',
                          () => setState(
                            () =>
                                _themeMode = theme.brightness == Brightness.dark
                                ? ThemeMode.light
                                : ThemeMode.dark,
                          ),
                        ),
                      ]),
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
                  child: _mode == EditorMode.workspace
                      ? _workspaceContent(context, theme)
                      : _editorTabs(context),
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
