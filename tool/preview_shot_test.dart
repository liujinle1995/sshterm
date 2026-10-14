// 用真实 widget 树渲染预览图（无 GUI 环境）。
//
//   SHOT=01 flutter test tool/preview_shot_test.dart --no-pub
//
// 放在 tool/ 而不是 test/：`flutter test` 默认只扫 test/，
// 这样日常跑测试不会顺带写出一堆 PNG。
//
// 为什么场景号要从环境变量读、而不是 --dart-define：
// --dart-define 会改变 kernel 缓存键，每张图都得全量重编译。
//
// 整个文件都在调 @visibleForTesting 的注入口（preview 会话、假存储、主题单例），
// analyzer 因为这里不是 test/ 目录会逐个报，索性整文件关掉。
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/models/ssh_host.dart';
import 'package:sshterm/services/catalog.dart';
import 'package:sshterm/services/demo_fs.dart';
import 'package:sshterm/services/terminal_prefs.dart';
import 'package:sshterm/services/terminal_session.dart';
import 'package:sshterm/services/theme_controller.dart';
import 'package:sshterm/services/theme_store.dart';
import 'package:sshterm/theme/app_theme.dart';
import 'package:sshterm/ui/appearance_page.dart';
import 'package:sshterm/ui/changelog_page.dart';
import 'package:sshterm/ui/host_list_page.dart';
import 'package:sshterm/ui/key_combo_page.dart';
import 'package:sshterm/ui/plugin_list_page.dart';
import 'package:sshterm/ui/settings_page.dart';
import 'package:sshterm/ui/sftp_page.dart';
import 'package:sshterm/ui/snippet_page.dart';
import 'package:sshterm/ui/terminal_page.dart';

const String _outDir = 'design/preview';

const String _shotDefine = String.fromEnvironment('SHOT');
final String _shot = _shotDefine.isNotEmpty
    ? _shotDefine
    : (Platform.environment['SHOT'] ?? '01');

const String _transcript =
    '\x1B[90mLast login: Tue Oct 13 22:58:41 2026 '
    'from 10.10.10.2\x1B[0m\r\n'
    'Welcome to Ubuntu 24.04.1 LTS (GNU/Linux 6.8.0-45-generic x86_64)\r\n'
    '\r\n'
    '\x1B[32mroot@nas\x1B[0m:\x1B[34m~\x1B[0m# ls -lh\r\n'
    'total 28K\r\n'
    'drwxr-xr-x 4 root root 4.0K Oct 12 21:03 backups\r\n'
    'drwxr-xr-x 2 root root 4.0K Oct 10 09:41 docker\r\n'
    '-rw-r--r-- 1 root root 1.2K Oct 13 22:41 notes.md\r\n'
    '\x1B[32mroot@nas\x1B[0m:\x1B[34m~\x1B[0m# docker ps --format '
    "'{{.Names}}\\t{{.Status}}'\r\n"
    'nginx\tUp 6 days\r\n'
    'postgres\tUp 6 days (healthy)\r\n'
    'gitea\tUp 3 days\r\n'
    '\x1B[32mroot@nas\x1B[0m:\x1B[34m~\x1B[0m# ';

/// 一个截图场景：一个 build 回调 + 一段可选的交互。
/// 画布尺寸统一用 [_shotWidth] x [_shotHeight]，不按图调。
class _Shot {
  const _Shot({
    required this.name,
    required this.build,
    this.after,
    this.brightness = Brightness.dark,
    this.size = const Size(_shotWidth, _shotHeight),
    this.dpr = _dpr,
    this.fontSize,
  });

  final String name;
  final Widget Function() build;

  /// 这一张用深色还是浅色渲染。夜间模式相关的几张要成对出图。
  final Brightness brightness;

  /// 画布尺寸（逻辑像素）。平板场景用横屏 1280x800。
  final Size size;

  /// 3x 只给手机用；1280 宽的平板再 3x 就 3840 像素，图大得没必要
  final double dpr;

  /// 渲染前要做的交互（点按钮开抽屉之类）
  final Future<void> Function(WidgetTester tester)? after;

  /// 这一张要把终端字号设成多少（缩放功能的效果图用）
  final double? fontSize;
}

/// 预览用的主机清单：平板上要能看出"多列卡片"的效果，至少得有几台
const List<SshHost> _previewHosts = <SshHost>[
  SshHost(id: 'p1', name: '家里的 NAS', hostname: '10.10.10.5', username: 'root'),
  SshHost(id: 'p2', name: '云服务器', hostname: '47.98.12.34', username: 'ubuntu'),
  SshHost(id: 'p3', name: '树莓派', hostname: '10.10.10.9', username: 'pi'),
  SshHost(id: 'p4', name: '老笔记本', hostname: '192.168.1.77', username: 'lele'),
  SshHost(id: 'p5', name: '路由器', hostname: '192.168.1.1', username: 'admin'),
];

/// 所有截图统一按 3x 密度渲染（和主流安卓机一致）
const double _dpr = 3;

const double _shotWidth = 360;
const double _shotHeight = 780;

SshHost get _host => SshHost(
  id: 'preview',
  name: '家里的 NAS',
  hostname: '10.10.10.5',
  username: 'root',
);

TerminalSession _terminalSession({bool blank = false}) {
  final session = TerminalSession.preview(_host);
  if (!blank) session.terminal.write(_transcript);
  return session;
}

Widget _terminal({bool blank = false}) => TerminalPage(
  host: _host,
  sessionOverride: _terminalSession(blank: blank),
  keyCombos: KeyCombo.defaults,
);

/// 终端字体没有中文，提示符里的主机名得用拉丁字母，
/// 否则截图里会是一串豆腐块（真机上用户自己的主机名也一样）
const Map<String, String> _latinHostAlias = <String, String>{
  'p1': 'nas',
  'p2': 'cloud',
  'p3': 'rpi',
  'p4': 'laptop',
  'p5': 'router',
};

/// 带输出的预览会话，多标签那张图要三个标签都有东西可看
TerminalSession _sessionFor(SshHost host) {
  final session = TerminalSession.preview(host);
  final alias = _latinHostAlias[host.id] ?? 'host';
  session.terminal.write(
    '\x1B[90mLast login: Tue Oct 13 22:58:41 2026 from 10.10.10.2\x1B[0m\r\n'
    '\x1B[32m${host.username}@$alias\x1B[0m:\x1B[34m~\x1B[0m\$ uptime\r\n'
    ' 16:52:03 up 6 days,  3:14,  1 user,  load average: 0.08, 0.12, 0.09\r\n'
    '\x1B[32m${host.username}@$alias\x1B[0m:\x1B[34m~\x1B[0m\$ ',
  );
  return session;
}

/// 三个标签的终端页。after 里点两次「＋」把另外两台开出来 ——
/// 走的是用户真会走的那条路，不是摆拍。
Widget _multiTabTerminal() => TerminalPage(
  host: _previewHosts[0],
  sessionOverride: _sessionFor(_previewHosts[0]),
  keyCombos: KeyCombo.defaults,
  hostOptions: _previewHosts,
  sessionFactory: _sessionFor,
);

Future<void> _openTwoMoreTabs(WidgetTester tester) async {
  for (final String name in <String>['云服务器', '树莓派']) {
    await tester.tap(find.byKey(const Key('tab-strip-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }
}

Widget _sftp() => SftpPage(fs: DemoFs(), initialPath: '/home/lele');

/// 文本预览页：直接喂 DemoFs 里那份 notes.md 的真内容
Widget _sftpText() => SftpTextPage(
  title: 'notes.md',
  bytes: Uint8List.fromList(
    utf8.encode('''
# 部署笔记

## 上线流程
1. `./deploy.sh build` 出包
2. `systemctl restart sshterm` 重启服务
3. 看 `/home/lele/logs/app.log` 确认没有异常栈

## 常用排查
- 端口占用：`ss -lntp | grep 8080`
- 磁盘满：`df -h` / `du -sh /var/log/*`
- 昨天那次 OOM 是 `backup-*.tar.gz` 在 /home 下堆了 46G

> 记住：改完 nginx.conf 先 `nginx -t` 再 reload。
'''),
  ),
);

List<PluginEntry> _readPlugins() {
  final json = jsonDecode(
    File('assets/plugins.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return (json['plugins'] as List<dynamic>)
      .whereType<Map<String, dynamic>>()
      .map(PluginEntry.fromJson)
      .toList();
}

List<ReleaseNote> _readChangelog() {
  final json = jsonDecode(
    File('assets/changelog.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return (json['releases'] as List<dynamic>)
      .whereType<Map<String, dynamic>>()
      .map(ReleaseNote.fromJson)
      .toList();
}

// ignore: library_private_types_in_public_api
Map<String, _Shot> buildShots() {
  final plugins = _readPlugins();

  return <String, _Shot>{
    '01': _Shot(name: '01_terminal.png', build: _terminal),
    '02': _Shot(
      name: '02_snippet_sheet.png',
      build: _terminal,
      after: (WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
      },
    ),
    '03': _Shot(
      name: '03_key_combo_page.png',
      build: () => const KeyComboPage(),
    ),
    '04': _Shot(name: '04_snippet_page.png', build: () => const SnippetPage()),
    '05': _Shot(
      name: '05_settings_page.png',
      build: () => const SettingsPage(),
    ),
    '06': _Shot(
      name: '06_plugin_list.png',
      build: () => const PluginListPage(),
    ),
    '07': _Shot(
      name: '07_plugin_detail.png',
      build: () => PluginDetailPage(plugin: plugins.first),
    ),
    // 最新一版默认就是展开的，进页面即见
    '08': _Shot(name: '08_changelog.png', build: () => const ChangelogPage()),
    '09': _Shot(
      name: '09_changelog_older.png',
      build: () => const ChangelogPage(debugExpandIndex: 1),
    ),
    // ---- 夜间模式：同一批页面出深浅两份，方便对照
    '10': _Shot(
      name: '10_appearance_page.png',
      build: () => const AppearancePage(),
    ),
    '11': _Shot(
      name: '11_terminal_light.png',
      build: _terminal,
      brightness: Brightness.light,
    ),
    '12': _Shot(
      name: '12_settings_light.png',
      build: () => const SettingsPage(),
      brightness: Brightness.light,
    ),
    '13': _Shot(
      name: '13_appearance_light.png',
      build: () => const AppearancePage(),
      brightness: Brightness.light,
    ),
    // ---- 宽屏 / 平板：1280x800 横屏，手机那张留着做对照
    '14': _Shot(
      name: '14_host_list_phone.png',
      build: () => const HostListPage(),
      size: Size(360, 780),
    ),
    '15': _Shot(
      name: '15_host_list_tablet.png',
      build: () => const HostListPage(),
      size: Size(1280, 800),
      dpr: 2,
    ),
    '16': _Shot(
      name: '16_terminal_tablet.png',
      build: _terminal,
      size: Size(1280, 800),
      dpr: 2,
    ),
    '17': _Shot(
      name: '17_settings_tablet.png',
      build: () => const SettingsPage(),
      size: Size(1280, 800),
      dpr: 2,
    ),
    '18': _Shot(
      name: '18_snippet_sheet_tablet.png',
      build: _terminal,
      size: Size(1280, 800),
      dpr: 2,
      after: (WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
      },
    ),
    // ---- 多标签：一次连三台机器
    '19': _Shot(
      name: '19_tabs_phone.png',
      build: _multiTabTerminal,
      after: _openTwoMoreTabs,
    ),
    '20': _Shot(
      name: '20_tabs_tablet.png',
      build: _multiTabTerminal,
      after: _openTwoMoreTabs,
      size: Size(1280, 800),
      dpr: 2,
    ),
    '21': _Shot(
      name: '21_tab_picker.png',
      build: _multiTabTerminal,
      after: (WidgetTester tester) async {
        await tester.tap(find.byKey(const Key('tab-strip-add')));
        await tester.pumpAndSettle();
      },
    ),
    // ---- SFTP
    '22': _Shot(name: '22_sftp_page.png', build: _sftp),
    '23': _Shot(
      name: '23_sftp_light.png',
      build: _sftp,
      brightness: Brightness.light,
    ),
    '24': _Shot(name: '24_sftp_text.png', build: _sftpText),
    '25': _Shot(
      name: '25_sftp_tablet.png',
      build: _sftp,
      size: Size(1280, 800),
      dpr: 2,
    ),
    // ---- 字号缩放：17 号字，跟默认 13 号对比很直观
    '26': _Shot(
      name: '26_terminal_zoom.png',
      build: _terminal,
      fontSize: 17,
    ),
  };
}

// ---------------------------------------------------------------- 字体

final String _materialFontsDir = () {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/home/lele/flutter';
  return '$root/bin/cache/artifacts/material_fonts';
}();

Future<void> _loadFonts() async {
  Future<ByteData> load(String path) async =>
      ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

  final latin = FontLoader('AppLatin')
    ..addFont(load('$_materialFontsDir/Roboto-Regular.ttf'))
    ..addFont(load('$_materialFontsDir/Roboto-Bold.ttf'));
  final cjk = FontLoader(
    'AppCJK',
  )..addFont(load('/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf'));
  // 代码里有 fontFamily: 'monospace' 的标签，不注册就是整片空白
  final mono = FontLoader('monospace')
    ..addFont(load('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'));
  // 不注册所有 Icon() 都是空心方块
  final icons = FontLoader('MaterialIcons')
    ..addFont(load('$_materialFontsDir/MaterialIcons-Regular.otf'));

  await latin.load();
  await cjk.load();
  await mono.load();
  await icons.load();
}

/// 用 App 里那套真实主题（只额外塞上预览用的字体），
/// 这样截图里的深浅配色就是用户真机上看到的。
ThemeData _previewTheme(Brightness brightness) {
  final base = AppTheme.of(brightness);
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'AppLatin',
      fontFamilyFallback: const <String>['AppCJK'],
    ),
  );
}

// ---------------------------------------------------------------- 主流程

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // widget 测试环境没有插件通道，两个 Store 会走 try/catch 兜底。
  // 给了 mock 才能真正读到"存进去"的值，预览图才有内容。
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // flutter test 不打包 asset，rootBundle 必定失败 —— 直接把 json 喂给 Catalog
  CatalogService.debugPluginsOverride = _readPlugins();
  CatalogService.debugChangelogOverride = _readChangelog();

  testWidgets('render preview $_shot', (WidgetTester tester) async {
    await _loadFonts();
    final shot = buildShots()[_shot]!;

    // 设置页 / 外观页读的是全局主题单例，把"当前：xx"的文案和这张图的
    // 亮度对齐，否则浅色截图里会写着"当前：深色"，看着像 bug。
    //
    // 注意外观页在 initState 里还会 load() 一次（真正从磁盘读），
    // 所以光改单例不够，mock 出来的"磁盘值"也得是同一档。
    final mode = shot.brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeStore.key: ThemeStore.encode(mode),
      // 主机列表也走本地存储，不喂数据的话截出来是空状态
      'sshterm.hosts.v1': jsonEncode(
        _previewHosts.map((SshHost h) => h.toJson()).toList(),
      ),
    });
    ThemeController.instance
      ..resetLoadedFlag()
      ..value = mode;

    // 字号是全局偏好，预览里直接注入，免得依赖本地存储
    TerminalPrefs.debugFontOverride = shot.fontSize;

    tester.view.physicalSize = shot.size * shot.dpr;
    tester.view.devicePixelRatio = shot.dpr;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _previewTheme(shot.brightness),
          home: shot.build(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.pump();

    final after = shot.after;
    if (after != null) {
      await after(tester);
      await tester.pump();
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    // ★ 必须放进 runAsync：fake-async 区里 toImage 之后任何 pump 都会永久挂起
    ByteData? png;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.35);
      png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
    });

    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/${shot.name}').writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('written -> $_outDir/${shot.name}');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
