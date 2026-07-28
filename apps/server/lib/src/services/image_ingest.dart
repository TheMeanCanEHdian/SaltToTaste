import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/exceptions.dart';

final Logger _log = Logger('images');

/// Largest accepted image, matching the serving route's cap.
const int maxImageBytes = 25 * 1024 * 1024;

/// Wall-clock budget for a from-URL fetch.
const Duration _fetchTimeout = Duration(seconds: 20);

/// Redirect hops a from-URL fetch will follow (each re-validated).
const int _maxRedirects = 3;

/// What the magic bytes say the image is.
typedef SniffedImage = ({String extension, String mimeType});

/// Identifies JPEG/PNG/WebP from [bytes] by signature, or null.
///
/// Uploads and URL fetches are accepted by content, never by the name or
/// header the client supplied.
SniffedImage? sniffImage(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return (extension: 'jpg', mimeType: 'image/jpeg');
  }
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length >= png.length) {
    var isPng = true;
    for (var i = 0; i < png.length; i += 1) {
      if (bytes[i] != png[i]) {
        isPng = false;
        break;
      }
    }
    if (isPng) {
      return (extension: 'png', mimeType: 'image/png');
    }
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50) {
    return (extension: 'webp', mimeType: 'image/webp');
  }
  return null;
}

/// Collects a request/response byte stream, rejecting anything over
/// [maxImageBytes] *while reading* so an oversized body cannot balloon
/// memory first.
Future<Uint8List> collectImageBytes(Stream<List<int>> source) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in source) {
    builder.add(chunk);
    if (builder.length > maxImageBytes) {
      throw const ValidationException(
        'Image is too large (25 MB maximum).',
      );
    }
  }
  return builder.takeBytes();
}

/// Validates [bytes] as a real image and writes it into the library's
/// images directory under a server-generated name.
///
/// Returns the document-relative reference (`images/<file>`) to store in
/// the recipe. The name is `<recipeId>-<utc stamp>.<sniffed ext>` — the id
/// is already filename-safe and the caller never controls the name.
String saveRecipeImage({
  required ServerConfig config,
  required String sourceSlug,
  required String recipeId,
  required Uint8List bytes,
}) {
  if (bytes.isEmpty) {
    throw const ValidationException('Image body is empty.');
  }
  final sniffed = sniffImage(bytes);
  if (sniffed == null) {
    throw const ValidationException(
      'Not a supported image (JPEG, PNG, or WebP).',
    );
  }
  // yyyymmdd-hhmmss
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp('[-:.]'), '')
      .replaceAll('T', '-')
      .substring(0, 15);
  final dir = Directory('${config.libraryDir}/$sourceSlug/images')
    ..createSync(recursive: true);
  var name = '$recipeId-$stamp.${sniffed.extension}';
  var suffix = 2;
  while (File('${dir.path}/$name').existsSync()) {
    name = '$recipeId-$stamp-$suffix.${sniffed.extension}';
    suffix += 1;
  }
  File('${dir.path}/$name.tmp')
    ..writeAsBytesSync(bytes, flush: true)
    ..renameSync('${dir.path}/$name');
  _log.info('Stored image $name (${bytes.length} bytes)');
  return 'images/$name';
}

/// Test-only substitute for the HTTP transport [fetchImageFromUrl] uses.
///
/// Null in production, where the client is exactly `HttpClient()`. It swaps
/// the transport ONLY, and it sits *below* every SSRF guard: the URL is
/// scheme/host/credential-validated and each hop's resolved addresses are
/// checked before this client is asked for anything, the connected peer is
/// re-checked after, and status/content-type/size/magic-byte validation is
/// unchanged. A substituted client therefore cannot reach a host — or smuggle
/// a body past a check — that the real one could not. Never set outside
/// tests.
@visibleForTesting
HttpClient Function()? debugImageHttpClientFactory;

/// Downloads an image from [rawUrl] with SSRF guards and returns its bytes.
///
/// Guards (per the plan's security section): http/https only; every DNS
/// answer for the host must be a public unicast address; redirects are
/// followed manually (max [_maxRedirects]) re-validating each hop; the
/// response must both claim an image content-type and pass magic-byte
/// sniffing; size and time are capped.
Future<Uint8List> fetchImageFromUrl(String rawUrl) async {
  final url = _validatedImageUrl(rawUrl);
  final client = (debugImageHttpClientFactory?.call() ?? HttpClient())
    ..userAgent = 'SaltToTaste'
    ..connectionTimeout = const Duration(seconds: 10)
    ..maxConnectionsPerHost = 2;
  try {
    return await _fetch(client, url).timeout(
      _fetchTimeout,
      onTimeout: () => throw const ValidationException(
        'Fetching the image took too long.',
      ),
    );
    // Transport-level failures are ordinary bad user input (a pasted URL
    // whose site has an expired certificate, refuses the connection, or
    // resets it) — a 422 naming the cause, like every other fetch failure
    // here, never a 500 with a SEVERE stack (review B16).
  } on HandshakeException {
    throw const ValidationException(
      'Could not fetch the image: the site’s TLS certificate failed '
      'verification (expired or self-signed?).',
    );
  } on SocketException catch (error) {
    throw ValidationException(
      'Could not fetch the image: connection failed '
      '(${error.osError?.message ?? error.message}).',
    );
  } on HttpException catch (error) {
    throw ValidationException(
      'Could not fetch the image: ${error.message}',
    );
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _fetch(HttpClient client, Uri initialUrl) async {
  var url = initialUrl;
  for (var hop = 0; hop <= _maxRedirects; hop += 1) {
    await _requirePublicHost(url.host);
    final request = await client.getUrl(url)
      ..followRedirects = false;
    final response = await request.close();
    // The connection re-resolved DNS after the check above (a rebinding
    // window); verify where the socket actually landed before consuming
    // anything. A GET has already been sent by now — the residual exposure
    // is one side-effect-free request, never a readable internal response.
    final connected = response.connectionInfo?.remoteAddress;
    if (connected != null && !_isPublicUnicast(connected)) {
      await response.drain<void>();
      throw const ValidationException(
        'Image URLs must point at a public host.',
      );
    }

    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) {
        throw const ValidationException('Image URL redirect has no target.');
      }
      // Each hop is re-validated from scratch (scheme + resolved addresses),
      // so a redirect cannot smuggle the fetch onto an internal host.
      url = _validatedImageUrl(url.resolve(location).toString());
      continue;
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw ValidationException(
        'Image URL returned HTTP ${response.statusCode}.',
      );
    }
    final contentType = response.headers.contentType?.mimeType ?? '';
    if (!contentType.startsWith('image/')) {
      await response.drain<void>();
      throw ValidationException(
        "Image URL returned '$contentType', not an image.",
      );
    }
    if (response.contentLength > maxImageBytes) {
      await response.drain<void>();
      throw const ValidationException('Image is too large (25 MB maximum).');
    }
    return collectImageBytes(response);
  }
  throw const ValidationException('Image URL redirected too many times.');
}

/// Parses and shape-checks a user-supplied image URL (scheme, host).
Uri _validatedImageUrl(String rawUrl) {
  final url = Uri.tryParse(rawUrl.trim());
  if (url == null ||
      (url.scheme != 'http' && url.scheme != 'https') ||
      url.host.isEmpty) {
    throw const ValidationException(
      "'url' must be an http(s) URL with a host.",
    );
  }
  if (url.userInfo.isNotEmpty) {
    throw const ValidationException(
      'Image URLs with embedded credentials are not allowed.',
    );
  }
  return url;
}

/// Resolves [host] and rejects it unless every answer is a public unicast
/// address — loopback, RFC1918/ULA, link-local, multicast, and unspecified
/// ranges would let a URL reach the server's own network.
Future<void> _requirePublicHost(String host) async {
  List<InternetAddress> addresses;
  final literal = InternetAddress.tryParse(host);
  if (literal != null) {
    addresses = [literal];
  } else {
    try {
      addresses = await InternetAddress.lookup(host);
    } on SocketException {
      throw ValidationException("Could not resolve host '$host'.");
    }
  }
  if (addresses.isEmpty) {
    throw ValidationException("Could not resolve host '$host'.");
  }
  for (final address in addresses) {
    if (!_isPublicUnicast(address)) {
      throw const ValidationException(
        'Image URLs must point at a public host.',
      );
    }
  }
}

bool _isPublicUnicast(InternetAddress address) {
  if (address.isLoopback ||
      address.isLinkLocal ||
      address.isMulticast ||
      address.address == '0.0.0.0' ||
      address.address == '::') {
    return false;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final a = bytes[0];
    final b = bytes[1];
    if (a == 10 || a == 127) {
      return false; // 10/8, 127/8
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return false; // 172.16/12
    }
    if (a == 192 && b == 168) {
      return false; // 192.168/16
    }
    if (a == 169 && b == 254) {
      return false; // 169.254/16
    }
    if (a == 100 && b >= 64 && b <= 127) {
      return false; // 100.64/10 (CGNAT)
    }
    if (a == 192 && b == 0 && bytes[2] == 0) {
      return false; // 192.0.0/24 (IETF protocol assignments)
    }
    return true;
  }
  // IPv6: unique-local fc00::/7; IPv4-mapped handled via its v4 form.
  if ((bytes[0] & 0xFE) == 0xFC) {
    return false;
  }
  if (bytes[0] == 0 && bytes[1] == 0) {
    // Possibly ::ffff:a.b.c.d (IPv4-mapped) — validate the embedded v4.
    var mapped = true;
    for (var i = 0; i < 10; i += 1) {
      if (bytes[i] != 0) {
        mapped = false;
        break;
      }
    }
    if (mapped && bytes[10] == 0xFF && bytes[11] == 0xFF) {
      final v4 = InternetAddress(
        '${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}',
      );
      return _isPublicUnicast(v4);
    }
  }
  return true;
}
