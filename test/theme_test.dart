import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/models/ssh_host.dart';
import 'package:sshterm/services/theme_controller.dart';
import 'package:sshterm/services/theme_store.dart';
import 'package:sshterm/theme/app_theme.dart';
import 'package:sshterm/ui/appearance_page.dart';
import 'package:sshterm/ui/soft_keys.dart';
import 'package:sshterm/ui/terminal_page.dart';
import 'package:xterm/xterm.dart';

/// 夜间模式的测试。
///
/// 分两层：
///  * 纯逻辑（存盘 / 兜底 / 三档往返）；
///  * widget —— 切了之后**真的**会重新渲染成另一套颜色，而不只是改了个变量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 全局单例会被设置页测试碰到，每个用例先归位，免得互相串
    ThemeController.instance
      ..value = ThemeStore.fallback
      ..resetLoadedFlag();
  });

  group('ThemeStore', () {
    test('没存过时是深色（保持老版本观感）', () async {
      expect(await ThemeStore().load(), ThemeMode.dark);
    });

    test('三档都能原样存取', () async {
      final store = ThemeStore();
      for (final mode in ThemeMode.values) {
        await store.save(mode);
        expect(await store.load(), mode, reason: '$mode 存取不回来');
      }
      // 顺带确认真的落到了 SharedPreferences，而不是只活在内存里
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ThemeStore.key),
        ThemeStore.encode(ThemeMode.values.last),
      );
    });

    test('存的是字符串不是下标：读不出来的值回落到深色', () {
      expect(ThemeStore.decode('light'), ThemeMode.light);
      expect(ThemeStore.decode('dark'), ThemeMode.dark);
      expect(ThemeStore.decode('system'), ThemeMode.system);
      expect(ThemeStore.decode('0'), ThemeMode.dark);
      expect(ThemeStore.decode(''), ThemeMode.dark);
      expect(ThemeStore.decode(null), ThemeMode.dark);
    });

    test('encode/decode 往返一致', () {
      for (final mode in ThemeMode.values) {
        expect(ThemeStore.decode(ThemeStore.encode(mode)), mode);
      }
    });
  });

  group('ThemeController', () {
    test('初值跟随 store，setMode 后落盘', () async {
      final controller = ThemeController();
      expect(controller.value, ThemeMode.dark);

      await controller.setMode(ThemeMode.light);
      expect(controller.value, ThemeMode.light);
      expect(await ThemeStore().load(), ThemeMode.light);

      // 新实例 load 一次能读到刚才的浅色
      final reloaded = ThemeController();
      await reloaded.load();
      expect(reloaded.value, ThemeMode.light);
    });

    test('重复 load 只读一次盘', () async {
      final controller = ThemeController();
      await controller.load();
      await controller.setMode(ThemeMode.system);
      await controller.load(); // 第二次不该把刚改的值读回去
      expect(controller.value, ThemeMode.system);
    });

    test('三档中文名', () {
      expect(ThemeController.label(ThemeMode.system), '跟随系统');
      expect(ThemeController.label(ThemeMode.light), '浅色');
      expect(ThemeController.label(ThemeMode.dark), '深色');
    });
  });

  group('AppTheme', () {
    test('浅色 / 深色两套 ThemeData', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.of(Brightness.light), same(AppTheme.light));
      expect(AppTheme.of(Brightness.dark), same(AppTheme.dark));
    });

    test('终端配色跟着亮度换，不是同一个黑底', () {
      final dark = AppTheme.terminalTheme(Brightness.dark);
      final light = AppTheme.terminalTheme(Brightness.light);

      expect(dark.background, const Color(0xFF000000));
      expect(light.background, isNot(dark.background));
      expect(
        light.background.computeLuminance(),
        greaterThan(0.5),
        reason: '浅色终端底色应该是亮的',
      );
      expect(
        light.foreground.computeLuminance(),
        lessThan(0.3),
        reason: '浅色终端字色应该是暗的',
      );
      // ANSI 绿在白底上必须看得清 —— xterm 预设那套绿在白底上几乎发白
      expect(light.green.computeLuminance(), lessThan(0.35));
      expect(light.red.computeLuminance(), lessThan(0.35));
    });

    test('外框色深浅不同', () {
      expect(
        AppTheme.chrome(Brightness.dark),
        isNot(AppTheme.chrome(Brightness.light)),
      );
      expect(
        AppTheme.chrome(Brightness.light).computeLuminance(),
        greaterThan(AppTheme.chrome(Brightness.dark).computeLuminance()),
      );
    });
  });

  group('界面', () {
    /// 一个会跟着控制器重建的壳，等价于 main.dart 里那个 MaterialApp
    Widget wrap(ThemeController controller, Widget home) {
      return ValueListenableBuilder<ThemeMode>(
        valueListenable: controller,
        builder: (BuildContext context, ThemeMode mode, Widget? _) =>
            MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,
              home: home,
            ),
      );
    }

    Future<void> pump(WidgetTester tester, Widget widget) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
    }

    testWidgets('外观页三档都在，默认选中深色', (WidgetTester tester) async {
      final controller = ThemeController();
      await pump(
        tester,
        wrap(controller, AppearancePage(controller: controller)),
      );

      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets('点「浅色」立刻换成亮色界面', (WidgetTester tester) async {
      final controller = ThemeController();
      await pump(
        tester,
        wrap(controller, AppearancePage(controller: controller)),
      );

      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(controller.value, ThemeMode.light);

      final context = tester.element(find.text('浅色'));
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        Theme.of(context).scaffoldBackgroundColor.computeLuminance(),
        greaterThan(0.5),
        reason: '切了浅色却还是暗底 —— 说明有硬编码颜色没跟主题走',
      );

      // 再切回去
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(controller.value, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.text('深色'))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('终端页在浅色下真的变白', (WidgetTester tester) async {
      final controller = ThemeController(initial: ThemeMode.light);
      // 地址留空 → connect() 不做任何网络 IO 就落到 error，
      // 否则测试结束时 socket 的等待定时器还挂着，会被判为 pending timer
      final host = SshHost(id: 'h1', hostname: '', username: 'root');

      await pump(
        tester,
        wrap(
          controller,
          TerminalPage(host: host, keyCombos: KeyCombo.defaults),
        ),
      );

      // 终端本体：不再写死 whiteOnBlack
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(
        view.theme.background,
        AppTheme.terminalTheme(Brightness.light).background,
      );

      // 外框：导航栏和快捷键栏都得跟着浅
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, AppTheme.chrome(Brightness.light));

      final keys = tester.widget<Container>(
        find.byKey(const Key('soft-keys-bar')),
      );
      expect(keys.color, AppTheme.chrome(Brightness.light));
      expect(find.byType(SoftKeys), findsOneWidget);
    });
  });
}
