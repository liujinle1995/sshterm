import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../services/credential_store.dart';
import '../services/host_store.dart';
import 'host_edit_page.dart';
import 'settings_page.dart';
import 'terminal_page.dart';
import 'adaptive.dart';

class HostListPage extends StatefulWidget {
  const HostListPage({super.key});

  @override
  State<HostListPage> createState() => _HostListPageState();
}

class _HostListPageState extends State<HostListPage> {
  final _store = HostStore();

  List<SshHost> _hosts = <SshHost>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hosts = await _store.load();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _loading = false;
    });
  }

  Future<void> _persist(List<SshHost> hosts) async {
    setState(() => _hosts = hosts);
    await _store.save(hosts);
  }

  Future<void> _openEditor({SshHost? host}) async {
    final result = await Navigator.of(context).push<SshHost>(
      MaterialPageRoute<SshHost>(
        builder: (BuildContext context) => HostEditPage(host: host),
      ),
    );
    if (result == null) return;

    final next = List<SshHost>.of(_hosts);
    final index = next.indexWhere((SshHost h) => h.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.insert(0, result);
    }
    await _persist(next);
  }

  Future<void> _delete(SshHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除主机'),
        content: Text('确定删除「${host.displayName}」吗？保存的密码/私钥会一并清掉。'),
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

    await CredentialStore.removeHostSecrets(host.id);
    if (host.privateKeyId != null) {
      await CredentialStore.removeKey(host.privateKeyId!);
    }
    await _persist(_hosts.where((SshHost h) => h.id != host.id).toList());
  }

  void _connect(SshHost host) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => TerminalPage(host: host),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 终端'),
        actions: <Widget>[
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const SettingsPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '添加主机',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hosts.isEmpty
          ? _EmptyState(onAdd: () => _openEditor())
          : _hostList(),
    );
  }

  /// 主机列表。窄屏一行一台；屏幕宽到能并排放两张卡片（平板 / 手机横屏）时
  /// 换成网格 —— 否则一张卡片会被横向拉成一米长，图标和按钮隔着半个屏。
  Widget _hostList() {
    if (!Adaptive.isWide(context)) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _hosts.length,
        itemBuilder: (BuildContext context, int index) =>
            _hostTile(_hosts[index], margin: const EdgeInsets.only(bottom: 8)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // 460 是"卡片里那行文字刚好不换行"的宽度，再宽就该多排一列而不是继续拉长
        maxCrossAxisExtent: 460,
        mainAxisExtent: 92,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _hosts.length,
      itemBuilder: (BuildContext context, int index) =>
          _hostTile(_hosts[index], margin: EdgeInsets.zero),
    );
  }

  Widget _hostTile(SshHost host, {required EdgeInsets margin}) {
    return Dismissible(
      key: ValueKey<String>(host.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade900,
        child: const Icon(Icons.delete_outline, color: Colors.white70),
      ),
      confirmDismiss: (DismissDirection _) async {
        await _delete(host);
        return false; // 由 _delete 自己维护列表，避免双重删除
      },
      child: Card(
        margin: margin,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            child: Icon(
              host.authMethod == HostAuthMethod.privateKey
                  ? Icons.vpn_key_outlined
                  : Icons.terminal_outlined,
              size: 19,
            ),
          ),
          title: Text(
            host.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${host.username.isEmpty ? '<未填用户>' : host.username}@${host.endpoint}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _openEditor(host: host),
              ),
              IconButton(
                tooltip: '连接',
                icon: const Icon(Icons.play_arrow, size: 22),
                onPressed: () => _connect(host),
              ),
            ],
          ),
          onTap: () => _connect(host),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.terminal_outlined,
              size: 60,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            const Text('还没有主机', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              '点下面的按钮，把你的 Linux 加进来',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('添加主机'),
            ),
          ],
        ),
      ),
    );
  }
}
