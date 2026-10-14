/// 远端的 POSIX 路径工具。
///
/// 不引 `package:path`：远端永远是 `/` 分隔，跟运行 App 的平台无关；
/// 直接用它默认的 `context` 会在 Windows 上判断出错，而 `p.posix` 又要多背一个
/// 传递依赖（还是别人带上来的）。这里的规则一共就这几条，自己写反而更好测。
class RemotePath {
  const RemotePath._();

  /// 把 [path] 规范化：拆成段、去掉空段和 `.`、处理 `..`。
  ///
  /// 结果一定以 `/` 开头（没有结尾的 `/`，根目录除外）。
  static String normalize(String path) {
    final isAbsolute = path.startsWith('/');
    final out = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        // 已经到顶了再 `..` 就停在根上，跟 POSIX 一致
        if (out.isNotEmpty && out.last != '..') {
          out.removeLast();
        } else if (!isAbsolute) {
          out.add('..');
        }
        continue;
      }
      out.add(segment);
    }
    if (isAbsolute) return out.isEmpty ? '/' : '/${out.join('/')}';
    return out.isEmpty ? '.' : out.join('/');
  }

  /// 拼两段。`b` 是绝对路径时直接返回它（跟 `path.join` 的语义一致）。
  static String join(String a, String b) {
    if (b.startsWith('/')) return normalize(b);
    return normalize('$a/$b');
  }

  /// 取父目录。根目录的父目录还是根目录（不然界面会跳到空字符串）。
  static String parent(String path) {
    final normalized = normalize(path);
    if (normalized == '/' || normalized == '.') return normalized;
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return '/';
    return normalized.substring(0, index);
  }

  /// 取最后一段。根目录返回 `/`。
  static String basename(String path) {
    final normalized = normalize(path);
    if (normalized == '/') return '/';
    final index = normalized.lastIndexOf('/');
    return normalized.substring(index + 1);
  }

  /// 面包屑要用的各层：`/a/b/c` → `['/', '/a', '/a/b', '/a/b/c']`。
  ///
  /// 直接给绝对路径而不是名字，点哪一层就跳哪一层，省得在 UI 里再拼一次。
  static List<String> crumbs(String path) {
    final normalized = normalize(path);
    // `.` 是"相对路径且已经到底"，在面包屑里等同于根
    if (normalized == '/' || normalized == '.') return const <String>['/'];
    final parts = normalized.split('/').where((String s) => s.isNotEmpty);
    final out = <String>['/'];
    var cursor = '';
    for (final part in parts) {
      cursor = '$cursor/$part';
      out.add(cursor);
    }
    return out;
  }

  /// 两段路径是不是同一个位置（用来判断"切目录时要不要重新读盘"）
  static bool same(String a, String b) => normalize(a) == normalize(b);
}
