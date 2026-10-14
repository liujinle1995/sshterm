import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 凭据 + 已知主机指纹的安全存储（Android 侧落在 Keystore 里）。
///
/// 约定（尖括号是占位符）：
///
///   `pw.<hostId>`            主机密码
///   `key.<keyId>`            私钥 PEM 文本
///   `keyphrase.<keyId>`      私钥口令
///   `kh.<hostname>:<port>`   该主机首次连接时记住的公钥指纹
class CredentialStore {
  CredentialStore._();

  // v9 的 Android 默认实现已经走 encryptedSharedPreferences，直接用默认配置即可
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _knownHostKey(String hostname, int port) =>
      'kh.$hostname:$port';

  // ---------------- 密码 ----------------
  static Future<void> setPassword(String hostId, String password) =>
      _storage.write(key: 'pw.$hostId', value: password);

  static Future<String?> password(String hostId) =>
      _storage.read(key: 'pw.$hostId');

  // ---------------- 私钥 ----------------
  static Future<void> setPrivateKey(String keyId, String pem) =>
      _storage.write(key: 'key.$keyId', value: pem);

  static Future<String?> privateKey(String keyId) =>
      _storage.read(key: 'key.$keyId');

  static Future<void> setPrivateKeyPassphrase(String keyId, String phrase) =>
      _storage.write(key: 'keyphrase.$keyId', value: phrase);

  static Future<String?> privateKeyPassphrase(String keyId) =>
      _storage.read(key: 'keyphrase.$keyId');

  // ---------------- 已知主机（TOFU） ----------------
  static Future<String?> knownFingerprint(String hostname, int port) =>
      _storage.read(key: _knownHostKey(hostname, port));

  static Future<void> rememberFingerprint(
    String hostname,
    int port,
    String fingerprint,
  ) => _storage.write(key: _knownHostKey(hostname, port), value: fingerprint);

  static Future<void> forgetFingerprint(String hostname, int port) =>
      _storage.delete(key: _knownHostKey(hostname, port));

  // ---------------- 清理 ----------------
  static Future<void> removeHostSecrets(String hostId) =>
      _storage.delete(key: 'pw.$hostId');

  static Future<void> removeKey(String keyId) async {
    await _storage.delete(key: 'key.$keyId');
    await _storage.delete(key: 'keyphrase.$keyId');
  }
}
