import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/key_combo.dart';

/// 自定义快捷键组合的持久化。
///
/// ⚠️ 所有方法都不能抛：软键盘第二排要在 `FutureBuilder` 里读它，
/// 一旦抛异常整个终端页会挂掉（渲染预览、widget 测试也会连带失败）。
class KeyComboStore {
  static const String _key = 'sshterm.keycombos.v1';

  Future<List<KeyCombo>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        await save(KeyCombo.defaults);
        return KeyCombo.defaults;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(KeyCombo.fromJson)
          .where((KeyCombo c) => c.key.isNotEmpty)
          .toList();
    } catch (_) {
      return KeyCombo.defaults;
    }
  }

  Future<void> save(List<KeyCombo> combos) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(combos.map((c) => c.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  /// 恢复出厂预设
  Future<void> reset() => save(KeyCombo.defaults);
}
