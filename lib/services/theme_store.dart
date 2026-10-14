import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观模式的持久化。
///
/// 和 KeyComboStore 一样：**任何情况都不许抛**。主题是在 `main()` 里读取的，
/// 一旦抛异常就是启动黑屏，代价比读不到主题大得多。
class ThemeStore {
  static const String key = 'sshterm.theme.mode.v1';

  /// 默认深色 —— 这是个终端 App，而且 1.1.0 全是深色，
  /// 老用户升级后不该突然变白。（想要跟随系统的人自己去设置里点一下。）
  static const ThemeMode fallback = ThemeMode.dark;

  Future<ThemeMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(key));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encode(mode));
    } catch (_) {
      // 存不进去就算了，本次运行内切换依然生效
    }
  }

  /// 落盘用字符串而不是下标：以后往枚举中间插一项也不会把老用户的设置读串。
  static String encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  static ThemeMode decode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => fallback,
  };
}
