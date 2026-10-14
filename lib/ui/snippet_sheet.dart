import 'package:flutter/material.dart';

import '../models/command_snippet.dart';
import '../services/snippet_store.dart';
import '../services/terminal_session.dart';
import 'snippet_page.dart';

/// 终端页底部的命令抽屉：点一下就把命令发到当前会话。
///
/// 不占常驻屏幕空间 —— 手机竖屏本来就窄，再钉一排 chips 终端就没地方了。
Future<void> showSnippetSheet(BuildContext context, TerminalSession session) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _SnippetSheet(session: session),
  );
}

class _SnippetSheet extends StatefulWidget {
  const _SnippetSheet({required this.session});

  final TerminalSession session;

  @override
  State<_SnippetSheet> createState() => _SnippetSheetState();
}

class _SnippetSheetState extends State<_SnippetSheet> {
  final _store = SnippetStore();
  final _searchController = TextEditingController();
  late Future<List<CommandSnippet>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.load();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _run(CommandSnippet snippet) {
    widget.session.sendText(
      snippet.newline ? '${snippet.command}\r' : snippet.command,
    );
    Navigator.of(context).pop();
  }

  Future<void> _openManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SnippetPage(),
      ),
    );
    if (!mounted) return;
    setState(() => _future = _store.load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text('常用命令', style: TextStyle(fontSize: 15.5)),
                ),
                TextButton.icon(
                  onPressed: _openManager,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('管理'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 19),
                hintText: '搜命令',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CommandSnippet>>(
              future: _future,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<CommandSnippet>> snap,
                  ) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final all = snap.data ?? const <CommandSnippet>[];
                    if (all.isEmpty) {
                      return Center(
                        child: TextButton.icon(
                          onPressed: _openManager,
                          icon: const Icon(Icons.add),
                          label: const Text('还没有命令，去添加'),
                        ),
                      );
                    }

                    final visible = query.isEmpty
                        ? all
                        : all
                              .where(
                                (CommandSnippet s) =>
                                    s.name.toLowerCase().contains(query) ||
                                    s.command.toLowerCase().contains(query) ||
                                    s.category.toLowerCase().contains(query),
                              )
                              .toList();

                    if (visible.isEmpty) {
                      return const Center(child: Text('没匹配到命令'));
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                      children: <Widget>[
                        for (final entry in _grouped(
                          visible,
                        ).entries) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 12, 0, 6),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: entry.value
                                .map(
                                  (CommandSnippet s) => _CommandChip(
                                    snippet: s,
                                    onTap: () => _run(s),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    );
                  },
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, List<CommandSnippet>> _grouped(List<CommandSnippet> list) {
  final order = <String>[];
  final buckets = <String, List<CommandSnippet>>{};
  for (final snippet in list) {
    buckets
        .putIfAbsent(snippet.category, () {
          order.add(snippet.category);
          return <CommandSnippet>[];
        })
        .add(snippet);
  }
  return <String, List<CommandSnippet>>{
    for (final key in order) key: buckets[key]!,
  };
}

class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.snippet, required this.onTap});

  final CommandSnippet snippet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ActionChip(
      key: ValueKey<String>('snippet-${snippet.id}'),
      avatar: snippet.newline
          ? Icon(Icons.keyboard_return, size: 14, color: scheme.primary)
          : Icon(
              Icons.edit_outlined,
              size: 13,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
      label: Text(snippet.name),
      tooltip: snippet.command,
      onPressed: onTap,
    );
  }
}
