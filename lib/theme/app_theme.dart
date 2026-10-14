import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 全 App 唯一定义主题的地方。
///
/// 之前 main.dart 里只有一份写死的深色 ThemeData，终端页和快捷键栏还各自
/// 硬编码了黑色，所以"夜间模式"没法当成一个开关来做 —— 得先把颜色收敛到一处。
///
/// 约定：
///  * [dark] 的观感必须和 1.1.0 保持一致（升级后不换脸）；
///  * 深色终端配色仍用 xterm 自带的 [TerminalThemes.whiteOnBlack]，浅色则是
///    一套纸白配色，两者都跟着 [Brightness] 走。
class AppTheme {
  const AppTheme._();

  /// 主题色种子。深色、浅色共用，保证两边"是同一个 App"。
  static const Color seed = Colors.teal;

  /// 终端页导航栏 / 快捷键栏的底色。
  ///
  /// 这两块刻意不用 `colorScheme.surface*` —— 它们是终端的外框，要和终端本体
  /// 贴在一起；用 M3 的自动配色会浮出一层灰。
  static const Color _darkChrome = Color(0xFF14161A);
  static const Color _lightChrome = Color(0xFFF3F4F6);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 终端外框底色（导航栏 + 快捷键栏）
  static Color chrome(Brightness brightness) =>
      brightness == Brightness.dark ? _darkChrome : _lightChrome;

  /// 终端页导航栏文字色
  static Color chromeForeground(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFE8EAED)
      : const Color(0xFF1F2328);

  /// 终端页导航栏次要文字（主机地址那一行）
  static Color chromeForegroundMuted(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF9AA0A6)
      : const Color(0xFF5B6270);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: seed,
    );
  }

  /// 终端本体配色。浅色模式下如果还用白字黑底，切了夜间模式等于没切。
  static TerminalTheme terminalTheme(Brightness brightness) =>
      brightness == Brightness.dark ? _terminalDark : _terminalLight;

  /// 深色：沿用 xterm 预设，观感和 1.1.0 完全一致
  static const TerminalTheme _terminalDark = TerminalThemes.whiteOnBlack;

  /// 浅色：纸白底 + 深灰字，ANSI 八色按"在白底上也看得清"重新挑过。
  /// 直接用 xterm 预设的那套色会在白底上糊成一片（绿和青几乎发白）。
  static const TerminalTheme _terminalLight = TerminalTheme(
    cursor: Color(0xFF0969DA),
    selection: Color(0x662F6FEB),
    foreground: Color(0xFF24292F),
    background: Color(0xFFFBFBFC),
    black: Color(0xFF24292F),
    red: Color(0xFFCF222E),
    green: Color(0xFF116329),
    yellow: Color(0xFF7D4E00),
    blue: Color(0xFF0550AE),
    magenta: Color(0xFF8250DF),
    cyan: Color(0xFF1B7C83),
    white: Color(0xFF6E7781),
    brightBlack: Color(0xFF57606A),
    brightRed: Color(0xFFA40E26),
    brightGreen: Color(0xFF1A7F37),
    brightYellow: Color(0xFF9A6700),
    brightBlue: Color(0xFF0969DA),
    brightMagenta: Color(0xFFA475F9),
    brightCyan: Color(0xFF3192AA),
    brightWhite: Color(0xFF24292F),
    searchHitBackground: Color(0xFFFFF8C5),
    searchHitBackgroundCurrent: Color(0xFFABF2BC),
    searchHitForeground: Color(0xFF000000),
  );
}
