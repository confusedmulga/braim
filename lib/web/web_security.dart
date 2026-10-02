// Braim Web request hardening: who may connect, which Host names are accepted,
// the CSRF header on mutations, the security headers on every response, and
// the request-size cap. See docs/braim-web-plan.md, section 5.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

/// The Content-Security-Policy sent on every response. No inline scripts and no
/// `on*` attributes are allowed anywhere; `https:` images are allowed because
/// Spark covers are remote.
const String kWebCsp =
    "default-src 'self'; script-src 'self'; "
    "style-src 'self' 'unsafe-inline'; img-src 'self' https: data:; "
    "font-src 'self'; connect-src 'self'; object-src 'none'; "
    "frame-ancestors 'none'; base-uri 'none'; form-action 'self'";

/// Largest request body the server reads.
const int kWebMaxBodyBytes = 2 * 1024 * 1024;

/// Largest image a browser may upload into a note.
const int kWebMaxImageBytes = 10 * 1024 * 1024;

final _imageUpload = RegExp(r'^api/notes/[^/]+/images$');

/// The most [request] may send: [kWebMaxImageBytes] for an image upload,
/// [kWebMaxBodyBytes] for anything else.
int bodyLimitFor(Request request) =>
    request.method == 'POST' && _imageUpload.hasMatch(request.url.path)
    ? kWebMaxImageBytes
    : kWebMaxBodyBytes;

/// The context key shelf_io stores the socket's [HttpConnectionInfo] under.
const String kConnectionInfoKey = 'shelf.io.connection_info';

/// The header every mutating request must carry, holding the page's token.
const String kCsrfHeader = 'x-braim-csrf';

/// The remote address of [request], or null when shelf_io didn't supply one.
InternetAddress? remoteAddressOf(Request request) {
  final info = request.context[kConnectionInfoKey];
  return info is HttpConnectionInfo ? info.remoteAddress : null;
}

/// Whether [a] is a loopback IPv4 address (127.0.0.0/8).
bool isLoopbackIPv4(InternetAddress a) =>
    a.type == InternetAddressType.IPv4 && a.rawAddress[0] == 127;

/// Whether [a] is a private or loopback IPv4 address: 10.0.0.0/8,
/// 172.16.0.0/12, 192.168.0.0/16 or 127.0.0.0/8. Everything else, IPv6
/// included, is refused; that keeps out the mobile-data interface.
bool isPrivateIPv4(InternetAddress a) {
  if (a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

/// Compares two strings in time that depends only on [given]'s length, so a
/// guess can't be refined by timing how early the comparison failed.
bool constantTimeEquals(String given, String expected) {
  final a = utf8.encode(given);
  final b = utf8.encode(expected);
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return diff == 0;
}

/// The CSRF token pages embed for a session. Derived from the session token
/// itself, so nothing extra is stored and the token can't be turned back into
/// the cookie.
String csrfTokenFor(String sessionToken) {
  final mac = Hmac(
    sha256,
    utf8.encode(sessionToken),
  ).convert(utf8.encode('braim-csrf'));
  return base64Url.encode(mac.bytes).replaceAll('=', '');
}

/// Whether [method] changes something and so needs the CSRF header.
bool isMutatingMethod(String method) =>
    method == 'POST' ||
    method == 'PUT' ||
    method == 'DELETE' ||
    method == 'PATCH';

/// Answers 403 unless the connection comes from a private or loopback IPv4
/// address.
Middleware addressCheck() =>
    (inner) => (request) {
      final remote = remoteAddressOf(request);
      if (remote == null || !isPrivateIPv4(remote)) {
        return Response.forbidden('Forbidden');
      }
      return inner(request);
    };

/// The DNS-rebinding defence: answers 421 unless the Host header names one of
/// the phone's own addresses with the server's port. `localhost` and
/// `127.0.0.1` are accepted only from a loopback connection, which is how
/// `adb forward` reaches the emulator.
Middleware hostCheck({
  required Iterable<String> Function() addresses,
  required int? Function() port,
}) =>
    (inner) => (request) {
      final p = port();
      final host = request.headers['host']?.trim().toLowerCase();
      if (p == null ||
          host == null ||
          !_hostAllowed(request, host, p, addresses())) {
        return Response(421, body: 'Misdirected Request');
      }
      return inner(request);
    };

bool _hostAllowed(
  Request request,
  String host,
  int port,
  Iterable<String> addresses,
) {
  for (final ip in addresses) {
    if (host == '$ip:$port') return true;
  }
  if (host == 'localhost:$port' || host == '127.0.0.1:$port') {
    final remote = remoteAddressOf(request);
    return remote != null && isLoopbackIPv4(remote);
  }
  return false;
}

/// Answers 413 when a request declares a body over its limit
/// ([bodyLimitFor]). Bodies sent without a length are capped by
/// [readBodyLimited] and [readBytesLimited].
Middleware bodyLimit() =>
    (inner) => (request) {
      final length = request.contentLength;
      if (length != null && length > bodyLimitFor(request)) {
        return Response(413, body: 'Payload Too Large');
      }
      return inner(request);
    };

/// Thrown by [readBodyLimited] when a body runs past [kWebMaxBodyBytes].
class BodyTooLarge implements Exception {
  const BodyTooLarge();
}

/// Reads [request]'s body as UTF-8, throwing [BodyTooLarge] past the cap.
Future<String> readBodyLimited(Request request) async {
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > kWebMaxBodyBytes) throw const BodyTooLarge();
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Reads [request]'s body as bytes, throwing [BodyTooLarge] past [max].
Future<Uint8List> readBytesLimited(Request request, int max) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    out.add(chunk);
    if (out.length > max) throw const BodyTooLarge();
  }
  return out.takeBytes();
}

/// Adds the security headers to every response: the CSP, `nosniff`, no
/// referrer, and `no-store` unless the handler chose its own caching (static
/// assets and images do).
Middleware securityHeaders() =>
    (inner) => (request) async {
      final response = await inner(request);
      return response.change(
        headers: {
          'content-security-policy': kWebCsp,
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
          if (!response.headers.containsKey('cache-control'))
            'cache-control': 'no-store',
        },
      );
    };

const _compressibleTypes = {
  'text/html',
  'text/css',
  'text/javascript',
  'application/javascript',
  'application/json',
  'font/ttf',
};

/// Lets `dart:io` compress text, JSON and fonts. The server's `autoCompress`
/// only applies to bodies sent without a length, so this drops the length
/// from compressible responses; `dart:io` then sends them chunked, and gzipped
/// when the browser accepts it. Event streams are never touched.
Middleware compressible() =>
    (inner) => (request) async {
      final response = await inner(request);
      final length = response.contentLength;
      if (length == null ||
          length < 512 ||
          !_compressibleTypes.contains(response.mimeType)) {
        return response;
      }
      return response.change(
        headers: {'content-length': null, 'vary': 'Accept-Encoding'},
        body: response.read(),
      );
    };
