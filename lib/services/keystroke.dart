import 'dart:typed_data';

import '../models/key_combo.dart';

/// 把 [KeyCombo] 编码成"发往远端 shell 的字节"。
///
/// 为什么要自己算：SSH 传的是**字节流**，什么组合键产生什么字节由**本地终端**决定，
/// 服务端只读流里的控制码。所以 Ctrl+C 不是"一个叫 Ctrl 的键"，而是字节 0x03。
///
/// 规则来源：xterm / VT220 / DECFNK 惯例。
///   - Ctrl + ASCII 字符  -> `char & 0x1F`（Ctrl+C=0x03、Ctrl+[/ESC=0x1B）
///   - Alt(Meta) + 任意    -> 前面补一个 ESC 0x1B
///   - 无修饰的功能键      -> VT 序列，如方向键 `ESC[A`、F1 `ESCOP`
///   - 带修饰的功能键      -> CSI 参数形式 `ESC[1;<mod>X`，
///                          mod = 1 + shift?1 + alt?2 + ctrl?4
///                          （Alt 已经走 ESC 前缀了，这里只算 Shift/Ctrl）
const int kEsc = 0x1B;
const int kTab = 0x09;
const int kCr = 0x0D;
const int kDel = 0x7F;
const int kBackspace2 = 0x08; // Ctrl+Backspace

/// 无修饰时的基础序列（不含开头的 ESC）
const Map<String, String> _sequences = <String, String>{
  'Up': '[A',
  'Down': '[B',
  'Right': '[C',
  'Left': '[D',
  'Home': '[H',
  'End': '[F',
  'Insert': '[2~',
  'Delete': '[3~',
  'PageUp': '[5~',
  'PageDown': '[6~',
  'F1': 'OP',
  'F2': 'OQ',
  'F3': 'OR',
  'F4': 'OS',
  'F5': '[15~',
  'F6': '[17~',
  'F7': '[18~',
  'F8': '[19~',
  'F9': '[20~',
  'F10': '[21~',
  'F11': '[23~',
  'F12': '[24~',
};

/// 单字节键（除了 '\n'/'\r' 这类）的特殊 handling
bool _isSequenceKey(String key) => _sequences.containsKey(key);

Uint8List encodeKeyCombo(KeyCombo combo) {
  final bytes = <int>[];

  // Meta / Alt 惯例：ESC 前缀
  if (combo.alt) bytes.add(kEsc);

  bytes.addAll(_base(combo));
  return Uint8List.fromList(bytes);
}

List<int> _base(KeyCombo combo) {
  final key = combo.key;

  // ---- 1) 功能键（VT / xterm 序列）
  if (_isSequenceKey(key)) {
    final modifier = 1 + (combo.shift ? 1 : 0) + (combo.ctrl ? 4 : 0);
    return modifier == 1
        ? <int>[kEsc, ..._seqBytes(_sequences[key]!)]
        : <int>[kEsc, ..._withModifier(_sequences[key]!, modifier)];
  }

  // ---- 2) 单字节特殊键
  switch (key) {
    case 'Enter':
      // readline 里 Ctrl+Enter 没什么标准，退化为回车
      return <int>[kCr];
    case 'Tab':
      if (combo.shift) return <int>[kEsc, 0x5B, 0x5A]; // ESC [ Z
      return <int>[kTab];
    case 'Escape':
      return <int>[kEsc];
    case 'Backspace':
      return <int>[combo.ctrl ? kBackspace2 : kDel];
  }

  // ---- 3) 普通字符
  if (key.isEmpty) return const <int>[];
  final code = key.codeUnitAt(0);

  if (combo.ctrl) {
    // Ctrl+? = (? | 0x40) & 0x1F —— 大小写、符号都按 ASCII 控制区算
    return <int>[code & 0x1F];
  }
  if (combo.shift) {
    // Shift+字母 -> 大写；符号键的 shift 形态太多且在手机软键意义不大，
    // 这里只对字母生效，其余原样发。
    if (code >= 0x61 && code <= 0x7A) return <int>[code - 32];
    return <int>[code];
  }
  return <int>[code];
}

/// 把字节序列翻译成人能读的形式，用于编辑器里的"实际发送"预览。
///   [0x03]          -> '^C'
///   [0x1B, 0x5B, 0x41] -> 'ESC [ A'
String describeBytes(List<int> bytes) {
  final parts = <String>[];
  for (final byte in bytes) {
    if (byte == kEsc) {
      parts.add('ESC');
    } else if (byte < 0x20) {
      // 控制字符按 caret 记法：0x01 -> ^A
      parts.add('^${String.fromCharCode(byte + 0x40)}');
    } else if (byte == kDel) {
      parts.add('DEL');
    } else {
      parts.add(String.fromCharCode(byte));
    }
  }
  return parts.isEmpty ? '（不发送任何内容）' : parts.join(' ');
}

Iterable<int> _seqBytes(String seq) => seq.codeUnits;

/// 把 `[params][final]` / `O<final>` 转成带修饰参数的 CSI：
///   `[A`  + mod 5 -> `[1;5A`
///   `[5~` + mod 3 -> `[5;3~`
///   `OP`  + mod 3 -> `[1;3P`（SS3 序列统一转成 CSI `1;n` + 结束符）
Iterable<int> _withModifier(String seq, int modifier) sync* {
  yield 0x5B; // '['

  String params;
  String finalChar;

  if (seq.startsWith('O')) {
    // SS3 序列（`OP` = F1）统一改写成等价的 CSI 形式 `[1P`
    params = '1';
    finalChar = seq.substring(1);
  } else {
    final body = seq.substring(1); // 去掉 '['
    final split = body.lastIndexOf(RegExp(r'[^0-9;]'));
    finalChar = body.substring(split); // 'A' / '~'
    params = body.substring(0, split); // '' / '5' / '15'
    if (params.isEmpty) params = '1';
  }

  yield* '$params;$modifier'.codeUnits;
  yield* finalChar.codeUnits;
}
