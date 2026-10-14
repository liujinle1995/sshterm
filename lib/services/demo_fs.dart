import 'dart:convert';
import 'dart:typed_data';

import '../models/remote_entry.dart';
import 'remote_fs.dart';
import 'remote_path.dart';

/// 内存里的假文件树。**只给预览截图和 widget 测试用**，生产路径上不会出现。
///
/// 存在的理由：SFTP 页面要能渲染、要能被点，而这两件事都不该依赖一台真的
/// Linux。真正跟协议打交道的部分在 [SftpFs] 里，那一层是真的。
class DemoFs implements RemoteFs {
  DemoFs({this.label = 'root@192.168.1.20', bool seed = true}) {
    if (seed) _seed();
  }

  @override
  final String label;

  final Map<String, RemoteEntry> _nodes = <String, RemoteEntry>{};
  final Map<String, Uint8List> _contents = <String, Uint8List>{};

  /// 测试用：设了它，下一次操作就抛这个异常，用来验证错误提示
  Object? failNext;

  void _maybeFail() {
    final error = failNext;
    if (error == null) return;
    failNext = null;
    throw error;
  }

  // ------------------------------------------------------------------ 种子数据

  void _seed() {
    // `/` 本身不建节点：它会是自己的父目录，children 计算会把自己也算进去。
    // list() 里对根目录单独处理。
    _dir('/home');
    _dir('/proc');
    _dir('/home/lele');
    _dir('/home/lele/projects');
    _dir('/home/lele/projects/sshterm');
    _dir('/home/lele/logs');
    _dir('/home/lele/.ssh');
    _dir('/home/lele/.config');
    _dir('/etc');
    _dir('/etc/nginx');
    _dir('/var');
    _dir('/var/log');

    _file('/home/lele/.bashrc', 3124, '-rw-r--r--');
    _file('/home/lele/.ssh/authorized_keys', 742, '-rw-------');
    _file('/home/lele/.ssh/id_ed25519.pub', 96, '-rw-r--r--');
    _file('/home/lele/notes.md', 2860, '-rw-r--r--');
    _file('/home/lele/deploy.sh', 1480, '-rwxr-xr-x');
    _file('/home/lele/backup-2026-10-12.tar.gz', 48234048, '-rw-r--r--');
    _file('/home/lele/projects/sshterm/pubspec.yaml', 902, '-rw-r--r--');
    _file('/home/lele/projects/sshterm/README.md', 4310, '-rw-r--r--');
    _file('/home/lele/logs/app.log', 1331200, '-rw-r--r--');
    _file('/home/lele/logs/nginx.access.log', 8292000, '-rw-r--r--');
    _file('/etc/nginx/nginx.conf', 2210, '-rw-r--r--');
    _file('/etc/hosts', 221, '-rw-r--r--');
    _file('/var/log/syslog', 512000, '-rw-r-----');
    _link('/etc/mtab', '/proc/mounts');

    _contents['/home/lele/notes.md'] = Uint8List.fromList(
      utf8.encode('''
# 部署笔记

## 上线流程
1. `./deploy.sh build` 出包
2. `systemctl restart sshterm` 重启服务
3. 看 `/home/lele/logs/app.log` 确认没有异常栈

## 常用排查
- 端口占用：`ss -lntp | grep 8080`
- 磁盘满：`df -h` / `du -sh /var/log/*`
- 昨天那次 OOM 是 `backup-*.tar.gz` 在 /home 下堆了 46G

> 记住：改完 nginx.conf 先 `nginx -t` 再 reload。
'''),
    );

    _contents['/home/lele/deploy.sh'] = Uint8List.fromList(
      utf8.encode('''#!/usr/bin/env bash
set -euo pipefail

TARGET="\${1:-build}"

case "\$TARGET" in
  build)
    flutter build apk --release
    ;;
  deploy)
    rsync -avz build/app/outputs/flutter-apk/app-release.apk \\
      prod:/srv/sshterm/
    systemctl restart sshterm
    ;;
esac
'''),
    );

    _contents['/home/lele/projects/sshterm/README.md'] = Uint8List.fromList(
      utf8.encode('''# sshterm

极简 SSH 终端。多标签会话 + SFTP + 可缩放终端。
'''),
    );

    _contents['/etc/hosts'] = Uint8List.fromList(
      utf8.encode('127.0.0.1\tlocalhost\n::1\tlocalhost\n10.0.10.20\tprod\n'),
    );
  }

  void _dir(String path) {
    final normalized = RemotePath.normalize(path);
    _nodes[normalized] = RemoteEntry(
      name: RemotePath.basename(normalized),
      path: normalized,
      type: RemoteEntryType.directory,
      modifiedAt: DateTime(2026, 10, 14, 15, 32),
      permissions: 'drwxr-xr-x',
    );
  }

  void _file(String path, int size, String permissions) {
    final normalized = RemotePath.normalize(path);
    _nodes[normalized] = RemoteEntry(
      name: RemotePath.basename(normalized),
      path: normalized,
      type: RemoteEntryType.file,
      size: size,
      modifiedAt: DateTime(2026, 10, 14, 9, 41),
      permissions: permissions,
    );
  }

  void _link(String path, String target) {
    final normalized = RemotePath.normalize(path);
    _nodes[normalized] = RemoteEntry(
      name: RemotePath.basename(normalized),
      path: normalized,
      type: RemoteEntryType.symlink,
      modifiedAt: DateTime(2026, 10, 1, 8, 0),
      permissions: 'lrwxrwxrwx',
    );
    _contents[normalized] = Uint8List.fromList(utf8.encode(target));
  }

  // ------------------------------------------------------------------ RemoteFs

  @override
  Future<String> home() async => '/home/lele';

  @override
  Future<String> canonical(String path) async {
    final normalized = RemotePath.normalize(path);
    if (_nodes.containsKey(normalized)) {
      final target = _contents[normalized];
      if (target != null &&
          _nodes[normalized]!.type == RemoteEntryType.symlink) {
        return RemotePath.normalize(utf8.decode(target));
      }
      return normalized;
    }
    // 不存在的路径按"相对于 home"处理，跟真实 SFTP 的 absolute() 手感接近
    return normalized;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    _maybeFail();
    final normalized = RemotePath.normalize(path);
    if (normalized != '/') {
      final node = _nodes[normalized];
      if (node == null) throw StateError('noSuchFile: $normalized');
      if (node.type != RemoteEntryType.directory) {
        throw StateError('notADirectory: $normalized');
      }
    }

    final children = _nodes.values
        .where((RemoteEntry e) => RemotePath.parent(e.path) == normalized)
        .toList();
    // 目录在前，然后按名字不区分大小写排 —— 跟 WindTerm / Termius 一样
    children.sort((RemoteEntry a, RemoteEntry b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return children;
  }

  @override
  Future<void> mkdir(String path) async {
    _maybeFail();
    _dir(path);
    _contents.remove(RemotePath.normalize(path));
  }

  @override
  Future<void> remove(RemoteEntry entry) async {
    _maybeFail();
    final normalized = RemotePath.normalize(entry.path);
    _nodes.removeWhere(
      (String path, _) =>
          path == normalized || path.startsWith('$normalized/'),
    );
    _contents.removeWhere(
      (String path, _) =>
          path == normalized || path.startsWith('$normalized/'),
    );
  }

  @override
  Future<void> rename(String from, String to) async {
    _maybeFail();
    final source = RemotePath.normalize(from);
    final target = RemotePath.normalize(to);
    if (_nodes.containsKey(target)) throw StateError('fileAlreadyExists: $to');

    // 先把整棵子树摘出来（改目录名时里面的东西要跟着走），再统一挂到新位置
    final moving = <String, RemoteEntry>{};
    for (final entry in _nodes.values.toList()) {
      if (entry.path == source || entry.path.startsWith('$source/')) {
        moving[entry.path] = entry;
      }
    }
    if (moving.isEmpty) throw StateError('noSuchFile: $from');

    final movedContent = <String, Uint8List>{};
    for (final path in moving.keys.toList()) {
      final content = _contents.remove(path);
      if (content != null) movedContent[path] = content;
      _nodes.remove(path);
    }

    moving.forEach((String path, RemoteEntry entry) {
      final newPath = target + path.substring(source.length);
      _nodes[newPath] = RemoteEntry(
        name: RemotePath.basename(newPath),
        path: newPath,
        type: entry.type,
        size: entry.size,
        modifiedAt: entry.modifiedAt,
        permissions: entry.permissions,
      );
      final content = movedContent[path];
      if (content != null) _contents[newPath] = content;
    });
  }

  @override
  Future<Uint8List> readBytes(String path, {int maxBytes = 262144}) async {
    _maybeFail();
    final normalized = RemotePath.normalize(path);
    final content = _contents[normalized];
    if (content == null) {
      // 没有内容的假文件给一段占位文本，截图里不至于是一片空白
      final node = _nodes[normalized];
      if (node == null) throw StateError('noSuchFile: $normalized');
      return Uint8List.fromList(
        utf8.encode('# ${node.name}\n\n（演示模式：这个文件没有真实内容）\n'),
      );
    }
    return content.length <= maxBytes
        ? content
        : Uint8List.sublistView(content, 0, maxBytes);
  }

  @override
  Stream<Uint8List> openRead(String path, {int chunkSize = 65536}) async* {
    _maybeFail();
    // 故意切几块再吐，好让 UI 的"边收边写"路径在测试里真的被走到
    final data = await readBytes(path, maxBytes: 1 << 30);
    for (var start = 0; start < data.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, data.length);
      yield Uint8List.sublistView(data, start, end);
    }
  }

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    _maybeFail();
    final normalized = RemotePath.normalize(path);
    _contents[normalized] = bytes;
    _nodes[normalized] = RemoteEntry(
      name: RemotePath.basename(normalized),
      path: normalized,
      type: RemoteEntryType.file,
      size: bytes.length,
      modifiedAt: DateTime.now(),
      permissions: '-rw-r--r--',
    );
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<void> close() async {}
}
