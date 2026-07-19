import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/slugify.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:yaml/yaml.dart' show YamlException, loadYaml;

final Logger _log = Logger('import');

/// Library/source identity for recipes imported from the legacy Python app.
const String legacySourceSlug = 'legacy-import';
const String _legacySourceName = 'Legacy SaltToTaste';

/// Whether [rootPath] looks like a legacy SaltToTaste v0 data directory
/// (`_recipes/` with YAML files, as the old Flask app laid it out) rather
/// than a v1/v2 extraction root (`recipes/`).
bool looksLikeLegacyRoot(String rootPath) =>
    Directory('$rootPath/_recipes').existsSync() &&
    !Directory('$rootPath/recipes').existsSync();

/// Imports every `_recipes/*.yaml` of a legacy v0 root into [db] and the
/// canonical YAML library, mapping the old flat format to schema v2:
///
/// * `description` → `background`; `prep`/`cook`/`ready` → `times`
/// * flat ingredient strings → one unnamed group, each line run through
///   [parseIngredientLine] to recover structured amounts
/// * `image`/`imagecredit` → `images.hero`/`images.credit` (file copied
///   from `_images/`)
/// * `source` (a URL in v0) → `source.url`; `calories` is dropped with a
///   warning — nutrition is recomputed from FDC data in this app
///
/// Recipe ids are `v0-<slug>`. Re-running is idempotent (same content
/// hashes as a regular import).
ImportSummary importLegacyRoot({
  required String sourceRootPath,
  required SaltDatabase db,
  required ServerConfig config,
  void Function(int done, int total)? onProgress,
}) {
  final root = Directory(sourceRootPath);
  final recipesDir = Directory('${root.path}/_recipes');
  if (!recipesDir.existsSync()) {
    throw ValidationException(
      'Legacy root has no _recipes/ directory: ${root.path}',
    );
  }
  final summary = ImportSummary();
  db.upsertSource(
    slug: legacySourceSlug,
    name: _legacySourceName,
    type: 'legacy-v0',
  );
  final imagesDirs = [
    Directory('${root.path}/_images'),
    Directory('${root.path}/images'),
  ];
  final libraryImagesDir = Directory(
    '${config.libraryDir}/$legacySourceSlug/images',
  )..createSync(recursive: true);

  final files =
      recipesDir
          .listSync()
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('.yaml') || file.path.endsWith('.yml'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  summary.total = files.length;

  var done = 0;
  for (final file in files) {
    final fileName = file.uri.pathSegments.last;
    try {
      var recipe = _convert(file, fileName, summary);
      // Resolve slug collisions BEFORE encoding, so the exported YAML, the
      // content hash, and the stored document all carry the same slug
      // (upsertRecipe would otherwise suffix only the stored copy).
      recipe = recipe.copyWith(
        slug: db.availableSlug(recipe.slug, ownerId: recipe.id),
      );
      final canonical = RecipeYamlCodec.encode(recipe);
      final outcome = db.upsertRecipe(
        recipe,
        sourceSlug: legacySourceSlug,
        contentHash: contentHashOfText(canonical),
      );
      final exportPath = exportPathFor(config, legacySourceSlug, recipe.id);
      if (outcome != UpsertOutcome.unchanged ||
          !File(exportPath).existsSync()) {
        File(exportPath).parent.createSync(recursive: true);
        writeAtomically(exportPath, canonical);
      }
      _copyLegacyImage(
        recipe: recipe,
        fileName: fileName,
        imagesDirs: imagesDirs,
        libraryImagesDir: libraryImagesDir,
        summary: summary,
      );
      switch (outcome) {
        case UpsertOutcome.unchanged:
          summary.skipped += 1;
        case UpsertOutcome.inserted:
          summary.imported += 1;
        case UpsertOutcome.updated:
          summary.updated += 1;
      }
      // One broken file must not abort the run; everything file-scoped is
      // caught and reported, mirroring the v1/v2 importer.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      summary.failed += 1;
      summary.warnings.add('$fileName: $error');
      _log.warning('Failed to import legacy $fileName', error);
    }
    done += 1;
    onProgress?.call(done, summary.total);
  }
  return summary;
}

Recipe _convert(File file, String fileName, ImportSummary summary) {
  final Object? doc;
  try {
    doc = yamlToPlain(loadYaml(file.readAsStringSync()));
  } on YamlException catch (error) {
    throw ValidationException('not valid YAML: ${'$error'.split('\n').first}');
  }
  if (doc is! Map<String, Object?>) {
    throw const ValidationException('root must be a mapping');
  }
  final title = doc['title']?.toString().trim();
  if (title == null || title.isEmpty) {
    throw const ValidationException('missing title');
  }
  final slug = slugify(title);
  if (slug.isEmpty) {
    throw const ValidationException('title produces an empty slug');
  }
  // The id derives from the FILE name, not the title: file names are unique
  // on disk by construction, so two legacy recipes whose titles slugify
  // identically cannot collapse onto one id (and a re-run maps every file
  // back to the same id, keeping the import idempotent).
  final baseName = fileName.replaceFirst(RegExp(r'\.ya?ml$'), '');
  final id = 'v0-${slugify(baseName)}';
  if (!isSafeRecipeId(id)) {
    throw ValidationException('unsafe recipe id: "$id"');
  }

  final warnings = <String>[];
  if (doc['calories'] != null) {
    warnings.add(
      'legacy calories value (${doc['calories']}) dropped; nutrition is '
      'recomputed from FDC data',
    );
    summary.warnings.add(
      '$fileName: legacy calories dropped (recomputed in-app later)',
    );
  }

  final ingredients = _ingredients(doc['ingredients'], fileName, summary);
  final steps = _steps(doc['directions']);
  final servings = _servingsText(doc['servings']);
  final url = doc['source']?.toString().trim();
  final image = doc['image']?.toString().trim();

  return Recipe(
    id: id,
    title: title,
    slug: slug,
    source: RecipeSource(
      name: _legacySourceName,
      type: 'legacy-v0',
      url: (url != null && url.isNotEmpty) ? url : null,
    ),
    servings: servings,
    serves: parseServings(servings),
    times: RecipeTimes(
      prep: _minutes(doc['prep']),
      cook: _minutes(doc['cook']),
      total: _minutes(doc['ready']),
    ),
    tags: [
      if (doc['tags'] is List)
        for (final tag in doc['tags']! as List)
          if (tag.toString().trim().isNotEmpty)
            tag.toString().trim().toLowerCase(),
    ],
    background: _text(doc['description']),
    ingredients: ingredients,
    steps: steps,
    images: RecipeImages(
      hero: (image != null && image.isNotEmpty) ? 'images/$image' : null,
      credit: _text(doc['imagecredit']),
    ),
    notes: _notes(doc['notes']),
    extraction: Extraction(
      extractor: 'salt-server-legacy-v0',
      extractorVersion: '1.0.0',
      // The source file's mtime, not "today": the conversion must be
      // deterministic so an unchanged source re-imports as `unchanged`
      // (a wall-clock date made every re-run on a later day an "update"
      // that clobbered in-app edits).
      extractedAt: file
          .lastModifiedSync()
          .toUtc()
          .toIso8601String()
          .split('T')
          .first,
      warnings: warnings,
    ),
  );
}

List<IngredientGroup> _ingredients(
  Object? raw,
  String fileName,
  ImportSummary summary,
) {
  if (raw is! List || raw.isEmpty) {
    return const [];
  }
  final items = <IngredientLine>[];
  var needsReview = 0;
  for (final entry in raw) {
    final line = entry?.toString().trim();
    if (line == null || line.isEmpty) {
      continue;
    }
    final parsed = parseIngredientLine(line);
    if (parsed.confidence == ParseConfidence.check) {
      needsReview += 1;
    }
    items.add(
      IngredientLine(
        raw: line,
        amounts: parsed.amounts,
        item: parsed.item,
        prep: parsed.prep,
      ),
    );
  }
  if (needsReview > 0) {
    summary.warnings.add(
      '$fileName: $needsReview ingredient line(s) parsed with low '
      'confidence — review in the editor',
    );
  }
  return [IngredientGroup(items: items)];
}

List<RecipeStep> _steps(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final steps = <RecipeStep>[];
  for (final entry in raw) {
    final text = entry?.toString().trim();
    if (text == null || text.isEmpty) {
      continue;
    }
    steps.add(RecipeStep(number: steps.length + 1, text: text));
  }
  return steps;
}

/// v0 stored `servings: 2` (a bare number, occasionally text). The verbatim
/// string is kept — the v2 servings parser reads a bare number fine.
String? _servingsText(Object? raw) {
  final text = raw?.toString().trim();
  return (text == null || text.isEmpty || text == 'null') ? null : text;
}

int? _minutes(Object? raw) {
  if (raw is int) {
    return (raw >= 0 && raw <= 100000) ? raw : null;
  }
  if (raw is String) {
    return _minutes(int.tryParse(raw.trim()));
  }
  return null;
}

String? _text(Object? raw) {
  final text = raw?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// v0 `notes` was usually `[]`, sometimes a list of strings or one string.
String? _notes(Object? raw) {
  if (raw is List) {
    final joined = [
      for (final entry in raw)
        if (entry != null && entry.toString().trim().isNotEmpty)
          entry.toString().trim(),
    ].join('\n\n');
    return joined.isEmpty ? null : joined;
  }
  return _text(raw);
}

void _copyLegacyImage({
  required Recipe recipe,
  required String fileName,
  required List<Directory> imagesDirs,
  required Directory libraryImagesDir,
  required ImportSummary summary,
}) {
  final reference = recipe.images.hero;
  if (reference == null) {
    return;
  }
  final servedName = safeImageName(reference);
  if (servedName.isEmpty) {
    return;
  }
  final destination = File('${libraryImagesDir.path}/$servedName');
  if (destination.existsSync()) {
    return;
  }
  final bare = reference.startsWith('images/')
      ? reference.substring('images/'.length)
      : reference;
  if (bare.startsWith('/') || bare.split(RegExp(r'[/\\]')).contains('..')) {
    summary.warnings.add('$fileName: image path escapes the root: $bare');
    return;
  }
  for (final dir in imagesDirs) {
    final candidate = File('${dir.path}/$bare');
    if (candidate.existsSync()) {
      candidate.copySync(destination.path);
      return;
    }
  }
  summary.warnings.add('$fileName: image not found: $bare');
}
