import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/remote_entry.dart';
import '../services/local_store.dart';
import '../services/remote_fs.dart';
import '../services/remote_path.dart';
import 'adaptive.dart';

/// SFTP 文件管理。
///
/// 只认 [RemoteFs] 接口，不认 dartssh2 —— 所以预览截图和 widget 测试可以喂一份
/// 内存文件树（`DemoFs`）把整套交互跑通，不需要真的连一台机器。
class SftpPage extends StatefulWidget {
  const SftpPage({super.key, required this.fs, this.initialPath});

  final RemoteFs fs;

  /// 预览 / 测试用：直接指定起始目录，跳过 `home()`
  final String? initialPath;

  @override
  State<SftpPage> createState() => SftpPageState();
}

class SftpPageState extends State<SftpPage> {
  String _path = '/';
  List<RemoteEntry> _entries = <RemoteEntry>[];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _showHidden = false;

  /// 传输中的任务描述（底部显示一条进度条）
  String? _busy;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 测试用：当前目录
  @visibleForTesting
  String get currentPath => _path;

  /// 测试用：当前列出来的东西（已过滤隐藏文件）
  @visibleForTesting
  List<RemoteEntry> get visibleEntries => _visible(_entries);

  /// 测试用：有没有传输/改动正在进行（顶部进度条的状态）。
  /// 传输本身跑在真实 IO 上，测试要等它真的收尾（进度条停掉）才能 pumpAndSettle，
  /// 否则会一直等那个无限循环的指示器。
  @visibleForTesting
  bool get busy => _busy != null;

  Future<void> _bootstrap() async {
    try {
      final start = widget.initialPath ?? await widget.fs.home();
      await _load(start);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = fsErrorMessage(error);
      });
    }
  }

  Future<void> _load(String path, {bool refresh = false}) async {
    // ★ 一进来就把 _path 挪到目标位置，而不是等 list 成功再挪。
    //   否则首次加载失败时 _path 还停在 '/'，面包屑显示的是根目录、
    //   点「重试」也是去重列根目录 —— 用户看到的"重试没反应"就是这么来的。
    _path = RemotePath.normalize(path);
    setState(() {
      if (refresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final entries = await widget.fs.list(path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = fsErrorMessage(error);
      });
    }
  }

  List<RemoteEntry> _visible(List<RemoteEntry> source) => _showHidden
      ? source
      : source.where((RemoteEntry e) => !e.isHidden).toList();

  // ------------------------------------------------------------------ 操作

  Future<void> _enter(RemoteEntry entry) async {
    final target = await _resolve(entry.path);
    await _load(target);
  }

  Future<String> _resolve(String path) async {
    try {
      return await widget.fs.canonical(path);
    } catch (_) {
      // canonical 失败（老服务端不支持 realpath）就退回自己拼的绝对路径
      return RemotePath.normalize(path);
    }
  }

  Future<void> _goHome() async {
    final home = await widget.fs.home();
    await _load(home);
  }

  Future<void> _newFolder() async {
    final name = await _askText(
      title: '新建文件夹',
      hint: '例如 backups',
      confirmLabel: '创建',
      validate: _validateName,
    );
    if (name == null) return;

    await _run('正在创建 $name', () async {
      await widget.fs.mkdir(RemotePath.join(_path, name));
      await _load(_path, refresh: true);
      _toast('已创建 $name');
    });
  }

  Future<void> _rename(RemoteEntry entry) async {
    final name = await _askText(
      title: '重命名',
      hint: entry.name,
      initial: entry.name,
      confirmLabel: '重命名',
      validate: _validateName,
    );
    if (name == null || name == entry.name) return;

    await _run('正在重命名', () async {
      await widget.fs.rename(entry.path, RemotePath.join(_path, name));
      await _load(_path, refresh: true);
      _toast('已重命名为 $name');
    });
  }

  Future<void> _delete(RemoteEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(entry.isDirectory ? '删除目录' : '删除文件'),
        content: Text(
          entry.isDirectory
              // 目录删不掉的原因是 rmdir 只能删空目录，提前说清楚省得用户
              // 以为是 App 的 bug
              ? '确定删除「${entry.name}」吗？\n\nSFTP 只能删空目录，'
                    '里面的东西需要先手动清掉。'
              : '确定删除「${entry.name}」吗？此操作不可撤销。',
        ),
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

    await _run('正在删除 ${entry.name}', () async {
      await widget.fs.remove(entry);
      await _load(_path, refresh: true);
      _toast('已删除 ${entry.name}');
    });
  }

  Future<void> _download(RemoteEntry entry) async {
    await _run('正在下载 ${entry.name}', () async {
      final file = await LocalStore.createIncoming(entry.name);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in widget.fs.openRead(entry.path)) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted) {
            setState(() => _busy = '正在下载 ${entry.name}（${RemoteEntry.formatBytes(received)}）');
          }
        }
      } finally {
        await sink.close();
      }
      _toast(
        '已保存 ${RemoteEntry.formatBytes(received)} 到\n${file.path}',
        seconds: 6,
      );
    });
  }

  Future<void> _upload() async {
    final source = await showModalBottomSheet<File>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => const _UploadPicker(),
    );
    if (source == null) return;

    final name = RemotePath.basename(source.path);
    await _run('正在上传 $name', () async {
      final bytes = await source.readAsBytes();
      await widget.fs.writeBytes(RemotePath.join(_path, name), bytes);
      await _load(_path, refresh: true);
      _toast('已上传 $name（${RemoteEntry.formatBytes(bytes.length)}）');
    });
  }

  Future<void> _preview(RemoteEntry entry) async {
    if (!entry.isTextLike) {
      final download = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('不是文本文件'),
          content: Text('「${entry.name}」不方便直接打开查看，要下载到本机吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      if (download == true) await _download(entry);
      return;
    }

    setState(() => _busy = '正在读取 ${entry.name}');
    try {
      final bytes = await widget.fs.readBytes(entry.path);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              SftpTextPage(title: entry.name, bytes: bytes),
        ),
      );
    } catch (error) {
      if (mounted) _toast('打不开：${fsErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _properties(RemoteEntry entry) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(entry.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PropertyRow('路径', entry.path),
            _PropertyRow(
              '类型',
              switch (entry.type) {
                RemoteEntryType.directory => '目录',
                RemoteEntryType.file => '普通文件',
                RemoteEntryType.symlink => '符号链接',
                RemoteEntryType.other => '特殊文件',
              },
            ),
            if (!entry.isDirectory)
              _PropertyRow('大小', entry.sizeLabel),
            _PropertyRow('权限', entry.permissions.isEmpty ? '未知' : entry.permissions),
            _PropertyRow(
              '修改时间',
              entry.modifiedLabel.isEmpty ? '未知' : entry.modifiedLabel,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 行内操作菜单（每个条目右边那个 ⋮）
  Future<void> _entryMenu(RemoteEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              dense: true,
              leading: const Icon(Icons.badge_outlined),
              title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                entry.permissions.isEmpty
                    ? entry.path
                    : '${entry.permissions}'
                          '${entry.isDirectory ? '' : ' · ${entry.sizeLabel}'}',
              ),
            ),
            const Divider(height: 1),
            if (!entry.isDirectory)
              _MenuTile(
                icon: entry.isTextLike
                    ? Icons.visibility_outlined
                    : Icons.info_outline,
                label: entry.isTextLike ? '查看内容' : '文件信息',
                onTap: () => Navigator.of(context).pop('view'),
              ),
            if (!entry.isDirectory)
              _MenuTile(
                icon: Icons.download_outlined,
                label: '下载到本机',
                onTap: () => Navigator.of(context).pop('download'),
              ),
            _MenuTile(
              icon: Icons.drive_file_rename_outline,
              label: '重命名',
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            _MenuTile(
              icon: Icons.delete_outline,
              label: '删除',
              danger: true,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            _MenuTile(
              icon: Icons.info_outline,
              label: '属性',
              onTap: () => Navigator.of(context).pop('info'),
            ),
          ],
        ),
      ),
    );

    switch (action) {
      case 'view':
        await _preview(entry);
      case 'download':
        await _download(entry);
      case 'rename':
        await _rename(entry);
      case 'delete':
        await _delete(entry);
      case 'info':
        _properties(entry);
    }
  }

  // ------------------------------------------------------------------ 小工具

  String? _validateName(String value) {
    final name = value.trim();
    if (name.isEmpty) return '名字不能为空';
    if (name.contains('/')) return '名字里不能带 /';
    if (name == '.' || name == '..') return '这个名字不能用';
    if (_entries.any((RemoteEntry e) => e.name == name)) return '当前目录已有同名项';
    return null;
  }

  Future<String?> _askText({
    required String title,
    required String confirmLabel,
    String? hint,
    String? initial,
    String? Function(String)? validate,
  }) {
    final controller = TextEditingController(text: initial);
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint, errorText: errorText),
            onChanged: (String value) {
              if (errorText == null) return;
              setLocal(() => errorText = null);
            },
            onSubmitted: (String value) {
              final error = validate?.call(value);
              if (error != null) {
                setLocal(() => errorText = error);
                return;
              }
              Navigator.of(context).pop(value.trim());
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text;
                final error = validate?.call(value);
                if (error != null) {
                  setLocal(() => errorText = error);
                  return;
                }
                Navigator.of(context).pop(value.trim());
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// 统一包一层：转圈 → 干活 → 出错弹提示 → 收尾
  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = label);
    try {
      await action();
    } catch (error) {
      if (mounted) _toast('失败：${fsErrorMessage(error)}', danger: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _toast(String message, {bool danger = false, int seconds = 3}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: seconds),
          backgroundColor: danger ? scheme.errorContainer : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '上传到当前目录',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _busy == null ? _upload : null,
          ),
          IconButton(
            tooltip: '新建文件夹',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _busy == null ? _newFolder : null,
          ),
          IconButton(
            tooltip: '回到主目录',
            icon: const Icon(Icons.home_outlined),
            onPressed: _busy == null ? _goHome : null,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _busy == null ? () => _load(_path, refresh: true) : null,
          ),
        ],
        bottom: _busy == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: const LinearProgressIndicator(minHeight: 2),
              ),
      ),
      body: SafeArea(
        child: ReadableWidth(
          child: Column(
            children: <Widget>[
              _pathBar(),
              const Divider(height: 1),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pathBar() {
    final crumbs = RemotePath.crumbs(_path);
    return SizedBox(
      height: 42,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一级',
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: _path == '/'
                ? null
                : () => _load(RemotePath.parent(_path)),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: crumbs.length,
              itemBuilder: (BuildContext context, int index) {
                final crumb = crumbs[index];
                final last = index == crumbs.length - 1;
                return Row(
                  children: <Widget>[
                    if (index > 0)
                      Text(
                        '/',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    TextButton(
                      onPressed: last ? null : () => _load(crumb),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: last
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      child: Text(
                        index == 0 ? '根目录' : crumb.split('/').last,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: last ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            tooltip: _showHidden ? '不显示隐藏项' : '显示隐藏项',
            icon: Icon(
              _showHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 19,
            ),
            onPressed: () => setState(() => _showHidden = !_showHidden),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_refreshing && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.folder_off_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text('打不开 $_path', style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _load(_path),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _visible(_entries);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.inbox_outlined,
              size: 46,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _entries.isEmpty ? '空目录' : '没有可见项（隐藏文件已折叠）',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 62),
      itemBuilder: (BuildContext context, int index) =>
          _entryTile(items[index]),
    );
  }

  Widget _entryTile(RemoteEntry entry) {
    return ListTile(
      key: ValueKey<String>('sftp-${entry.path}'),
      leading: _EntryIcon(entry: entry),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          // 隐藏项淡一点，一眼能看出它是 dotfile
          color: entry.isHidden
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
              : null,
        ),
      ),
      subtitle: Text(
        entry.isDirectory
            ? (entry.modifiedLabel.isEmpty ? '目录' : '目录 · ${entry.modifiedLabel}')
            : '${entry.sizeLabel}'
                  '${entry.modifiedLabel.isEmpty ? '' : ' · ${entry.modifiedLabel}'}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: IconButton(
        tooltip: '操作',
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: _busy == null ? () => _entryMenu(entry) : null,
      ),
      onTap: _busy != null
          ? null
          : () {
              if (entry.isDirectory) {
                _enter(entry);
              } else {
                _preview(entry);
              }
            },
      onLongPress: _busy == null ? () => _entryMenu(entry) : null,
    );
  }
}

// ---------------------------------------------------------------------- 子组件

/// 按后缀挑图标，比清一色的文件图标好认得多
class _EntryIcon extends StatelessWidget {
  const _EntryIcon({required this.entry});

  final RemoteEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = _describe(scheme, entry);
    return CircleAvatar(
      radius: 17,
      backgroundColor: color.withValues(alpha: 0.14),
      child: Icon(icon, size: 18, color: color),
    );
  }

  static (IconData, Color) _describe(ColorScheme scheme, RemoteEntry entry) {
    if (entry.isDirectory) return (Icons.folder_rounded, scheme.primary);
    if (entry.isSymlink) return (Icons.link_rounded, scheme.tertiary);

    final name = entry.name.toLowerCase();
    if (name.endsWith('.tar.gz') ||
        name.endsWith('.tgz') ||
        name.endsWith('.zip') ||
        name.endsWith('.gz') ||
        name.endsWith('.xz')) {
      return (Icons.folder_zip_outlined, Colors.orange.shade700);
    }
    if (name.endsWith('.sh') || name.endsWith('.bash') || name.endsWith('.zsh')) {
      return (Icons.terminal, Colors.teal.shade600);
    }
    if (name.endsWith('.log')) return (Icons.receipt_long_outlined, Colors.brown.shade400);
    if (name.endsWith('.md') || name.endsWith('.txt')) {
      return (Icons.description_outlined, Colors.blueGrey.shade400);
    }
    if (name.endsWith('.yaml') ||
        name.endsWith('.yml') ||
        name.endsWith('.json') ||
        name.endsWith('.toml') ||
        name.endsWith('.ini') ||
        name.endsWith('.conf')) {
      return (Icons.tune, Colors.deepPurple.shade300);
    }
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif')) {
      return (Icons.image_outlined, Colors.pink.shade300);
    }
    return (Icons.insert_drive_file_outlined, scheme.onSurfaceVariant);
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 上传的来源选择。
///
/// App 自己的传输目录是首选项 —— 不需要任何存储权限，插上数据线就能往里丢文件。
/// 想上传别处的文件就走下面那个手填路径的入口。
class _UploadPicker extends StatefulWidget {
  const _UploadPicker();

  @override
  State<_UploadPicker> createState() => _UploadPickerState();
}

class _UploadPickerState extends State<_UploadPicker> {
  late Future<List<FileSystemEntity>> _files;
  final TextEditingController _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    _files = LocalStore.listForUpload();
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _useManualPath() async {
    final path = _manual.text.trim();
    if (path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这个路径下没有文件')),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(file);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('选择要上传的文件', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            FutureBuilder<String>(
              future: LocalStore.transferDir().then((Directory d) => d.path),
              builder: (BuildContext context, AsyncSnapshot<String> snap) => Text(
                'App 的传输目录：${snap.data ?? '…'}\n'
                '把文件拷进这个目录，或用下面的输入框填绝对路径。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: FutureBuilder<List<FileSystemEntity>>(
                future: _files,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<FileSystemEntity>> snap,
                    ) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final items = snap.data!;
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            '传输目录还是空的',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (BuildContext context, int index) {
                          final file = items[index] as File;
                          final size = file.statSync().size;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.insert_drive_file_outlined),
                            title: Text(
                              file.uri.pathSegments.last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(RemoteEntry.formatBytes(size)),
                            onTap: () => Navigator.of(context).pop(file),
                          );
                        },
                      );
                    },
              ),
            ),
            const Divider(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _manual,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '/storage/emulated/0/Download/x.zip',
                      labelText: '或者手填一个绝对路径',
                    ),
                    onSubmitted: (_) => _useManualPath(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _useManualPath,
                  child: const Text('用它'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 文本文件预览。大文件会被截断，并在顶部说明截到哪了。
class SftpTextPage extends StatelessWidget {
  const SftpTextPage({super.key, required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  /// 超过这个大小就只显示前面一段 —— 一个 2MB 的单行 JSON 直接铺出来会卡住渲染
  static const int previewLimit = 262144;

  @override
  Widget build(BuildContext context) {
    final truncated = bytes.length >= previewLimit;
    final text = utf8.decode(
      truncated ? Uint8List.sublistView(bytes, 0, previewLimit) : bytes,
      allowMalformed: true,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              // 不引依赖：用 SnackBar 提示即可，真要复制可以让系统选择菜单来
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('长按正文即可选中、复制')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ReadableWidth(
          child: Column(
            children: <Widget>[
              if (truncated)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: const Text(
                    '文件较大，只显示前 256 KB',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
