import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/models/remote_entry.dart';
import 'package:sshterm/services/demo_fs.dart';
import 'package:sshterm/services/remote_path.dart';
import 'package:sshterm/services/sftp_fs.dart';

/// 远端路径、条目模型、假文件树 —— 都是纯逻辑，不需要 widget 环境。
void main() {
  group('RemotePath', () {
    test('规范化的各种边角', () {
      expect(RemotePath.normalize('/a/b/../c'), '/a/c');
      expect(RemotePath.normalize('/a//b/'), '/a/b');
      expect(RemotePath.normalize('/a/./b'), '/a/b');
      expect(RemotePath.normalize('/'), '/');
      // 空串在 POSIX 语义里就是"当前目录"，不是根
      expect(RemotePath.normalize(''), '.');
      // 根目录再往上还是根，不能变成空串（面包屑会因此断掉）
      expect(RemotePath.normalize('/../..'), '/');
      expect(RemotePath.normalize('a/b'), 'a/b');
    });

    test('join：第二段是绝对路径时直接顶掉第一段', () {
      expect(RemotePath.join('/home/lele', 'notes.md'), '/home/lele/notes.md');
      expect(RemotePath.join('/home/lele', '/etc/hosts'), '/etc/hosts');
      expect(RemotePath.join('/', 'tmp'), '/tmp');
    });

    test('parent / basename', () {
      expect(RemotePath.parent('/home/lele/notes.md'), '/home/lele');
      expect(RemotePath.parent('/home'), '/');
      expect(RemotePath.parent('/'), '/');
      expect(RemotePath.basename('/home/lele/notes.md'), 'notes.md');
      expect(RemotePath.basename('/'), '/');
    });

    test('crumbs 给的是可直接跳转的绝对路径', () {
      expect(RemotePath.crumbs('/home/lele/logs'), <String>[
        '/',
        '/home',
        '/home/lele',
        '/home/lele/logs',
      ]);
      expect(RemotePath.crumbs('/'), <String>['/']);
    });
  });

  group('RemoteEntry', () {
    test('大小格式化', () {
      expect(RemoteEntry.formatBytes(0), '0 B');
      expect(RemoteEntry.formatBytes(999), '999 B');
      expect(RemoteEntry.formatBytes(1024), '1.0 KB');
      expect(RemoteEntry.formatBytes(1536), '1.5 KB');
      // 超过 10 就不留小数位了，跟 ls -h 的手感一致
      expect(RemoteEntry.formatBytes(1024 * 123), '123 KB');
      expect(RemoteEntry.formatBytes(48234048), '46 MB');
      expect(RemoteEntry.formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('时间格式化补零', () {
      final time = DateTime(2026, 3, 7, 9, 5);
      expect(RemoteEntry.formatTime(time), '2026-03-07 09:05');
    });

    test('哪些后缀当文本看', () {
      RemoteEntry of(String name) =>
          RemoteEntry(name: name, path: '/x/$name', type: RemoteEntryType.file);

      expect(of('app.log').isTextLike, isTrue);
      expect(of('notes.md').isTextLike, isTrue);
      expect(of('deploy.sh').isTextLike, isTrue);
      expect(of('nginx.conf').isTextLike, isTrue);
      expect(of('backup.tar.gz').isTextLike, isFalse);
      expect(of('photo.png').isTextLike, isFalse);
      expect(of('a.out').isTextLike, isFalse);
    });

    test('隐藏项就是点开头的', () {
      RemoteEntry of(String name) =>
          RemoteEntry(name: name, path: '/x/$name', type: RemoteEntryType.file);
      expect(of('.bashrc').isHidden, isTrue);
      expect(of('bashrc').isHidden, isFalse);
    });
  });

  group('权限串', () {
    test('从 mode 位还原成 ls -l 那一列', () {
      expect(formatMode(0x81A4), '-rw-r--r--'); // 0644 普通文件
      expect(formatMode(0x41ED), 'drwxr-xr-x'); // 0755 目录
      expect(formatMode(0x8180), '-rw-------'); // 0600 私钥
      expect(formatMode(0xA1FF), 'lrwxrwxrwx'); // 0777 符号链接
      expect(formatMode(null), '');
    });
  });

  group('DemoFs', () {
    test('列目录：目录在前，其余按名字排', () async {
      final fs = DemoFs();
      final entries = await fs.list('/home/lele');
      final names = entries.map((RemoteEntry e) => e.name).toList();

      final firstFile = entries.indexWhere((RemoteEntry e) => !e.isDirectory);
      final lastDir = entries.lastIndexWhere((RemoteEntry e) => e.isDirectory);
      expect(
        lastDir,
        lessThan(firstFile),
        reason: '目录必须全排在文件前面，实际：$names',
      );
      expect(names, contains('projects'));
      expect(names, contains('deploy.sh'));
    });

    test('home 和 canonical', () async {
      final fs = DemoFs();
      expect(await fs.home(), '/home/lele');
      expect(await fs.canonical('/home/lele/../etc'), '/home/etc');
      // 符号链接要解开（面板上点进去才是真实目录）
      expect(await fs.canonical('/etc/mtab'), '/proc/mounts');
    });

    test('mkdir / rename / remove 会把子树一起带走', () async {
      final fs = DemoFs();
      await fs.mkdir('/home/lele/tmpdir');
      await fs.writeBytes(
        '/home/lele/tmpdir/a.txt',
        Uint8List.fromList(utf8.encode('hello')),
      );
      expect((await fs.list('/home/lele/tmpdir')).length, 1);

      await fs.rename('/home/lele/tmpdir', '/home/lele/renamed');
      final renamed = await fs.list('/home/lele/renamed');
      expect(renamed.single.name, 'a.txt');
      expect(
        renamed.single.path,
        '/home/lele/renamed/a.txt',
        reason: '子项的 path 也要跟着改，否则点它会跳到旧位置',
      );
      expect(
        utf8.decode(await fs.readBytes('/home/lele/renamed/a.txt')),
        'hello',
        reason: '内容也要跟着搬',
      );

      await fs.remove(renamed.single);
      expect(await fs.list('/home/lele/renamed'), isEmpty);
    });

    test('rename 撞名要报错', () async {
      final fs = DemoFs();
      await fs.mkdir('/home/lele/dup');
      expect(
        () => fs.rename('/home/lele/dup', '/home/lele/logs'),
        throwsA(isA<StateError>()),
      );
    });

    test('流式读会分块吐出来（UI 的边收边写要走这条路径）', () async {
      final fs = DemoFs();
      await fs.writeBytes(
        '/home/lele/big.txt',
        Uint8List.fromList(List<int>.filled(10000, 0x61)),
      );
      final chunks = <int>[];
      await for (final chunk in fs.openRead('/home/lele/big.txt', chunkSize: 4096)) {
        chunks.add(chunk.length);
      }
      expect(chunks, <int>[4096, 4096, 1808]);
    });

    test('读超过 maxBytes 的内容会截断', () async {
      final fs = DemoFs();
      await fs.writeBytes(
        '/home/lele/long.txt',
        Uint8List.fromList(List<int>.filled(5000, 0x62)),
      );
      final bytes = await fs.readBytes('/home/lele/long.txt', maxBytes: 1024);
      expect(bytes.length, 1024);
    });

    test('failNext 能把错误注入进来（给 UI 的错误态用）', () async {
      final fs = DemoFs();
      fs.failNext = StateError('permissionDenied');
      expect(() => fs.list('/home/lele'), throwsA(isA<StateError>()));
      // 只失败一次
      expect(await fs.list('/home/lele'), isNotEmpty);
    });
  });
}
