/// The tag chip colour wire format, defined ONCE (review S5).
///
/// Three hand-copied `^#[0-9a-fA-F]{6}$` regexes — the server's write-side
/// validator, the app's editor validation, and the app's chip renderer —
/// once had to agree by luck: a widening applied to one site would have let
/// the server store a colour the renderer silently dropped to the default
/// palette. Every site now consumes this definition.
final RegExp _tagColorHex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Whether [value] is exactly `#RRGGBB`.
bool isValidTagColorHex(String value) => _tagColorHex.hasMatch(value);
