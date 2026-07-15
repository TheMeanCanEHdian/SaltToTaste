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

/// An image resolved inside the library dir, ready to serve.
class ResolvedImage {
  /// Bundles the file [bytes] with their [contentType].
  const ResolvedImage({required this.bytes, required this.contentType});

  /// Raw file contents.
  final Uint8List bytes;

  /// MIME type derived from the file extension (e.g. `image/jpeg`).
  final String contentType;
}

/// Resolves and reads `<libraryDir>/<source>/images/<file>`.
///
/// SECURITY-CRITICAL path containment:
///
/// * Both [source] and [file] must match [_segmentPattern] and must not
///   contain `..`, `/`, or `\` — otherwise [ValidationException].
/// * The file extension must be a known image type — otherwise
///   [NotFoundException] (no probing of arbitrary files).
/// * The path is canonicalized (symlinks resolved) and must remain inside
///   the canonicalized [libraryDir]; escapes and missing files are both
///   [NotFoundException].
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
    canonicalPath =
        File('$libraryDir/$source/images/$file').resolveSymbolicLinksSync();
  } on FileSystemException {
    // Missing file, missing directory, or dangling symlink.
    throw NotFoundException('image not found: $source/$file');
  }
  if (!canonicalPath
      .startsWith('$canonicalLibraryDir${Platform.pathSeparator}')) {
    // A symlink (or other trickery) escaped the library dir.
    throw NotFoundException('image not found: $source/$file');
  }

  return ResolvedImage(
    bytes: File(canonicalPath).readAsBytesSync(),
    contentType: contentType,
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
