import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/main.dart';
import 'package:re_editor/re_editor.dart';

void main() {
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
