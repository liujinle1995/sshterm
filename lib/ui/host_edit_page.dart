import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../services/credential_store.dart';
import 'adaptive.dart';

/// 新增 / 编辑一台主机。
///
/// 返回 true 表示保存成功。密码和私钥单独存进 CredentialStore，
/// 不写回 SshHost（那个对象会被存到 SharedPreferences 里）。
class HostEditPage extends StatefulWidget {
  const HostEditPage({super.key, this.host});

  final SshHost? host;

  bool get isNew => host == null;

  @override
  State<HostEditPage> createState() => _HostEditPageState();
}

class _HostEditPageState extends State<HostEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _hostname;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _privateKey;
  late final TextEditingController _passphrase;

  late HostAuthMethod _authMethod;
  bool _keyPasswordVisible = false;
  bool _hiddenPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    final h = widget.host;
    _name = TextEditingController(text: h?.name ?? '');
    _hostname = TextEditingController(text: h?.hostname ?? '');
    _port = TextEditingController(text: '${h?.port ?? 22}');
    _username = TextEditingController(text: h?.username ?? '');
    _password = TextEditingController();
    _privateKey = TextEditingController();
    _passphrase = TextEditingController();
    _authMethod = h?.authMethod ?? HostAuthMethod.password;

    if (h != null) {
      _loadSecrets(h);
    }
  }

  /// 已有凭据回填到输入框，方便直接点保存
  Future<void> _loadSecrets(SshHost host) async {
    final password = await CredentialStore.password(host.id);
    if (!mounted) return;
    if (password != null) {
      _password.text = password;
    }
    final keyId = host.privateKeyId;
    if (keyId == null) return;
    final pem = await CredentialStore.privateKey(keyId);
    final passphrase = await CredentialStore.privateKeyPassphrase(keyId);
    if (!mounted) return;
    if (pem != null) {
      _privateKey.text = pem;
    }
    if (passphrase != null) {
      _passphrase.text = passphrase;
    }
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _name,
      _hostname,
      _port,
      _username,
      _password,
      _privateKey,
      _passphrase,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final base = widget.host;
    final id = base?.id ?? SshHost.newId();

    final useKey = _authMethod == HostAuthMethod.privateKey;
    final keyId = useKey ? 'k-$id' : null;

    if (useKey) {
      await CredentialStore.setPrivateKey(keyId!, _privateKey.text.trim());
      final phrase = _passphrase.text;
      if (phrase.isEmpty) {
        await CredentialStore.setPrivateKeyPassphrase(keyId, '');
      } else {
        await CredentialStore.setPrivateKeyPassphrase(keyId, phrase);
      }
    } else if (_password.text.isNotEmpty) {
      await CredentialStore.setPassword(id, _password.text);
    } else {
      await CredentialStore.removeHostSecrets(id);
    }

    final newHost = (base ?? SshHost(id: id, username: _username.text.trim()))
        .copyWith(
          name: _name.text.trim(),
          hostname: _hostname.text.trim(),
          port: int.tryParse(_port.text.trim()) ?? 22,
          username: _username.text.trim(),
          authMethod: _authMethod,
          privateKeyId: keyId,
          clearPrivateKeyId: !useKey,
        );

    if (!mounted) return;
    // 非空即表示"保存了"
    Navigator.of(context).pop(newHost);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isNew ? '添加主机' : '编辑主机')),
      body: ReadableWidth(
        maxWidth: Adaptive.formWidth,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '备注名',
                  hintText: '家里的 NAS',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hostname,
                decoration: const InputDecoration(
                  labelText: '主机地址',
                  hintText: '192.168.1.10 或 example.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? '不能为空' : null,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _port,
                decoration: const InputDecoration(
                  labelText: '端口',
                  prefixIcon: Icon(Icons.numbers_outlined),
                ),
                validator: (String? v) {
                  final p = int.tryParse(v?.trim() ?? '');
                  if (p == null || p < 1 || p > 65535) return '1-65535';
                  return null;
                },
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  hintText: 'root',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? '不能为空' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              Text('认证方式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<HostAuthMethod>(
                segments: const <ButtonSegment<HostAuthMethod>>[
                  ButtonSegment<HostAuthMethod>(
                    value: HostAuthMethod.password,
                    label: Text('密码'),
                    icon: Icon(Icons.password_outlined),
                  ),
                  ButtonSegment<HostAuthMethod>(
                    value: HostAuthMethod.privateKey,
                    label: Text('私钥'),
                    icon: Icon(Icons.vpn_key_outlined),
                  ),
                ],
                selected: <HostAuthMethod>{_authMethod},
                onSelectionChanged: (Set<HostAuthMethod> next) {
                  setState(() => _authMethod = next.first);
                },
              ),
              const SizedBox(height: 16),
              if (_authMethod == HostAuthMethod.password) ...<Widget>[
                TextFormField(
                  controller: _password,
                  obscureText: !_hiddenPasswordVisible,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hiddenPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(
                        () => _hiddenPasswordVisible = !_hiddenPasswordVisible,
                      ),
                    ),
                  ),
                  validator: (String? v) =>
                      widget.isNew && (v == null || v.isEmpty)
                      ? '新主机需要填密码'
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  '密码会存进 Android Keystore，不会明文写进配置文件。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...<Widget>[
                TextFormField(
                  controller: _privateKey,
                  maxLines: 8,
                  minLines: 6,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                  decoration: const InputDecoration(
                    labelText: '私钥（PEM 格式）',
                    alignLabelWithHint: true,
                    hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                  ),
                  validator: (String? v) {
                    if (v == null || v.trim().isEmpty) return '不能为空';
                    if (!v.contains('PRIVATE KEY')) return '看起来不是 PEM 私钥';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passphrase,
                  obscureText: !_keyPasswordVisible,
                  decoration: InputDecoration(
                    labelText: '私钥口令（没有就留空）',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _keyPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(
                        () => _keyPasswordVisible = !_keyPasswordVisible,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
