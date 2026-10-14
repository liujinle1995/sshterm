import 'package:flutter/material.dart';

import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import 'adaptive.dart';

/// 夜间模式（外观）设置页：浅色 / 深色 / 跟随系统 三选一。
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key, this.controller});

  /// 测试 / 预览用：注入一个独立控制器，免得动到全局单例。
  @visibleForTesting
  final ThemeController? controller;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late final ThemeController _controller =
      widget.controller ?? ThemeController.instance;

  @override
  void initState() {
    super.initState();
    // 冷启动时 main() 已经读过盘了，这里只是兜底（例如从深链直接进来）
    _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('夜间模式')),
      body: ReadableWidth(
        maxWidth: Adaptive.readableWidth,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? _) {
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: <Widget>[
                Text(
                  '选一套配色。切换是立刻生效的，不用重启 App，'
                  '终端本体和快捷键栏会一起跟着变。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final ThemeMode mode in const <ThemeMode>[
                  ThemeMode.system,
                  ThemeMode.light,
                  ThemeMode.dark,
                ])
                  _ModeCard(
                    mode: mode,
                    selected: _controller.value == mode,
                    onTap: () => _controller.setMode(mode),
                  ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '「跟随系统」会读手机的深色模式开关；'
                        '选浅色或深色则固定不动，系统怎么切都不受影响。',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.6,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  String get _subtitle => switch (mode) {
    ThemeMode.system => '手机开深色，App 就是深色',
    ThemeMode.light => '始终亮色，白天看得清',
    ThemeMode.dark => '始终深色，夜里不刺眼',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: ValueKey<String>('appearance-${ThemeController.label(mode)}'),
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: <Widget>[
                _ModePreview(mode: mode, selected: selected),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ThemeController.label(mode),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一张缩略图：上半是终端外框、下半是内容区，用来看清这套配色长什么样。
/// 「跟随系统」画成左右各半。
class _ModePreview extends StatelessWidget {
  const _ModePreview({required this.mode, required this.selected});

  final ThemeMode mode;
  final bool selected;

  static const double _w = 74;
  static const double _h = 52;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget body = switch (mode) {
      ThemeMode.system => Row(
        children: <Widget>[
          Expanded(child: _Pane(brightness: Brightness.light)),
          Expanded(child: _Pane(brightness: Brightness.dark)),
        ],
      ),
      ThemeMode.light => _Pane(brightness: Brightness.light),
      ThemeMode.dark => _Pane(brightness: Brightness.dark),
    };

    return Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          body,
          if (mode == ThemeMode.system)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.brightness_auto,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 同一套配色在"深色/浅色"下的样子：一条外框 + 两行"文本" + 一个光标块
class _Pane extends StatelessWidget {
  const _Pane({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final chrome = AppTheme.chrome(brightness);
    final theme = AppTheme.terminalTheme(brightness);
    final dark = brightness == Brightness.dark;

    return Container(
      color: theme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 11,
            color: chrome,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: AppTheme.chromeForeground(brightness)
                    .withValues(alpha: dark ? 0.55 : 0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _bar(theme.foreground, 0.75, width: 26),
                  const SizedBox(height: 4),
                  _bar(theme.green, 0.9, width: 18),
                  const SizedBox(height: 5),
                  Container(width: 5, height: 7, color: theme.cursor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(Color color, double alpha, {required double width}) => Container(
    width: width,
    height: 3,
    decoration: BoxDecoration(
      color: color.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
