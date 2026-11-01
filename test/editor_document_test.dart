import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/editor_document.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('两个编辑器视图共享内容，但各自保留光标位置', () {
    final document = EditorDocument(id: 1, text: '第一行\n第二行');
    var nextId = 1;
    final light = document.viewFor(EditorMode.lightEdit, () => nextId++);
    final workspace = document.viewFor(EditorMode.workspace, () => nextId++);
    final secondWorkspace = document.createView(
      EditorMode.workspace,
      () => nextId++,
    );
    expect(light.id, isNot(workspace.id));
    expect(workspace.id, isNot(secondWorkspace.id));
    expect(light.controller, isNot(same(workspace.controller)));

    light.controller.selection = CodeLineSelection.collapsed(
      index: 1,
      offset: 2,
    );
    workspace.controller.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: 1,
    );
    light.controller.replaceSelection('！');
    expect(workspace.controller.text, light.controller.text);
    expect(workspace.controller.selection.extentIndex, 0);
    expect(workspace.controller.selection.extentOffset, 1);
    expect(secondWorkspace.controller.text, light.controller.text);
    expect(document.isDirty, isTrue);

    workspace.controller.replaceSelection('新');
    expect(light.controller.text, workspace.controller.text);
    expect(secondWorkspace.controller.text, workspace.controller.text);
    expect(light.controller.selection.extentIndex, 1);

    workspace.controller.selection = CodeLineSelection.collapsed(
      index: 1,
      offset: 2,
    );
    light.controller.text = '短';
    expect(workspace.controller.text, '短');
    expect(workspace.controller.selection.extentIndex, 0);
    expect(workspace.controller.selection.extentOffset, 1);
    document.dispose();
  });
}
