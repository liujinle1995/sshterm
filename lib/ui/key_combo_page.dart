import 'package:flutter/material.dart';

import '../models/key_combo.dart';
import '../services/key_combo_store.dart';
import '../services/keystroke.dart';
import 'adaptive.dart';

/// 快捷键组合管理：增 / 删 / 改 / 排序。
///
/// 列表顺序就是软键盘第二排的显示顺序，所以支持长按拖动排序。
class KeyComboPage extends StatefulWidget {
  const KeyComboPage({super.key});

  @override
  State<KeyComboPage> createState() => _KeyComboPageState();
}

class _KeyComboPageState extends State<KeyComboPage> {
  final _store = KeyComboStore();

  List<KeyCombo> _items = <KeyCombo>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _persist(List<KeyCombo> items) async {
    setState(() => _items = items);
    await _store.save(items);
  }

  // ------------------------------------------------------------------ 操作

  Future<void> _openEditor({KeyCombo? existing}) async {
    final result = await showModalBottomSheet<KeyCombo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _ComboEditorSheet(initial: existing),
    );
    if (result == null) return;

    final duplicateIndex = _items.indexWhere(
      (KeyCombo c) =>
          c.id != result.id &&
          c.key == result.key &&
          c.ctrl == result.ctrl &&
          c.alt == result.alt &&
          c.shift == result.shift,
    );
    if (duplicateIndex >= 0) {
      _snack('已经有一样的组合了（第 ${duplicateIndex + 1} 个）');
      return;
    }

    final next = List<KeyCombo>.of(_items);
    final index = next.indexWhere((KeyCombo c) => c.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      // 插到最前面：列表可能很长，插末尾用户得滚到底才看得见新加的
      next.insert(0, result);
    }
    await _persist(next);
  }

  Future<void> _delete(KeyCombo combo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除快捷键'),
        content: Text('确定删掉「${combo.displayLabel}」吗？'),
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
    await _persist(_items.where((KeyCombo c) => c.id != combo.id).toList());
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final next = List<KeyCombo>.of(_items);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    _persist(next);
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('当前所有自定义快捷键会被预设列表覆盖，无法撤销。'),
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
    _snack('已恢复默认快捷键');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷键组合'),
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
        tooltip: '新增组合',
        child: const Icon(Icons.add),
      ),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? _EmptyHint(onAdd: () => _openEditor())
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
                itemCount: _items.length,
                onReorderItem: _reorder,
                itemBuilder: (BuildContext context, int index) {
                  final combo = _items[index];
                  final bytes = encodeKeyCombo(combo);
                  return ListTile(
                    key: ValueKey<String>(combo.id),
                    leading: const Icon(Icons.drag_handle, size: 20),
                    title: Text(
                      combo.displayLabel,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    subtitle: Text(
                      describeBytes(bytes),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _openEditor(existing: combo),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _delete(combo),
                        ),
                      ],
                    ),
                    onTap: () => _openEditor(existing: combo),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.keyboard_hide, size: 56),
            const SizedBox(height: 14),
            const Text('一个快捷键都没有'),
            const SizedBox(height: 6),
            Text(
              'Ctrl+C 中断进程、Ctrl+D 退出登录这类组合，'
              '手机上必须自己补一个',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增组合'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 组合键编辑器：三个修饰键开关 + 按键选择 + 实际发送预览
class _ComboEditorSheet extends StatefulWidget {
  const _ComboEditorSheet({this.initial});

  final KeyCombo? initial;

  @override
  State<_ComboEditorSheet> createState() => _ComboEditorSheetState();
}

class _ComboEditorSheetState extends State<_ComboEditorSheet> {
  late String _key;
  late bool _ctrl;
  late bool _alt;
  late bool _shift;
  final _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _key = initial?.key ?? 'c';
    _ctrl = initial?.ctrl ?? true;
    _alt = initial?.alt ?? false;
    _shift = initial?.shift ?? false;
    _labelController.text = initial?.label ?? '';
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  KeyCombo get _current => KeyCombo(
    id: widget.initial?.id ?? KeyCombo.newId(),
    key: _key,
    ctrl: _ctrl,
    alt: _alt,
    shift: _shift,
    label: _labelController.text.trim().isEmpty
        ? null
        : _labelController.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final groups = KeyCatalog.groups;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // 用固定高度而不是 DraggableScrollableSheet：后者的内部 controller
    // 会和下面的 ListView 抢滚动手势，键盘弹出时更容易出问题。
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.initial == null ? '新增组合' : '编辑组合',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_current),
                    child: const Text('保存'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: <Widget>[
                  // 当前效果
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: _ComboPreview(combo: _current),
                  ),

                  const _GroupLabel(text: '修饰键'),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Ctrl'),
                    value: _ctrl,
                    onChanged: (bool v) => setState(() => _ctrl = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Alt （远程机器常叫 Meta）'),
                    value: _alt,
                    onChanged: (bool v) => setState(() => _alt = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Shift'),
                    value: _shift,
                    onChanged: (bool v) => setState(() => _shift = v),
                  ),

                  const _GroupLabel(text: '主键'),
                  SizedBox(
                    height: 260,
                    child: DefaultTabController(
                      length: groups.length,
                      child: Column(
                        children: <Widget>[
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: groups.keys
                                .map((String g) => Tab(text: g))
                                .toList(),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: groups.entries
                                  .map(
                                    (MapEntry<String, List<String>> e) =>
                                        _KeyGrid(
                                          keys: e.value,
                                          selected: _key,
                                          onPick: (String key) =>
                                              setState(() => _key = key),
                                        ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const _GroupLabel(text: '自定义显示名（选填）'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      key: const Key('field-label'),
                      controller: _labelController,
                      decoration: const InputDecoration(
                        hintText: '留空就自动显示成 Ctrl+C 这样',
                        isDense: true,
                      ),
                      onChanged: (String _) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComboPreview extends StatelessWidget {
  const _ComboPreview({required this.combo});

  final KeyCombo combo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Text(
            combo.displayLabel,
            style: const TextStyle(
              fontSize: 22,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '实际发送：${describeBytes(encodeKeyCombo(combo))}',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (!combo.hasModifier && combo.key.length == 1) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '没加修饰键：软键盘上点亮粘滞 Ctrl 后，点它就是 Ctrl+'
              '${combo.key.toUpperCase()}',
              style: TextStyle(fontSize: 11, color: scheme.primary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({
    required this.keys,
    required this.selected,
    required this.onPick,
  });

  final List<String> keys;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GridView.count(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      crossAxisCount: 6,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.15,
      children: keys.map((String key) {
        final active = key == selected;
        return Material(
          key: ValueKey<String>('pick-${KeyCatalog.labelOf(key)}'),
          color: active
              ? scheme.primary
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onPick(key),
            child: Center(
              child: Text(
                KeyCatalog.labelOf(key),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: active ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
