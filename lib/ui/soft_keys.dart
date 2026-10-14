import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/key_combo.dart';
import '../services/key_combo_store.dart';
import '../services/key_mapping.dart';
import '../services/keystroke.dart';
import '../services/terminal_prefs.dart';
import '../services/terminal_session.dart';
import '../theme/app_theme.dart';

/// 一排按键的高度。缩放组要跟它对齐，所以提到顶层。
const double _keyRowExtent = 34;

/// 手机软键盘没有 ESC / CTRL / Tab / 方向键，这里补两排。
///
/// 布局要点：**一律有一边可滚动、另一边写死**。
/// 千万别把 `Wrap` 直接放在 Column 里 —— `Wrap` 会把每行自动折成多行，
/// 手机上能折出 6 行、把上面的终端挤没。靠滚动才能保证占位恒定。
///
/// 两种形态：
///  * [vertical] = false（手机、窄窗口）：贴在终端下方，两排横向滚动；
///  * [vertical] = true（平板、手机横屏）：靠左**竖着两列**，把高度全留给终端。
///
/// 第二排的内容来自 [KeyComboStore]，用户可以在设置里随便增删改。
/// Ctrl 是"粘滞键"：点一下点亮，再点字母键就是 Ctrl+字母。
class SoftKeys extends StatefulWidget {
  const SoftKeys({
    super.key,
    required this.session,
    this.comboOverride,
    this.vertical = false,
    this.fontSize = TerminalPrefs.defaultFont,
    this.onZoom,
  });

  final TerminalSession session;

  /// 预览图 / 测试用：直接给一组组合，跳过读本地存储。
  /// 生产代码永远不传这个参数。
  @visibleForTesting
  final List<KeyCombo>? comboOverride;

  /// 竖排模式（宽屏）。宽度写死，高度由父级撑满。
  final bool vertical;

  /// 终端当前字号，缩放组要显示这个数
  final double fontSize;

  /// 点缩放键时回调（带 ±step 的增量）。为 null 就不显示缩放组 ——
  /// 只在极少数"不给改字号"的场景里会这样。
  final ValueChanged<double>? onZoom;

  /// 横排两排 + 间距 + 上下 padding 的总高度，TerminalPage 会引用它做布局断言
  static const double totalHeight = 84;

  /// 竖排两列 + 间距 + 左右 padding 的总宽度。
  /// 200 是"Shift+Tab / Ctrl+Alt+Del 这类标签不会被截成 Alt+…"的下限。
  static const double totalWidth = 200;

  @override
  State<SoftKeys> createState() => _SoftKeysState();
}

class _SoftKeysState extends State<SoftKeys> {
  bool _ctrl = false;
  late Future<List<KeyCombo>> _combosFuture;

  @override
  void initState() {
    super.initState();
    final override = widget.comboOverride;
    _combosFuture = override != null
        ? Future<List<KeyCombo>>.value(override)
        : KeyComboStore().load();
  }

  void _tapCombo(KeyCombo combo) {
    final session = widget.session;

    // ① 带修饰键 —— 自己按 xterm 规范编码
    if (combo.hasModifier) {
      session.sendBytes(encodeKeyCombo(combo));
      return;
    }

    // ② 无修饰的单个字符 —— 粘滞 Ctrl 点亮时升级成 Ctrl+字母
    if (combo.key.length == 1) {
      if (_ctrl) {
        session.sendCtrlLetter(combo.key);
        setState(() => _ctrl = false);
      } else {
        session.sendText(combo.key);
      }
      return;
    }

    // ③ 无修饰的功能键 —— 交给 xterm，它会按当前终端模式挑正确的序列
    final namedKey = terminalKeyOf(combo.key);
    if (namedKey != null) {
      session.sendKey(namedKey);
      return;
    }

    session.sendBytes(encodeKeyCombo(combo));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final axis = widget.vertical ? Axis.vertical : Axis.horizontal;

    // 缩放组固定挂在第二排的尾巴上（竖排时挂在最底下）：
    // 屏上多两个显式按钮，但**一格高度都不多占**，这正是手机上最缺的东西。
    final zoom = widget.onZoom == null
        ? null
        : _ZoomGroup(
            fontSize: widget.fontSize,
            onZoom: widget.onZoom!,
          );

    final builtin = _KeyRow(
      axis: axis,
      children: <Widget>[
        _KeyChip(
          dense: widget.vertical,
          label: 'Ctrl',
          active: _ctrl,
          onTap: () => setState(() => _ctrl = !_ctrl),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: 'Esc',
          onTap: () => widget.session.sendKey(TerminalKey.escape),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: 'Tab',
          onTap: () => widget.session.sendKey(TerminalKey.tab),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: '↑',
          onTap: () => widget.session.sendKey(TerminalKey.arrowUp),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: '↓',
          onTap: () => widget.session.sendKey(TerminalKey.arrowDown),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: '←',
          onTap: () => widget.session.sendKey(TerminalKey.arrowLeft),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: '→',
          onTap: () => widget.session.sendKey(TerminalKey.arrowRight),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: 'Home',
          onTap: () => widget.session.sendKey(TerminalKey.home),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: 'End',
          onTap: () => widget.session.sendKey(TerminalKey.end),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: 'PgUp',
          onTap: () => widget.session.sendKey(TerminalKey.pageUp),
        ),
        _KeyChip(
          dense: widget.vertical,
          label: 'PgDn',
          onTap: () => widget.session.sendKey(TerminalKey.pageDown),
        ),
      ],
    );

    final custom = FutureBuilder<List<KeyCombo>>(
      future: _combosFuture,
      builder: (BuildContext context, AsyncSnapshot<List<KeyCombo>> snap) {
        final combos = snap.data ?? KeyCombo.defaults;
        return _KeyRow(
          axis: axis,
          children: combos
              .map(
                (KeyCombo combo) => _KeyChip(
                  dense: widget.vertical,
                  label: combo.displayLabel,
                  accent: combo.key == 'c' && combo.ctrl
                      ? colorScheme.errorContainer
                      : null,
                  onTap: () => _tapCombo(combo),
                ),
              )
              .toList(),
        );
      },
    );

    return Container(
      // 测试用它取整条快捷键栏的外框色（断言浅色模式下不再是黑的）
      key: const Key('soft-keys-bar'),
      // 铺满的那一边必须写死：放进 Column 是宽度铺满，放进 Row 是宽度固定
      width: widget.vertical ? SoftKeys.totalWidth : double.infinity,
      // 和终端页导航栏同色，浅色模式下这两处得一起变浅
      color: AppTheme.chrome(theme.brightness),
      padding: widget.vertical
          ? const EdgeInsets.all(6)
          : const EdgeInsets.fromLTRB(0, 5, 0, 6),
      child: widget.vertical
          ? Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(child: builtin),
                      const SizedBox(width: 6),
                      Expanded(child: custom),
                    ],
                  ),
                ),
                if (zoom != null) ...<Widget>[
                  const SizedBox(height: 6),
                  zoom,
                ],
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                builtin,
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    Expanded(child: custom),
                    if (zoom != null) ...<Widget>[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: zoom,
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

/// 一排（或一列）**可滚动**的按键。没滚动方向的那一边写死，
/// 所以永远不会把整个页面撑大。
class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.children, this.axis = Axis.horizontal});

  final List<Widget> children;
  final Axis axis;

  /// 横排时的行高见 [_keyRowExtent]。竖排时不需要 —— 列宽由外层 Expanded 决定。

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;

    final list = ListView.builder(
      scrollDirection: axis,
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 6),
      itemCount: children.length,
      itemBuilder: (BuildContext context, int index) => Padding(
        padding: EdgeInsets.only(
          right: !vertical && index != children.length - 1 ? 4 : 0,
          bottom: vertical && index != children.length - 1 ? 4 : 0,
        ),
        child: children[index],
      ),
    );

    // 竖排时宽度由 Row 里的 Expanded 决定，这里只要滚动轴（高度）有界即可
    return vertical ? list : SizedBox(height: _keyRowExtent, child: list);
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({
    required this.label,
    required this.onTap,
    this.active = false,
    this.accent,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? accent;

  /// 竖排时列宽是固定的，标签得挤一挤才放得下
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // 深色下沿用原来的"半透明灰块"；浅色下换成实心浅块 + 一道细边，
    // 否则半透明灰叠在浅灰底上就看不出按键边界了。
    final background = active
        ? colorScheme.primary
        : (accent ??
              (dark
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                  : theme.cardColor));
    final side = (!active && accent == null && !dark)
        ? BorderSide(color: colorScheme.outlineVariant, width: 0.8)
        : BorderSide.none;

    return Tooltip(
      // 万一还是被截断（用户自定义了超长组合），至少有个地方能看全
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        // 给测试一个稳定的锚点，用来断言"按键贴文字宽度、没占满整行"
        key: ValueKey<String>('softkey-$label'),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: side,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // ★ 必须给 widthFactor：`Center` 在宽松约束下会取 constraints.biggest，
            //   放进 Wrap / 横向列表里就会撑成整行宽，一个键占一行。
            padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 11),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                // 竖排时列宽固定，长标签（Ctrl+Shift+T 之类）要截断而不是溢出
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 11.5 : 12.5,
                  fontFamily: 'monospace',
                  color: active
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `[ − | 13 | ＋ ]`。
///
/// 为什么不让它浮在终端上：终端第一行永远是文字，浮层一定会压住东西，
/// 之前那个浮动的状态标签就是这么被挪进导航栏的。放在按键栏里属于"蹭位置"，
/// 不额外占高度。
class _ZoomGroup extends StatelessWidget {
  const _ZoomGroup({required this.fontSize, required this.onZoom});

  final double fontSize;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final atMin = fontSize <= TerminalPrefs.minFont;
    final atMax = fontSize >= TerminalPrefs.maxFont;

    return Material(
      color: dark
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
          : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: dark
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _keyRowExtent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _zoomButton(
              context,
              buttonKey: const Key('zoom-out'),
              icon: Icons.remove,
              tooltip: '字号变小',
              onTap: atMin ? null : () => onZoom(-TerminalPrefs.step),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                '${fontSize.round()}',
                key: const Key('zoom-level'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: scheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
            _zoomButton(
              context,
              buttonKey: const Key('zoom-in'),
              icon: Icons.add,
              tooltip: '字号变大',
              onTap: atMax ? null : () => onZoom(TerminalPrefs.step),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoomButton(
    BuildContext context, {
    required Key buttonKey,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 到顶/到底把按钮灰掉：比按了没反应要好，至少知道是没得调了
    final color = onTap == null
        ? scheme.onSurface.withValues(alpha: 0.3)
        : scheme.onSurface.withValues(alpha: 0.85);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: _keyRowExtent,
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
