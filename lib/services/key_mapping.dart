import 'package:xterm/xterm.dart';

/// [KeyCombo.key] 的功能键名 → xterm 的按键枚举。
///
/// 为什么**无修饰**的功能键要走这条路：xterm 知道当前终端处在哪套模式里
/// （application cursor keys / keypad mode 等），同一个 Home 在不同模式下要发
/// 的序列是不一样的。让它自己决定，比我们硬编码 `ESC[H` 准。
const Map<String, TerminalKey> kNamedTerminalKeys = <String, TerminalKey>{
  'Enter': TerminalKey.enter,
  'Escape': TerminalKey.escape,
  'Backspace': TerminalKey.backspace,
  'Tab': TerminalKey.tab,
  'Space': TerminalKey.space,
  'Insert': TerminalKey.insert,
  'Delete': TerminalKey.delete,
  'Home': TerminalKey.home,
  'End': TerminalKey.end,
  'PageUp': TerminalKey.pageUp,
  'PageDown': TerminalKey.pageDown,
  'Up': TerminalKey.arrowUp,
  'Down': TerminalKey.arrowDown,
  'Left': TerminalKey.arrowLeft,
  'Right': TerminalKey.arrowRight,
  'F1': TerminalKey.f1,
  'F2': TerminalKey.f2,
  'F3': TerminalKey.f3,
  'F4': TerminalKey.f4,
  'F5': TerminalKey.f5,
  'F6': TerminalKey.f6,
  'F7': TerminalKey.f7,
  'F8': TerminalKey.f8,
  'F9': TerminalKey.f9,
  'F10': TerminalKey.f10,
  'F11': TerminalKey.f11,
  'F12': TerminalKey.f12,
};

TerminalKey? terminalKeyOf(String name) => kNamedTerminalKeys[name];
