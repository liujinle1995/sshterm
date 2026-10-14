import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/models/ssh_host.dart';
import 'package:sshterm/services/terminal_prefs.dart';
import 'package:sshterm/services/terminal_session.dart';
import 'package:sshterm/ui/soft_keys.dart';
import 'package:sshterm/ui/terminal_page.dart';
import 'package:xterm/xterm.dart';

/// 多标签会话 + 终端字号缩放。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 地址留空 → 万一真去连也不会做网络 IO（这里基本都注入 preview 会话）
  const hostA = SshHost(id: 'a', name: '家里的 NAS', hostname: '', username: 'root');
  const hostB = SshHost(id: 'b', name: '云服务器', hostname: '', username: 'ubuntu');

  const phone = Size(360, 800);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TerminalPrefs.debugFontOverride = null;
  });

  tearDown(() => TerminalPrefs.debugFontOverride = null);

  Future<void> pumpAt(WidgetTester tester, Widget home, Size logical) async {
    const dpr = 2.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  /// SnackBar 的自动关闭是个 Timer，不把它放掉测试结束会报 pending timer
  Future<void> flushSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  double terminalFontSize(WidgetTester tester) => tester
      .widget<TerminalView>(find.byType(TerminalView).first)
      .textStyle
      .fontSize;

  // ------------------------------------------------------------ 多标签

  group('多标签', () {
    testWidgets('只有一个标签时标签条也在，但没有关闭按钮', (WidgetTester tester) async {
      await pumpAt(tester, workspace(), phone);

      // 标签条是「发现多标签能力」的唯一入口，藏起来用户根本不会去点菜单
      expect(find.byKey(const Key('tabchip-tab-0')), findsOneWidget);
      expect(find.text('家里的 NAS'), findsWidgets);
      expect(
        find.byIcon(Icons.close),
        findsNothing,
        reason: '只有一个标签时给个叉，等于鼓励用户误触退出',
      );
      expect(find.byKey(const Key('tab-strip-add')), findsOneWidget);
    });

    testWidgets('从「＋」选一台主机开新标签，两个终端同时活着', (WidgetTester tester) async {
      final sessionA = TerminalSession.preview(hostA);
      final sessionB = TerminalSession.preview(hostB);

      await pumpAt(
        tester,
        workspace(
          first: sessionA,
          options: <SshHost>[hostA, hostB],
          sessions: <SshHost, TerminalSession>{hostB: sessionB},
        ),
        phone,
      );

      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));
      expect(state.tabCount, 1);

      await tester.tap(find.byKey(const Key('tab-strip-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('云服务器'));
      await tester.pumpAndSettle();

      expect(state.tabCount, 2);
      expect(state.activeHostName, '云服务器');
      // ★ 必须 skipOffstage: false。IndexedStack 会把没选中的孩子标成"不在台上"，
      //   默认的 finder 只能看见当前那一个；但它们的 State 是活的 ——
      //   这正是我们要的（切回去滚动位置和输出都还在）。
      expect(
        find.byType(TerminalView, skipOffstage: false),
        findsNWidgets(2),
        reason: '切走的标签要留在 IndexedStack 里，不能销毁（否则滚动位置和输出全丢）',
      );
      expect(
        find.byType(TerminalView),
        findsOneWidget,
        reason: '同时在台上的只该有一个，不然两层终端会叠着画',
      );
      expect(
        state.activeSession,
        same(sessionB),
        reason: '新标签要指向新会话，不是复用第一个',
      );
    });

    testWidgets('已经开着的机器在新标签弹窗里点不动', (WidgetTester tester) async {
      await pumpAt(
        tester,
        workspace(
          options: <SshHost>[hostA, hostB],
          sessions: <SshHost, TerminalSession>{
            hostA: TerminalSession.preview(hostA),
            hostB: TerminalSession.preview(hostB),
          },
        ),
        phone,
      );

      await tester.tap(find.byKey(const Key('tab-strip-add')));
      await tester.pumpAndSettle();

      final opened = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('家里的 NAS'),
          matching: find.byType(ListTile),
        ),
      );
      expect(opened.enabled, isFalse, reason: '同一台机器开两个标签没有意义，直接禁掉');
    });

    testWidgets('切标签后按键发给新标签，旧标签同时交出焦点', (WidgetTester tester) async {
      final sessionA = TerminalSession.preview(hostA);
      final sessionB = TerminalSession.preview(hostB);

      await pumpAt(
        tester,
        workspace(
          first: sessionA,
          options: <SshHost>[hostA, hostB],
          sessions: <SshHost, TerminalSession>{hostB: sessionB},
        ),
        phone,
      );
      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));

      // 开第二个标签（会自动切过去）
      await tester.tap(find.byKey(const Key('tab-strip-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('云服务器'));
      await tester.pumpAndSettle();

      // 模拟"用户正在 B 里打字"
      await tester.tap(find.byType(TerminalView).last);
      await tester.pumpAndSettle();
      expect(state.terminalHasFocus, isTrue);

      // 点第一个标签切回去
      await tester.tap(find.byKey(const Key('tabchip-tab-0')));
      await tester.pumpAndSettle();

      expect(state.activeHostName, '家里的 NAS');
      expect(
        state.terminalHasFocus,
        isFalse,
        reason: '不交还焦点的话软键盘会赖着不走，而按键已经发给另一个标签了',
      );

      // 这时候点终端，字节只能进 A
      sessionA.debugSentBytes.clear();
      sessionB.debugSentBytes.clear();
      final buffer = sessionA.terminal.buffer;
      state.handleTapAtCell(
        CellOffset(buffer.cursorX + 2, buffer.absoluteCursorY),
      );
      expect(
        String.fromCharCodes(sessionA.debugSentBytes),
        '\x1B[C\x1B[C',
        reason: '字节应该发给当前标签',
      );
      expect(sessionB.debugSentBytes, isEmpty);
    });

    testWidgets('关掉当前标签后自动落到前一个', (WidgetTester tester) async {
      await pumpAt(
        tester,
        workspace(
          options: <SshHost>[hostA, hostB],
          sessions: <SshHost, TerminalSession>{
            hostA: TerminalSession.preview(hostA),
            hostB: TerminalSession.preview(hostB),
          },
        ),
        phone,
      );
      final state = tester.state<TerminalPageState>(find.byType(TerminalPage));

      await tester.tap(find.byKey(const Key('tab-strip-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('云服务器'));
      await tester.pumpAndSettle();
      expect(state.activeHostName, '云服务器');

      // 两个标签 → 两个叉，点第二个（当前这个）
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      expect(state.tabCount, 1);
      expect(state.activeHostName, '家里的 NAS');
      expect(
        find.byType(TerminalView, skipOffstage: false),
        findsOneWidget,
        reason: '被关掉的标签必须从树上摘掉，不能只是不显示',
      );
    });
  });

  // ------------------------------------------------------------ 字号缩放

  group('字号缩放', () {
    testWidgets('缩放组显示当前字号，＋ / − 都能改，终端样式跟着变', (WidgetTester tester) async {
      await pumpAt(tester, workspace(), phone);

      expect(find.byKey(const Key('zoom-level')), findsOneWidget);
      expect(terminalFontSize(tester), TerminalPrefs.defaultFont);
      expect(find.text('${TerminalPrefs.defaultFont.round()}'), findsOneWidget);

      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.pumpAndSettle();
      expect(terminalFontSize(tester), TerminalPrefs.defaultFont + 1);
      expect(find.text('${(TerminalPrefs.defaultFont + 1).round()}'), findsOneWidget);

      await tester.tap(find.byKey(const Key('zoom-out')));
      await tester.pumpAndSettle();
      expect(terminalFontSize(tester), TerminalPrefs.defaultFont);
    });

    testWidgets('缩放不额外占高度（快捷键栏高度不变）', (WidgetTester tester) async {
      await pumpAt(tester, workspace(), phone);
      expect(
        tester.getSize(find.byType(SoftKeys)).height,
        lessThanOrEqualTo(100),
        reason: '缩放组是塞进已有那一排的，不该把按键栏撑高',
      );
    });

    testWidgets('到上下限后按钮失效，不会无限放大', (WidgetTester tester) async {
      TerminalPrefs.debugFontOverride = TerminalPrefs.maxFont;
      await pumpAt(tester, workspace(), phone);

      expect(terminalFontSize(tester), TerminalPrefs.maxFont);
      final plus = tester.widget<InkWell>(find.byKey(const Key('zoom-in')));
      expect(plus.onTap, isNull, reason: '到顶了要把按钮灰掉，而不是按了没反应');

      final minus = tester.widget<InkWell>(find.byKey(const Key('zoom-out')));
      expect(minus.onTap, isNotNull);

      await tester.tap(find.byKey(const Key('zoom-out')));
      await tester.pumpAndSettle();
      expect(terminalFontSize(tester), TerminalPrefs.maxFont - 1);
      await flushSnackBars(tester);
    });

    testWidgets('字号写进本地存储，重开页面还认得', (WidgetTester tester) async {
      await pumpAt(tester, workspace(), phone);

      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(TerminalPrefs.fontKey), TerminalPrefs.defaultFont + 1);

      // 重新挂一次页面，应该读回刚才那个字号
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      TerminalPrefs.debugFontOverride = null;
      await pumpAt(tester, workspace(), phone);
      expect(terminalFontSize(tester), TerminalPrefs.defaultFont + 1);
    });
  });
}

/// 造一个终端页：第一个标签直接注入会话，后面开的标签从 [sessions] 里取。
Widget workspace({
  TerminalSession? first,
  List<SshHost>? options,
  Map<SshHost, TerminalSession>? sessions,
}) {
  const hostA = SshHost(id: 'a', name: '家里的 NAS', hostname: '', username: 'root');
  return TerminalPage(
    host: hostA,
    sessionOverride: first ?? TerminalSession.preview(hostA),
    keyCombos: KeyCombo.defaults,
    hostOptions: options,
    sessionFactory: (SshHost host) =>
        sessions?[host] ?? TerminalSession.preview(host),
  );
}
