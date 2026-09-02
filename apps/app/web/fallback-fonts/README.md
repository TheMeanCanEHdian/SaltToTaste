# Self-hosted engine font fallbacks

Flutter web's engine resolves its font fallbacks against `fontFallbackBaseUrl`,
which defaults to `https://fonts.gstatic.com/s/`. A build that bundles every
font it renders — this one does: OpenSans, Arimo, Inter, RobotoMono — still
calls Google on every load for the engine's own default face, and again per
missing glyph for Noto. On a self-hosted app that request buys nothing and
hands a third party every visitor's IP.

`web/flutter_bootstrap.js` points that base URL here instead, so the engine
asks this server.

## Why the filename looks wrong

`roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2` is not our choice — the engine
builds that exact path from the base URL (a lazy static in the compiled
engine: `fontFallbackBaseUrl + "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"`).
The file must sit at that path to be found.

The BYTES are `Roboto-Regular.ttf`, copied from the Flutter SDK's bundled
material fonts (`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/`), not a
woff2. CanvasKit parses the font from the bytes it is handed and ignores the
extension, exactly as it does for the app's other `.ttf` assets. Roboto is
Apache-2.0, the same license as the RobotoMono already vendored in
`assets/fonts/`.

Nothing in the app renders in Roboto; it exists only as the engine's
last-resort default, so a glyph missing from every bundled family degrades to
a real face instead of failing to load.
