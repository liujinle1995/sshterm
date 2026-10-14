import 'dart:typed_data';

import '../models/remote_entry.dart';

/// 远端文件系统的最小可用面。
///
/// 抽出来只有一个目的：SFTP 页面能在**没有网络**的环境里跑起来 ——
/// 预览截图和 widget 测试都喂 [DemoFs]（内存文件树）就够了，
/// 不用去 mock dartssh2 的一堆包结构。
abstract class RemoteFs {
  /// 界面上显示这一份文件系统连的是谁（主机名之类）
  String get label;

  /// 起始目录。SFTP 上就是登录后的 home。
  Future<String> home();

  Future<List<RemoteEntry>> list(String path);

  /// 把路径解析成绝对路径（`.bashrc` → `/home/lele/.bashrc`）
  Future<String> canonical(String path);

  Future<void> mkdir(String path);

  Future<void> remove(RemoteEntry entry);

  Future<void> rename(String from, String to);

  /// 读文件内容，最多 [maxBytes] 字节（文本预览用，别把一个大日志读进内存）
  Future<Uint8List> readBytes(String path, {int maxBytes = 262144});

  /// 流式读整个文件。下载走这里 —— 手机上一个日志动辄几百兆，
  /// 先攒成 Uint8List 再落盘会被系统直接杀掉进程。
  Stream<Uint8List> openRead(String path, {int chunkSize = 65536});

  /// 覆盖写入
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  });

  Future<void> close();
}

/// 把 [RemoteFs] 的方法名和参数拼成给人看的一句话。
/// 异常文案散落各处很容易漂，集中在这里。
String fsErrorMessage(Object error) {
  final raw = error.toString();
  // dartssh2 的 SftpStatusError 长这样：SftpStatusError(SftpStatusCode.permissionDenied, ...)
  if (raw.contains('permissionDenied')) return '权限不足';
  if (raw.contains('noSuchFile')) return '文件或目录不存在';
  if (raw.contains('notADirectory')) return '对方不是目录';
  if (raw.contains('fileAlreadyExists')) return '同名文件已存在';
  if (raw.contains('directoryNotEmpty')) return '目录非空';
  if (raw.contains('connectionLost') || raw.contains('SocketException')) {
    return '连接已断开';
  }
  return raw;
}
