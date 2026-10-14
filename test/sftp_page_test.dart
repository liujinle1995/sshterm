import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/models/remote_entry.dart';
import 'package:sshterm/services/demo_fs.dart';
import 'package:sshterm/services/local_store.dart';
import 'package:sshterm/ui/sftp_page.dart';

/// SFTP 文件管理的交互。跑在假文件树（[DemoFs]）上，不碰网络。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const home = '/home/lele';

  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sshterm_sftp');
    LocalStore.debugRoot = tempRoot;
  });

  tearDown(() {
    LocalStore.debugRoot = null;
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  Future<SftpPageState> pumpSftp(
    WidgetTester tester, {
    DemoFs? fs,
    String initialPath = home,
    Size size = const Size(390, 820),
  }) async {
    const dpr = 2.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = size * dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: SftpPage(fs: fs ?? DemoFs(), initialPath: initialPath),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<SftpPageState>(find.byType(SftpPage));
  }

  Future<void> flushSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  /// 传输走的是真实的 dart:io。flutter_test 的 pumpAndSettle 跑在假时钟上，
  /// 推不动真实文件系统 —— 必须用 runAsync 把控制权还给真实事件循环，
  /// 否则就是死等（下载那个用例最早就是卡在这儿超时的）。
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var round = 0; round < 80; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (done()) return;
    }
  }

  Finder tile(String path) => find.byKey(ValueKey<String>('sftp-$path'));

  Future<void> openMenu(WidgetTester tester, String path) async {
    await tester.tap(
      find.descendant(of: tile(path), matching: find.byTooltip('操作')),
    );
    await tester.pumpAndSettle();
  }

  group('浏览', () {
    testWidgets('列出目录内容，隐藏文件默认折叠、能切出来', (WidgetTester tester) async {
      await pumpSftp(tester);

      expect(tile('/home/lele/notes.md'), findsOneWidget);
      expect(tile('/home/lele/projects'), findsOneWidget);
      expect(
        tile('/home/lele/.bashrc'),
        findsNothing,
        reason: '点开头的文件默认折叠，否则 home 目录一上来全是配置噪声',
      );

      await tester.tap(find.byTooltip('显示隐藏项'));
      await tester.pumpAndSettle();
      expect(tile('/home/lele/.bashrc'), findsOneWidget);
      expect(tile('/home/lele/.ssh'), findsOneWidget);
    });

    testWidgets('文件显示大小和修改时间，目录显示"目录"', (WidgetTester tester) async {
      await pumpSftp(tester);
      expect(find.textContaining('46 MB'), findsOneWidget);
      expect(find.textContaining('目录 · 2026-10-14'), findsWidgets);
    });

    testWidgets('点进子目录，面包屑能跳回上一级', (WidgetTester tester) async {
      final state = await pumpSftp(tester);

      await tester.tap(tile('/home/lele/projects'));
      await tester.pumpAndSettle();

      expect(state.currentPath, '/home/lele/projects');
      expect(tile('/home/lele/projects/sshterm'), findsOneWidget);
      expect(tile('/home/lele/notes.md'), findsNothing);

      // 面包屑里的 "lele" 那一段
      await tester.tap(find.widgetWithText(TextButton, 'lele'));
      await tester.pumpAndSettle();
      expect(state.currentPath, home);
      expect(tile('/home/lele/notes.md'), findsOneWidget);
    });

    testWidgets('上一级按钮到根目录就灰掉', (WidgetTester tester) async {
      await pumpSftp(tester, initialPath: '/');
      expect(tile('/etc'), findsOneWidget);
      expect(tile('/home'), findsOneWidget);

      // byTooltip 命中的是 Tooltip 本身，要往下取一层才是 IconButton
      final up = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_upward),
      );
      expect(up.onPressed, isNull);
    });
  });

  group('改动远端', () {
    testWidgets('新建文件夹', (WidgetTester tester) async {
      final state = await pumpSftp(tester);

      await tester.tap(find.byTooltip('新建文件夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'backups');
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();

      expect(state.currentPath, home);
      expect(tile('/home/lele/backups'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('重名会被拦下，不会把弹窗关掉', (WidgetTester tester) async {
      await pumpSftp(tester);

      await tester.tap(find.byTooltip('新建文件夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'projects');
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();

      expect(find.text('当前目录已有同名项'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget, reason: '弹窗应该留着让用户改名字');
    });

    testWidgets('重命名', (WidgetTester tester) async {
      await pumpSftp(tester);

      await openMenu(tester, '/home/lele/notes.md');
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'notes-2026.md');
      await tester.tap(find.widgetWithText(FilledButton, '重命名'));
      await tester.pumpAndSettle();

      expect(tile('/home/lele/notes-2026.md'), findsOneWidget);
      expect(tile('/home/lele/notes.md'), findsNothing);
      await flushSnackBars(tester);
    });

    testWidgets('删除要确认，确认后条目消失', (WidgetTester tester) async {
      await pumpSftp(tester);

      await openMenu(tester, '/home/lele/notes.md');
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('此操作不可撤销'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(tile('/home/lele/notes.md'), findsNothing);
      await flushSnackBars(tester);
    });
  });

  group('传输与查看', () {
    testWidgets('点文本文件打开预览，内容读的是远端', (WidgetTester tester) async {
      await pumpSftp(tester);

      await tester.tap(tile('/home/lele/notes.md'));
      await tester.pumpAndSettle();

      final page = tester.widget<SftpTextPage>(find.byType(SftpTextPage));
      expect(utf8.decode(page.bytes), contains('部署笔记'));
    });

    testWidgets('二进制文件不硬套文本框，改成问要不要下载', (WidgetTester tester) async {
      await pumpSftp(tester);

      await tester.tap(tile('/home/lele/backup-2026-10-12.tar.gz'));
      await tester.pumpAndSettle();

      expect(find.text('不是文本文件'), findsOneWidget);
      expect(tile('/home/lele/backup-2026-10-12.tar.gz'), findsOneWidget);
    });

    testWidgets('下载到本机：写进传输目录，内容一致', (WidgetTester tester) async {

      final state = await pumpSftp(tester);

      await openMenu(tester, '/home/lele/deploy.sh');
      await tester.tap(find.text('下载到本机'));
      await tester.pump();

      final saved = File('${tempRoot.path}/transfer/deploy.sh');
      await waitFor(
        tester,
        () => !state.busy && saved.existsSync() && saved.lengthSync() > 0,
      );
      expect(saved.existsSync(), isTrue, reason: '应该落在 App 的传输目录里');
      expect(saved.readAsStringSync(), contains('flutter build apk'));
      await flushSnackBars(tester);
    });

    testWidgets('上传：传输目录里的文件能传上去并出现在列表里', (WidgetTester tester) async {
      final transfer = Directory('${tempRoot.path}/transfer')
        ..createSync(recursive: true);
      File('${transfer.path}/hello.txt').writeAsStringSync('from phone');

      final state = await pumpSftp(tester);

      await tester.tap(find.byTooltip('上传到当前目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('hello.txt'));
      await tester.pump();

      await waitFor(
        tester,
        () =>
            !state.busy &&
            state.visibleEntries.any((RemoteEntry e) => e.name == 'hello.txt'),
      );
      await tester.pumpAndSettle();

      expect(tile('/home/lele/hello.txt'), findsOneWidget);
      expect(state.currentPath, home);
      await flushSnackBars(tester);
    });

    testWidgets('属性弹窗把权限和时间都列出来', (WidgetTester tester) async {
      await pumpSftp(tester);

      // .bashrc 是隐藏项，先把它放出来
      await tester.tap(find.byTooltip('显示隐藏项'));
      await tester.pumpAndSettle();
      await openMenu(tester, '/home/lele/.bashrc');
      await tester.tap(find.text('属性'));
      await tester.pumpAndSettle();

      expect(find.text('-rw-r--r--'), findsOneWidget);
      expect(find.text('2026-10-14 09:41'), findsOneWidget);
    });
  });

  group('错误处理', () {
    testWidgets('目录打不开时给中文原因和重试按钮', (WidgetTester tester) async {
      final fs = DemoFs()
        ..failNext = StateError('permissionDenied: /home/lele');
      final state = await pumpSftp(tester, fs: fs);

      expect(find.text('权限不足'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(state.visibleEntries, isNotEmpty);
      expect(tile('/home/lele/notes.md'), findsOneWidget);
    });
  });

  group('远端条目模型', () {
    test('大文件在列表里显示成 MB 而不是一长串数字', () {
      const entry = RemoteEntry(
        name: 'backup.tar.gz',
        path: '/home/lele/backup.tar.gz',
        type: RemoteEntryType.file,
        size: 48234048,
      );
      expect(entry.sizeLabel, '46 MB');
    });
  });
}
