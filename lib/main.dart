import 'package:flutter/material.dart';

import 'services/theme_controller.dart';
import 'theme/app_theme.dart';
import 'ui/host_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先把主题读出来再起 UI：否则会先画一帧深色、再闪成浅色
  await ThemeController.instance.load();
  runApp(const SshTermApp());
}

class SshTermApp extends StatelessWidget {
  const SshTermApp({super.key, this.controller});

  /// 测试 / 预览用：换成一个干净的控制器，不污染全局单例
  @visibleForTesting
  final ThemeController? controller;

  @override
  Widget build(BuildContext context) {
    final themeController = controller ?? ThemeController.instance;

    return ListenableBuilder(
      listenable: themeController,
      builder: (BuildContext context, Widget? _) => MaterialApp(
        title: 'SSH 终端',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.value,
        home: const HostListPage(),
      ),
    );
  }
}
