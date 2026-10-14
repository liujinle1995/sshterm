import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 终端的显示偏好。目前只有字号，将来要塞行高、光标样式也放这儿。
class TerminalPrefs {
  TerminalPrefs._();

  /// 10 是"手机竖屏 360dp 能放下 34 列"的下限，再小就没法看 PDF 里的宽表；
  /// 22 是"一行放不下 16 列"的上限，再大 command 就折得没法读。
  static const double minFont = 10;
  static const double maxFont = 22;
  static const double defaultFont = 13;
  static const double step = 1;

  static const String fontKey = 'sshterm.terminal.fontSize.v1';

  /// 测试 / 预览用：直接给值，不读本地存储
  @visibleForTesting
  static double? debugFontOverride;

  static double clampFont(double value) {
    if (value.isNaN) return defaultFont;
    return value.clamp(minFont, maxFont).toDouble();
  }

  static Future<double> loadFontSize() async {
    final override = debugFontOverride;
    if (override != null) return clampFont(override);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(fontKey);
      if (stored == null) return defaultFont;
      return clampFont(stored);
    } catch (_) {
      // 读不出来就用默认值，不该因为偏好读失败就打不开终端
      return defaultFont;
    }
  }

  static Future<void> saveFontSize(double value) async {
    if (debugFontOverride != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(fontKey, clampFont(value));
    } catch (_) {
      // 存不上只影响下次启动，不打断当前操作
    }
  }

  /// 上面那个 `unawaited` 用得到
  static void saveFontSizeInBackground(double value) {
    unawaited(saveFontSize(value));
  }
}
