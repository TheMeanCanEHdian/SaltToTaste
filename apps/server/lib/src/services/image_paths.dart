/// Maps a document image reference (e.g. `images/0857-...-hero.jpg`, possibly
/// with subdirectories, spaces, or non-ASCII characters) to a single
/// route-safe library filename, and builds the serving URL from it.
///
/// This is the single source of truth shared by the importer (which names the
/// copied file) and the DAL/handlers (which build the card/detail URL): both
/// must produce the identical name, or the URL and the file on disk diverge.
library;

/// Characters not allowed in a served image filename (anything outside
/// `[A-Za-z0-9._-]`), which the image route's segment validation also
/// forbids and which URLs would otherwise have to percent-encode.
final RegExp _unsafe = RegExp('[^A-Za-z0-9._-]+');
final RegExp _dashRuns = RegExp('-{2,}');
final RegExp _leadingDotsDashes = RegExp('^[-.]+');
const String _imagesPrefix = 'images/';

/// A deterministic, URL-safe, single-segment filename for [reference].
///
/// The extraction convention roots references at `images/`; that prefix is
/// stripped so flat corpus names (`0857-slug-hero.jpg`) pass through
/// unchanged. Any remaining separators or unusual characters become hyphens,
/// so distinct references keep distinct names (`a/hero.jpg` -> `a-hero.jpg`,
/// `b/hero.jpg` -> `b-hero.jpg`) instead of colliding on the basename.
String safeImageName(String reference) {
  var name = reference.trim();
  if (name.startsWith(_imagesPrefix)) {
    name = name.substring(_imagesPrefix.length);
  }
  return name
      .replaceAll(_unsafe, '-')
      .replaceAll(_dashRuns, '-')
      .replaceAll(_leadingDotsDashes, '');
}

/// The serving URL for a stored `hero_image` [reference] under [sourceSlug],
/// or null when there is no image. Output is already URL-safe.
String? imageUrl(String sourceSlug, String? reference) {
  if (reference == null || reference.trim().isEmpty) {
    return null;
  }
  return '/images/$sourceSlug/${safeImageName(reference)}';
}
