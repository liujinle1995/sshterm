import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 手机上"本机这一侧"的文件目录。
///
/// 下载到哪、上传从哪选，都落在这里。
///
/// 为什么不用 `/sdcard/Download`：Android 10 起的分区存储不允许按裸路径写公共目录
/// （除非申请 MANAGE_EXTERNAL_STORAGE，那个权限商店审核很麻烦）。走
/// `getExternalStorageDirectory()` 拿到的是 `Android/data/<包名>/files/`，
/// 不需要任何权限、插上电脑也能看到，最适合当传输中转站。
class LocalStore {
  LocalStore._();

  static const String transferFolderName = 'transfer';

  /// 测试 / 预览用：把根目录指到临时目录，避免碰真实设备目录
  @visibleForTesting
  static Directory? debugRoot;

  static Directory? _cached;

  /// 传输目录。里面放的就是"能上传到远端 / 从远端下载下来"的文件。
  static Future<Directory> transferDir() async {
    final root = await _root();
    final dir = Directory('${root.path}/$transferFolderName');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        // 目录建不出来（只读挂载之类）就让调用方在写的时候报错，别在这里吞掉
      }
    }
    return dir;
  }

  static Future<Directory> _root() async {
    final override = debugRoot;
    if (override != null) return override;
    final cached = _cached;
    if (cached != null) return cached;

    Directory? dir;
    try {
      // Android：/storage/emulated/0/Android/data/<pkg>/files
      dir = await getExternalStorageDirectory();
    } catch (_) {
      dir = null;
    }
    if (dir == null) {
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = null;
      }
    }
    // 桌面 / 测试环境（没有插件通道）就退到系统临时目录，功能照常只是位置不同
    dir ??= Directory.systemTemp;
    return _cached = dir;
  }

  /// 列传输目录里的文件，新的在前
  static Future<List<FileSystemEntity>> listForUpload() async {
    final dir = await transferDir();
    if (!dir.existsSync()) return <FileSystemEntity>[];
    final items = dir.listSync()
      ..removeWhere((FileSystemEntity e) => e is Directory);
    items.sort((FileSystemEntity a, FileSystemEntity b) {
      final at = a.statSync().modified;
      final bt = b.statSync().modified;
      return bt.compareTo(at);
    });
    return items;
  }

  /// 在传输目录里占一个不重名的空文件。
  ///
  /// 先占位再流式写入，是为了下载大文件时不用把整个文件攒在内存里 ——
  /// 手机上随便一个日志就是几百兆，全读进 RAM 会被系统杀掉。
  static Future<File> createIncoming(String name) async {
    final dir = await transferDir();
    final file = _uniqueFile(dir, name);
    await file.create(recursive: true);
    return file;
  }

  /// 小文件直接一把梭
  static Future<File> writeIncoming(String name, List<int> bytes) async {
    final file = await createIncoming(name);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static File _uniqueFile(Directory dir, String name) {
    var candidate = File('${dir.path}/$name');
    if (!candidate.existsSync()) return candidate;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      candidate = File('${dir.path}/$stem-$i$ext');
      if (!candidate.existsSync()) return candidate;
    }
    return File(
      '${dir.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext',
    );
  }
}
