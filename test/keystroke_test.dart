import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/models/key_combo.dart';
import 'package:sshterm/services/keystroke.dart';

/// SSH 通道里传的是**字节**，没有"Ctrl 键"这种东西。
/// 什么组合对应什么字节由本地终端决定，服务端只读控制码。
/// 这些断言就是把这套约定钉死，重构编码器时不至于悄悄改坏。
void main() {
  Uint8List bytes(KeyCombo combo) => encodeKeyCombo(combo);

  KeyCombo combo(
    String key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
  }) => KeyCombo(id: 'x', key: key, ctrl: ctrl, alt: alt, shift: shift);

  List<int> esc(Iterable<int> rest) => <int>[0x1B, ...rest];

  group('Ctrl + 字符', () {
    test('Ctrl+C -> 0x03（SIGINT，中止进程）', () {
      expect(bytes(combo('c', ctrl: true)), <int>[0x03]);
    });

    test('Ctrl+D -> 0x04（EOF，退出登录）', () {
      expect(bytes(combo('d', ctrl: true)), <int>[0x04]);
    });

    test('Ctrl+Z -> 0x1A（挂起）', () {
      expect(bytes(combo('z', ctrl: true)), <int>[0x1A]);
    });

    test('大写字母与小写等价：char & 0x1F 会抹掉 0x20 位', () {
      expect(bytes(combo('C', ctrl: true)), bytes(combo('c', ctrl: true)));
    });

    test('Ctrl+[ -> ESC 0x1B', () {
      expect(bytes(combo('[', ctrl: true)), <int>[0x1B]);
    });
  });

  group('Alt / Meta', () {
    test('Alt+. -> ESC .（readline 的上个参数）', () {
      expect(bytes(combo('.', alt: true)), esc(<int>[0x2E]));
    });

    test('Alt+Backspace -> ESC DEL（删一个词）', () {
      expect(bytes(combo('Backspace', alt: true)), <int>[0x1B, 0x7F]);
    });

    test('Ctrl+Alt+A -> ESC + 0x01（tmux prefix 常用）', () {
      expect(bytes(combo('a', ctrl: true, alt: true)), <int>[0x1B, 0x01]);
    });
  });

  group('功能键', () {
    test('方向键不带修饰 -> CSI 序列', () {
      expect(bytes(combo('Up')), esc(<int>[0x5B, 0x41])); // ESC [ A
      expect(bytes(combo('Down')), esc(<int>[0x5B, 0x42])); // ESC [ B
    });

    test('带修饰 -> CSI 参数形式 ESC [ 1;mod X', () {
      // Ctrl+Up：mod = 1 + ctrl(4) = 5
      expect(
        bytes(combo('Up', ctrl: true)),
        esc(<int>[0x5B, 0x31, 0x3B, 0x35, 0x41]), // ESC [ 1 ; 5 A
      );
      // Shift+Up：mod = 1 + shift(1) = 2
      expect(
        bytes(combo('Up', shift: true)),
        esc(<int>[0x5B, 0x31, 0x3B, 0x32, 0x41]), // ESC [ 1 ; 2 A
      );
    });

    test('波浪号结尾的键要把修修饰插到 ~ 之前', () {
      expect(bytes(combo('PageUp')), esc(<int>[0x5B, 0x35, 0x7E])); // [5~
      expect(
        bytes(combo('PageUp', ctrl: true)),
        esc(<int>[0x5B, 0x35, 0x3B, 0x35, 0x7E]), // [5;5~
      );
      expect(
        bytes(combo('Delete', shift: true)),
        esc(<int>[0x5B, 0x33, 0x3B, 0x32, 0x7E]), // [3;2~
      );
    });

    test('F1-F4 的 SS3 序列带修饰时改写成等价 CSI', () {
      expect(bytes(combo('F1')), <int>[0x1B, 0x4F, 0x50]); // ESC O P
      expect(
        bytes(combo('F1', shift: true)),
        esc(<int>[0x5B, 0x31, 0x3B, 0x32, 0x50]), // ESC [ 1;2P
      );
    });

    test('F5 及以上本身就是 CSI', () {
      expect(bytes(combo('F5')), esc(<int>[0x5B, 0x31, 0x35, 0x7E])); // [15~
    });
  });

  group('单字节键', () {
    test('Enter -> CR', () {
      expect(bytes(combo('Enter')), <int>[0x0D]);
    });

    test('Tab -> 0x09；Shift+Tab -> ESC [ Z（反向补全）', () {
      expect(bytes(combo('Tab')), <int>[0x09]);
      expect(bytes(combo('Tab', shift: true)), esc(<int>[0x5B, 0x5A]));
    });

    test('Backspace 默认 DEL，Ctrl 版本是 0x08', () {
      expect(bytes(combo('Backspace')), <int>[0x7F]);
      expect(bytes(combo('Backspace', ctrl: true)), <int>[0x08]);
    });
  });

  test('普通字符原样发送；Shift 只对字母生效', () {
    expect(bytes(combo('a')), <int>[0x61]);
    expect(bytes(combo('a', shift: true)), <int>[0x41]);
    expect(bytes(combo('1')), <int>[0x31]);
  });

  group('describeBytes 预览', () {
    test('控制字符用 caret 记法', () {
      expect(describeBytes(<int>[0x03]), '^C');
      expect(describeBytes(<int>[0x1B, 0x5B, 0x41]), 'ESC [ A');
      expect(describeBytes(<int>[0x7F]), 'DEL');
      expect(describeBytes(const <int>[]), '（不发送任何内容）');
    });
  });

  group('KeyCombo 模型', () {
    test('JSON 往返保持一致', () {
      const original = KeyCombo(
        id: 'k1',
        key: 'p',
        ctrl: true,
        alt: true,
        shift: false,
        label: '前缀键',
      );
      final roundTripped = KeyCombo.fromJson(original.toJson());

      expect(roundTripped.id, 'k1');
      expect(roundTripped.key, 'p');
      expect(roundTripped.ctrl, isTrue);
      expect(roundTripped.alt, isTrue);
      expect(roundTripped.shift, isFalse);
      expect(roundTripped.label, '前缀键');
    });

    test('没有自定义名时自动拼出 Ctrl+C 这种形式', () {
      expect(
        const KeyCombo(id: '', key: 'c', ctrl: true).displayLabel,
        'Ctrl+C',
      );
      expect(
        const KeyCombo(id: '', key: 'Up', alt: true).displayLabel,
        'Alt+↑',
      );
      expect(const KeyCombo(id: '', key: 'a').displayLabel, 'A');
    });

    test('缺字段的旧数据不会崩', () {
      final parsed = KeyCombo.fromJson(<String, dynamic>{'key': 'l'});
      expect(parsed.key, 'l');
      expect(parsed.ctrl, isFalse);
      expect(parsed.label, isNull);
    });

    test('预设列表里每个组合都能编码出字节', () {
      for (final preset in KeyCombo.defaults) {
        expect(
          encodeKeyCombo(preset),
          isNotEmpty,
          reason: '${preset.displayLabel} 编码不出任何字节',
        );
      }
    });
  });
}
