/// A recipe id that is safe to use as a single filesystem path segment and
/// inside HTTP headers: starts with an alphanumeric, then alphanumerics, dot,
/// underscore, or hyphen. Excludes `/`, `\`, whitespace, quotes, and control
/// characters, so it cannot traverse directories or break header syntax.
///
/// Every corpus id (`atk-tv-2023-0857-rich-chocolate-bundt-cake`) and every
/// in-app id (`manual-<yyyymmdd>-<slug>`) satisfies this.
final RegExp _safeRecipeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// v111 Y5 (4): the longest recipe id every file name derived from it fits
/// (NAME_MAX 255 bytes; the longest suffix is a same-second conflict copy's
/// temp, `.conflict-<yyyyMMddTHHmmss>-<nn>.yaml.tmp`, 37). An imported
/// `id:` of 247+ characters stored a row whose export could not be written
/// (the import counted it failed; the scan's add stored it and threw).
const int maxRecipeIdLength = 218;

/// Whether [id] is safe to use as a filename and header value.
///
/// A traversal segment (`..`) fails because it does not start with an
/// alphanumeric; any id containing a separator fails because `/` and `\`
/// are not permitted; an id over [maxRecipeIdLength] fails (v111 Y5 (4)).
bool isSafeRecipeId(String id) =>
    id.length <= maxRecipeIdLength && _safeRecipeId.hasMatch(id);
