import 'package:flutter/foundation.dart';

/// 认证方式：密码 或 私钥
enum HostAuthMethod {
  password,
  privateKey;

  static HostAuthMethod fromIndex(int? index) {
    if (index == null || index < 0 || index >= values.length) {
      return password;
    }
    return values[index];
  }
}

/// 一台远程主机的连接配置。
///
/// 这里只存"非敏感"的部分（地址、端口、用户名），
/// 密码和私钥一律不落在这里，统一放 CredentialStore（Android Keystore）。
@immutable
class SshHost {
  const SshHost({
    required this.id,
    this.name = '',
    this.hostname = '',
    this.port = 22,
    this.username = '',
    this.authMethod = HostAuthMethod.password,
    this.privateKeyId,
  });

  final String id;
  final String name;
  final String hostname;
  final int port;
  final String username;
  final HostAuthMethod authMethod;

  /// 私钥在 CredentialStore 里的 key，本身不是私钥内容
  final String? privateKeyId;

  String get displayName => name.trim().isEmpty ? hostname : name;

  String get endpoint => '$hostname:$port';

  SshHost copyWith({
    String? name,
    String? hostname,
    int? port,
    String? username,
    HostAuthMethod? authMethod,
    String? privateKeyId,
    bool clearPrivateKeyId = false,
  }) {
    return SshHost(
      id: id,
      name: name ?? this.name,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      privateKeyId: clearPrivateKeyId
          ? null
          : (privateKeyId ?? this.privateKeyId),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'hostname': hostname,
    'port': port,
    'username': username,
    'authMethod': authMethod.index,
    'privateKeyId': privateKeyId,
  };

  factory SshHost.fromJson(Map<String, dynamic> json) {
    return SshHost(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hostname: json['hostname'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      authMethod: HostAuthMethod.fromIndex(json['authMethod'] as int?),
      privateKeyId: json['privateKeyId'] as String?,
    );
  }

  static String newId() =>
      'h${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
