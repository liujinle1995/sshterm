/// 远端目录里的一项。
///
/// 刻意不直接暴露 dartssh2 的 `SftpName` / `SftpFileAttrs`：SFTP 层换实现、
/// 或者预览/测试用假文件树时，UI 不该跟着动。权限位在这里已经拍成
/// `-rw-r--r--` 这种字符串了。
enum RemoteEntryType { directory, file, symlink, other }

class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.type,
    this.size = 0,
    this.modifiedAt,
    this.permissions = '',
  });

  final String name;

  /// 绝对路径，点进去/下载/删除都用它，省得到处拼
  final String path;

  final RemoteEntryType type;

  final int size;

  final DateTime? modifiedAt;

  /// `ls -l` 那一列，拿不到就是空串
  final String permissions;

  bool get isDirectory => type == RemoteEntryType.directory;

  bool get isSymlink => type == RemoteEntryType.symlink;

  bool get isHidden => name.startsWith('.');

  bool get isTextLike {
    final lower = name.toLowerCase();
    return const <String>[
      '.txt',
      '.md',
      '.log',
      '.json',
      '.yaml',
      '.yml',
      '.toml',
      '.ini',
      '.conf',
      '.cfg',
      '.sh',
      '.bash',
      '.zsh',
      '.sql',
      '.csv',
      '.xml',
      '.html',
      '.css',
      '.js',
      '.ts',
      '.py',
      '.dart',
      '.go',
      '.rs',
      '.java',
      '.c',
      '.h',
      '.cpp',
      '.service',
    ].any(lower.endsWith);
  }

  /// `1.4 MB` 这种人类可读的写法
  String get sizeLabel => formatBytes(size);

  /// `2026-10-14 16:20`；没有 mtime 就留空
  String get modifiedLabel => modifiedAt == null ? '' : formatTime(modifiedAt!);

  static String formatBytes(int bytes) {
    if (bytes < 0) return '-';
    if (bytes < 1024) return '$bytes B';
    const units = <String>['KB', 'MB', 'GB', 'TB', 'PB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    // 小于 10 的留一位小数（1.4 MB），大了就不必（123 MB），跟 `ls -h` 的手感一致
    final text = value < 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(0);
    return '$text ${units[unit]}';
  }

  static String formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
