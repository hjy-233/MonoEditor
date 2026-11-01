import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_editor/file_icons.dart';

void main() {
  testWidgets('JetBrains 图标按文件类型和文件夹名称匹配', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: Row(
          children: [
            JetBrainsFileIcon(name: 'main.dart', isDirectory: false),
            JetBrainsFileIcon(name: 'lib', isDirectory: true),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    final paths = pictures
        .map((picture) => (picture.bytesLoader as SvgAssetLoader).assetName)
        .toList();
    expect(paths, contains(contains('dart')));
    expect(paths, contains(contains('folder_framework')));
  });
}
