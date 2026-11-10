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
///
/// A file included from inside a `server { }` (Ubuntu's
/// `include snippets/snakeoil.conf;`) is printed once, as its own section,
/// wherever nginx first opened it. Its top-level `listen`, `server_name`,
/// `root` and `ssl_certificate` belong to every vhost whose block (at the
/// server's own level) has a matching include, before or after the section.
///
/// Bounded for hostile input: at most [nginxMaxDepth] nested contexts (deeper
/// blocks are skipped and mark the dump truncated), [nginxMaxIncludes]
/// includes and [nginxMaxSections] sections matched against them.
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

  /// The dump ended (or a new section began) inside an open block, or a
  /// bound below was hit.
  final bool truncated;

  @override
  String toString() =>
      'NginxDumpResult(vhosts: $vhosts, '
      'errorLogPaths: $errorLogPaths, accessLogPaths: $accessLogPaths, '
      'truncated: $truncated)';
}

const _headerPrefix = 'configuration file ';

/// Max nested contexts (the include's context plus open blocks).
const nginxMaxDepth = 64;

/// Max `include` directives recorded.
const nginxMaxIncludes = 2000;

/// Max sections whose include context is looked up.
const nginxMaxSections = 2000;

/// Max server-level directives kept per section for vhosts that include it.
const _maxSectionDirectives = 1000;

/// Directives a file included at server level can give its vhost.
const _vhostDirectives = {'server_name', 'listen', 'root', 'ssl_certificate'};

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

  /// Its `}` was seen; a vhost cut by a new section or the end never is.
  bool closed = false;
}

class _Include {
  _Include(this.pattern, this.context, {this.vhost, this.section});
  final String pattern;
  final List<String> context;

  /// The vhost whose own level holds this include, if any.
  final _Block? vhost;

  /// The section (index) whose top level holds this include, if any.
  final int? section;
}

class _Section {
  _Section(this.file);
  final String file;

  /// Top-level [_vhostDirectives], in order.
  final directives = <List<String>>[];
}

/// Max entries per vhost list (names, listens, certs).
const _maxPerVhost = 256;

void _apply(_Block b, String name, List<String> args) {
  switch (name) {
    case 'server_name':
      for (final a in args) {
        if (b.serverNames.length < _maxPerVhost) b.serverNames.add(a);
      }
    case 'listen':
      if (args.isNotEmpty && b.listen.length < _maxPerVhost) {
        b.listen.add(args.join(' '));
        if (args.skip(1).contains('ssl')) b.tls = true;
      }
    case 'root':
      if (args.isNotEmpty) b.root ??= args.first;
    case 'ssl_certificate':
      if (args.isNotEmpty && b.certPaths.length < _maxPerVhost) {
        b.certPaths.add(args.first);
      }
  }
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
  final vhosts = <_Block>[];
  final errorLogs = <String>[];
  final accessLogs = <String>[];
  final includes = <_Include>[];
  final sections = <_Section>[];
  final stack = <_Block>[];
  var base = <String>[];
  var truncated = false;
  var currentFile = '';
  String? mainFile;
  // Blocks open past [nginxMaxDepth]: skipped whole.
  var skipDepth = 0;

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
    if (words.isEmpty || skipDepth > 0) return;
    final name = words.first;
    final args = words.sublist(1);
    if (name == 'error_log' && args.isNotEmpty) addLog(errorLogs, args.first);
    if (name == 'access_log' && args.isNotEmpty) {
      addLog(accessLogs, args.first);
    }
    if (name == 'include' && args.length == 1) {
      if (includes.length >= nginxMaxIncludes) {
        truncated = true;
      } else {
        var pattern = args.first;
        if (!pattern.startsWith('/') && mainFile != null) {
          pattern = '${_dirOf(mainFile!)}/$pattern';
        }
        final top = stack.isEmpty ? null : stack.last;
        includes.add(
          _Include(
            pattern,
            context(),
            vhost: top != null && top.vhost ? top : null,
            section: stack.isEmpty && sections.isNotEmpty
                ? sections.length - 1
                : null,
          ),
        );
      }
    }
    if (stack.isEmpty) {
      // Top level of an included file: kept for the vhosts including it.
      if (sections.isNotEmpty &&
          _vhostDirectives.contains(name) &&
          sections.last.directives.length < _maxSectionDirectives) {
        sections.last.directives.add(words);
      }
      return;
    }
    if (!stack.last.vhost) return;
    _apply(stack.last, name, args);
  }

  void startSection(String file) {
    // A header inside an open block or statement means the previous file's
    // text was cut.
    if (stack.isNotEmpty || words.isNotEmpty || inWord || skipDepth > 0) {
      truncated = true;
    }
    stack.clear();
    skipDepth = 0;
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
    if (sections.length >= nginxMaxSections) {
      // Past the bound: not matched, and its directives are not kept.
      truncated = true;
      return;
    }
    sections.add(_Section(file));
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
      if (skipDepth > 0 || base.length + stack.length >= nginxMaxDepth) {
        skipDepth++;
        truncated = true;
      } else {
        final name = words.isEmpty ? '?' : words.first;
        final isVhost =
            name == 'server' &&
            words.length == 1 &&
            base.length + stack.length == 1 &&
            (base.isEmpty ? stack.first.name : base.first) == 'http';
        final b = _Block(name, vhost: isVhost, sourceFile: currentFile);
        stack.add(b);
        if (isVhost) vhosts.add(b);
      }
      words = [];
      i++;
    } else if (c == 0x7d) {
      endWord();
      directive(); // a directive missing its ';' before '}'
      words = [];
      if (skipDepth > 0) {
        skipDepth--;
      } else if (stack.isNotEmpty) {
        stack.removeLast().closed = true;
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
  if (stack.isNotEmpty || skipDepth > 0) truncated = true;

  // A vhost cut by a new section or the end: only complete blocks count.
  final complete = [
    for (final v in vhosts)
      if (v.closed) v,
  ];
  if (!_attributeSections(sections, includes, complete.toSet())) {
    truncated = true;
  }

  return NginxDumpResult(
    vhosts: [
      for (final b in complete)
        WebVhost(
          serverNames: List.unmodifiable(b.serverNames),
          listen: List.unmodifiable(b.listen),
          tls: b.tls,
          root: b.root,
          certPath: b.certPaths.isEmpty ? null : b.certPaths.first,
          certPaths: List.unmodifiable(b.certPaths),
          sourceFile: b.sourceFile,
        ),
    ],
    errorLogPaths: errorLogs,
    accessLogPaths: accessLogs,
    truncated: truncated,
  );
}

/// Max rounds of include-inside-include followed from a vhost.
const _maxIncludeRounds = 8;

/// Steps (pattern matches, vhost links, directives applied) the attribution
/// may take; past it, it stops and the dump reads as truncated.
const _attributionBudget = 1000000;

/// Gives each section's top-level directives to every vhost that includes
/// it at its own level, directly or through up to [_maxIncludeRounds]
/// includes at the top level of other such sections. False when it stopped
/// at [_attributionBudget].
bool _attributeSections(
  List<_Section> sections,
  List<_Include> includes,
  Set<_Block> vhosts,
) {
  if (sections.isEmpty) return true;
  var budget = _attributionBudget;
  final owners = List.generate(sections.length, (_) => <_Block>{});
  // Direct: an include at a vhost's own level.
  final direct = [
    for (final inc in includes)
      if (inc.vhost != null && vhosts.contains(inc.vhost)) inc,
  ];
  final nested = [
    for (final inc in includes)
      if (inc.section != null) inc,
  ];
  if (direct.isEmpty) return true;
  for (var s = 0; s < sections.length; s++) {
    for (final inc in direct) {
      if (--budget < 0) return false;
      if (_globMatch(inc.pattern, sections[s].file)) owners[s].add(inc.vhost!);
    }
  }
  for (var round = 0; round < _maxIncludeRounds; round++) {
    var changed = false;
    for (final inc in nested) {
      final from = owners[inc.section!];
      if (from.isEmpty) continue;
      for (var s = 0; s < sections.length; s++) {
        if (--budget < 0) return false;
        if (s == inc.section || !_globMatch(inc.pattern, sections[s].file)) {
          continue;
        }
        budget -= from.length;
        if (budget < 0) return false;
        final before = owners[s].length;
        owners[s].addAll(from);
        if (owners[s].length != before) changed = true;
      }
    }
    if (!changed) break;
  }
  for (var s = 0; s < sections.length; s++) {
    for (final v in owners[s]) {
      for (final d in sections[s].directives) {
        if (--budget < 0) return false;
        _apply(v, d.first, d.sublist(1));
      }
    }
  }
  return true;
}
