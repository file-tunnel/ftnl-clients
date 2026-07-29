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
}
