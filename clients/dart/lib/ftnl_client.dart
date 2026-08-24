import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

final class FileTunnelException implements Exception {
  const FileTunnelException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => 'FileTunnelException($status, $code)';
}

final class Tunnel {
  const Tunnel({
    required this.apiVersion,
    required this.tunnelId,
    required this.status,
    required this.pairingUri,
    required this.desktopCapability,
    required this.expiresAt,
  });
  final String apiVersion;
  final String tunnelId;
  final String status;
  final Uri pairingUri;
  final String desktopCapability;
  final DateTime expiresAt;

  factory Tunnel.fromJson(Map<String, Object?> json) => Tunnel(
    apiVersion: json['api_version']! as String,
    tunnelId: json['tunnel_id']! as String,
    status: json['status']! as String,
    pairingUri: Uri.parse(json['pairing_uri']! as String),
    desktopCapability: json['desktop_capability']! as String,
    expiresAt: DateTime.parse(json['expires_at']! as String),
  );

  @override
  String toString() =>
      'Tunnel(apiVersion: $apiVersion, tunnelId: $tunnelId, '
      'status: $status, expiresAt: $expiresAt)';
}

final class TunnelClaim {
  const TunnelClaim({required this.phoneCapability, required this.expiresAt});
  final String phoneCapability;
  final DateTime expiresAt;

  factory TunnelClaim.fromJson(Map<String, Object?> json) => TunnelClaim(
    phoneCapability: json['phone_capability']! as String,
    expiresAt: DateTime.parse(json['expires_at']! as String),
  );

  @override
  String toString() => 'TunnelClaim(expiresAt: $expiresAt)';
}

final class FileDescriptor {
  const FileDescriptor({
    required this.fileId,
    required this.name,
    required this.mediaType,
    required this.sizeBytes,
    required this.bytesTransferred,
    required this.status,
    required this.createdAt,
  });
  final String fileId;
  final String name;
  final String mediaType;
  final int sizeBytes;
  final int bytesTransferred;
  final String status;
  final DateTime createdAt;

  factory FileDescriptor.fromJson(Map<String, Object?> json) => FileDescriptor(
    fileId: json['file_id']! as String,
    name: json['name']! as String,
    mediaType: json['media_type']! as String,
    sizeBytes: json['size_bytes']! as int,
    bytesTransferred: json['bytes_transferred']! as int,
    status: json['status']! as String,
    createdAt: DateTime.parse(json['created_at']! as String),
  );
}

final class TunnelSnapshot {
  const TunnelSnapshot({
    required this.tunnelId,
    required this.status,
    required this.expiresAt,
    required this.files,
  });
  final String tunnelId;
  final String status;
  final DateTime expiresAt;
  final List<FileDescriptor> files;

  factory TunnelSnapshot.fromJson(Map<String, Object?> json) => TunnelSnapshot(
    tunnelId: json['tunnel_id']! as String,
    status: json['status']! as String,
    expiresAt: DateTime.parse(json['expires_at']! as String),
    files: (json['files']! as List<Object?>)
        .map((file) => FileDescriptor.fromJson((file! as Map).cast()))
        .toList(growable: false),
  );
}

bool _internalHostAllowed(String hostname) {
  final host = hostname.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host == '::1' || host == '::') return true;
  if (RegExp(r'^f[cd][0-9a-f]*:', caseSensitive: false).hasMatch(host) ||
      RegExp(r'^fe[89ab][0-9a-f]*:', caseSensitive: false).hasMatch(host)) {
    return true;
  }

  final octets = host.split('.').map(int.tryParse).toList();
  if (octets.length == 4 &&
      octets.every((value) => value != null && value >= 0 && value <= 255)) {
    final a = octets[0]!;
    final b = octets[1]!;
    return a == 127 ||
        a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        a == 0;
  }

  return host.isNotEmpty &&
      ((!host.contains('.') && !host.contains(':')) ||
          host.endsWith('.svc.cluster.local') ||
          host.endsWith('.internal'));
}

Uri _checkedBaseUri(Uri baseUri) {
  if (baseUri.scheme != 'https' && baseUri.scheme != 'http') {
    throw ArgumentError.value(
      baseUri,
      'baseUri',
      'ftnl: unsupported URL scheme "${baseUri.scheme}"; use https:// or an '
          'allowed internal http:// URL',
    );
  }
  if (!baseUri.hasAuthority ||
      baseUri.host.isEmpty ||
      baseUri.userInfo.isNotEmpty ||
      baseUri.hasQuery ||
      baseUri.hasFragment) {
    throw ArgumentError.value(
      baseUri,
      'baseUri',
      'ftnl: base URL must have an authority and no credentials, query, or '
          'fragment',
    );
  }
  if (baseUri.scheme == 'http' && !_internalHostAllowed(baseUri.host)) {
    throw ArgumentError.value(
      baseUri,
      'baseUri',
      'ftnl: refusing cleartext http:// to public host "${baseUri.host}": '
          'use https://, an in-cluster address, or loopback',
    );
  }
  return baseUri;
}

Duration _checkedTimeout(Duration timeout) {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(
      timeout,
      'requestTimeout',
      'ftnl: request timeout must be greater than zero',
    );
  }
  return timeout;
}

final class FileTunnelClient {
  FileTunnelClient(
    Uri baseUri, {
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _baseUri = _checkedBaseUri(baseUri),
       _http = httpClient ?? http.Client(),
       _requestTimeout = _checkedTimeout(requestTimeout);

  final Uri _baseUri;
  final http.Client _http;
  final Duration _requestTimeout;

  Future<Tunnel> createTunnel({
    required String applicationId,
    List<String> accept = const ['image/*'],
    int maxFiles = 10,
    int maxFileBytes = 50 * 1024 * 1024,
    int expiresInSeconds = 600,
  }) async {
    final response = await _send(
      'POST',
      '/v1/tunnels',
      jsonBody: {
        'application_id': applicationId,
        'accept': accept,
        'max_files': maxFiles,
        'max_file_bytes': maxFileBytes,
        'expires_in_seconds': expiresInSeconds,
      },
    );
    return Tunnel.fromJson(_json(response));
  }

  Future<String> claimTunnel(
    String tunnelId,
    String pairingSecret, {
    String? deviceLabel,
  }) async => (await claimTunnelDetails(
    tunnelId,
    pairingSecret,
    deviceLabel: deviceLabel,
  )).phoneCapability;

  Future<TunnelClaim> claimTunnelDetails(
    String tunnelId,
    String pairingSecret, {
    String? deviceLabel,
  }) async {
    final response = await _send(
      'POST',
      '/v1/tunnels/${_segment(tunnelId)}/claim',
      jsonBody: {'pairing_secret': pairingSecret, 'device_label': ?deviceLabel},
    );
    return TunnelClaim.fromJson(_json(response));
  }

  Future<TunnelSnapshot> snapshot(String tunnelId, String capability) async {
    final response = await _send(
      'GET',
      '/v1/tunnels/${_segment(tunnelId)}',
      capability: capability,
    );
    return TunnelSnapshot.fromJson(_json(response));
  }

  Future<FileDescriptor> declareFile({
    required String tunnelId,
    required String capability,
    required String name,
    required String mediaType,
    required int sizeBytes,
    int? lastModifiedMillis,
    String? sha256,
    String? idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/v1/tunnels/${_segment(tunnelId)}/files',
      capability: capability,
      idempotencyKey: idempotencyKey,
      jsonBody: {
        'name': name,
        'media_type': mediaType,
        'size_bytes': sizeBytes,
        'last_modified_ms': ?lastModifiedMillis,
        'sha256': ?sha256,
      },
    );
    return FileDescriptor.fromJson(_json(response));
  }

  Future<void> upload({
    required String tunnelId,
    required String fileId,
    required String capability,
    required Uint8List bytes,
  }) async {
    await _send(
      'PUT',
      '/v1/tunnels/${_segment(tunnelId)}/files/${_segment(fileId)}/content',
      capability: capability,
      body: bytes,
      contentType: 'application/octet-stream',
    );
  }

  Future<Uint8List> download({
    required String tunnelId,
    required String fileId,
    required String capability,
  }) async {
    final response = await _send(
      'GET',
      '/v1/tunnels/${_segment(tunnelId)}/files/${_segment(fileId)}/content',
      capability: capability,
    );
    return response.bodyBytes;
  }

  Future<Uri> eventSocketUri(String tunnelId, String capability) async {
    final response = await _send(
      'POST',
      '/v1/tunnels/${_segment(tunnelId)}/event-tickets',
      capability: capability,
    );
    final ticket = _json(response)['ticket']! as String;
    return _baseUri.replace(
      scheme: _baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/tunnels/${_segment(tunnelId)}/events',
      queryParameters: {'ticket': ticket},
    );
  }

  Future<WebSocketChannel> connectEvents(
    String tunnelId,
    String capability,
  ) async =>
      WebSocketChannel.connect(await eventSocketUri(tunnelId, capability));

  Future<void> cancel(String tunnelId, String capability) async {
    await _send(
      'DELETE',
      '/v1/tunnels/${_segment(tunnelId)}',
      capability: capability,
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? capability,
    String? idempotencyKey,
    Map<String, Object?>? jsonBody,
    Object? body,
    String? contentType,
  }) async {
    final request = http.Request(method, _baseUri.resolve(path));
    request.followRedirects = false;
    if (capability != null) {
      request.headers['authorization'] = 'Bearer $capability';
    }
    if (idempotencyKey != null) {
      request.headers['idempotency-key'] = idempotencyKey;
    }
    if (jsonBody != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    } else if (body is Uint8List) {
      request.headers['content-type'] =
          contentType ?? 'application/octet-stream';
      request.bodyBytes = body;
    }
    final streamed = await _http.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    var code = 'request_failed';
    try {
      code = (_json(response)['code'] as String?) ?? code;
    } on Object {
      // Never surface arbitrary bodies that may contain sensitive data.
    }
    throw FileTunnelException(response.statusCode, code);
  }

  Map<String, Object?> _json(http.Response response) =>
      (jsonDecode(response.body) as Map).cast<String, Object?>();
}

String? pairingSecretFromUri(Uri uri) =>
    uri.queryParameters.containsKey('c') || uri.fragment.isEmpty
    ? null
    : Uri.splitQueryString(uri.fragment)['c'];

String _segment(String value) {
  if (value.isEmpty || !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'path segment',
      'ftnl: invalid path value',
    );
  }
  return Uri.encodeComponent(value);
}
