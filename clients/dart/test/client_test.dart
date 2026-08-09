import 'package:ftnl_client/ftnl_client.dart';
import 'package:test/test.dart';

void main() {
  test('pairing secret is fragment only', () {
    expect(
      pairingSecretFromUri(Uri.parse('https://portal.test/t/id#c=secret')),
      'secret',
    );
    expect(
      pairingSecretFromUri(Uri.parse('https://portal.test/t/id?c=leaky')),
      isNull,
    );
  });

  test('public cleartext and non-HTTP schemes are rejected', () {
    expect(
      () => FileTunnelClient(Uri.parse('http://api.example.com')),
      throwsArgumentError,
    );
    expect(
      () => FileTunnelClient(Uri.parse('file:///tmp/socket')),
      throwsArgumentError,
    );
  });

  test('internal cleartext endpoints remain available', () {
    for (final endpoint in <String>[
      'http://127.0.0.1:8080',
      'http://[::1]:8080',
      'http://10.2.3.4',
      'http://ftnl-api',
      'http://ftnl-api.default.svc.cluster.local',
    ]) {
      expect(() => FileTunnelClient(Uri.parse(endpoint)), returnsNormally);
    }
  });

  test('request timeout must be positive', () {
    expect(
      () => FileTunnelClient(
        Uri.parse('https://api.example.com'),
        requestTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
