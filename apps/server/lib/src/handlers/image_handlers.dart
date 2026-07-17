import 'dart:io';
import 'dart:typed_data';

import 'package:salt_server/src/exceptions.dart';

/// Allowed shape of a single URL path segment (source slug or file name):
/// starts with an alphanumeric, then alphanumerics, dot, underscore, space,
/// or hyphen. Notably excludes `/`, `\`, `%`, and a leading dot.
final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._ -]*$');

/// Servable image types by (lowercased) file extension. Anything else 404s.
const Map<String, String> _contentTypeByExtension = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

/// Largest image the server will read into memory and serve. Recipe images
/// are photos of a few hundred KB; a much larger file signals corruption or
/// abuse, so it is treated as not servable rather than buffered whole.
const int _maxImageBytes = 25 * 1024 * 1024;

/// An image resolved inside the library dir, ready to serve.
class ResolvedImage {
  /// Bundles the on-disk [file] with its [contentType] and [lastModified]
  /// timestamp (truncated to whole seconds for HTTP date comparison).
  const ResolvedImage({
    required this.file,
    required this.contentType,
    required this.lastModified,
  });

  /// The canonical file inside the library dir.
  final File file;

  /// MIME type derived from the file extension (e.g. `image/jpeg`).
  final String contentType;

  /// Last-modified time, whole seconds, for `Last-Modified`/`If-Modified-Since`.
  final DateTime lastModified;

  /// Reads and returns the file bytes.
  Uint8List readBytes() => file.readAsBytesSync();
}

/// Resolves `<libraryDir>/<source>/images/<file>` to servable metadata
/// (without reading the bytes).
///
/// SECURITY-CRITICAL path containment:
///
/// * Both [source] and [file] must match [_segmentPattern] and must not
///   contain `..`, `/`, or `\` — otherwise [ValidationException].
/// * The file extension must be a known image type — otherwise
///   [NotFoundException] (no probing of arbitrary files).
/// * The path is canonicalized (symlinks resolved) and must remain inside
///   the canonicalized [libraryDir]; escapes, missing files, and files
///   larger than [_maxImageBytes] are all [NotFoundException].
ResolvedImage resolveLibraryImage({
  required String libraryDir,
  required String source,
  required String file,
}) {
  _validateSegment(source, 'source');
  _validateSegment(file, 'file');

  final contentType = _contentTypeByExtension[_extensionOf(file)];
  if (contentType == null) {
    throw NotFoundException('image not found: $source/$file');
  }

  final String canonicalLibraryDir;
  final String canonicalPath;
  try {
    canonicalLibraryDir = Directory(libraryDir).resolveSymbolicLinksSync();
    canonicalPath = File(
      '$libraryDir/$source/images/$file',
    ).resolveSymbolicLinksSync();
  } on FileSystemException {
    // Missing file, missing directory, or dangling symlink.
    throw NotFoundException('image not found: $source/$file');
  }
  if (!canonicalPath.startsWith(
    '$canonicalLibraryDir${Platform.pathSeparator}',
  )) {
    // A symlink (or other trickery) escaped the library dir.
    throw NotFoundException('image not found: $source/$file');
  }

  final resolved = File(canonicalPath);
  final stat = resolved.statSync();
  if (stat.size > _maxImageBytes) {
    throw NotFoundException('image not found: $source/$file');
  }
  // Whole-second resolution: HTTP dates have no sub-second precision.
  final lastModified = DateTime.fromMillisecondsSinceEpoch(
    (stat.modified.millisecondsSinceEpoch ~/ 1000) * 1000,
  );
  return ResolvedImage(
    file: resolved,
    contentType: contentType,
    lastModified: lastModified,
  );
}

void _validateSegment(String value, String name) {
  if (value.contains('..') ||
      value.contains('/') ||
      value.contains(r'\') ||
      !_segmentPattern.hasMatch(value)) {
    throw ValidationException('invalid $name path segment.');
  }
}

String _extensionOf(String file) {
  final dot = file.lastIndexOf('.');
  return dot < 0 ? '' : file.substring(dot).toLowerCase();
}
