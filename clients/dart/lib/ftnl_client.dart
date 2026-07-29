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
    required this.tunnelId,
    required this.pairingUri,
    required this.desktopCapability,
    required this.expiresAt,
  });
  final String tunnelId;
  final Uri pairingUri;
  final String desktopCapability;
  final DateTime expiresAt;

  factory Tunnel.fromJson(Map<String, Object?> json) => Tunnel(
    tunnelId: json['tunnel_id']! as String,
    pairingUri: Uri.parse(json['pairing_uri']! as String),
    desktopCapability: json['desktop_capability']! as String,
    expiresAt: DateTime.parse(json['expires_at']! as String),
  );
}

final class FileDescriptor {
  const FileDescriptor({
    required this.fileId,
    required this.name,
    required this.mediaType,
    required this.sizeBytes,
    required this.bytesTransferred,
    required this.status,
  });
  final String fileId;
  final String name;
  final String mediaType;
  final int sizeBytes;
  final int bytesTransferred;
  final String status;

  factory FileDescriptor.fromJson(Map<String, Object?> json) => FileDescriptor(
    fileId: json['file_id']! as String,
    name: json['name']! as String,
    mediaType: json['media_type']! as String,
    sizeBytes: json['size_bytes']! as int,
    bytesTransferred: json['bytes_transferred']! as int,
    status: json['status']! as String,
  );
}

final class FileTunnelClient {
  FileTunnelClient(Uri baseUri, {http.Client? httpClient})
    : _baseUri = baseUri,
      _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _http;

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

  Future<String> claimTunnel(String tunnelId, String pairingSecret) async {
    final response = await _send(
      'POST',
      '/v1/tunnels/$tunnelId/claim',
      jsonBody: {'pairing_secret': pairingSecret},
    );
    return _json(response)['phone_capability']! as String;
  }

  Future<FileDescriptor> declareFile({
    required String tunnelId,
    required String capability,
    required String name,
    required String mediaType,
    required int sizeBytes,
  }) async {
    final response = await _send(
      'POST',
      '/v1/tunnels/$tunnelId/files',
      capability: capability,
      jsonBody: {
        'name': name,
        'media_type': mediaType,
        'size_bytes': sizeBytes,
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
      '/v1/tunnels/$tunnelId/files/$fileId/content',
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
      '/v1/tunnels/$tunnelId/files/$fileId/content',
      capability: capability,
    );
    return response.bodyBytes;
  }

  Future<Uri> eventSocketUri(String tunnelId, String capability) async {
    final response = await _send(
      'POST',
      '/v1/tunnels/$tunnelId/event-tickets',
      capability: capability,
    );
    final ticket = _json(response)['ticket']! as String;
    return _baseUri.replace(
      scheme: _baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/tunnels/$tunnelId/events',
      queryParameters: {'ticket': ticket},
    );
  }

  Future<WebSocketChannel> connectEvents(
    String tunnelId,
    String capability,
  ) async =>
      WebSocketChannel.connect(await eventSocketUri(tunnelId, capability));

  Future<void> cancel(String tunnelId, String capability) async {
    await _send('DELETE', '/v1/tunnels/$tunnelId', capability: capability);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? capability,
    Map<String, Object?>? jsonBody,
    Object? body,
    String? contentType,
  }) async {
    final request = http.Request(method, _baseUri.resolve(path));
    if (capability != null) {
      request.headers['authorization'] = 'Bearer $capability';
    }
    if (jsonBody != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    } else if (body is Uint8List) {
      request.headers['content-type'] =
          contentType ?? 'application/octet-stream';
      request.bodyBytes = body;
    }
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    var code = 'request_failed';
    try {
      code = (_json(response)['code'] as String?) ?? code;
    } on FormatException {
      // Never surface arbitrary bodies that may contain sensitive data.
    }
    throw FileTunnelException(response.statusCode, code);
  }

  Map<String, Object?> _json(http.Response response) =>
      (jsonDecode(response.body) as Map).cast<String, Object?>();
}

String? pairingSecretFromUri(Uri uri) =>
    uri.fragment.isEmpty ? null : Uri.splitQueryString(uri.fragment)['c'];
