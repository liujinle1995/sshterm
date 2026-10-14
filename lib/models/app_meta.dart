/// App 的元信息。
///
/// 刻意不放额外依赖去读 package_info —— 版本号本来就该跟 pubspec.yaml 一起改，
/// 写在这里反而提醒自己：发版时这里和 `assets/changelog.json` 要同步更新。
class AppMeta {
  const AppMeta._();

  static const String name = 'SSH 终端';
  static const String package = 'top.lele.sshterm';
  static const String version = '1.4.1';
  static const String build = '6';

  static String get fullVersion => '$version+$build';
}
