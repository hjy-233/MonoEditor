import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/main.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('编辑状态刷新时保留 Tab 实例和输入焦点', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    final tab = tester.widget<Tab>(find.byType(Tab).first);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final focusNode = editor.focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    editor.controller!.text = '正在编辑';
    await tester.pump();
    expect(tester.widget<Tab>(find.byType(Tab).first), same(tab));
    expect(focusNode.hasFocus, isTrue);
    expect(find.text('临时文档 ●'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('切换到空 Workspace 后返回 LightEdit 保留文档和光标', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    final light = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller!;
    light.text = '第一行\n第二行';
    light.selection = CodeLineSelection.collapsed(index: 1, offset: 1);
    await tester.pump();

    await tester.tap(find.text('LightEdit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();
    expect(find.byType(CodeEditor), findsNothing);
    expect(find.text('MonoEditor'), findsOneWidget);
    expect(find.text('未选择文件夹'), findsOneWidget);
    expect(find.text('选择文件夹开始 Workspace 工作'), findsOneWidget);
    expect(find.byTooltip('保存'), findsNothing);
    expect(find.byTooltip('新建'), findsNothing);

    await tester.tap(find.text('Workspace').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('LightEdit').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller,
      same(light),
    );
    expect(light.selection.extentIndex, 1);
    expect(find.text('临时文档 ●'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Workspace 保留顶栏和状态栏，不显示文件操作按钮', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    await tester.tap(find.text('LightEdit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();

    expect(find.text('MonoEditor'), findsOneWidget);
    expect(find.text('未选择文件夹'), findsOneWidget);
    expect(find.text('Workspace'), findsNWidgets(2));
    expect(find.byTooltip('保存'), findsNothing);
    expect(find.byTooltip('新建'), findsNothing);
    expect(find.byIcon(FluentIcons.more), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Workspace 左侧文件浏览器可以收起并重新显示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    await tester.tap(find.text('LightEdit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();

    expect(find.text('文件'), findsOneWidget);
    await tester.tap(find.byTooltip('隐藏文件浏览器'));
    await tester.pumpAndSettle();
    expect(find.text('文件'), findsNothing);
    await tester.tap(find.byTooltip('显示文件浏览器'));
    await tester.pumpAndSettle();
    expect(find.text('文件'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Workspace Explorer 宽度可拖动调整', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    await tester.tap(find.text('LightEdit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey('explorer-resize-handle'));
    final before = tester.getTopLeft(handle).dx;
    await tester.drag(handle, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(handle).dx, greaterThan(before + 70));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('状态栏可切换编码与换行符并跳转行列', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    final first = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller!;
    first.text = '第一行\n第二行';
    await tester.pump();

    await tester.tap(find.text('UTF-8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UTF-8 BOM'));
    await tester.pumpAndSettle();
    expect(find.text('UTF-8 BOM'), findsOneWidget);

    await tester.tap(find.text('LF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CRLF'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller!;
    expect(controller, same(first));
    expect(controller.text, '第一行\n第二行');
    expect(find.text('CRLF'), findsOneWidget);

    await tester.tap(find.text('第 1 行，第 1 列'));
    await tester.pumpAndSettle();
    final field = find.byType(TextBox);
    expect(field, findsOneWidget);
    expect(tester.getSize(field).height, lessThanOrEqualTo(40));
    await tester.enterText(field, '2:2');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.selection.extentIndex, 1);
    expect(controller.selection.extentOffset, 1);
    expect(find.text('第 2 行，第 2 列'), findsOneWidget);
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode?.hasFocus,
      isTrue,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('切换换行符后保留编辑撤销历史', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    final controller = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller!;
    controller.replaceSelection('内容');
    expect(controller.canUndo, isTrue);

    await tester.tap(find.text('LF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CRLF'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller,
      same(controller),
    );
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.text, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('LightEdit 的标签保留各自内容，关闭未保存标签会先确认', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    await tester.pump(const Duration(milliseconds: 120));
    final first = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller!;
    first.text = '第一份内容';
    await tester.pump();
    expect(find.text('临时文档 ●'), findsOneWidget);

    await tester.tap(find.byTooltip('新建'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final second = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller!;
    expect(second, isNot(same(first)));
    second.text = '第二份内容';
    await tester.pump();
    expect(find.text('临时文档 ●'), findsNWidgets(2));

    await tester.tap(find.text('临时文档 ●').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller,
      same(first),
    );
    expect(first.text, '第一份内容');

    tester.widgetList<Tab>(find.byType(Tab)).first.onClosed!();
    await tester.pump();
    expect(find.text('临时文档 尚未保存'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('临时文档 ●'), findsNWidgets(2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('切换亮色和暗色主题', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const MonoEditorApp());
    expect(find.byType(CodeEditor), findsOneWidget);
    final themeButton = find.byTooltip('切换亮色模式').evaluate().isNotEmpty
        ? find.byTooltip('切换亮色模式')
        : find.byTooltip('切换深色模式');
    final initialBrightness = FluentTheme.of(
      tester.element(themeButton),
    ).brightness;
    final controller = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .controller;
    expect(controller, isNotNull);
    controller!.text = '你好，MonoEditor';

    await tester.tap(themeButton);
    await tester.pumpAndSettle();
    expect(
      FluentTheme.of(tester.element(find.byType(CodeEditor))).brightness,
      initialBrightness == Brightness.dark ? Brightness.light : Brightness.dark,
    );
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller,
      same(controller),
    );
    expect(controller.text, '你好，MonoEditor');
    debugDefaultTargetPlatformOverride = null;
  });
}
