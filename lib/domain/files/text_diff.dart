String unifiedDiff(String original, String edited, {required String path}) {
  final a = _lines(original);
  final b = _lines(edited);
  if (_equal(a, b)) {
    return '';
  }
  final buf = StringBuffer();
  buf.writeln('--- $path');
  buf.writeln('+++ $path');
  final lcs = _lcs(a, b);
  var i = 0;
  var j = 0;
  var k = 0;
  while (i < a.length || j < b.length) {
    if (k < lcs.length && i < a.length && a[i] == lcs[k] && j < b.length && b[j] == lcs[k]) {
      buf.writeln(' ${a[i]}');
      i++;
      j++;
      k++;
      continue;
    }
    if (i < a.length && (k >= lcs.length || a[i] != lcs[k])) {
      buf.writeln('-${a[i]}');
      i++;
      continue;
    }
    if (j < b.length && (k >= lcs.length || b[j] != lcs[k])) {
      buf.writeln('+${b[j]}');
      j++;
    }
  }
  return buf.toString();
}

List<String> _lines(String text) {
  if (text.isEmpty) {
    return const [];
  }
  final parts = text.split('\n');
  if (parts.isNotEmpty && parts.last.isEmpty) {
    return parts.sublist(0, parts.length - 1);
  }
  return parts;
}

bool _equal(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

List<String> _lcs(List<String> a, List<String> b) {
  final m = a.length;
  final n = b.length;
  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }
  final out = <String>[];
  var i = m;
  var j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] == b[j - 1]) {
      out.add(a[i - 1]);
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return out.reversed.toList();
}
