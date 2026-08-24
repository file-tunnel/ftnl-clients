import 'dart:convert';
import 'dart:typed_data';

import 'package:ftnl_client/ftnl_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    expect(
      pairingSecretFromUri(
        Uri.parse('https://portal.test/t/id?c=leaky#c=fragment'),
      ),
      isNull,
    );
  });

  test('public cleartext and non-HTTP schemes are rejected', () {
    expect(
      () => FileTunnelClient(Uri.parse('http://api.example.com')),
      throwsArgumentError,
    );
    expect(
      () => FileTunnelClient(Uri.parse('http://[2001:4860:4860::8888]')),
      throwsArgumentError,
    );
    expect(
      () => FileTunnelClient(Uri.parse('file:///tmp/socket')),
      throwsArgumentError,
    );
    expect(
      () => FileTunnelClient(Uri.parse('https://user:secret@api.example.com')),
      throwsArgumentError,
    );
    expect(
      () => FileTunnelClient(Uri.parse('https://api.example.com?debug=true')),
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

  test('full mobile transfer contract keeps credentials out of URLs', () async {
    const tunnelId = '8be939aa-686e-41c4-a7e1-d4152150a8ad';
    const fileId = 'e156358a-8382-4ad8-91f3-7d9becd8b69d';
    const pairingSecret = 'pairing-secret-000000000000000000';
    const desktopCapability = 'desktop-capability-00000000000000';
    const phoneCapability = 'phone-capability-0000000000000000';
    const eventTicket = 'event-ticket-000000000000000000000';
    final payload = Uint8List.fromList([0, 1, 2, 3, 255]);
    Uint8List? uploaded;

    final client = FileTunnelClient(
      Uri.parse('https://api.file-tunnel.dev'),
      httpClient: MockClient((request) async {
        switch ((request.method, request.url.path)) {
          case ('POST', '/v1/tunnels'):
            expect(request.headers['authorization'], isNull);
            expect(
              jsonDecode(request.body)['application_id'],
              'dart-conformance',
            );
            return http.Response(
              jsonEncode({
                'api_version': 'v1',
                'tunnel_id': tunnelId,
                'status': 'waiting',
                'pairing_uri':
                    'https://file-tunnel.dev/pair/$tunnelId#c=$pairingSecret',
                'desktop_capability': desktopCapability,
                'expires_at': '2030-01-01T00:00:00Z',
              }),
              201,
            );
          case ('POST', '/v1/tunnels/$tunnelId/claim'):
            expect(request.headers['authorization'], isNull);
            expect(jsonDecode(request.body)['pairing_secret'], pairingSecret);
            return http.Response(
              jsonEncode({
                'phone_capability': phoneCapability,
                'expires_at': '2030-01-01T00:00:00Z',
              }),
              200,
            );
          case ('GET', '/v1/tunnels/$tunnelId'):
            _expectCapability(request, desktopCapability);
            return http.Response(
              jsonEncode({
                'tunnel_id': tunnelId,
                'status': 'connected',
                'expires_at': '2030-01-01T00:00:00Z',
                'files': <Object?>[],
              }),
              200,
            );
          case ('POST', '/v1/tunnels/$tunnelId/files'):
            _expectCapability(request, phoneCapability);
            expect(request.headers['idempotency-key'], 'dart-test-request');
            return http.Response(
              jsonEncode({
                'file_id': fileId,
                'name': 'photo.jpg',
                'media_type': 'image/jpeg',
                'size_bytes': payload.length,
                'bytes_transferred': 0,
                'status': 'declared',
                'created_at': '2030-01-01T00:00:00Z',
              }),
              201,
            );
          case ('PUT', '/v1/tunnels/$tunnelId/files/$fileId/content'):
            _expectCapability(request, phoneCapability);
            expect(request.headers['content-type'], 'application/octet-stream');
            uploaded = request.bodyBytes;
            return http.Response('', 204);
          case ('GET', '/v1/tunnels/$tunnelId/files/$fileId/content'):
            _expectCapability(request, desktopCapability);
            return http.Response.bytes(payload, 200);
          case ('POST', '/v1/tunnels/$tunnelId/event-tickets'):
            _expectCapability(request, desktopCapability);
            return http.Response(
              jsonEncode({
                'ticket': eventTicket,
                'expires_at': '2030-01-01T00:00:00Z',
              }),
              201,
            );
          case ('DELETE', '/v1/tunnels/$tunnelId'):
            _expectCapability(request, desktopCapability);
            return http.Response('', 204);
          default:
            fail('unexpected request: ${request.method} ${request.url.path}');
        }
      }),
    );

    final tunnel = await client.createTunnel(
      applicationId: 'dart-conformance',
      accept: const ['image/*'],
      maxFiles: 2,
      maxFileBytes: 1024,
      expiresInSeconds: 120,
    );
    expect(tunnel.tunnelId, tunnelId);
    expect(pairingSecretFromUri(tunnel.pairingUri), pairingSecret);
    expect(tunnel.toString(), isNot(contains(pairingSecret)));
    expect(tunnel.toString(), isNot(contains(desktopCapability)));

    final claim = await client.claimTunnelDetails(
      tunnelId,
      pairingSecret,
      deviceLabel: 'flutter-example',
    );
    expect(claim.phoneCapability, phoneCapability);
    expect(claim.toString(), isNot(contains(phoneCapability)));
    expect((await client.snapshot(tunnelId, desktopCapability)).files, isEmpty);

    final file = await client.declareFile(
      tunnelId: tunnelId,
      capability: phoneCapability,
      name: 'photo.jpg',
      mediaType: 'image/jpeg',
      sizeBytes: payload.length,
      lastModifiedMillis: 123,
      sha256: 'a' * 64,
      idempotencyKey: 'dart-test-request',
    );
    expect(file.fileId, fileId);
    await client.upload(
      tunnelId: tunnelId,
      fileId: fileId,
      capability: phoneCapability,
      bytes: payload,
    );
    expect(uploaded, payload);
    expect(
      await client.download(
        tunnelId: tunnelId,
        fileId: fileId,
        capability: desktopCapability,
      ),
      payload,
    );

    final eventUri = await client.eventSocketUri(tunnelId, desktopCapability);
    expect(eventUri.scheme, 'wss');
    expect(eventUri.queryParameters['ticket'], eventTicket);
    await client.cancel(tunnelId, desktopCapability);
  });

  test('problem bodies never escape through exceptions', () async {
    const capability = 'desktop-capability-00000000000000';
    const bodySecret = 'body-secret-must-never-escape';
    final client = FileTunnelClient(
      Uri.parse('https://api.file-tunnel.dev'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'code': 'pairing_expired', 'detail': bodySecret}),
          401,
        ),
      ),
    );

    await expectLater(
      client.snapshot('error', capability),
      throwsA(
        isA<FileTunnelException>()
            .having((error) => error.status, 'status', 401)
            .having((error) => error.code, 'code', 'pairing_expired')
            .having(
              (error) => error.toString(),
              'safe description',
              allOf(isNot(contains(bodySecret)), isNot(contains(capability))),
            ),
      ),
    );
  });
}

void _expectCapability(http.Request request, String capability) {
  expect(request.headers['authorization'], 'Bearer $capability');
  expect(request.url.query, isEmpty);
}
