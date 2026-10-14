import 'package:flutter/material.dart';

import '../models/app_meta.dart';
import '../services/catalog.dart';
import '../services/key_combo_store.dart';
import '../services/snippet_store.dart';
import '../services/theme_controller.dart';
import 'appearance_page.dart';
import 'changelog_page.dart';
import 'key_combo_page.dart';
import 'plugin_list_page.dart';
import 'snippet_page.dart';
import 'adaptive.dart';

/// 设置总入口。四个二级页面都从这里进。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _comboStore = KeyComboStore();
  final _snippetStore = SnippetStore();
  final _catalog = CatalogService();

  int _comboCount = 0;
  int _snippetCount = 0;
  int _pluginCount = 0;
  String _latestVersion = '—';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      _comboStore.load(),
      _snippetStore.load(),
      _catalog.plugins(),
      _catalog.changelog(),
    ]);
    if (!mounted) return;

    final combos = results[0] as List;
    final snippets = results[1] as List;
    final plugins = results[2] as List;
    final releases = results[3] as List<ReleaseNote>;

    setState(() {
      _comboCount = combos.length;
      _snippetCount = snippets.length;
      _pluginCount = plugins.length;
      _latestVersion = releases.isNotEmpty ? releases.first.version : '—';
    });
  }

  /// 从二级页返回时刷新计数（那边可能刚增删过）
  Future<void> _refresh<T>(Object? _) async {
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            const _SectionHeader(title: '输入'),
            _EntryTile(
              icon: Icons.keyboard_command_key,
              title: '快捷键组合',
              subtitle: '软键盘第二排，共 $_comboCount 个',
              onTap: () => _push<void>(const KeyComboPage()).then(_refresh),
            ),
            _EntryTile(
              icon: Icons.terminal_outlined,
              title: '常用命令',
              subtitle: '终端里一键发送，共 $_snippetCount 条',
              onTap: () => _push<void>(const SnippetPage()).then(_refresh),
            ),
            const _SectionHeader(title: '外观'),
            // 副标题要跟着主题变化，所以套一层监听
            ListenableBuilder(
              listenable: ThemeController.instance,
              builder: (BuildContext context, Widget? _) => _EntryTile(
                icon: Icons.dark_mode_outlined,
                title: '夜间模式',
                subtitle:
                    '当前：${ThemeController.label(ThemeController.instance.value)}',
                onTap: () => _push<void>(const AppearancePage()).then(_refresh),
              ),
            ),
            const _SectionHeader(title: '关于'),
            _EntryTile(
              icon: Icons.extension_outlined,
              title: '插件列表',
              subtitle: '内置模块清单，共 $_pluginCount 项',
              onTap: () => _push<void>(const PluginListPage()).then(_refresh),
            ),
            _EntryTile(
              icon: Icons.history_outlined,
              title: '更新记录',
              subtitle: '当前版本 $_latestVersion',
              onTap: () => _push<void>(const ChangelogPage()).then(_refresh),
            ),
            _EntryTile(
              icon: Icons.info_outline,
              title: '关于 ${AppMeta.name}',
              subtitle: '${AppMeta.package} · ${AppMeta.fullVersion}',
              onTap: () => _showAbout(context, scheme),
            ),
          ],
        ),
      ),
    );
  }

  Future<T?> _push<T>(Widget page) {
    return Navigator.of(context)
        .push<T>(MaterialPageRoute<T>(builder: (BuildContext context) => page));
  }
}

Future<void> _showAbout(BuildContext context, ColorScheme scheme) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      icon: Icon(Icons.terminal_outlined, color: scheme.primary),
      title: const Text(AppMeta.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('版本 ${AppMeta.fullVersion}'),
          const SizedBox(height: 10),
          const Text(
            '用 Flutter + dartssh2 + xterm 从零写的手机 SSH 终端，'
            '整包都是 Dart 代码，不依赖任何原生 .so。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('好'),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 21),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
