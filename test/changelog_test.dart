import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/services/catalog.dart';
import 'package:sshterm/ui/changelog_page.dart';

/// 更新记录：一层交互。
///
/// 为什么数据要自己从磁盘读进来注入：`flutter test` 不打包项目 asset，
/// `rootBundle.loadString('assets/changelog.json')` 在这个环境里必然失败，
/// 页面会退化成"还没有更新记录"，什么都断言不了。CatalogService 为此留了
/// debugChangelogOverride 这个静态注入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final releases = () {
    final json =
        jsonDecode(File('assets/changelog.json').readAsStringSync())
            as Map<String, dynamic>;
    return (json['releases'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(ReleaseNote.fromJson)
        .toList();
  }();

  setUp(() => CatalogService.debugChangelogOverride = releases);
  tearDown(() => CatalogService.debugChangelogOverride = null);

  /// 视口给高一点：最新一版默认是展开的，占掉不少高度，
  /// 用默认的 800 逻辑高会把第二个版本挤到屏幕外（ListView 懒得构建它）。
  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('进页面就能直接看到最新一版的条目', (WidgetTester tester) async {
    await pump(tester, const ChangelogPage());

    final latest = releases.first;
    expect(find.text('v${latest.version}'), findsOneWidget);
    expect(
      find.text(latest.items.first.text),
      findsOneWidget,
      reason: '最新一版默认就该展开，"看到日志"不该还要再点一次',
    );
  });

  testWidgets('旧版本默认收起，点标题就地展开 / 收起', (WidgetTester tester) async {
    await pump(tester, const ChangelogPage());

    final older = releases[1];
    expect(find.text(older.items.first.text), findsNothing);

    await tester.tap(find.text('v${older.version}'));
    await tester.pumpAndSettle();
    expect(find.text(older.items.first.text), findsOneWidget);

    await tester.tap(find.text('v${older.version}'));
    await tester.pumpAndSettle();
    expect(find.text(older.items.first.text), findsNothing);
  });

  testWidgets('展开是就地发生，不会再推一个二级页', (WidgetTester tester) async {
    await pump(tester, const ChangelogPage());

    final older = releases[1];
    await tester.tap(find.text('v${older.version}'));
    await tester.pumpAndSettle();

    expect(find.text('更新记录'), findsOneWidget);
    expect(
      find.widgetWithText(AppBar, 'v${older.version}'),
      findsNothing,
      reason: '二级页的标题栏是版本号；出现了就说明又退回成两层交互了',
    );
  });

  testWidgets('预览用 debugExpandIndex 能指定默认展开哪一版', (
    WidgetTester tester,
  ) async {
    await pump(tester, const ChangelogPage(debugExpandIndex: 1));

    final older = releases[1];
    expect(find.text(older.items.first.text), findsOneWidget);
    expect(find.text(releases.first.items.first.text), findsNothing);
  });
}
