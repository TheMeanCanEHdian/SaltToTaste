import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/image_paths.dart';
import 'package:salt_server/src/services/slugify.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:yaml/yaml.dart';

final Logger _log = Logger('import');

/// Maximum size of a single YAML file the importer will read into memory, a
/// guard against a crafted multi-gigabyte document OOM-ing the process.
const int _maxYamlBytes = 8 * 1024 * 1024;

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
/// text), and upserted. The canonical YAML is written atomically to
/// `<library>/<slug>/recipes/<id>.yaml` and referenced images copied into
/// `<library>/<slug>/images/`; a recipe that hashes as unchanged still
/// re-materializes a missing export file or image, so a lost library
/// directory self-heals on re-import. Undecodable files (and files whose
/// recipe id is not a safe filename) count as failed and are reported in
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
    throw ValidationException('Source root does not exist: ${root.path}');
  }
  final recipesDir = Directory('${root.path}/recipes');
  if (!recipesDir.existsSync()) {
    throw ValidationException(
      'Source root has no recipes/ directory: ${root.path}',
    );
  }

  final summary = ImportSummary();
  final sourceYaml = File('${root.path}/source.yaml');
  final source = _readSourceIdentity(root, sourceYaml, summary);
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

  final materializedImages = <String>{};
  var done = 0;
  for (final file in files) {
    final fileName = _basename(file.path);
    try {
      _checkSize(file, fileName);
      final decoded = RecipeYamlCodec.decode(file.readAsStringSync());
      for (final warning in decoded.warnings) {
        summary.warnings.add('$fileName: $warning');
      }
      var recipe = decoded.recipe;
      // The id becomes a filename and a Content-Disposition value; a `..`,
      // slash, quote, or control character would escape the library dir or
      // break the header, so reject the file rather than trust it.
      if (!isSafeRecipeId(recipe.id)) {
        throw ValidationException('unsafe recipe id: "${recipe.id}"');
      }
      // Resolve slug collisions BEFORE encoding, so the exported YAML, the
      // content hash, and the stored document all carry the same slug.
      recipe = recipe.copyWith(
        slug: db.availableSlug(recipe.slug, ownerId: recipe.id),
      );
      final canonical = RecipeYamlCodec.encode(recipe);
      final contentHash = sha256.convert(utf8.encode(canonical)).toString();
      final exportPath = '${libraryRecipesDir.path}/${recipe.id}.yaml';

      final outcome = db.upsertRecipe(
        recipe,
        sourceSlug: source.slug,
        contentHash: contentHash,
      );
      // Re-materialize a missing export even when the DB row is unchanged, so
      // losing the library directory heals on the next run.
      if (outcome != UpsertOutcome.unchanged ||
          !File(exportPath).existsSync()) {
        _writeAtomically(exportPath, canonical);
      }
      _copyImages(
        recipe: recipe,
        fileName: fileName,
        sourceRoot: root.path,
        libraryImagesDir: libraryImagesDir.path,
        materializedImages: materializedImages,
        summary: summary,
      );

      // Count only after the filesystem side effects succeed, so a write
      // failure is reported once (as failed) rather than double-counted.
      switch (outcome) {
        case UpsertOutcome.unchanged:
          summary.skipped += 1;
        case UpsertOutcome.inserted:
          summary.imported += 1;
        case UpsertOutcome.updated:
          summary.updated += 1;
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

/// Throws a [ValidationException] when [file] is larger than [_maxYamlBytes].
void _checkSize(File file, String label) {
  final bytes = file.lengthSync();
  if (bytes > _maxYamlBytes) {
    throw ValidationException(
      '$label is too large ($bytes bytes > $_maxYamlBytes).',
    );
  }
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

_SourceIdentity _readSourceIdentity(
  Directory root,
  File sourceYaml,
  ImportSummary summary,
) {
  var name = _basename(root.path);
  var type = 'manual';
  final meta = <String, Object?>{};
  if (!sourceYaml.existsSync()) {
    summary.warnings.add(
      'source.yaml: not found; deriving source name "$name" '
      'from the directory name',
    );
  } else {
    _checkSize(sourceYaml, 'source.yaml');
    final Object? doc;
    try {
      doc = yamlToPlain(loadYaml(sourceYaml.readAsStringSync()));
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
    throw ValidationException('Source name "$name" produces an empty slug.');
  }
  return _SourceIdentity(slug: slug, name: name, type: type, meta: meta);
}

/// Copies the images referenced by [recipe] (hero, gallery, technique steps)
/// from the source root into the library images directory under a flat,
/// route-safe name ([safeImageName]).
///
/// Already-materialized names (existing on disk, or copied earlier this run)
/// are skipped, so a missing image self-heals on re-import while present ones
/// cost only a stat. The source path is resolved (symlinks followed) and must
/// stay inside the source root, so a symlinked source image cannot smuggle a
/// host file into the publicly served library.
void _copyImages({
  required Recipe recipe,
  required String fileName,
  required String sourceRoot,
  required String libraryImagesDir,
  required Set<String> materializedImages,
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
    if (relative.isEmpty) {
      continue;
    }
    final servedName = safeImageName(relative);
    if (servedName.isEmpty || !materializedImages.add(servedName)) {
      continue;
    }
    final destination = File('$libraryImagesDir/$servedName');
    if (destination.existsSync()) {
      continue;
    }
    if (relative.startsWith('/') ||
        relative.split(RegExp(r'[/\\]')).contains('..')) {
      summary.warnings.add(
        '$fileName: image path escapes the source root: $relative',
      );
      continue;
    }
    final String canonicalRoot;
    final String canonicalSource;
    try {
      canonicalRoot = Directory(sourceRoot).resolveSymbolicLinksSync();
      canonicalSource =
          File('$sourceRoot/$relative').resolveSymbolicLinksSync();
    } on FileSystemException {
      summary.warnings.add('$fileName: image not found: $relative');
      continue;
    }
    final rootPrefix = '$canonicalRoot${Platform.pathSeparator}';
    if (canonicalSource != canonicalRoot &&
        !canonicalSource.startsWith(rootPrefix)) {
      summary.warnings.add(
        '$fileName: image resolves outside the source root: $relative',
      );
      continue;
    }
    File(canonicalSource).copySync(destination.path);
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
