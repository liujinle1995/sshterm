import 'package:flutter/material.dart';

import '../models/command_snippet.dart';
import '../services/snippet_store.dart';
import 'adaptive.dart';

/// 常用命令管理：增 / 删 / 改。
///
/// 终端页的底部抽屉会读同一份数据，这里改完返回终端立即生效。
class SnippetPage extends StatefulWidget {
  const SnippetPage({super.key});

  @override
  State<SnippetPage> createState() => _SnippetPageState();
}

class _SnippetPageState extends State<SnippetPage> {
  final _store = SnippetStore();
  final _searchController = TextEditingController();

  List<CommandSnippet> _all = <CommandSnippet>[];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _store.load();
    if (!mounted) return;
    setState(() {
      _all = items;
      _loading = false;
    });
  }

  Future<void> _persist(List<CommandSnippet> items) async {
    setState(() => _all = items);
    await _store.save(items);
  }

  List<CommandSnippet> get _visible {
    if (_query.isEmpty) return _all;
    final lower = _query.toLowerCase();
    return _all
        .where(
          (CommandSnippet s) =>
              s.name.toLowerCase().contains(lower) ||
              s.command.toLowerCase().contains(lower) ||
              s.category.toLowerCase().contains(lower),
        )
        .toList();
  }

  /// 按分类分区，同时保留既有的分组顺序（不是字母序）
  List<MapEntry<String, List<CommandSnippet>>> get _sections {
    final order = <String>[];
    final buckets = <String, List<CommandSnippet>>{};
    for (final snippet in _visible) {
      final bucket = buckets.putIfAbsent(snippet.category, () {
        order.add(snippet.category);
        return <CommandSnippet>[];
      });
      bucket.add(snippet);
    }
    return order
        .map(
          (String c) => MapEntry<String, List<CommandSnippet>>(c, buckets[c]!),
        )
        .toList();
  }

  // ------------------------------------------------------------------ 操作

  Future<void> _openEditor({CommandSnippet? existing}) async {
    final result = await showModalBottomSheet<CommandSnippet>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _SnippetEditorSheet(
        initial: existing,
        categories: _all.map((CommandSnippet s) => s.category).toSet().toList()
          ..sort(),
      ),
    );
    if (result == null) return;

    final next = List<CommandSnippet>.of(_all);
    final index = next.indexWhere((CommandSnippet s) => s.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.insert(0, result);
    }
    await _persist(next);
  }

  Future<void> _delete(CommandSnippet snippet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除命令'),
        content: Text('确定删掉「${snippet.name}」吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _persist(
      _all.where((CommandSnippet s) => s.id != snippet.id).toList(),
    );
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('当前所有自定义命令会被预设列表覆盖，无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.reset();
    await _load();
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final sections = _sections;

    return Scaffold(
      appBar: AppBar(
        title: const Text('常用命令'),
        actions: <Widget>[
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetDefaults,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: '新增命令',
        child: const Icon(Icons.add),
      ),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: '搜命令名或内容',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _searchController.clear,
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _all.isEmpty
                        ? const Center(child: Text('一条命令都没有'))
                        : sections.isEmpty
                        ? const Center(child: Text('没有匹配的命令'))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: sections.length,
                            itemBuilder: (BuildContext context, int index) {
                              final entry = sections[index];
                              return _CategorySection(
                                category: entry.key,
                                snippets: entry.value,
                                onEdit: _openEditor,
                                onDelete: _delete,
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.snippets,
    required this.onEdit,
    required this.onDelete,
  });

  final String category;
  final List<CommandSnippet> snippets;
  final Future<void> Function({CommandSnippet existing}) onEdit;
  final Future<void> Function(CommandSnippet snippet) onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 16, 4),
          child: Row(
            children: <Widget>[
              Text(
                category,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${snippets.length}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        ...snippets.map(
          (CommandSnippet snippet) => Dismissible(
            key: ValueKey<String>(snippet.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red.shade900,
              child: const Icon(Icons.delete_outline, color: Colors.white70),
            ),
            confirmDismiss: (DismissDirection _) async {
              await onDelete(snippet);
              return false; // 列表由 onDelete 自己维护
            },
            child: ListTile(
              dense: true,
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      snippet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_return,
                    size: 14,
                    color: snippet.newline
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.18),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  snippet.command.isEmpty ? '<空>' : snippet.command,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
              trailing: IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: () => onEdit(existing: snippet),
              ),
              onTap: () => onEdit(existing: snippet),
            ),
          ),
        ),
      ],
    );
  }
}

class _SnippetEditorSheet extends StatefulWidget {
  const _SnippetEditorSheet({this.initial, required this.categories});

  final CommandSnippet? initial;
  final List<String> categories;

  @override
  State<_SnippetEditorSheet> createState() => _SnippetEditorSheetState();
}

class _SnippetEditorSheetState extends State<_SnippetEditorSheet> {
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _categoryController = TextEditingController();
  final _noteController = TextEditingController();
  late bool _newline;

  /// 类型签名的问题：TextEditingController 的 listener 要用 void Function()
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController.text = initial?.name ?? '';
    _commandController.text = initial?.command ?? '';
    _categoryController.text = initial?.category ?? '常用';
    _noteController.text = initial?.note ?? '';
    _newline = initial?.newline ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameController.text.trim().isNotEmpty &&
      _commandController.text.isNotEmpty;

  void _save() {
    if (!_valid) return;

    final initial = widget.initial;
    final note = _noteController.text.trim();
    final category = _categoryController.text.trim().isEmpty
        ? '常用'
        : _categoryController.text.trim();

    final snippet = CommandSnippet(
      id: initial?.id ?? CommandSnippet.newId(),
      name: _nameController.text.trim(),
      command: _commandController.text.replaceAll('\r\n', '\n').trimRight(),
      category: category,
      newline: _newline,
      note: note.isEmpty ? null : note,
    );
    Navigator.of(context).pop(snippet);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.initial == null ? '新增命令' : '编辑命令',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  FilledButton(
                    onPressed: _valid ? _save : null,
                    child: const Text('保存'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: <Widget>[
                  TextField(
                    key: const Key('field-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '手机屏幕上显示的名字',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (String _) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('field-command'),
                    controller: _commandController,
                    decoration: const InputDecoration(
                      labelText: '命令',
                      hintText: 'journalctl -xeu nginx',
                      isDense: true,
                      alignLabelWithHint: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    maxLines: 3,
                    minLines: 2,
                    onChanged: (String _) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _categoryController,
                    decoration: InputDecoration(
                      labelText: '分类',
                      isDense: true,
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: '选已有分类',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (String value) =>
                            setState(() => _categoryController.text = value),
                        itemBuilder: (BuildContext context) => widget.categories
                            .map(
                              (String c) => PopupMenuItem<String>(
                                value: c,
                                child: Text(c),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('发送后立即执行'),
                    subtitle: const Text(
                      '关掉的话只把命令填到命令行上，方便自己补参数',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _newline,
                    onChanged: (bool v) => setState(() => _newline = v),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: '备注（选填）',
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
