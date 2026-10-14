import 'package:flutter/foundation.dart';

/// 一个"软键盘按不出来"的按键组合，比如 Ctrl+C、Alt+.、Shift+Tab。
///
/// [key] 的取值有两种：
///   - 单个字符：`a`-`z`、`0`-`9`、以及标点符号 `/` `-` `.` 等
///   - 功能键名：`Enter` `Tab` `Escape` `Backspace` `Delete` `Insert`
///     `Home` `End` `PageUp` `PageDown` `Up` `Down` `Left` `Right` `F1`-`F12`
///
/// 具体按键名以 [KeyCatalog.availableKeys] 为准，编辑器只让挑这些。
@immutable
class KeyCombo {
  const KeyCombo({
    required this.id,
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.label,
  });

  final String id;

  /// 键值：单字符或功能键名
  final String key;

  final bool ctrl;
  final bool alt;
  final bool shift;

  /// 自定义显示名，为空时自动拼成 `Ctrl+Alt+X`
  final String? label;

  bool get hasModifier => ctrl || alt || shift;

  /// 是可打印字符（而不是功能键名）
  bool get isPrintable => key.length == 1;

  /// 显示名
  String get displayLabel {
    final custom = label?.trim();
    if (custom != null && custom.isNotEmpty) return custom;

    final parts = <String>[
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
    ];

    final presentation = KeyCatalog.display[key];
    if (presentation != null) {
      // 功能键（↑ 这种）直接跟在后面：`Ctrl+↑`
      parts.add(presentation);
    } else if (key.length == 1) {
      // 字母键大写更好看：`Ctrl+C`
      parts.add(key.toUpperCase());
    } else {
      parts.add(key);
    }
    return parts.join('+');
  }

  KeyCombo copyWith({
    String? key,
    bool? ctrl,
    bool? alt,
    bool? shift,
    String? label,
    bool clearLabel = false,
  }) {
    return KeyCombo(
      id: id,
      key: key ?? this.key,
      ctrl: ctrl ?? this.ctrl,
      alt: alt ?? this.alt,
      shift: shift ?? this.shift,
      label: clearLabel ? null : (label ?? this.label),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'key': key,
    'ctrl': ctrl,
    'alt': alt,
    'shift': shift,
    'label': label,
  };

  factory KeyCombo.fromJson(Map<String, dynamic> json) {
    return KeyCombo(
      id: json['id'] as String? ?? '',
      key: json['key'] as String? ?? '',
      ctrl: json['ctrl'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      label: json['label'] as String?,
    );
  }

  static String newId() =>
      'k${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// 第一次打开 App 时的预设组合。
  ///
  /// 顺序即软键盘第二排的显示顺序，用户之后可以随便改。
  static List<KeyCombo> get defaults => <KeyCombo>[
    KeyCombo(id: 'd1', key: 'c', ctrl: true),
    KeyCombo(id: 'd2', key: 'd', ctrl: true),
    KeyCombo(id: 'd3', key: 'z', ctrl: true),
    KeyCombo(id: 'd4', key: 'l', ctrl: true),
    KeyCombo(id: 'd5', key: 'r', ctrl: true),
    KeyCombo(id: 'd6', key: 'u', ctrl: true),
    KeyCombo(id: 'd7', key: 'k', ctrl: true),
    KeyCombo(id: 'd8', key: 'w', ctrl: true),
    KeyCombo(id: 'd9', key: '.', alt: true),
    KeyCombo(id: 'd10', key: 'Tab', shift: true),
    KeyCombo(id: 'd11', key: 'a'),
    KeyCombo(id: 'd12', key: 'e'),
  ];
}

/// 允许的按键名清单 + 显示名映射。
///
/// 编辑器、编码器、UI 都从这里取，避免三处各写一串字符串。
class KeyCatalog {
  const KeyCatalog._();

  /// 功能键 → 显示符号（单字符 letters/symbols 不需要登记在这里）
  static const Map<String, String> display = <String, String>{
    'Enter': '⏎',
    'Tab': 'Tab',
    'Escape': 'Esc',
    'Backspace': '⌫',
    'Delete': 'Del',
    'Insert': 'Ins',
    'Home': 'Home',
    'End': 'End',
    'PageUp': 'PgUp',
    'PageDown': 'PgDn',
    'Up': '↑',
    'Down': '↓',
    'Left': '←',
    'Right': '→',
    'F1': 'F1',
    'F2': 'F2',
    'F3': 'F3',
    'F4': 'F4',
    'F5': 'F5',
    'F6': 'F6',
    'F7': 'F7',
    'F8': 'F8',
    'F9': 'F9',
    'F10': 'F10',
    'F11': 'F11',
    'F12': 'F12',
  };

  /// 编辑器里可挑的键，分组用。值为 [KeyCombo.key] 的取值。
  static const Map<String, List<String>> groups = <String, List<String>>{
    '字母': <String>[
      'a',
      'b',
      'c',
      'd',
      'e',
      'f',
      'g',
      'h',
      'i',
      'j',
      'k',
      'l',
      'm',
      'n',
      'o',
      'p',
      'q',
      'r',
      's',
      't',
      'u',
      'v',
      'w',
      'x',
      'y',
      'z',
    ],
    '功能': <String>[
      'Enter',
      'Tab',
      'Escape',
      'Backspace',
      'Delete',
      'Insert',
      'Home',
      'End',
      'PageUp',
      'PageDown',
      'Up',
      'Down',
      'Left',
      'Right',
      'F1',
      'F2',
      'F3',
      'F4',
      'F5',
      'F6',
      'F7',
      'F8',
      'F9',
      'F10',
      'F11',
      'F12',
    ],
    '符号': <String>[
      ' ',
      '/',
      '\\',
      '.',
      ',',
      '-',
      '_',
      '=',
      '+',
      ':',
      ';',
      "'",
      '"',
      '`',
      '~',
      '!',
      '@',
      '#',
      r'$',
      '%',
      '^',
      '&',
      '*',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '<',
      '>',
      '?',
      '|',
    ],
    '数字': <String>['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
  };

  /// 单个 key 的展示名（'` $' 这类空格键要特殊处理）
  static String labelOf(String key) {
    if (key == ' ') return 'Space';
    final named = display[key];
    if (named != null) return named;
    return key.toUpperCase();
  }

  /// 所有合法 key 的扁平列表
  static List<String> get allKeys =>
      groups.values.expand((List<String> g) => g).toList(growable: false);
}
