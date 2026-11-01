import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/syntax_highlighting.dart';

void main() {
  test('按文件名和扩展名选择 Re-Editor 高亮语言', () {
    expect(syntaxLanguageFor('/work/lib/main.dart'), 'dart');
    expect(syntaxLanguageFor('/work/app.tsx'), 'typescript');
    expect(syntaxLanguageFor('/work/README.md'), 'markdown');
    expect(syntaxLanguageFor('/work/Dockerfile'), 'dockerfile');
    expect(syntaxLanguageFor('/work/data.unknown'), isNull);
  });

  test('亮暗主题分别使用对应的高亮样式', () {
    final light = syntaxThemeFor('/work/main.py', Brightness.light);
    final dark = syntaxThemeFor('/work/main.py', Brightness.dark);
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.languages.keys, contains('python'));
    expect(light.theme, isNot(same(dark!.theme)));
  });
}
