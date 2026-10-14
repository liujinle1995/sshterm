import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/command_snippet.dart';

/// 常用命令片段的持久化。约定同 [KeyComboStore]：任何情况都不抛。
class SnippetStore {
  static const String _key = 'sshterm.snippets.v1';

  Future<List<CommandSnippet>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        await save(CommandSnippet.defaults);
        return CommandSnippet.defaults;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(CommandSnippet.fromJson)
          .where((CommandSnippet s) => s.command.isNotEmpty)
          .toList();
    } catch (_) {
      return CommandSnippet.defaults;
    }
  }

  Future<void> save(List<CommandSnippet> snippets) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(snippets.map((s) => s.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> reset() => save(CommandSnippet.defaults);
}
