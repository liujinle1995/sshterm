import 'package:flutter_test/flutter_test.dart';
import 'package:sshterm/models/ssh_host.dart';

void main() {
  group('SshHost 序列化', () {
    test('JSON 往返保持一致', () {
      final host = SshHost(
        id: 'h1',
        name: '家里的 NAS',
        hostname: '192.168.1.10',
        port: 2222,
        username: 'root',
        authMethod: HostAuthMethod.privateKey,
        privateKeyId: 'k-h1',
      );

      final restored = SshHost.fromJson(host.toJson());

      expect(restored.id, host.id);
      expect(restored.hostname, host.hostname);
      expect(restored.port, 2222);
      expect(restored.username, 'root');
      expect(restored.authMethod, HostAuthMethod.privateKey);
      expect(restored.privateKeyId, 'k-h1');
    });

    test('字段缺失时回落到安全默认值', () {
      final host = SshHost.fromJson(<String, dynamic>{'id': 'x'});

      expect(host.port, 22);
      expect(host.authMethod, HostAuthMethod.password);
      expect(host.privateKeyId, isNull);
    });

    test('备注名为空时把主机名当标题', () {
      const host = SshHost(id: 'y', name: '  ', hostname: 'example.com');
      expect(host.displayName, 'example.com');
      expect(host.endpoint, 'example.com:22');
    });
  });
}
