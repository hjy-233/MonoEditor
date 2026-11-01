import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class JetBrainsFileIcon extends StatelessWidget {
  const JetBrainsFileIcon({
    required this.name,
    required this.isDirectory,
    this.size = 16,
    super.key,
  });

  final String name;
  final bool isDirectory;
  final double size;

  static final Future<_IconTheme> _light = _IconTheme.load('light');
  static final Future<_IconTheme> _dark = _IconTheme.load('dark');

  @override
  Widget build(BuildContext context) {
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    return FutureBuilder<_IconTheme>(
      future: dark ? _dark : _light,
      builder: (context, snapshot) {
        final path = snapshot.data?.pathFor(name, isDirectory);
        if (path == null) return SizedBox(width: size, height: size);
        return SvgPicture.asset(path, width: size, height: size);
      },
    );
  }
}

class _IconTheme {
  _IconTheme(
    this.definitions,
    this.fileNames,
    this.fileExtensions,
    this.folderNames,
    this.file,
    this.folder,
  );

  final Map<String, String> definitions;
  final Map<String, String> fileNames;
  final Map<String, String> fileExtensions;
  final Map<String, String> folderNames;
  final String file;
  final String folder;

  static Future<_IconTheme> load(String brightness) async {
    final source = await rootBundle.loadString(
      'assets/jetbrains_icons/$brightness.json',
    );
    final json = jsonDecode(source) as Map<String, dynamic>;
    final paths = (json['iconDefinitions'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        'assets/jetbrains_icons/${(value as Map<String, dynamic>)['iconPath'].toString().substring(2)}',
      ),
    );
    Map<String, String> names(String key) => (json[key] as Map<String, dynamic>)
        .map((name, value) => MapEntry(name.toLowerCase(), value as String));
    return _IconTheme(
      paths,
      names('fileNames'),
      names('fileExtensions'),
      names('folderNames'),
      json['file'] as String,
      json['folder'] as String,
    );
  }

  String? pathFor(String name, bool isDirectory) {
    final lower = name.toLowerCase();
    String? key;
    if (isDirectory) {
      key = folderNames[lower] ?? folder;
    } else {
      key = fileNames[lower];
      if (key == null) {
        var dot = lower.indexOf('.');
        while (dot >= 0) {
          key = fileExtensions[lower.substring(dot + 1)];
          if (key != null) break;
          dot = lower.indexOf('.', dot + 1);
        }
      }
      key ??= file;
    }
    return definitions[key];
  }
}
