import 'package:flutter/material.dart';

import '../services/catalog.dart';
import 'adaptive.dart';

/// 插件 / 模块清单。数据来自 `assets/plugins.json`，改那个文件即可，
/// 不必碰代码。
class PluginListPage extends StatelessWidget {
  const PluginListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('插件列表')),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: FutureBuilder<List<PluginEntry>>(
          future: CatalogService().plugins(),
          builder:
              (BuildContext context, AsyncSnapshot<List<PluginEntry>> snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final plugins = snap.data ?? const <PluginEntry>[];
                if (plugins.isEmpty) {
                  return const Center(child: Text('插件清单没加载到'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  itemCount: plugins.length,
                  separatorBuilder: (BuildContext _, int _) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final plugin = plugins[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: _KindBadge(kind: plugin.kind),
                      title: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              plugin.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            plugin.version,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        plugin.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                PluginDetailPage(plugin: plugin),
                          ),
                        );
                      },
                    );
                  },
                );
              },
        ),
      ),
    );
  }
}

class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.plugin});

  final PluginEntry plugin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(plugin.name)),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                _KindBadge(kind: plugin.kind),
                const SizedBox(width: 8),
                Text(
                  'v${plugin.version}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              plugin.summary,
              style: const TextStyle(fontSize: 14.5, height: 1.55),
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 8),
            _MetaRow(label: '基于', value: plugin.package),
            _MetaRow(label: '标识', value: plugin.id),
            _MetaRow(
              label: '状态',
              value: switch (plugin.kind) {
                PluginKind.core => '核心能力，不可关闭',
                PluginKind.builtin => plugin.enabled ? '已启用' : '已停用',
                PluginKind.planned => '规划中，尚未实现',
              },
            ),
            if (plugin.details.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '说明',
                style: TextStyle(fontSize: 12.5, color: scheme.primary),
              ),
              const SizedBox(height: 6),
              ...plugin.details.map(
                (String line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 8),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final PluginKind kind;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (kind) {
      PluginKind.core => (Colors.teal.shade800, Colors.teal.shade50),
      PluginKind.builtin => (Colors.indigo.shade800, Colors.indigo.shade50),
      PluginKind.planned => (Colors.grey.shade700, Colors.grey.shade200),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(kind.label, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}
