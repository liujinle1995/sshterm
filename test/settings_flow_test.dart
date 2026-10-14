import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshterm/models/command_snippet.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/services/theme_controller.dart';
import 'package:sshterm/services/theme_store.dart';
import 'package:sshterm/ui/key_combo_page.dart';
import 'package:sshterm/ui/settings_page.dart';
import 'package:sshterm/ui/snippet_page.dart';

/// 设置页及其四个入口的冒烟测试。
///
/// 为什么一定要 mock SharedPreferences：widget 测试环境里没有插件通道，
/// 真调用 SharedPreferences.getInstance() 会抛 MissingPluginException。
/// Store 内部虽然有 try/catch 兜底（生产里必须这么做，否则终端页会连带崩），
/// 但兜底后读到的永远是预设值，覆盖不到"真的存进去了"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 夜间模式是全局单例，切过之后会串到别的用例上，先归位
    ThemeController.instance
      ..value = ThemeStore.fallback
      ..resetLoadedFlag();
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('设置页列出全部入口', (WidgetTester tester) async {
    await pumpApp(tester, const SettingsPage());

    expect(find.text('快捷键组合'), findsOneWidget);
    expect(find.text('常用命令'), findsOneWidget);
    expect(find.text('夜间模式'), findsOneWidget);
    expect(find.text('插件列表'), findsOneWidget);
    expect(find.text('更新记录'), findsOneWidget);

    // 副标题里会显示实时数量
    expect(
      find.textContaining('共 ${KeyCombo.defaults.length} 个'),
      findsOneWidget,
    );
    expect(
      find.textContaining('共 ${CommandSnippet.defaults.length} 条'),
      findsOneWidget,
    );
  });

  testWidgets('夜间模式能切到浅色，返回后设置页跟着更新', (WidgetTester tester) async {
    await pumpApp(tester, const SettingsPage());

    // 没存过 → 深色（保持老版本观感）
    expect(find.textContaining('当前：深色'), findsOneWidget);

    await tester.tap(find.text('夜间模式'));
    await tester.pumpAndSettle();

    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.value, ThemeMode.light);

    // 真的存进去了，不是只改了内存
    expect(await ThemeStore().load(), ThemeMode.light);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('当前：浅色'), findsOneWidget);
  });

  testWidgets('快捷键可以新增和删除', (WidgetTester tester) async {
    await pumpApp(tester, const KeyComboPage());

    // 列表是懒构建的，屏幕外压根没进 widget 树，
    // 所以按"可见文本"断言，而不是数 ListTile 个数。
    expect(find.text('Ctrl+C'), findsWidgets);

    // ---- 新增：默认是 Ctrl+C，再叠个 Alt 让它不和预设重复
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('field-label')), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w is SwitchListTile &&
            (w.title as Text).data == 'Alt （远程机器常叫 Meta）',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 新项插在最前面，不用滚就能看到
    expect(find.text('Ctrl+Alt+C'), findsOneWidget);

    // ---- 删掉刚才那条
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('Ctrl+Alt+C'), findsNothing);
    expect(find.text('Ctrl+C'), findsOneWidget);
  });

  testWidgets('重复的组合会被挡下来', (WidgetTester tester) async {
    await pumpApp(tester, const KeyComboPage());

    // 直接保存默认的 Ctrl+C，应该撞上列表里已有的那条
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已经有一样的组合'), findsOneWidget);
  });

  testWidgets('常用命令可以新增', (WidgetTester tester) async {
    await pumpApp(tester, const SnippetPage());

    expect(find.text('df -h'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 名称或命令有一个是空的，保存按钮必须保持不可点
    expect(
      tester.widget<FilledButton>(
        find.ancestor(of: find.text('保存'), matching: find.byType(FilledButton)),
      ),
      isA<FilledButton>().having(
        (FilledButton b) => b.enabled,
        'enabled',
        isFalse,
      ),
    );

    await tester.enterText(find.byKey(const Key('field-name')), '看看负载');
    await tester.enterText(
      find.byKey(const Key('field-command')),
      'cat /proc/loadavg',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 新命令插到列表最前面
    expect(find.text('看看负载'), findsOneWidget);
    expect(find.text('cat /proc/loadavg'), findsOneWidget);
  });

  testWidgets('搜索能过滤命令', (WidgetTester tester) async {
    await pumpApp(tester, const SnippetPage());

    expect(find.text('df -h'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ip');
    await tester.pumpAndSettle();

    // 'ip -br addr' 留下，'df -h' 被过滤掉
    expect(find.text('ip -br addr'), findsOneWidget);
    expect(find.text('df -h'), findsNothing);
  });
}
