import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 插件状态：核心能力 / 可选模块 / 规划中
enum PluginKind {
  core,
  builtin,
  planned;

  static PluginKind parse(String? raw) => switch (raw) {
    'builtin' => builtin,
    'planned' => planned,
    _ => core,
  };

  String get label => switch (this) {
    core => '核心',
    builtin => '内置',
    planned => '规划中',
  };
}

@immutable
class PluginEntry {
  const PluginEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.kind,
    required this.enabled,
    required this.summary,
    required this.package,
    this.details = const <String>[],
  });

  final String id;
  final String name;
  final String version;

  /// 底层依赖的包名 / "内置" / "规划中"
  final String package;
  final PluginKind kind;
  final bool enabled;
  final String summary;
  final List<String> details;

  factory PluginEntry.fromJson(Map<String, dynamic> json) => PluginEntry(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
    package: json['package'] as String? ?? '',
    kind: PluginKind.parse(json['kind'] as String?),
    enabled: json['enabled'] as bool? ?? false,
    summary: json['summary'] as String? ?? '',
    details: (json['details'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList(),
  );
}

/// 更新记录条目
enum ChangeType { added, changed, fixed, removed }

@immutable
class ChangeItem {
  const ChangeItem({required this.type, required this.text});

  final ChangeType type;
  final String text;

  factory ChangeItem.fromJson(Map<String, dynamic> json) => ChangeItem(
    type: switch (json['type'] as String?) {
      'changed' => ChangeType.changed,
      'fixed' => ChangeType.fixed,
      'removed' => ChangeType.removed,
      _ => ChangeType.added,
    },
    text: json['text'] as String? ?? '',
  );
}

@immutable
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.summary,
    required this.items,
    this.tagline = '',
  });

  final String version;
  final String date;
  final String tagline;
  final String summary;
  final List<ChangeItem> items;

  bool get isEmpty => items.isEmpty;

  factory ReleaseNote.fromJson(Map<String, dynamic> json) => ReleaseNote(
    version: json['version'] as String? ?? '',
    date: json['date'] as String? ?? '',
    tagline: json['tagline'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ChangeItem.fromJson)
        .toList(),
  );
}

/// 读取 `assets/plugins.json` 与 `assets/changelog.json`。
///
/// 这两份是**过期也无妨**的说明性数据，所以任何解析失败都回落到空列表，
/// 绝不让设置页因为一个 JSON 打错符号而整页崩掉。
class CatalogService {
  static const String _pluginAsset = 'assets/plugins.json';
  static const String _changelogAsset = 'assets/changelog.json';

  /// 缓存：同一进程里重复进设置页不必反复读
  static List<PluginEntry>? _pluginCache;
  static List<ReleaseNote>? _changelogCache;

  /// 预览图 / 测试用：绕开 rootBundle 直接喂数据。
  ///
  /// 为什么需要：`flutter test` 不打包 asset，`rootBundle.loadString` 一定失败，
  /// 于是设置页永远显示"没加载到"。截图脚本自己从磁盘读 json 填进来。
  static List<PluginEntry>? debugPluginsOverride;
  static List<ReleaseNote>? debugChangelogOverride;

  Future<List<PluginEntry>> plugins() async {
    final pluginOverride = debugPluginsOverride;
    if (pluginOverride != null) return pluginOverride;

    final cached = _pluginCache;
    if (cached != null) return cached;

    final List<PluginEntry> result;
    try {
      final raw = await rootBundle.loadString(_pluginAsset);
      final json = _decodeMap(raw);
      final list = json['plugins'] as List<dynamic>? ?? const <dynamic>[];
      result = list
          .whereType<Map<String, dynamic>>()
          .map(PluginEntry.fromJson)
          .where((PluginEntry p) => p.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <PluginEntry>[];
    }
    _pluginCache = result;
    return result;
  }

  Future<List<ReleaseNote>> changelog() async {
    final noteOverride = debugChangelogOverride;
    if (noteOverride != null) return noteOverride;

    final cached = _changelogCache;
    if (cached != null) return cached;

    final List<ReleaseNote> result;
    try {
      final raw = await rootBundle.loadString(_changelogAsset);
      final json = _decodeMap(raw);
      final list = json['releases'] as List<dynamic>? ?? const <dynamic>[];
      result = list
          .whereType<Map<String, dynamic>>()
          .map(ReleaseNote.fromJson)
          .where((ReleaseNote r) => r.version.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <ReleaseNote>[];
    }
    _changelogCache = result;
    return result;
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }
}
