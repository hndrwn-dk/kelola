import 'web_lens.dart';

/// M52: parses the output of `nginx -T`. Pure and total: the dump comes from
/// the host, so nothing here throws or backtracks on hostile input.
///
/// Real `nginx -T` prints every configuration file as its own section
/// (`# configuration file <path>:`) and leaves `include` directives literal.
/// An included file's top-level `server { }` therefore sits at brace depth 0
/// in the dump, and its true context is that of the `include` that pulled it
/// in. The parser records each include with its full context and gives every
/// later section the context of the first include whose pattern matches it.
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

  /// The dump ended (or a new section began) inside an open block.
  final bool truncated;

  @override
  String toString() =>
      'NginxDumpResult(vhosts: $vhosts, '
      'errorLogPaths: $errorLogPaths, accessLogPaths: $accessLogPaths, '
      'truncated: $truncated)';
}

const _headerPrefix = 'configuration file ';

class _Block {
  _Block(this.name, {required this.vhost, required this.sourceFile});
  final String name;
  final bool vhost;
  final String sourceFile;
  final serverNames = <String>[];
  final listen = <String>[];
  final certPaths = <String>[];
  bool tls = false;
  String? root;
}

class _Include {
  _Include(this.pattern, this.context);
  final String pattern;
  final List<String> context;
}

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0x0b || c == 0x0c;

/// `*` matches any run of characters except `/`. Iterative, no regex.
bool _segmentMatch(String p, String s) {
  var pi = 0, si = 0, star = -1, mark = 0;
  while (si < s.length) {
    if (pi < p.length && p[pi] == '*') {
      star = pi++;
      mark = si;
    } else if (pi < p.length && p[pi] == s[si]) {
      pi++;
      si++;
    } else if (star >= 0) {
      pi = star + 1;
      si = ++mark;
    } else {
      return false;
    }
  }
  while (pi < p.length && p[pi] == '*') {
    pi++;
  }
  return pi == p.length;
}

bool _globMatch(String pattern, String path) {
  final ps = pattern.split('/');
  final xs = path.split('/');
  if (ps.length != xs.length) return false;
  for (var i = 0; i < ps.length; i++) {
    if (!_segmentMatch(ps[i], xs[i])) return false;
  }
  return true;
}

String _dirOf(String file) {
  final i = file.lastIndexOf('/');
  return i <= 0 ? '' : file.substring(0, i);
}

NginxDumpResult parseNginxDump(String dump) {
  final vhosts = <WebVhost>[];
  final errorLogs = <String>[];
  final accessLogs = <String>[];
  final includes = <_Include>[];
  final stack = <_Block>[];
  var base = <String>[];
  var truncated = false;
  var currentFile = '';
  String? mainFile;

  var words = <String>[];
  final word = StringBuffer();
  var inWord = false;

  void endWord() {
    if (inWord) {
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

  List<String> context() => [...base, ...stack.map((b) => b.name)];

  void directive() {
    if (words.isEmpty) return;
    final name = words.first;
    final args = words.sublist(1);
    if (name == 'error_log' && args.isNotEmpty) addLog(errorLogs, args.first);
    if (name == 'access_log' && args.isNotEmpty) {
      addLog(accessLogs, args.first);
    }
    if (name == 'include' && args.length == 1) {
      var pattern = args.first;
      if (!pattern.startsWith('/') && mainFile != null) {
        pattern = '${_dirOf(mainFile!)}/$pattern';
      }
      includes.add(_Include(pattern, context()));
    }
    if (stack.isEmpty || !stack.last.vhost) return;
    final top = stack.last;
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
        if (args.isNotEmpty) top.certPaths.add(args.first);
    }
  }

  void startSection(String file) {
    // A header inside an open block or statement means the previous file's
    // text was cut.
    if (stack.isNotEmpty || words.isNotEmpty || inWord) truncated = true;
    stack.clear();
    words = [];
    word.clear();
    inWord = false;
    currentFile = file;
    if (mainFile == null) {
      mainFile = file;
      base = [];
      return;
    }
    base = ['http'];
    for (final inc in includes) {
      if (_globMatch(inc.pattern, file)) {
        base = inc.context;
        break;
      }
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
    if (lineStart &&
        !inWord &&
        words.isEmpty &&
        c == 0x6e &&
        dump.startsWith('nginx:', i)) {
      // `nginx: ... syntax is ok` stderr preamble.
      while (i < n && dump.codeUnitAt(i) != 0x0a) {
        i++;
      }
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
          startSection(
            text.substring(_headerPrefix.length, text.length - 1).trim(),
          );
        }
      }
      i = j;
      continue;
    }
    lineStart = false;
    if (c == 0x3b) {
      endWord();
      directive();
      words = [];
      i++;
    } else if (c == 0x7b) {
      endWord();
      final name = words.isEmpty ? '?' : words.first;
      final isVhost =
          name == 'server' &&
          words.length == 1 &&
          context().length == 1 &&
          context().first == 'http';
      stack.add(_Block(name, vhost: isVhost, sourceFile: currentFile));
      words = [];
      i++;
    } else if (c == 0x7d) {
      endWord();
      directive(); // a directive missing its ';' before '}'
      words = [];
      if (stack.isNotEmpty) {
        final b = stack.removeLast();
        if (b.vhost) {
          vhosts.add(
            WebVhost(
              serverNames: List.unmodifiable(b.serverNames),
              listen: List.unmodifiable(b.listen),
              tls: b.tls,
              root: b.root,
              certPath: b.certPaths.isEmpty ? null : b.certPaths.first,
              certPaths: List.unmodifiable(b.certPaths),
              sourceFile: b.sourceFile,
            ),
          );
        }
      }
      i++;
    } else if ((c == 0x22 || c == 0x27) && !inWord) {
      // Quoted token (quotes are special only at token start, as in nginx).
      inWord = true;
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
      // ${var}: not a block. The scan stops at structure so it cannot hide it.
      inWord = true;
      word.write(r'${');
      var j = i + 2;
      while (j < n) {
        final d = dump.codeUnitAt(j);
        if (_isSpace(d) || d == 0x3b || d == 0x7b) break;
        word.writeCharCode(d);
        j++;
        if (d == 0x7d) break;
      }
      i = j;
    } else {
      inWord = true;
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
  if (stack.isNotEmpty) truncated = true;

  return NginxDumpResult(
    vhosts: vhosts,
    errorLogPaths: errorLogs,
    accessLogPaths: accessLogs,
    truncated: truncated,
  );
}
