import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/remote_entry.dart';
import 'remote_fs.dart';
import 'remote_path.dart';

/// 真实实现：包一层 dartssh2 的 [SftpClient]。
class SftpFs implements RemoteFs {
  SftpFs(this._client, {required this.label});

  final SftpClient _client;

  @override
  final String label;

  bool _closed = false;

  @override
  Future<String> home() async {
    // `.` 就是登录后的 cwd，绝大多数 sshd 直接把用户丢在 home 下
    final cwd = await _client.absolute('.');
    return RemotePath.normalize(cwd);
  }

  @override
  Future<String> canonical(String path) async =>
      RemotePath.normalize(await _client.absolute(path));

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final names = await _client.listdir(path);
    final entries = <RemoteEntry>[];
    for (final name in names) {
      // 服务端一般会把这两个塞进来，界面上不该出现（".." 我们自己在面包屑里给）
      if (name.filename == '.' || name.filename == '..') continue;
      final attr = name.attr;
      final mode = attr.mode;
      final relative = attr.modifyTime;
      entries.add(
        RemoteEntry(
          name: name.filename,
          path: RemotePath.join(path, name.filename),
          type: _typeOf(mode?.type),
          size: attr.size ?? 0,
          modifiedAt: relative == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(relative * 1000),
          permissions: formatMode(mode?.value),
        ),
      );
    }
    return entries;
  }

  @override
  Future<void> mkdir(String path) => _client.mkdir(path);

  @override
  Future<void> remove(RemoteEntry entry) =>
      entry.isDirectory ? _client.rmdir(entry.path) : _client.remove(entry.path);

  @override
  Future<void> rename(String from, String to) => _client.rename(from, to);

  @override
  Future<Uint8List> readBytes(String path, {int maxBytes = 262144}) async {
    final file = await _client.open(path);
    try {
      return await file.readBytes(length: maxBytes);
    } finally {
      await file.close();
    }
  }

  @override
  Stream<Uint8List> openRead(String path, {int chunkSize = 65536}) async* {
    final file = await _client.open(path);
    try {
      await for (final chunk in file.read(chunkSize: chunkSize)) {
        yield chunk;
      }
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = await _client.open(
      path,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(bytes);
      onProgress?.call(bytes.length, bytes.length);
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _client.close();
    } catch (_) {
      // 通道可能已经随主连接一起没了，这里不该再抛给界面
    }
  }

  static RemoteEntryType _typeOf(SftpFileType? type) => switch (type) {
    SftpFileType.directory => RemoteEntryType.directory,
    SftpFileType.regularFile => RemoteEntryType.file,
    SftpFileType.symbolicLink => RemoteEntryType.symlink,
    null => RemoteEntryType.other,
    _ => RemoteEntryType.other,
  };
}

/// `mode`（含类型位和权限位）→ `-rw-r--r--`。
///
/// 没直接用 `SftpName.longname`：那个字段依赖服务端实现，有空串的情况；
/// 权限位是协议里必须给的，更可靠。
String formatMode(int? mode) {
  if (mode == null) return '';
  final value = mode & 0xFFF; // 只留权限位
  final chars = StringBuffer(_typeChar(mode));
  const masks = <int>[0x100, 0x80, 0x40, 0x20, 0x10, 0x8, 0x4, 0x2, 0x1];
  const letters = <String>['r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x'];
  for (var i = 0; i < masks.length; i++) {
    chars.write((value & masks[i]) != 0 ? letters[i] : '-');
  }
  return chars.toString();
}

String _typeChar(int mode) {
  const mask = 0xF000;
  return switch (mode & mask) {
    0x4000 => 'd',
    0xA000 => 'l',
    0x1000 => 'p',
    0x2000 => 'c',
    0x6000 => 'b',
    0xC000 => 's',
    _ => '-',
  };
}
