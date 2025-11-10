import 'dart:io';

void main() {
  final dir = Directory('lib'); // your lib folder
  final dartFiles = dir
      .listSync(recursive: true)
      .where((f) => f is File && f.path.endsWith('.dart'))
      .map((f) => f as File);

  for (final file in dartFiles) {
    String content = file.readAsStringSync();
    String newContent = content;

    // Wrap async callbacks that use context
    final asyncPattern = RegExp(
      r'(async\s*{[^}]*?)(context\.[a-zA-Z0-9_]+\([^\)]*\))',
      multiLine: true,
    );
    newContent = newContent.replaceAllMapped(asyncPattern, (m) {
      final asyncBlock = m[1]!;
      final ctxCall = m[2]!;
      return '$asyncBlock if (!mounted) return; $ctxCall';
    });

    // Wrap findRenderObject usage
    final findRenderObjectPattern = RegExp(
      r'context\.findRenderObject\(\)',
      multiLine: true,
    );
    newContent = newContent.replaceAllMapped(findRenderObjectPattern, (m) {
      return 'mounted ? context.findRenderObject() : null';
    });

    // Wrap FocusScope.of(context)
    final focusScopePattern = RegExp(
      r'FocusScope\.of\(context\)',
      multiLine: true,
    );
    newContent = newContent.replaceAllMapped(focusScopePattern, (m) {
      return 'mounted ? FocusScope.of(context) : null';
    });

    // Wrap ScrollController.position / ScrollPosition access
    final scrollPattern = RegExp(
      r'([a-zA-Z0-9_]+)\.(position)',
      multiLine: true,
    );
    newContent = newContent.replaceAllMapped(scrollPattern, (m) {
      return 'mounted ? ${m[1]}.${m[2]} : null';
    });

    if (newContent != content) {
      file.writeAsStringSync(newContent);
      print('✅ Updated: ${file.path}');
    }
  }

  print('🎯 All Dart files scanned and guards added.');
}
