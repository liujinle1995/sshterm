import 'package:flutter/material.dart';

/// 平板 / 折叠屏 / 手机横屏的断点与限宽工具。
///
/// 为什么需要：整套界面是按 360dp 手机写的单列布局，扔到 1280dp 的平板上
/// 会出现两种丑法 —— 列表卡片横向拉成一条长带、设置项的文字和开关隔着一屏远。
///
/// 处理原则很朴素：
///  * 一维列表（设置、命令、插件、更新记录）→ **限宽居中**，别让它无限拉长；
///  * 二维列表（主机卡片）→ **多列网格**，把横向空间用起来；
///  * 终端页 → 快捷键栏从底部挪到**左侧竖排**，横屏时把高度全留给终端。
class Adaptive {
  const Adaptive._();

  /// Material 3 里 "expanded" 的下限。720dp 之上再按单列铺满就明显浪费了。
  static const double wide = 720;

  /// 列表类页面的可读宽度上限。再宽就该用多列了，而不是继续放宽。
  static const double readableWidth = 720;

  /// 表单页（新建/编辑主机）窄一点，输入框太长反而不好读
  static const double formWidth = 620;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

/// 把内容限制在可读宽度内并顶部居中。
///
/// 手机上（宽度 <= [maxWidth]）等于原样透传，不会有任何布局变化。
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = Adaptive.readableWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
