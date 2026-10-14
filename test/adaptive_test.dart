import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/models/ssh_host.dart';
import 'package:sshterm/services/host_store.dart';
import 'package:sshterm/services/terminal_session.dart';
import 'package:sshterm/ui/adaptive.dart';
import 'package:sshterm/ui/host_list_page.dart';
import 'package:sshterm/ui/settings_page.dart';
import 'package:sshterm/ui/soft_keys.dart';
import 'package:sshterm/ui/terminal_page.dart';
import 'package:xterm/xterm.dart';

/// 平板 / 宽屏适配，外加终端页的两处交互修正：
///  * 点一下终端把远端光标挪过去；
///  * 关掉命令抽屉后不要自动把软键盘顶回来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 地址留空 → 万一真去连也不会做网络 IO（测试里基本都注入 preview 会话）
  const host = SshHost(id: 'h1', hostname: '', username: 'root');

  const phone = Size(360, 800);
  const tablet = Size(1280, 800);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpAt(WidgetTester tester, Widget home, Size logical) async {
    const dpr = 2.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  Widget terminal({TerminalSession? session}) => TerminalPage(
    host: host,
    sessionOverride: session ?? TerminalSession.preview(host),
    keyCombos: KeyCombo.defaults,
  );

  // ------------------------------------------------------------ 平板适配

  group('平板适配', () {
    testWidgets('主机列表：平板并排放多张卡片，手机仍是一行一台', (
      WidgetTester tester,
    ) async {
      final hosts = <SshHost>[
        const SshHost(id: 'a', name: '家里的 NAS', hostname: '10.10.10.5', username: 'root'),
        const SshHost(id: 'b', name: '云服务器', hostname: '1.2.3.4', username: 'ubuntu'),
        const SshHost(id: 'c', name: '树莓派', hostname: '10.10.10.9', username: 'pi'),
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        // 私有 key，这里按存储格式直接喂
        'sshterm.hosts.v1': jsonEncode(
          hosts.map((SshHost h) => h.toJson()).toList(),
        ),
      });

      // 先确认 mock 真的被读到了，否则下面的断言是在空列表上做的
      expect((await HostStore().load()).length, 3);

      await pumpAt(tester, const HostListPage(), tablet);
      expect(
        find.byType(GridView),
        findsOneWidget,
        reason: '平板宽度下应该换成网格，一张卡片拉满整屏太丑',
      );

      await pumpAt(tester, const HostListPage(), phone);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('列表页在平板上限宽居中，不会拉成一条长带', (WidgetTester tester) async {
      await pumpAt(tester, const SettingsPage(), tablet);
      final wideWidth = tester.getSize(find.byType(ListView).first).width;
      expect(
        wideWidth,
        lessThanOrEqualTo(Adaptive.readableWidth),
        reason: '设置页在 1280 宽下被拉到了 $wideWidth，说明限宽没生效',
      );

      await pumpAt(tester, const SettingsPage(), phone);
      final phoneWidth = tester.getSize(find.byType(ListView).first).width;
      expect(phoneWidth, phone.width, reason: '手机上不该有任何宽度变化');
    });

    testWidgets('终端页：平板把快捷键栏挪到左侧竖排', (WidgetTester tester) async {
      await pumpAt(tester, terminal(), tablet);

      final keys = tester.getRect(find.byType(SoftKeys));
      final view = tester.getRect(find.byType(TerminalView));

      expect(
        tester.widget<SoftKeys>(find.byType(SoftKeys)).vertical,
        isTrue,
        reason: '宽屏还按横排铺在底部，等于白扔一半高度',
      );
      expect(keys.right, lessThanOrEqualTo(view.left + 0.5));
      expect(keys.width, SoftKeys.totalWidth);
      expect(view.width, greaterThan(tablet.width * 0.6));
    });

    testWidgets('终端页：手机上快捷键栏仍在底部', (WidgetTester tester) async {
      await pumpAt(tester, terminal(), phone);

      final keys = tester.getRect(find.byType(SoftKeys));
      final view = tester.getRect(find.byType(TerminalView));

      expect(tester.widget<SoftKeys>(find.byType(SoftKeys)).vertical, isFalse);
      expect(keys.top, greaterThanOrEqualTo(view.bottom - 0.5));
      expect(keys.width, phone.width);
    });
  });

  // ------------------------------------------------------- 点一下移动光标

  group('点按移动光标', () {
    testWidgets('点在光标右边 → 发对应数量的右方向键', (WidgetTester tester) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);

      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));
      final buffer = session.terminal.buffer;
      session.debugSentBytes.clear();

      state.handleTapAtCell(CellOffset(buffer.cursorX + 3, buffer.absoluteCursorY));

      expect(
        String.fromCharCodes(session.debugSentBytes),
        '\x1B[C\x1B[C\x1B[C',
        reason: '应该发三次右方向键',
      );
    });

    testWidgets('点在光标左边 → 发左方向键', (WidgetTester tester) async {
      final session = TerminalSession.preview(host);
      // 先写入几个字符，把光标推到第 3 列（初始在 0，没法往左走）
      session.terminal.write('abc');
      await pumpAt(tester, terminal(session: session), phone);

      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));
      final buffer = session.terminal.buffer;
      expect(buffer.cursorX, greaterThanOrEqualTo(3));
      session.debugSentBytes.clear();

      state.handleTapAtCell(CellOffset(1, buffer.absoluteCursorY));

      expect(
        String.fromCharCodes(session.debugSentBytes),
        '\x1B[D' * (buffer.cursorX - 1),
      );
    });

    testWidgets('点在别的行 → 一个字都不发', (WidgetTester tester) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);

      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));
      final buffer = session.terminal.buffer;
      session.debugSentBytes.clear();

      // 上一行是历史输出，终端里没法把光标"点"上去 —— 上下键在 shell 里是翻历史
      state.handleTapAtCell(CellOffset(0, buffer.absoluteCursorY + 1));
      state.handleTapAtCell(CellOffset(0, buffer.absoluteCursorY - 1));

      expect(session.debugSentBytes, isEmpty);
    });

    testWidgets('点在同一列 → 不发任何按键', (WidgetTester tester) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);

      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));
      final buffer = session.terminal.buffer;
      session.debugSentBytes.clear();

      state.handleTapAtCell(CellOffset(buffer.cursorX, buffer.absoluteCursorY));
      expect(session.debugSentBytes, isEmpty);
    });

    // ---- 下面这几条走的是**真实的指针事件**，不是直接调 handleTapAtCell。
    //
    // 之前这个功能"写了但按上去没反应"，就是因为老测试全都直接调
    // handleTapAtCell，把"手势层到底有没有把事件送进来"这一段整个跳过了：
    // xterm 4.0.0 的 TerminalView.onTapUp 压根不会触发（来龙去脉见
    // `_TerminalTapArea` 的注释），逻辑层再对也白搭。所以这里必须从
    // tester.tapAt 打进去，把 Listener → RenderTerminal.getCellOffset →
    // moveCursorBy 整条链一起验掉。

    /// 把「光标右边 dCols 格、下边 dRows 行」换算成屏幕坐标。
    /// 格子宽高直接从 xterm 自己的 cursorRect 里取，免得在测试里手算字号。
    Offset pixelOfCell(
      WidgetTester tester, {
      required int dCols,
      int dRows = 0,
    }) {
      final view = tester.state<TerminalViewState>(
        find.byType(TerminalView).first,
      );
      final box = view.renderTerminal as RenderBox;
      final cursor = view.cursorRect; // renderTerminal 的局部坐标
      return box.localToGlobal(
        Offset(
          cursor.left + (dCols + 0.5) * cursor.width,
          cursor.top + (dRows + 0.5) * cursor.height,
        ),
      );
    }

    /// xterm 的点击识别器会挂一个 300ms 的双击判定 Timer，
    /// 不放掉它测试结束会报 "A Timer is still pending"。
    Future<void> flushTapTimers(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 350));

    testWidgets('真的用手指点下去 → 光标挪过去（走完整手势层）', (
      WidgetTester tester,
    ) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);
      session.debugSentBytes.clear();

      await tester.tapAt(pixelOfCell(tester, dCols: 3));
      await tester.pump();

      expect(
        String.fromCharCodes(session.debugSentBytes),
        '\x1B[C\x1B[C\x1B[C',
        reason: '手指点屏幕就该发右方向键；这条挂了说明手势层又断了',
      );

      await flushTapTimers(tester);
    });

    testWidgets('远方回显还没回来时，同一格连点两下只发一遍', (
      WidgetTester tester,
    ) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);
      session.debugSentBytes.clear();

      final point = pixelOfCell(tester, dCols: 2);
      await tester.tapAt(point);
      await tester.pump();
      expect(session.debugSentBytes, isNotEmpty);

      session.debugSentBytes.clear();
      await tester.tapAt(point);
      await tester.pump();

      expect(
        session.debugSentBytes,
        isEmpty,
        reason: '双击选词时第二下不该按"还没更新的 cursorX"再发一遍方向键，否则光标冲过头',
      );

      await flushTapTimers(tester);
    });

    testWidgets('长按不挪光标（那是选词的手势）', (WidgetTester tester) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);
      session.debugSentBytes.clear();

      // flutter_test 合成的指针事件 timeStamp 默认是 Duration.zero，
      // 光靠 pump 不会让它走字，所以这里显式给抬手事件一个晚 600ms 的时间戳。
      final gesture = await tester.startGesture(pixelOfCell(tester, dCols: 3));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up(timeStamp: const Duration(milliseconds: 600));
      await tester.pump();

      expect(session.debugSentBytes, isEmpty);

      await flushTapTimers(tester);
    });

    testWidgets('手指拖动（滚动）不挪光标', (WidgetTester tester) async {
      final session = TerminalSession.preview(host);
      await pumpAt(tester, terminal(session: session), phone);
      session.debugSentBytes.clear();

      final gesture = await tester.startGesture(pixelOfCell(tester, dCols: 3));
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();
      await tester.pump();

      expect(session.debugSentBytes, isEmpty);

      await flushTapTimers(tester);
    });
  });

  // --------------------------------------------------- 命令抽屉不该弹键盘

  testWidgets('打开命令抽屉会交出焦点，关掉后也不会把软键盘顶回来', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, terminal(), phone);
    final state = tester.state<TerminalPageState>(find.byType(TerminalPage));

    // 模拟"用户点过终端、正在打字"
    await tester.tap(find.byType(TerminalView));
    await tester.pumpAndSettle();
    expect(state.terminalHasFocus, isTrue, reason: '点了终端它就该拿到焦点');

    await tester.tap(find.byIcon(Icons.library_books_outlined));
    await tester.pumpAndSettle();
    expect(
      state.terminalHasFocus,
      isFalse,
      reason: '抽屉打开前必须先 unfocus，否则 pop 时会被焦点恢复顶出键盘',
    );

    // 点遮罩关掉抽屉。用固定坐标而不是 ModalBarrier 的中心：
    // 抽屉本身会盖住遮罩中心，tester 会报 "would not hit test"，
    // 那样其实是点在了抽屉上，测不到真正的关闭路径。
    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();
    expect(state.terminalHasFocus, isFalse, reason: '关掉抽屉后不该自动弹键盘');
  });
}
