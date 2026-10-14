import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/models/ssh_host.dart';
import 'package:sshterm/ui/soft_keys.dart';
import 'package:sshterm/ui/terminal_page.dart';
import 'package:xterm/xterm.dart';

/// 回归：`_KeyChip` 里的 `Center` 在宽松约束下会取 `constraints.biggest`，
/// 放进 `Wrap` 就成了「一个键占满一整行」，20 个键排成 20 行、把终端压成 0 高度，
/// 整个界面看起来"全是快捷键"。
void main() {
  // 主机地址留空 → connect() 不做任何网络 IO 就立刻落到 error，
  // 这样 widget 测试里不会留悬挂的 socket / 定时器。
  final host = SshHost(id: 'h1', hostname: '', username: 'root');

  Future<void> pumpTerminal(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 直接给一组组合，省得 FutureBuilder 在测试里异步读本地存储
    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(host: host, keyCombos: KeyCombo.defaults),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('快捷键栏高度固定，不会把终端挤没', (WidgetTester tester) async {
    await pumpTerminal(tester);

    const screenHeight = 800.0; // 1080/3 x 2400/3 = 360 x 800 逻辑像素

    final keysSize = tester.getSize(find.byType(SoftKeys));
    final terminalSize = tester.getSize(find.byType(TerminalView));

    expect(
      keysSize.height,
      lessThanOrEqualTo(100),
      reason: '快捷键栏撑到了 ${keysSize.height}px，说明又变成竖排多行了',
    );
    expect(
      terminalSize.height,
      greaterThan(screenHeight * 0.6),
      reason: '终端只剩 ${terminalSize.height}px，被快捷键栏挤扁了',
    );
    expect(terminalSize.width, greaterThan(0));
  });

  testWidgets('单个按键贴着文字宽度，不是占满整行', (WidgetTester tester) async {
    await pumpTerminal(tester);

    // 短标签不该有整屏那么宽。注意 ListView.builder 是懒构建的，
    // 屏幕外的键（如 PgDn）压根没进 widget 树，只能断言可见的那几个。
    for (final label in <String>['Ctrl', 'Esc', 'Tab', 'Ctrl+C']) {
      final finder = find.byKey(ValueKey<String>('softkey-$label'));
      expect(finder, findsOneWidget, reason: '按键 "$label" 应该可见');
      final size = tester.getSize(finder);
      expect(
        size.width,
        lessThan(120),
        reason: '按键 "$label" 宽 ${size.width}px —— Center 又把宽度撑满了',
      );
      expect(size.height, lessThanOrEqualTo(34));
    }
  });

  testWidgets('可以收起快捷键栏，把空间让给终端', (WidgetTester tester) async {
    await pumpTerminal(tester);

    final before = tester.getSize(find.byType(TerminalView)).height;
    expect(find.byType(SoftKeys), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_hide));
    await tester.pumpAndSettle();

    expect(find.byType(SoftKeys), findsNothing);
    final after = tester.getSize(find.byType(TerminalView)).height;
    expect(after, greaterThan(before));

    // 还能再展开回来
    await tester.tap(find.byIcon(Icons.keyboard));
    await tester.pumpAndSettle();
    expect(find.byType(SoftKeys), findsOneWidget);
    expect(tester.getSize(find.byType(TerminalView)).height, before);
  });

  testWidgets('两排按键都能横向滚动，不换行', (WidgetTester tester) async {
    await pumpTerminal(tester);

    // 横向 ListView 两排；若哪天被改回 Wrap，最先看到的就是行数变化
    final rows = tester
        .widgetList<ListView>(
          find.descendant(
            of: find.byType(SoftKeys),
            matching: find.byType(ListView),
          ),
        )
        .toList();
    expect(rows.length, 2);
    for (final row in rows) {
      expect(row.scrollDirection, Axis.horizontal);
    }
  });
}
