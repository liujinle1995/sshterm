import 'package:flutter/material.dart';

import 'theme_store.dart';

/// 全局主题开关。
///
/// 做成 `ValueNotifier` 而不是 setState：`main()` 里的 MaterialApp 和设置页
/// 隔着好几层路由，用 InheritedWidget 传一次全局单例反而更省事。
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController({ThemeStore? store, ThemeMode? initial})
    : _store = store ?? ThemeStore(),
      super(initial ?? ThemeStore.fallback);

  /// 生产代码用这个；测试里 new 一个自己的实例，避免相互串状态。
  static final ThemeController instance = ThemeController();

  final ThemeStore _store;
  bool _loaded = false;

  /// 从磁盘恢复。重复调只读一次（`main()` 和设置页都会调）。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final mode = await _store.load();
    if (mode != value) value = mode;
  }

  /// 只覆盖已读标记，测试用：让下一次 [load] 重新读盘。
  @visibleForTesting
  void resetLoadedFlag() => _loaded = false;

  Future<void> setMode(ThemeMode mode) async {
    // 先改内存再落盘：切主题必须是立刻的，不能让用户等一次磁盘 IO
    if (value != mode) value = mode;
    await _store.save(mode);
  }

  /// 三档的中文名，设置页和外观页共用
  static String label(ThemeMode mode) => switch (mode) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
    ThemeMode.system => '跟随系统',
  };
}
