import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

const _aliases = <String, String>{
  'adoc': 'asciidoc',
  'bat': 'dos',
  'cc': 'cpp',
  'cjs': 'javascript',
  'clj': 'clojure',
  'cls': 'latex',
  'coffee': 'coffeescript',
  'cs': 'csharp',
  'cxx': 'cpp',
  'ex': 'elixir',
  'exs': 'elixir',
  'fs': 'fsharp',
  'fsx': 'fsharp',
  'h': 'c',
  'hpp': 'cpp',
  'htm': 'xml',
  'html': 'xml',
  'ipynb': 'json',
  'java': 'java',
  'js': 'javascript',
  'jsonc': 'json',
  'jsx': 'javascript',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'less': 'less',
  'm': 'objectivec',
  'md': 'markdown',
  'mdx': 'markdown',
  'mjs': 'javascript',
  'mm': 'objectivec',
  'mli': 'ocaml',
  'patch': 'diff',
  'pl': 'perl',
  'ps1': 'powershell',
  'py': 'python',
  'rake': 'ruby',
  'rb': 'ruby',
  'rs': 'rust',
  'sass': 'scss',
  'sh': 'bash',
  'sql': 'sql',
  'svelte': 'xml',
  'tex': 'latex',
  'toml': 'ini',
  'ts': 'typescript',
  'tsx': 'typescript',
  'txt': 'plaintext',
  'vue': 'vue',
  'xhtml': 'xml',
  'yml': 'yaml',
  'zsh': 'bash',
};

const _fileNames = <String, String>{
  'dockerfile': 'dockerfile',
  'gemfile': 'ruby',
  'makefile': 'makefile',
  'cmakelists.txt': 'cmake',
  '.bashrc': 'bash',
  '.zshrc': 'bash',
  '.gitignore': 'plaintext',
};

String? syntaxLanguageFor(String? path) {
  if (path == null) return null;
  final name = Uri.file(path).pathSegments.last.toLowerCase();
  final named = _fileNames[name];
  if (named != null) return named;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final extension = name.substring(dot + 1);
  final language = _aliases[extension] ?? extension;
  return builtinAllLanguages.containsKey(language) ? language : null;
}

final _lightThemes = <String, CodeHighlightTheme>{};
final _darkThemes = <String, CodeHighlightTheme>{};

CodeHighlightTheme? syntaxThemeFor(String? path, Brightness brightness) {
  final language = syntaxLanguageFor(path);
  if (language == null) return null;
  final mode = builtinAllLanguages[language];
  if (mode == null) return null;
  final cache = brightness == Brightness.dark ? _darkThemes : _lightThemes;
  return cache.putIfAbsent(
    language,
    () => CodeHighlightTheme(
      languages: {language: CodeHighlightThemeMode(mode: mode)},
      theme: brightness == Brightness.dark
          ? atomOneDarkTheme
          : atomOneLightTheme,
    ),
  );
}
