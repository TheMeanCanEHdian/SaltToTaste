/// A recipe id that is safe to use as a single filesystem path segment and
/// inside HTTP headers: starts with an alphanumeric, then alphanumerics, dot,
/// underscore, or hyphen. Excludes `/`, `\`, whitespace, quotes, and control
/// characters, so it cannot traverse directories or break header syntax.
///
/// Every corpus id (`atk-tv-2023-0857-rich-chocolate-bundt-cake`) and every
/// in-app id (`manual-<yyyymmdd>-<slug>`) satisfies this.
final RegExp _safeRecipeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Whether [id] is safe to use as a filename and header value.
///
/// A traversal segment (`..`) fails because it does not start with an
/// alphanumeric; any id containing a separator fails because `/` and `\`
/// are not permitted.
bool isSafeRecipeId(String id) => _safeRecipeId.hasMatch(id);
