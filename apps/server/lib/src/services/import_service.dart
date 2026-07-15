import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/slugify.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:yaml/yaml.dart';

final Logger _log = Logger('import');

/// Aggregated result of one [importSourceRoot] run.
class ImportSummary {
  /// Creates an empty summary; [importSourceRoot] mutates it as it goes.
  ImportSummary();

  /// Number of `recipes/*.yaml` files considered.
  int total = 0;

  /// Files whose recipe was newly inserted.
  int imported = 0;

  /// Files whose recipe existed with different content and was rewritten.
  int updated = 0;

  /// Files whose recipe was already stored with the same content hash.
  int skipped = 0;

  /// Files that could not be decoded or stored.
  int failed = 0;

  /// Human-readable notes, each prefixed with the file it belongs to.
  final List<String> warnings = [];

  @override
  String toString() =>
      '$total file(s): $imported imported, $updated updated, '
      '$skipped skipped, $failed failed, ${warnings.length} warning(s)';
}

/// Imports every recipe under `<sourceRootPath>/recipes/` into [db] and the
/// exported YAML library below `config.libraryDir`.
///
/// The source root must exist and contain a `recipes/` directory (otherwise
/// a [ValidationException] is thrown). Source identity comes from
/// `<sourceRootPath>/source.yaml` when present (`name`, `type`; every other
/// key becomes source meta); otherwise the directory name is used with a
/// warning. The source slug is `slugify(name)`.
///
/// For every `recipes/*.yaml` (sorted by file name) the document is decoded,
/// re-encoded to canonical v2 YAML, content-hashed (SHA-256 of the canonical
/// text), and upserted. Inserted/updated recipes get their canonical YAML
/// written atomically to `<library>/<slug>/recipes/<id>.yaml` and their
/// referenced images (hero, gallery, technique steps) copied from the source
/// root into `<library>/<slug>/images/`. Unchanged recipes count as skipped;
/// undecodable files count as failed and are reported in
/// [ImportSummary.warnings] without aborting the run. [onProgress] is called
/// after every file.
ImportSummary importSourceRoot({
  required String sourceRootPath,
  required SaltDatabase db,
  required ServerConfig config,
  void Function(int done, int total)? onProgress,
}) {
  final root = Directory(sourceRootPath);
  if (!root.existsSync()) {
    throw ValidationException(
      'Source root does not exist: ${root.path}',
    );
  }
  final recipesDir = Directory('${root.path}/recipes');
  if (!recipesDir.existsSync()) {
    throw ValidationException(
      'Source root has no recipes/ directory: ${root.path}',
    );
  }

  final summary = ImportSummary();
  final source = _readSourceIdentity(root, summary);
  db.upsertSource(
    slug: source.slug,
    name: source.name,
    type: source.type,
    meta: source.meta,
  );

  final librarySourceDir = '${config.libraryDir}/${source.slug}';
  final libraryRecipesDir = Directory('$librarySourceDir/recipes')
    ..createSync(recursive: true);
  final libraryImagesDir = Directory('$librarySourceDir/images')
    ..createSync(recursive: true);

  final sourceYaml = File('${root.path}/source.yaml');
  if (sourceYaml.existsSync()) {
    sourceYaml.copySync('$librarySourceDir/source.yaml');
  }

  final files = recipesDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  summary.total = files.length;

  final copiedImages = <String>{};
  var done = 0;
  for (final file in files) {
    final fileName = _basename(file.path);
    try {
      final decoded = RecipeYamlCodec.decode(file.readAsStringSync());
      for (final warning in decoded.warnings) {
        summary.warnings.add('$fileName: $warning');
      }
      final recipe = decoded.recipe;
      final canonical = RecipeYamlCodec.encode(recipe);
      final contentHash = sha256.convert(utf8.encode(canonical)).toString();
      final outcome = db.upsertRecipe(
        recipe,
        sourceSlug: source.slug,
        contentHash: contentHash,
      );
      switch (outcome) {
        case UpsertOutcome.unchanged:
          summary.skipped += 1;
        case UpsertOutcome.inserted:
        case UpsertOutcome.updated:
          if (outcome == UpsertOutcome.inserted) {
            summary.imported += 1;
          } else {
            summary.updated += 1;
          }
          _writeAtomically(
            '${libraryRecipesDir.path}/${recipe.id}.yaml',
            canonical,
          );
          _copyImages(
            recipe: recipe,
            fileName: fileName,
            sourceRoot: root.path,
            libraryImagesDir: libraryImagesDir.path,
            copiedImages: copiedImages,
            summary: summary,
          );
      }
      // A single unreadable or malformed file must not abort a corpus-sized
      // run, so everything file-scoped is caught and reported.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      summary.failed += 1;
      summary.warnings.add('$fileName: $error');
      _log.warning('Failed to import $fileName', error);
    }
    done += 1;
    onProgress?.call(done, summary.total);
  }
  return summary;
}

/// Source identity resolved from `source.yaml` (or the directory name).
class _SourceIdentity {
  _SourceIdentity({
    required this.slug,
    required this.name,
    required this.type,
    required this.meta,
  });

  final String slug;
  final String name;
  final String type;
  final Map<String, Object?> meta;
}

_SourceIdentity _readSourceIdentity(Directory root, ImportSummary summary) {
  final file = File('${root.path}/source.yaml');
  var name = _basename(root.path);
  var type = 'manual';
  final meta = <String, Object?>{};
  if (!file.existsSync()) {
    summary.warnings.add(
      'source.yaml: not found; deriving source name "$name" '
      'from the directory name',
    );
  } else {
    final Object? doc;
    try {
      doc = _toPlain(loadYaml(file.readAsStringSync()));
    } on YamlException catch (error) {
      throw ValidationException('source.yaml is not valid YAML: $error');
    }
    if (doc is! Map<String, Object?>) {
      throw const ValidationException('source.yaml root must be a mapping.');
    }
    final rawName = doc['name']?.toString().trim();
    if (rawName == null || rawName.isEmpty) {
      summary.warnings.add(
        'source.yaml: missing "name"; deriving source name "$name" '
        'from the directory name',
      );
    } else {
      name = rawName;
    }
    final rawType = doc['type']?.toString().trim();
    if (rawType != null && rawType.isNotEmpty) {
      type = rawType;
    }
    for (final entry in doc.entries) {
      if (entry.key != 'name' && entry.key != 'type') {
        meta[entry.key] = entry.value;
      }
    }
  }
  final slug = slugify(name);
  if (slug.isEmpty) {
    throw ValidationException(
      'Source name "$name" produces an empty slug.',
    );
  }
  return _SourceIdentity(slug: slug, name: name, type: type, meta: meta);
}

/// Copies the images referenced by [recipe] (hero, gallery, technique steps)
/// from the source root into the library images directory. Paths already
/// copied this run are skipped; a missing or non-contained source path adds
/// a warning instead of failing the file.
void _copyImages({
  required Recipe recipe,
  required String fileName,
  required String sourceRoot,
  required String libraryImagesDir,
  required Set<String> copiedImages,
  required ImportSummary summary,
}) {
  final references = <String>[
    if (recipe.images.hero != null) recipe.images.hero!,
    ...recipe.images.gallery,
    for (final technique in recipe.techniques)
      for (final step in technique.steps)
        if (step.image != null) step.image!,
  ];
  for (final reference in references) {
    final relative = reference.trim();
    if (relative.isEmpty || !copiedImages.add(relative)) {
      continue;
    }
    // Containment: image paths come from document data and must stay inside
    // the source root — reject absolute paths and any `..` traversal.
    if (relative.startsWith('/') ||
        relative.split('/').contains('..')) {
      summary.warnings.add(
        '$fileName: image path escapes the source root: $relative',
      );
      continue;
    }
    final sourceFile = File('$sourceRoot/$relative');
    if (!sourceFile.existsSync()) {
      summary.warnings.add('$fileName: image not found: $relative');
      continue;
    }
    // Mirror the DB card URL convention: the served name is the path after
    // the `images/` prefix (or the basename when the prefix is absent).
    const prefix = 'images/';
    final servedName = relative.startsWith(prefix)
        ? relative.substring(prefix.length)
        : _basename(relative);
    final destination = File('$libraryImagesDir/$servedName');
    final parent = destination.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    sourceFile.copySync(destination.path);
  }
}

/// Writes [content] to `<path>.tmp` and renames it over [path] so readers
/// never observe a half-written file.
void _writeAtomically(String path, String content) {
  File('$path.tmp')
    ..writeAsStringSync(content, flush: true)
    ..renameSync(path);
}

String _basename(String path) {
  var end = path.length;
  while (end > 1 && (path[end - 1] == '/' || path[end - 1] == r'\')) {
    end -= 1;
  }
  final trimmed = path.substring(0, end);
  final slash = trimmed.lastIndexOf('/');
  final backslash = trimmed.lastIndexOf(r'\');
  final cut = slash > backslash ? slash : backslash;
  return trimmed.substring(cut + 1);
}

/// Deep-converts `YamlMap`/`YamlList` nodes into plain maps/lists so meta
/// values survive `jsonEncode` in the DAL.
Object? _toPlain(Object? node) {
  if (node is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in node.entries)
        entry.key.toString(): _toPlain(entry.value),
    };
  }
  if (node is List) {
    return <Object?>[for (final Object? item in node) _toPlain(item)];
  }
  return node;
}
