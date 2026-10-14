import 'dart:async';
import 'dart:convert';
import 'dart:io' as io show SocketException;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_host.dart';
import 'credential_store.dart';

enum SessionStatus { connecting, connected, disconnected, error }

/// 可读的连接失败原因
class SshFailure implements Exception {
  SshFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次 SSH 会话：把 dartssh2 的通道和 xterm 的终端粘起来。
///
/// 数据流向：
///   远端 stdout/stderr  ->  terminal.write()       -> 屏幕
///   terminal.onOutput   ->  session.stdin          -> 远端
///   terminal.onResize   ->  session.resizeTerminal -> 远端 PTY
class TerminalSession extends ChangeNotifier {
  TerminalSession(this.host) {
    _terminal = Terminal(
      maxLines: 5000,
      onOutput: (String data) {
        final session = _session;
        if (session != null) {
          session.stdin.add(utf8.encode(data));
        } else {
          _capture(utf8.encode(data));
        }
      },
      onResize: (int w, int h, int pw, int ph) {
        // 记下来：PTY 还没建好时 onResize 会被丢掉，建好后要补发一次
        _lastPixelWidth = pw;
        _lastPixelHeight = ph;
        _session?.resizeTerminal(w, h, pw, ph);
      },
    );
    unawaited(connect());
  }

  final SshHost host;

  /// 预览图 / 截图测试专用：造一个"已连接"外观的会话，**不拨号、不读凭据**。
  /// 生产代码永远不要用它。
  @visibleForTesting
  TerminalSession.preview(this.host) {
    _terminal = Terminal(
      maxLines: 5000,
      // 没有真实通道，但按键编码这条路要能和线上跑一模一样，
      // 否则"点一下终端"这种行为根本没法测
      onOutput: (String data) => _capture(utf8.encode(data)),
    );
    _captureOutput = true;
    _status = SessionStatus.connected;
  }

  late final Terminal _terminal;

  Terminal get terminal => _terminal;

  SSHClient? _client;
  SSHSession? _session;
  SftpClient? _sftp;

  int _lastPixelWidth = 0;
  int _lastPixelHeight = 0;

  /// 预览 / 测试专用：没有真实 SSH 通道时，"本该发出去的字节"会留一份在这里，
  /// 让测试能断言按了什么键。生产路径上它永远是空的。
  @visibleForTesting
  final List<int> debugSentBytes = <int>[];

  bool _captureOutput = false;

  /// 只在捕获模式下记，且只留最后 4KB —— 免得长时间跑把内存吃满
  void _capture(List<int> bytes) {
    if (!_captureOutput) return;
    debugSentBytes.addAll(bytes);
    if (debugSentBytes.length > 4096) {
      debugSentBytes.removeRange(0, debugSentBytes.length - 4096);
    }
  }

  /// ★ 初始值必须是 disconnected，不能是 connecting。
  /// 构造函数里就会调 connect()，而 connect() 开头有"已在连接中就直接返回"的守卫；
  /// 如果这里写成 connecting，connect() 会立刻 return，永远连不上、
  /// 界面卡在"连接中"（connect() 自己会第一时间把状态置为 connecting）。
  SessionStatus _status = SessionStatus.disconnected;

  String? _error;

  SessionStatus get status => _status;

  String? get error => _error;

  bool get isConnected => _status == SessionStatus.connected;

  void _setStatus(SessionStatus status, {String? error}) {
    _status = status;
    _error = error;
    notifyListeners();
  }

  // ------------------------------------------------------------------ 生命周期

  Future<void> connect() async {
    if (_status == SessionStatus.connecting ||
        _status == SessionStatus.connected) {
      return;
    }
    _setStatus(SessionStatus.connecting);
    _writeln('正在连接 ${host.endpoint} ...');

    // 主机密钥对不上时的具体原因，冒泡到下面的 catch 里报给用户
    String? hostKeyReject;

    try {
      if (host.hostname.isEmpty) {
        throw SshFailure('主机地址为空');
      }
      if (host.username.isEmpty) {
        throw SshFailure('用户名为空');
      }

      final socket = await SSHSocket.connect(
        host.hostname,
        host.port,
        timeout: const Duration(seconds: 15),
      );

      _client = SSHClient(
        socket,
        username: host.username,
        identities: await _loadIdentities(),
        onPasswordRequest: () async {
          if (host.authMethod != HostAuthMethod.password) return null;
          return CredentialStore.password(host.id);
        },
        onVerifyHostKey: (String type, Uint8List fingerprint) async {
          final fp = utf8.decode(fingerprint, allowMalformed: true);
          final known = await CredentialStore.knownFingerprint(
            host.hostname,
            host.port,
          );
          if (known == null) {
            // 首次连接：TOFU，记下指纹并显示出来，方便用户自己核对
            await CredentialStore.rememberFingerprint(
              host.hostname,
              host.port,
              fp,
            );
            _writeln('\x1B[36m首次连接，已记录 $type 主机指纹：\x1B[0m');
            _writeln('\x1B[36m  $fp\x1B[0m');
            return true;
          }
          if (known != fp) {
            // 不能直接 throw：异常从 dartssh2 的握手回调里抛出去会变成
            // 没信息的 SSHHostkeyError。记下原因、返回 false 更可控。
            hostKeyReject =
                '主机公钥指纹和上次记录的不一致，已中断连接\n'
                '  上次：$known\n'
                '  本次：$fp\n'
                '  这可能是中间人攻击。若确认是自己重装了系统，'
                '请删掉这台主机重新添加。';
            return false;
          }
          return true;
        },
        keepAliveInterval: const Duration(seconds: 30),
      );

      await _client!.authenticated.timeout(const Duration(seconds: 25));

      // TerminalView 还没量出尺寸时 viewWidth/viewHeight 是 0，
      // 拿 0 当 PTY 大小部分服务端会拒绝或行为异常，兜底 80x24。
      final cols = _terminal.viewWidth > 0 ? _terminal.viewWidth : 80;
      final rows = _terminal.viewHeight > 0 ? _terminal.viewHeight : 24;

      _session = await _client!.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: cols, height: rows),
      );

      // 补一次 resize：PTY 建好之前 TerminalView 触发的 onResize 都被丢掉了，
      // 不发这一下远端会一直以为终端是 80x24。
      if (_terminal.viewWidth > 0 && _terminal.viewHeight > 0) {
        _session!.resizeTerminal(
          _terminal.viewWidth,
          _terminal.viewHeight,
          _lastPixelWidth,
          _lastPixelHeight,
        );
      }

      _session!.stdout.listen(
        (Uint8List data) {
          _writeBytes(data);
        },
        onError: (Object error) {
          _writeln('\x1B[31m读取失败：$error\x1B[0m');
        },
        cancelOnError: false,
      );

      _session!.stderr.listen((Uint8List data) {
        _writeBytes(data);
      }, cancelOnError: false);

      unawaited(
        _session!.done.then((_) {
          if (_status == SessionStatus.connected) {
            _writeln('\r\n\x1B[33m连接已断开。\x1B[0m');
            _setStatus(SessionStatus.disconnected);
          }
        }),
      );

      _setStatus(SessionStatus.connected);
    } on SSHAuthFailError catch (_) {
      _setStatus(SessionStatus.error, error: '认证失败：用户名或凭据不正确');
      _writelnErr('认证失败：用户名或凭据不正确');
    } on SSHAuthAbortError catch (_) {
      _setStatus(SessionStatus.error, error: '认证被服务端中止');
      _writelnErr('认证被服务端中止');
    } on SSHHostkeyError catch (_) {
      final reason = hostKeyReject ?? '主机密钥校验失败';
      _setStatus(SessionStatus.error, error: hostKeyReject ?? '主机密钥校验失败');
      _writelnErr(reason);
    } on SSHKeyDecodeError catch (_) {
      _setStatus(SessionStatus.error, error: '私钥解析失败，检查格式（需要 PEM）或口令');
      _writelnErr('私钥解析失败：格式不对（需要 PEM）或口令错误');
    } on io.SocketException catch (e) {
      _setStatus(SessionStatus.error, error: '连不上：${e.message}');
      _writelnErr('连不上 ${host.endpoint}：${e.message}');
    } on TimeoutException catch (_) {
      _setStatus(SessionStatus.error, error: '连接超时');
      _writelnErr('连接超时，检查网络或目标端口是否放行');
    } on SshFailure catch (e) {
      _setStatus(SessionStatus.error, error: e.message);
      _writelnErr(e.message);
    } catch (e) {
      _setStatus(SessionStatus.error, error: '$e');
      _writelnErr('$e');
    }
  }

  Future<List<SSHIdentity>?> _loadIdentities() async {
    if (host.authMethod != HostAuthMethod.privateKey) return null;

    final keyId = host.privateKeyId;
    if (keyId == null || keyId.isEmpty) {
      throw SshFailure('这台主机配置成了私钥登录，但没有绑定私钥');
    }
    final pem = await CredentialStore.privateKey(keyId);
    if (pem == null || pem.trim().isEmpty) {
      throw SshFailure('找不到私钥，可能已被删除');
    }
    final passphrase = await CredentialStore.privateKeyPassphrase(keyId);
    final pairs = SSHKeyPair.fromPem(pem, passphrase);
    if (pairs.isEmpty) {
      throw SshFailure('私钥文件里没有可用的密钥');
    }
    return pairs;
  }

  /// 打开 SFTP 文件通道。
  ///
  /// ★ 复用当前这条 SSH 连接，而不是另拨一次：
  ///   免掉第二次认证（私钥带口令时尤其明显），主机指纹 TOFU 也只做一遍。
  ///   dartssh2 允许在一条连接上同时开 shell 和 sftp 两条 channel。
  Future<SftpClient> openSftp() async {
    final existing = _sftp;
    if (existing != null) return existing;

    final client = _client;
    if (client == null || _status != SessionStatus.connected) {
      throw SshFailure('还没连上，无法打开文件管理');
    }
    final sftp = await client.sftp();
    _sftp = sftp;
    return sftp;
  }

  /// 老版本服务端可能没开 sftp 子系统，界面上要能区分"没连上"和"对方不支持"
  static bool looksLikeSubsystemMissing(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('subsystem') ||
        text.contains('unsupported') ||
        text.contains('unknown channel');
  }

  Future<void> disconnect() async {
    if (_status == SessionStatus.disconnected) return;
    try {
      _sftp?.close();
    } catch (_) {}
    _sftp = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _session = null;
    _writeln('\r\n\x1B[33m已断开连接。\x1B[0m');
    _setStatus(SessionStatus.disconnected);
  }

  // ------------------------------------------------------------------ 输入

  /// 方向键 / Home / End / PgUp / PgDn / Tab / Esc
  void sendKey(TerminalKey key) {
    if (_session == null && !_captureOutput) return;
    _terminal.keyInput(key);
  }

  /// 把远端光标在**当前输入行内**左右移动 [delta] 格。触摸点终端走这里。
  ///
  /// 只发左右方向键：上下方向键在 shell / readline 里是"翻历史命令"，
  /// 拿它去定位光标会把用户正在敲的那一行整个换掉。
  void moveCursorBy(int delta) {
    if (delta == 0) return;
    // 屏幕上不可能有超过这么多列，超出的当作误触直接截断
    final steps = delta.abs().clamp(0, 200);
    final key = delta > 0 ? TerminalKey.arrowRight : TerminalKey.arrowLeft;
    for (var i = 0; i < steps; i++) {
      sendKey(key);
    }
  }

  /// 粘滞 Ctrl 关闭时，字母键当普通字符发过去。
  ///
  /// ★ 直接写 SSH 通道，不走 `_terminal.charInput()`：
  ///   charInput 会同时改本地终端 buffer，而远端 readline 也会回显同一个字符，
  ///   结果就是屏幕上出现两个。SSH 会话里回显永远是远端的事。
  void sendLetter(String letter) {
    if (_session == null) return;
    final lower = letter.toLowerCase();
    if (lower.length != 1) return;
    sendText(lower);
  }

  /// Ctrl + 字母（Ctrl+C / Ctrl+D / Ctrl+L ...）直接发控制字节，最可靠
  void sendCtrlLetter(String letter) {
    final upper = letter.toUpperCase();
    if (upper.length != 1) return;
    final code = upper.codeUnitAt(0);
    if (code < 0x41 || code > 0x5A) return;
    final bytes = <int>[code - 0x40];
    final session = _session;
    if (session == null) {
      _capture(bytes);
      return;
    }
    session.stdin.add(Uint8List.fromList(bytes));
  }

  /// 原样把文本塞进命令行（不回车）。常用命令片段走这里。
  void sendText(String text) {
    if (text.isEmpty) return;
    final session = _session;
    if (session == null) {
      _capture(utf8.encode(text));
      return;
    }
    session.stdin.add(utf8.encode(text));
  }

  /// 发送任意字节，自定义组合键（Ctrl+Alt+X 之类）走这里
  void sendBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    final session = _session;
    if (session == null) {
      _capture(bytes);
      return;
    }
    session.stdin.add(bytes);
  }

  // ------------------------------------------------------------------ 内部

  void _writeBytes(Uint8List data) {
    _terminal.write(utf8.decode(data, allowMalformed: true));
  }

  void _writeln(String text) => _terminal.write('$text\r\n');

  void _writelnErr(String message) {
    _terminal.write('\r\n\x1B[31m$message\x1B[0m\r\n');
  }

  @override
  void dispose() {
    try {
      _sftp?.close();
    } catch (_) {}
    _sftp = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _session = null;
    super.dispose();
  }
}
