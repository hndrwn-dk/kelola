import 'web_lens.dart';

/// M52: parses the output of `nginx -T`. Pure and total: the dump comes from
/// the host, so nothing here throws or backtracks on hostile input.
class NginxDumpResult {
  const NginxDumpResult({
    this.vhosts = const [],
    this.errorLogPaths = const [],
    this.accessLogPaths = const [],
    this.truncated = false,
  });

  final List<WebVhost> vhosts;
  final List<String> errorLogPaths;
  final List<String> accessLogPaths;

  /// The dump ended inside an open block.
  final bool truncated;

  @override
  String toString() =>
      'NginxDumpResult(vhosts: $vhosts, '
      'errorLogPaths: $errorLogPaths, accessLogPaths: $accessLogPaths, '
      'truncated: $truncated)';
}

const _headerPrefix = 'configuration file ';

class _Block {
  _Block(this.name, this.sourceFile);
  final String name;
  final String sourceFile;
  final serverNames = <String>[];
  final listen = <String>[];
  bool tls = false;
  String? root;
  String? certPath;
}

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0x0b || c == 0x0c;

NginxDumpResult parseNginxDump(String dump) {
  final vhosts = <WebVhost>[];
  final errorLogs = <String>[];
  final accessLogs = <String>[];
  final stack = <_Block>[];
  var currentFile = '';

  var words = <String>[];
  final word = StringBuffer();
  var inWord = false;
  // File in effect when the first word of the current statement began.
  var stmtFile = '';

  void endWord() {
    if (inWord) {
      if (words.isEmpty) stmtFile = currentFile;
      words.add(word.toString());
      word.clear();
      inWord = false;
    }
  }

  void addLog(List<String> into, String p) {
    if (p.isEmpty || p == 'off' || p == 'stderr') return;
    if (p.startsWith('syslog:') || p.startsWith('memory:')) return;
    if (p.contains(r'$')) return;
    if (!into.contains(p)) into.add(p);
  }

  void directive() {
    if (words.isEmpty) return;
    final name = words.first;
    final args = words.sublist(1);
    if (name == 'error_log' && args.isNotEmpty) addLog(errorLogs, args.first);
    if (name == 'access_log' && args.isNotEmpty) {
      addLog(accessLogs, args.first);
    }
    if (stack.isEmpty) return;
    final top = stack.last;
    if (top.name != 'server' || stack.length < 2) return;
    switch (name) {
      case 'server_name':
        top.serverNames.addAll(args);
      case 'listen':
        if (args.isNotEmpty) {
          top.listen.add(args.join(' '));
          if (args.skip(1).contains('ssl')) top.tls = true;
        }
      case 'root':
        if (args.isNotEmpty) top.root ??= args.first;
      case 'ssl_certificate':
        if (args.isNotEmpty) top.certPath ??= args.first;
    }
  }

  final n = dump.length;
  var i = 0;
  var lineStart = true; // only whitespace seen so far on this line
  while (i < n) {
    final c = dump.codeUnitAt(i);
    if (c == 0x0a) {
      lineStart = true;
      endWord();
      i++;
      continue;
    }
    if (_isSpace(c)) {
      endWord();
      i++;
      continue;
    }
    if (c == 0x23 && !inWord) {
      // Comment to end of line.
      var j = i + 1;
      while (j < n && dump.codeUnitAt(j) != 0x0a) {
        j++;
      }
      if (lineStart && j - i < 4096) {
        final text = dump.substring(i + 1, j).trim();
        if (text.startsWith(_headerPrefix) && text.endsWith(':')) {
          currentFile = text
              .substring(_headerPrefix.length, text.length - 1)
              .trim();
        }
      }
      i = j;
      continue;
    }
    lineStart = false;
    if (c == 0x3b) {
      // ;
      endWord();
      directive();
      words = [];
      i++;
    } else if (c == 0x7b) {
      // {
      endWord();
      final name = words.isEmpty ? '' : words.first;
      final parent = stack.isEmpty ? '' : stack.last.name;
      // Only a server directly under http keeps its identity.
      final isVhost = name == 'server' && parent == 'http';
      stack.add(
        _Block(isVhost ? 'server' : (name.isEmpty ? '?' : name), stmtFile),
      );
      words = [];
      i++;
    } else if (c == 0x7d) {
      // }
      endWord();
      directive(); // a directive missing its ';' before '}'
      words = [];
      if (stack.isNotEmpty) {
        final b = stack.removeLast();
        if (b.name == 'server' &&
            stack.isNotEmpty &&
            stack.last.name == 'http') {
          vhosts.add(
            WebVhost(
              serverNames: List.unmodifiable(b.serverNames),
              listen: List.unmodifiable(b.listen),
              tls: b.tls,
              root: b.root,
              certPath: b.certPath,
              sourceFile: b.sourceFile,
            ),
          );
        }
      }
      i++;
    } else if (c == 0x22 || c == 0x27) {
      // quoted segment, part of the current word
      if (!inWord) {
        inWord = true;
        if (words.isEmpty) stmtFile = currentFile;
      }
      var j = i + 1;
      while (j < n) {
        final d = dump.codeUnitAt(j);
        if (d == 0x5c && j + 1 < n) {
          word.writeCharCode(dump.codeUnitAt(j + 1));
          j += 2;
          continue;
        }
        if (d == c) break;
        word.writeCharCode(d);
        j++;
      }
      i = j + 1;
    } else if (c == 0x24 && i + 1 < n && dump.codeUnitAt(i + 1) == 0x7b) {
      // ${var}: not a block
      if (!inWord) {
        inWord = true;
        if (words.isEmpty) stmtFile = currentFile;
      }
      var j = i;
      while (j < n && dump.codeUnitAt(j) != 0x7d) {
        word.writeCharCode(dump.codeUnitAt(j));
        j++;
      }
      if (j < n) word.writeCharCode(0x7d);
      i = j + 1;
    } else {
      if (!inWord) {
        inWord = true;
        if (words.isEmpty) stmtFile = currentFile;
      }
      if (c == 0x5c && i + 1 < n) {
        word.writeCharCode(dump.codeUnitAt(i + 1));
        i += 2;
      } else {
        word.writeCharCode(c);
        i++;
      }
    }
  }
  endWord();

  return NginxDumpResult(
    vhosts: vhosts,
    errorLogPaths: errorLogs,
    accessLogPaths: accessLogs,
    truncated: stack.isNotEmpty,
  );
}
