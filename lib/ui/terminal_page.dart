import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../models/key_combo.dart';
import '../models/ssh_host.dart';
import '../services/host_store.dart';
import '../services/remote_fs.dart';
import '../services/sftp_fs.dart';
import '../services/terminal_prefs.dart';
import '../services/terminal_session.dart';
import '../theme/app_theme.dart';
import 'adaptive.dart';
import 'sftp_page.dart';
import 'snippet_sheet.dart';
import 'soft_keys.dart';

/// 终端工作区。
///
/// 名字还叫 TerminalPage，但它现在装的是**一组**标签页：每个标签是一条独立的
/// SSH 会话（自己的 ssh 通道、自己的 xterm buffer、自己的焦点）。这样从列表里
/// 连第二台机器时不用先退出第一台。
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.host,
    this.sessionOverride,
    this.keyCombos,
    this.hostOptions,
    this.sessionFactory,
  });

  final SshHost host;

  /// 预览图 / 测试用：注入一个现成的会话，跳过真实拨号。
  /// 生产代码永远不传这个参数。
  @visibleForTesting
  final TerminalSession? sessionOverride;

  /// 预览图 / 测试用：直接指定软键盘第二排的组合列表，
  /// 省得去读 SharedPreferences（测试环境里没有插件通道）。
  @visibleForTesting
  final List<KeyCombo>? keyCombos;

  /// 预览图 / 测试用：新建标签页时可选的其它主机。
  /// 不传就去 HostStore 读真实列表。
  @visibleForTesting
  final List<SshHost>? hostOptions;

  /// 预览图 / 测试用：后面新开的标签怎么造会话（预览里要直接给"已连接"的样子）
  @visibleForTesting
  final TerminalSession Function(SshHost host)? sessionFactory;

  @override
  State<TerminalPage> createState() => TerminalPageState();
}

/// 一个标签页。会话和焦点节点绑在一起，切换标签就是换一组。
class _Tab {
  _Tab({
    required this.id,
    required this.host,
    required this.session,
    required this.focusNode,
  });

  final String id;
  final SshHost host;
  final TerminalSession session;
  final FocusNode focusNode;

  /// 「点一下挪光标」的一次性状态，只给 [_TerminalPageState._handleTap] 用。
  ///
  /// 本地光标要等远端回显才知道自己动了，这两个值用来避免连点两下时按
  /// 同一个 delta 重复发方向键（细节见那个方法的注释）。
  int? seenCursorX;
  int? commandedX;
}

/// 类名不私有，是为了让测试能问一句"终端现在拿着焦点吗"。
class TerminalPageState extends State<TerminalPage> {
  final List<_Tab> _tabs = <_Tab>[];

  int _active = 0;
  int _seq = 0;

  /// 快捷键栏占掉约 84px，看长输出时可以收起来
  bool _showKeys = true;

  /// 终端字号。全局一份（不是每标签一份）—— 这是"我眼睛看得清多大字"的偏好，
  /// 不该开个新标签就变回去。改完会写进 SharedPreferences。
  double _fontSize = TerminalPrefs.defaultFont;

  /// 打开 SFTP 通道时显示顶部进度条
  String? _busy;

  @override
  void initState() {
    super.initState();
    final first = widget.sessionOverride ?? _newSession(widget.host);
    _tabs.add(_makeTab(widget.host, first));
    _restoreFontSize();
  }

  Future<void> _restoreFontSize() async {
    final size = await TerminalPrefs.loadFontSize();
    if (!mounted || size == _fontSize) return;
    setState(() => _fontSize = size);
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.session.removeListener(_onSessionChanged);
      tab.session.dispose();
      tab.focusNode.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ 会话

  TerminalSession _newSession(SshHost host) =>
      widget.sessionFactory?.call(host) ?? TerminalSession(host);

  _Tab _makeTab(SshHost host, TerminalSession session) {
    final tab = _Tab(
      id: 'tab-${_seq++}',
      host: host,
      session: session,
      focusNode: FocusNode(debugLabel: 'terminal-${host.displayName}'),
    );
    session.addListener(_onSessionChanged);
    return tab;
  }

  /// 任何一个会话的状态变了都要重画：标签上的小圆点、标题栏的连接状态都依赖它。
  /// 终端**输出**不走这里（xterm 自己通知渲染层），所以这个监听很便宜。
  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  _Tab get _activeTab => _tabs[_active];

  /// 测试用：终端是否聚焦（软键盘弹不弹就看它）
  @visibleForTesting
  bool get terminalHasFocus => _activeTab.focusNode.hasFocus;

  /// 测试用：当前标签数
  @visibleForTesting
  int get tabCount => _tabs.length;

  /// 测试用：当前标签是哪台机器
  @visibleForTesting
  String get activeHostName => _activeTab.host.displayName;

  /// 测试用：当前标签的会话
  @visibleForTesting
  TerminalSession get activeSession => _activeTab.session;

  /// 测试用：直接开一个新标签（省得去点弹窗）
  @visibleForTesting
  void openTabForTest(SshHost host) => _openTab(host);

  void _selectTab(int index) {
    if (index == _active || index < 0 || index >= _tabs.length) return;
    // ★ 切走之前必须交还焦点：IndexedStack 里的旧标签还在树上，
    //   它的 FocusNode 若仍持有焦点，软键盘会赖着不走，而按键又发给了新标签。
    _activeTab.focusNode.unfocus();
    setState(() => _active = index);
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;

    // 只剩一个标签时，"关掉"等于退出终端页
    if (_tabs.length == 1) {
      Navigator.of(context).maybePop();
      return;
    }

    final tab = _tabs[index];
    tab.session.removeListener(_onSessionChanged);
    tab.session.dispose();
    tab.focusNode.dispose();

    setState(() {
      _tabs.removeAt(index);
      if (_active > index) _active -= 1;
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  void _openTab(SshHost host) {
    final tab = _makeTab(host, _newSession(host));
    setState(() {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    });
  }

  Future<void> _pickHostForNewTab() async {
    final hosts = widget.hostOptions ?? await HostStore().load();
    if (!mounted) return;

    final chosen = await showModalBottomSheet<SshHost>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: hosts.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Text(
                  '还没有别的主机。回到列表页点「＋」先加一台，'
                  '就可以在这里开新标签了。',
                  style: TextStyle(fontSize: 13),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: hosts.length,
                itemBuilder: (BuildContext context, int index) {
                  final host = hosts[index];
                  // 已经开着的那台就不再列出来，省得同一台机器开两遍
                  final opened = _tabs.any((_Tab t) => t.host.id == host.id);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        host.authMethod == HostAuthMethod.privateKey
                            ? Icons.vpn_key_outlined
                            : Icons.terminal_outlined,
                        size: 18,
                      ),
                    ),
                    title: Text(host.displayName),
                    subtitle: Text(
                      '${host.username}@${host.endpoint}'
                      '${opened ? ' · 已在标签里' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    enabled: !opened,
                    onTap: () => Navigator.of(context).pop(host),
                  );
                },
              ),
      ),
    );

    if (chosen == null) return;
    _openTab(chosen);
  }

  // ------------------------------------------------------------------ SFTP

  Future<void> _openSftp() async {
    final tab = _activeTab;
    if (!tab.session.isConnected) {
      _toast('先连上这台主机，再开文件管理');
      return;
    }

    setState(() => _busy = '正在打开文件通道…');
    try {
      // 复用这条 SSH 连接开 sftp 子系统，不再问一次密码
      final client = await tab.session.openSftp();
      if (!mounted) return;
      setState(() => _busy = null);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => SftpPage(
            fs: SftpFs(client, label: '${tab.host.username}@${tab.host.endpoint}'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _toast(
        TerminalSession.looksLikeSubsystemMissing(error)
            ? '这台服务器没有开 SFTP 子系统（sshd_config 里加 Subsystem sftp …）'
            : '打不开文件通道：${fsErrorMessage(error)}',
        danger: true,
      );
    } finally {
      if (mounted && _busy != null) setState(() => _busy = null);
    }
  }

  // ------------------------------------------------------------------ 字号

  void _zoom(double delta) {
    final next = TerminalPrefs.clampFont(_fontSize + delta);
    if (next == _fontSize) {
      // 到顶/到底了给个反馈，否则用户会以为按钮坏了
      _toast(
        delta > 0 ? '已经放到最大（${TerminalPrefs.maxFont.round()}）' : '已经缩到最小（${TerminalPrefs.minFont.round()}）',
      );
      return;
    }
    setState(() => _fontSize = next);
    TerminalPrefs.saveFontSizeInBackground(next);
  }

  void _resetZoom() {
    if (_fontSize == TerminalPrefs.defaultFont) return;
    setState(() => _fontSize = TerminalPrefs.defaultFont);
    TerminalPrefs.saveFontSizeInBackground(TerminalPrefs.defaultFont);
  }

  // ------------------------------------------------------------------ 交互

  /// 点一下终端 → 把远端光标挪到点的位置。
  ///
  /// 只在"点的正是光标所在那一行"时动手：
  ///  * 终端里光标只能在**输入行内**左右走，点上面的历史输出没法定位；
  ///  * 上下方向键在 shell / readline 里是翻历史命令，拿它跳行会把用户
  ///    正在敲的命令整行换掉。
  ///
  /// 比的是 [Buffer.absoluteCursorY] 而不是 `cursorY`：前者是内容坐标，
  /// 与点击位置（同样由内容坐标算出）在同一坐标系，滚动过屏幕也不会错位。
  void _handleTap(_Tab tab, CellOffset cell) {
    final terminal = tab.session.terminal;

    // 远端开了鼠标上报（vim/tmux/htop 之类）时，点击该由那边的程序自己处理，
    // 我们再插一手发方向键就成了捣乱。
    if (terminal.mouseMode != MouseMode.none) return;

    final buffer = terminal.buffer;
    if (cell.y != buffer.absoluteCursorY) return;

    // 本地 buffer 的光标要等远端把方向键回显回来才会动，中间有个来回延迟。
    // 拿这个延迟去双击选词时，第二下会按"还没更新的 cursorX"再发一遍方向键，
    // 光标一下就冲过头。所以：
    //   * 本地光标列跟我们上次看到的不一样 → 说明回显（或用户打字）到了，
    //     我们的认知是新的，把待定目标清掉；
    //   * 本地没变、而用户又点了**同一格** → 那就是刚才那一击的重复，忽略。
    // 点别的格子不拦，否则一旦回显丢了就会永久卡住再也点不动。
    if (tab.seenCursorX != buffer.cursorX) {
      tab.seenCursorX = buffer.cursorX;
      tab.commandedX = null;
    }
    if (tab.commandedX == cell.x) return;

    final delta = cell.x - buffer.cursorX;
    if (delta == 0) {
      tab.commandedX = null;
      return;
    }
    tab.session.moveCursorBy(delta);
    tab.commandedX = cell.x;
    // 挪没挪、挪了几格，屏幕上未必看得出来（光标本来就在闪），给个震动反馈
    HapticFeedback.selectionClick();
  }

  /// [handleTapAtCell] 的实际逻辑，单独公开出来是为了让测试直接喂格子坐标 ——
  /// 走 `tester.tapAt(像素)` 的话得先猜 xterm 的 cellSize，字体一换坐标就全错。
  @visibleForTesting
  void handleTapAtCell(CellOffset cell) => _handleTap(_activeTab, cell);

  /// 打开常用命令抽屉。
  ///
  /// ★ 先 unfocus：ModalRoute 在 pop 时会把焦点还给上一个 route 里原先聚焦的节点，
  ///   终端一拿回焦点，xterm 就重新 attach 输入连接 → 软键盘被顶出来。
  ///   用户点一条命令是想看输出，不是想接着打字。
  Future<void> _openSnippets() async {
    _activeTab.focusNode.unfocus();
    await showSnippetSheet(context, _activeTab.session);
  }

  Future<void> _askDisconnect() async {
    final tab = _activeTab;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('断开连接'),
        content: Text('确定要断开「${tab.host.displayName}」吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await tab.session.disconnect();
    }
  }

  void _toast(String message, {bool danger = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: danger
              ? Theme.of(context).colorScheme.errorContainer
              : null,
        ),
      );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // 终端页整体跟着主题走：夜间模式切到浅色时，黑色外框和黑底终端要一起变，
    // 否则会出现"白导航栏 + 黑终端"这种半截效果。
    final brightness = Theme.of(context).brightness;
    final terminalTheme = AppTheme.terminalTheme(brightness);
    final tab = _activeTab;

    return Scaffold(
      backgroundColor: terminalTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.chrome(brightness),
        foregroundColor: AppTheme.chromeForeground(brightness),
        elevation: 0,
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              tab.host.displayName,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.chromeForeground(brightness),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _subtitle(tab),
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.chromeForegroundMuted(brightness),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: <Widget>[
          // 状态放导航栏，不再浮在终端上 —— 之前那个浮层会压住第一行文字
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: _StatusChip(status: tab.session.status),
          ),
          IconButton(
            tooltip: '常用命令',
            icon: const Icon(Icons.library_books_outlined, size: 20),
            onPressed: _openSnippets,
          ),
          IconButton(
            tooltip: _showKeys ? '收起快捷键栏' : '展开快捷键栏',
            icon: Icon(
              _showKeys ? Icons.keyboard_hide : Icons.keyboard,
              size: 21,
            ),
            onPressed: () => setState(() => _showKeys = !_showKeys),
          ),
          _opsMenu(tab),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_TabStrip.height),
          child: _TabStrip(
            tabs: _tabs,
            active: _active,
            fontSize: _fontSize,
            onSelect: _selectTab,
            onClose: _closeTab,
            onAdd: _pickHostForNewTab,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_busy != null)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(child: _workspace(terminalTheme, brightness, tab)),
          ],
        ),
      ),
    );
  }

  /// 终端 + 快捷键栏。宽屏把快捷键栏竖排挪到左边，把宝贵的高度全留给终端。
  Widget _workspace(
    TerminalTheme terminalTheme,
    Brightness brightness,
    _Tab tab,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final verticalKeys = constraints.maxWidth >= Adaptive.wide;

        // IndexedStack：非活动标签的终端仍然活着（buffer、滚动位置、正在跑的
        // 东西都不丢），但只有当前这个参与绘制。
        final terminals = IndexedStack(
          index: _active,
          sizing: StackFit.expand,
          children: <Widget>[
            for (final _Tab item in _tabs)
              _terminalView(item, terminalTheme, brightness),
          ],
        );

        if (!_showKeys) return terminals;

        final keys = SoftKeys(
          session: tab.session,
          comboOverride: widget.keyCombos,
          vertical: verticalKeys,
          fontSize: _fontSize,
          onZoom: _zoom,
        );

        return verticalKeys
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[keys, Expanded(child: terminals)],
              )
            : Column(
                children: <Widget>[
                  Expanded(child: terminals),
                  keys,
                ],
              );
      },
    );
  }

  Widget _opsMenu(_Tab tab) {
    final connected = tab.session.isConnected;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (String value) {
        switch (value) {
          case 'tab':
            _pickHostForNewTab();
          case 'sftp':
            _openSftp();
          case 'toggle':
            connected ? _askDisconnect() : tab.session.connect();
          case 'zoom-in':
            _zoom(TerminalPrefs.step);
          case 'zoom-out':
            _zoom(-TerminalPrefs.step);
          case 'zoom-reset':
            _resetZoom();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        _menuItem('tab', Icons.add, '新建标签页'),
        _menuItem('sftp', Icons.folder_open_outlined, '文件管理（SFTP）'),
        _menuItem(
          'toggle',
          connected ? Icons.link_off : Icons.refresh,
          connected ? '断开连接' : '重新连接',
        ),
        const PopupMenuDivider(),
        _menuItem('zoom-out', Icons.text_decrease, '字号变小'),
        _menuItem('zoom-in', Icons.text_increase, '字号变大'),
        _menuItem(
          'zoom-reset',
          Icons.restart_alt,
          '恢复默认字号（${TerminalPrefs.defaultFont.round()}）',
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  /// 终端本体。每个标签一个，共享同一份主题与字号。
  ///
  /// 外面套一层 [_TerminalTapArea]：xterm 4.0.0 的 `TerminalView.onTapUp` 是个
  /// 死参数（来龙去脉写在那个类的注释里），"点一下挪光标"得自己接手势。
  Widget _terminalView(
    _Tab tab,
    TerminalTheme theme,
    Brightness brightness,
  ) {
    return _TerminalTapArea(
      // 按标签 id 而不是按下标定位：关掉中间某个标签时，IndexedStack 的下标
      // 会整体前移，不带 key 的话 State 会被错配到别的标签上。
      key: ValueKey<String>('term-${tab.id}'),
      onTapCell: (CellOffset cell) => _handleTap(tab, cell),
      builder: (GlobalKey<TerminalViewState> viewKey) => TerminalView(
        tab.session.terminal,
        key: viewKey,
        // 每个标签自己的 FocusNode：切标签时才能精确地"交出焦点"，而不是
        // 把键盘在所有标签之间来回甩
        focusNode: tab.focusNode,
        theme: theme,
        // 字号变了就重建 TerminalStyle：xterm 会重算格子尺寸并回调 onResize，
        // 远端 PTY 跟着一起变，不用自己做任何同步。
        textStyle: TerminalStyle(fontSize: _fontSize),
        // 不再 autofocus：一进终端页就弹软键盘会吃掉半屏高度，
        // 关掉命令抽屉时还会被焦点恢复"顶"回来。想打字点一下终端即可。
        autofocus: false,
        backgroundOpacity: 1,
        keyboardAppearance: brightness,
        padding: const EdgeInsets.all(6),
      ),
    );
  }

  String _subtitle(_Tab tab) {
    final host = tab.host;
    switch (tab.session.status) {
      case SessionStatus.connecting:
        return '${host.endpoint} · 连接中…';
      case SessionStatus.connected:
        return '${host.username}@${host.endpoint} · 已连接';
      case SessionStatus.disconnected:
        return '${host.endpoint} · 已断开';
      case SessionStatus.error:
        return '${host.endpoint} · ${tab.session.error ?? '连接失败'}';
    }
  }
}

// ---------------------------------------------------------------------- 标签条

/// 顶部标签条。横向滚动，窄屏也不会把标签压扁；右端固定的「＋」用来开新标签。
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.active,
    required this.fontSize,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  final List<_Tab> tabs;
  final int active;
  final double fontSize;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;

  /// 标签条高度。AppBar.bottom 要按它申报 preferredSize。
  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final chrome = AppTheme.chrome(brightness);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: chrome,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.chromeForeground(brightness).withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: tabs.length,
              itemBuilder: (BuildContext context, int index) =>
                  _chip(context, index),
            ),
          ),
          IconButton(
            key: const Key('tab-strip-add'),
            tooltip: '新建标签页',
            icon: const Icon(Icons.add, size: 19),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, int index) {
    final tab = tabs[index];
    final selected = index == active;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final foreground = AppTheme.chromeForeground(brightness);

    return Padding(
      padding: const EdgeInsets.only(right: 4, top: 3, bottom: 3),
      child: Material(
        // 测试按标签名找它，断言"关掉当前标签后剩下的是哪一个"
        key: ValueKey<String>('tabchip-${tab.id}'),
        color: selected
            ? scheme.primary.withValues(
                alpha: brightness == Brightness.dark ? 0.28 : 0.16,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelect(index),
          child: Padding(
            padding: EdgeInsets.only(left: 9, right: tabs.length > 1 ? 2 : 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StatusDot(status: tab.session.status),
                const SizedBox(width: 6),
                ConstrainedBox(
                  // 主机名再长也不能把标签条吃光 —— 每开一台机器就挤掉一截
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Text(
                    tab.host.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? foreground
                          : foreground.withValues(alpha: 0.72),
                    ),
                  ),
                ),
                if (tabs.length > 1)
                  InkWell(
                    onTap: () => onClose(index),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 13,
                        color: foreground.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签上那个小圆点：不用点开就知道这条会话是什么状态
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SessionStatus.connecting => Colors.amber.shade700,
      SessionStatus.connected => Colors.green.shade600,
      SessionStatus.disconnected => Colors.grey.shade600,
      SessionStatus.error => Colors.red.shade600,
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      SessionStatus.connecting => ('连接中', Colors.amber.shade700),
      SessionStatus.connected => ('已连接', Colors.green.shade600),
      SessionStatus.disconnected => ('已断开', Colors.grey.shade600),
      SessionStatus.error => ('失败', Colors.red.shade600),
    };

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: status == SessionStatus.connected ? 0.35 : 1,
        duration: const Duration(milliseconds: 400),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color, width: 0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: TextStyle(fontSize: 10.5, color: color)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 点击挪光标

/// 终端「点一下就挪光标」的点击层。
///
/// ## 为什么不用 `TerminalView.onTapUp`
///
/// xterm 4.0.0 里那条回调链是断的：
///
/// ```
/// TerminalView(onTapUp: ...)  →  TerminalGestureHandler.onTapUp: widget.onTapUp
///   →  TerminalGestureDetector.onTapUp  →  ✂ 没有接到任何手势识别器上
/// ```
///
/// `TerminalGestureDetector` 只把 `TapGestureRecognizer.onTapUp` 接给了自己的
/// `_handleTapUp`，而 `_handleTapUp` 里唯一的出路是 `onSingleTapUp`——
/// 这个参数 `TerminalView` 从来没往下传过。于是 `onTapUp` 成了个只声明不兑现的
/// 参数：实测把它单独 pump 出来点几次，回调次数都是 0。
///
/// 上游最新版就是 4.0.0，没有可升的修复，只能自己接一层。
///
/// ## 为什么用 [Listener] 而不是 GestureDetector
///
/// [Listener] 只是旁听原始指针事件，**不进手势竞技场**，所以不会和 xterm 自己的
/// 滚动、长按选词、双击选词，以及远端开鼠标上报后 vim/tmux 的手势抢。
/// 误判靠两道过滤挡掉：位移超过 [_slop] 当成滚动，按住超过 [_maxTap] 当成选词。
class _TerminalTapArea extends StatefulWidget {
  const _TerminalTapArea({
    super.key,
    required this.onTapCell,
    required this.builder,
  });

  /// 判定为「一次干净的点击」后，把落在哪个字符格子报出去。
  final ValueChanged<CellOffset> onTapCell;

  /// 把 [GlobalKey] 交给调用方贴在 `TerminalView` 上。我们需要它拿到
  /// `TerminalViewState.renderTerminal`，才能把像素坐标换算成字符格子——
  /// 自己按字号推格子宽高，遇到中文、粗体、连字会算歪，直接用 xterm 自己那套
  /// 换算（`getCellOffset`）才和它画出来的光标严格对齐。
  final Widget Function(GlobalKey<TerminalViewState> viewKey) builder;

  @override
  State<_TerminalTapArea> createState() => _TerminalTapAreaState();
}

class _TerminalTapAreaState extends State<_TerminalTapArea> {
  final GlobalKey<TerminalViewState> _viewKey = GlobalKey<TerminalViewState>();

  /// 只认第一根手指：终端里多点触控没有别的用途，多出来的手指直接忽略，
  /// 免得「双指」被拆成两次点击。
  int? _pointer;
  Offset? _downAt;
  Duration? _downStamp;
  bool _dragged = false;

  /// 手指抖动的容忍范围，超过就说明用户在滚动或选词，不是点击。
  static const double _slop = 18;

  /// 按住超过这么久算长按（选词），不挪光标。Flutter 的长按阈值是 500ms，
  /// 这里留一截余量，避免和 xterm 的长按选词打架。
  static const Duration _maxTap = Duration(milliseconds: 380);

  void _onDown(PointerDownEvent event) {
    _pointer = event.pointer;
    _downAt = event.position;
    _downStamp = event.timeStamp;
    _dragged = false;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final from = _downAt;
    if (from == null) return;
    if ((event.position - from).distance > _slop) _dragged = true;
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final from = _downAt;
    final at = _downStamp;
    _pointer = null;
    _downAt = null;
    _downStamp = null;
    if (from == null || at == null || _dragged) return;
    if (event.timeStamp - at > _maxTap) return;
    _report(event.position);
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _downAt = null;
    _downStamp = null;
  }

  void _report(Offset globalPosition) {
    final state = _viewKey.currentState;
    if (state == null) return;

    // renderTerminal 就是 xterm 用来画字、算格子的那个 RenderObject，
    // 它自己的 getCellOffset() 正是 xterm 内部处理点击时用的同一套换算。
    final render = state.renderTerminal;
    final box = render as RenderBox;
    if (!box.hasSize) return;
    widget.onTapCell(render.getCellOffset(box.globalToLocal(globalPosition)));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.builder(_viewKey),
    );
  }
}
