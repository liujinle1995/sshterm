import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/models/ssh_host.dart';
import 'package:sshterm/services/terminal_session.dart';

void main() {
  group('TerminalSession 连接状态机', () {
    // 回归：曾经 _status 初始值是 connecting，而 connect() 开头有
    // "已在 connecting 就直接 return" 的守卫 —— 结果构造函数里那次
    // connect() 立刻返回，永远不发连接，界面死卡在"连接中"。
    test('构造后会自动发起连接，而不是被守卫吃掉', () {
      final host = SshHost(id: 'h1', hostname: '127.0.0.1', port: 1);
      final session = TerminalSession(host);

      // 关键点：构造函数里没 await，但 connect() 必须真的跑起来了。
      // 若被守卫吞掉，状态会永远停在 connecting。
      expect(session.status, isNot(SessionStatus.connected));
      addTearDown(session.dispose);

      // 127.0.0.1:1 没有服务 → 应快速落到 error，而不是停在 connecting
      return Future<void>.delayed(const Duration(seconds: 3), () {
        expect(
          session.status,
          SessionStatus.error,
          reason: 'connect() 没有真正执行，状态停在 ${session.status}',
        );
      });
    });

    test('主机地址为空时给出可读的错误状态', () {
      final session = TerminalSession(SshHost(id: 'h2', hostname: ''));
      addTearDown(session.dispose);
      expect(session.status, SessionStatus.error);
      expect(session.error, contains('主机地址为空'));
    });

    test('用户名为空时给出可读的错误状态', () {
      final session = TerminalSession(
        SshHost(id: 'h3', hostname: 'example.com', username: ''),
      );
      addTearDown(session.dispose);
      expect(session.status, SessionStatus.error);
      expect(session.error, contains('用户名为空'));
    });

    test('连接失败后可以再次发起连接', () async {
      final session = TerminalSession(
        SshHost(id: 'h4', hostname: '127.0.0.1', port: 1),
      );
      addTearDown(session.dispose);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(session.status, SessionStatus.error);

      // 状态是 error（不是 connecting），所以重连按钮必须能再次触发 connect()
      unawaited(session.connect());
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(session.status, SessionStatus.error);
    });
  });
}
