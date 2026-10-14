import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_host.dart';

/// 主机列表持久化。
///
/// 注意：这里只存连接参数，任何密码/私钥都不经过这个 Store。
class HostStore {
  static const String _key = 'sshterm.hosts.v1';

  Future<List<SshHost>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <SshHost>[];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SshHost.fromJson)
          .where((h) => h.id.isNotEmpty && h.hostname.isNotEmpty)
          .toList();
    } catch (_) {
      return <SshHost>[];
    }
  }

  Future<void> save(List<SshHost> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(hosts.map((h) => h.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
