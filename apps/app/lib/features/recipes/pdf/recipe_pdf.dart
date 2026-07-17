import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:salt_shared/salt_shared.dart';

/// Builds the recipe's export PDF (US Letter). [personalNote] is the signed-in
/// user's private note, omitted when null/blank.
Future<Uint8List> buildRecipePdf({
  required Recipe recipe,
  String? personalNote,
  @visibleForTesting bool compress = true,
}) async {
  final fonts = await _loadFonts();
  final doc = pw.Document(
    // Tests turn compression off so they can count what was actually DRAWN.
    // Byte length is not a proxy for that: a dropped widget still reserves its
    // height, which shifts every later coordinate and changes the byte count
    // on its own — a header ceiling once deleted every tag chip while the
    // byte-length assertion stayed green.
    compress: compress,
    title: recipe.title,
    author: recipe.source.name,
    creator: 'SaltToTaste',
  );
  final page = _RecipeDocument(
    recipe: recipe,
    fonts: fonts,
    personalNote: _clean(personalNote),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      theme: fonts.theme,
      margin: const pw.EdgeInsets.all(0.5 * PdfPageFormat.inch),
      // The default cap of 20 is a runaway-layout guard, not a real limit. A
      // recipe with several full sub-recipes and technique sidebars can
      // legitimately run long, and hitting the cap throws rather than
      // truncates — so raise it well past anything the corpus produces.
      maxPages: 100,
      footer: page.footer,
      build: page.build,
    ),
  );
  return doc.save();
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

/// The print palette, mirroring `SaltColors` (core/theme/salt_theme.dart).
/// That one is Material-typed and so unusable inside a `pdf` document; these
/// are the same values in `PdfColor`. Keep the two in sync.
abstract final class _Ink {
  static final maroon = PdfColor.fromInt(0xFF960000);
  static final deepMaroon = PdfColor.fromInt(0xFF7D1420);
  static final rose = PdfColor.fromInt(0xFF8C4242);
  static final chipFill = PdfColor.fromInt(0xFFF6E4E4);
  static final chipInk = PdfColor.fromInt(0xFF7D1420);
  static final ink = PdfColor.fromInt(0xFF23201F);
  static final body = PdfColor.fromInt(0xFF4A4442);
  static final muted = PdfColor.fromInt(0xFF6D6763);
  static final hairline = PdfColor.fromInt(0xFFE7E2DE);
  static final panel = PdfColor.fromInt(0xFFFDFBF9);
  static final white = PdfColor.fromInt(0xFFFFFFFF);
}

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

/// The document's typefaces. The [theme] carries regular/bold/italic so that
/// `fontWeight`/`fontStyle` resolve without naming a font; [semiBold] and
/// [extraBold] are the weights the design uses that a `pdf` theme has no slot
/// for, so styles reach for them explicitly.
class _Fonts {
  const _Fonts({
    required this.theme,
    required this.regular,
    required this.semiBold,
    required this.extraBold,
  });

  final pw.ThemeData theme;

  /// The body face, held separately from [theme] so step layout can MEASURE
  /// text (see `_stepLineBound`) instead of guessing at it.
  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font extraBold;
}

/// Parsing ~700 KB of TTF dominates the cost of an export, and the parsed
/// fonts are immutable — hold them for the session. Only a resolved value is
/// cached, so a failed load never poisons later attempts.
_Fonts? _cachedFonts;

Future<_Fonts> _loadFonts() async {
  final cached = _cachedFonts;
  if (cached != null) {
    return cached;
  }
  Future<pw.Font> load(String file) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));

  // The web build runs with --no-web-resources-cdn, so the pdf package's
  // default fonts (fetched from Google's CDN at document build time) are not
  // an option: everything the document draws must come from the bundle.
  final regular = await load('OpenSans-Regular.ttf');
  final bold = await load('OpenSans-Bold.ttf');
  final italic = await load('OpenSans-Italic.ttf');
  final semiBold = await load('OpenSans-SemiBold.ttf');
  final extraBold = await load('OpenSans-ExtraBold.ttf');
  // Open Sans has no ⅓/⅔ (they show up in real ingredient lines) and a
  // missing glyph renders as nothing at all. Arimo covers them, so it backs
  // every style via the theme's fallback chain.
  final fallback = await load('Arimo-Variable.ttf');

  final fonts = _Fonts(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      // No bold-italic is bundled. Naming the italic here keeps any
      // bold+italic run inside the family instead of letting the pdf package
      // silently drop it to its built-in Helvetica.
      boldItalic: italic,
      fontFallback: [fallback],
    ),
    regular: regular,
    semiBold: semiBold,
    extraBold: extraBold,
  );
  return _cachedFonts = fonts;
}

/// An upper bound on the lines [text] needs in a [columnWidth] column, or null
/// when no bound can be proven.
///
/// A BOUND, not a guess — which is the whole point. Within a run containing no
/// hard break, greedy wrapping leaves every line at least HALF full, provided
/// no single word is wider than half the column. So such a run needs at most
/// `2 * totalWidth / columnWidth` lines. A word wider than half the column
/// breaks that argument, so this returns null and the caller must take the
/// always-safe spanning branch rather than assume.
///
/// It exists because the two cheaper answers were both wrong, and this file
/// paid for each: a CHARACTER COUNT cannot bound a height — a 1,397-char
/// checklist of 44 short newline-separated lines reached the page-retry band
/// and hung a release tab — and `maxLines` bounds height only by throwing text
/// away invisibly (pdf's TextOverflow has no ellipsis member).
@visibleForTesting
int? stepLineBound({
  required PdfFont font,
  required double fontSize,
  required String text,
  required double columnWidth,
}) {
  double widthOf(String s) => font.stringMetrics(s).width * fontSize;
  final half = columnWidth / 2;
  var total = 0.0;
  var hardBreaks = 0;
  for (final line in text.split('\n')) {
    hardBreaks++;
    for (final word in line.split(' ')) {
      if (word.isEmpty) {
        continue;
      }
      if (widthOf(word) > half) {
        // One word can hold a line on its own; the half-full argument
        // collapses and nothing here is provable.
        return null;
      }
    }
    total += widthOf(line);
  }
  return hardBreaks + (2 * total / columnWidth).ceil();
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

/// Emits the recipe as a flat list of page-level widgets.
///
/// Every row, step, and paragraph is its own top-level widget: `MultiPage`
/// breaks *between* the widgets it is given, so anything grouped into one
/// un-splittable column would be forced onto a single page (and throws once it
/// outgrows one). That also rules out the reading-view's side-by-side
/// ingredients rail — print gets a single flowing column instead.
class _RecipeDocument {
  _RecipeDocument({
    required this.recipe,
    required this.fonts,
    required this.personalNote,
  });

  final Recipe recipe;
  final _Fonts fonts;
  final String? personalNote;

  List<pw.Widget> build(pw.Context context) => [
    _header(),
    ..._prose(recipe.background, style: _headnoteStyle, justify: true),
    if (_clean(recipe.prepNotes) case final prepNotes?)
      ..._cookbookNote(prepNotes),
    if (_clean(personalNote) case final note?) ..._personalNote(note),
    ..._ingredientBlock(recipe.ingredients, heading: 'Ingredients'),
    ..._stepBlock(context, recipe.steps, heading: 'Directions'),
    for (final subsection in recipe.subsections)
      ..._subsection(context, subsection),
    for (final technique in recipe.techniques) ..._technique(technique),
    ..._recipeNotes(),
    _sourceLine(),
  ];

  pw.Widget footer(pw.Context context) => pw.Container(
    alignment: pw.Alignment.centerRight,
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Text(
      '${context.pageNumber} of ${context.pagesCount}',
      style: pw.TextStyle(fontSize: 7.5, color: _Ink.muted, letterSpacing: 0.9),
    ),
  );

  // -- header ---------------------------------------------------------------

  /// The header's caps exist to keep ONE invariant true: the whole header must
  /// always fit a single page. They are chosen together and must be changed
  /// together — `header always fits one page, whatever the user typed` in
  /// recipe_pdf_test.dart is the thing that actually enforces this.
  ///
  /// Why the invariant, rather than a cap per field: the header is a
  /// `Container > Row`, a non-spanning direct MultiPage child, so its height is
  /// the SUM of its children's caps. Bounding each child individually is not
  /// enough and is actively dangerous — it was tried, and it made things worse.
  /// MultiPage's fit check ignores the ~20pt footer (multi_page.dart:376-391),
  /// so a widget in the band (699.8pt, 720pt] neither fits nor is big enough to
  /// be rejected: it retries on a fresh page forever. The runaway guard is
  /// inside an `assert`, which `flutter build web --release` strips — so the
  /// tab hangs. Per-child caps summed to ~1004pt, which SWEEPS that band as a
  /// title grows: input that used to throw cleanly began hanging instead.
  /// Keeping the saturated sum below the band is what makes the band
  /// unreachable, and no individual cap can express that.
  ///
  /// Measured against the corpus (1,198 recipes) and the API's own limits:
  ///
  /// | field    | corpus max | API cap | cap here            |
  /// |----------|-----------:|--------:|---------------------|
  /// | title    |   86 chars |     250 | [_maxTitleLines]    |
  /// | category |   52 chars |     120 | [_maxCategoryLines] |
  /// | tags     |     1 tag  |      50 | [_maxHeaderChips]   |
  /// | tag text |    7 chars |      60 | [_maxChipChars]     |
  ///
  /// How many tag chips the header prints before summarising the rest.
  ///
  /// 50 API-legal tags cannot fit a page in any layout — measured at 990.7pt
  /// of chips alone against a 699.8pt usable page — so a cap is unavoidable
  /// here. The overflow is STATED rather than dropped: a height ceiling was
  /// tried and silently deleted every chip, which is strictly worse than
  /// printing "+38 more".
  static const _maxHeaderChips = 12;

  /// A tag longer than this is ellipsized, so a chip is always exactly one
  /// line. 60 matches the API's own tag cap, so no tag the API accepts is ever
  /// shortened — a 60-char chip measures 15.9pt, one line, with room to spare.
  ///
  /// It earns its keep on the tags the API would REJECT but the importer lets
  /// through (it never calls `_validateRecipe`, and library YAML is
  /// hand-editable). Measured at the header's 408pt column: 120 chars wraps to
  /// 2 lines (26.8pt), 200+ to 3 (37.7pt), and 13 such chips come to 537.9pt —
  /// a third of the page spent on tags nobody asked for. The ellipsis, rather
  /// than `maxLines` alone, is what makes the shortening VISIBLE: pdf's
  /// TextOverflow has no ellipsis member, so a line cap just stops mid-word.
  ///
  /// (An earlier version of this comment claimed a 69-char tag wrapped to 3
  /// lines and 13 of them came to 578pt. Both figures were invented; a 69-char
  /// tag is one line, 15.9pt. The cap is right, the stated reason was not.)
  static const _maxChipChars = 60;

  /// Measured: the API's longest legal title (250 chars) needs 9 lines, so 10
  /// leaves one to spare and no legal title is ever cut. The corpus's longest
  /// is 86 chars — 3 lines. 8 was tried and silently dropped 2 of 25 words.
  static const _maxTitleLines = 10;

  /// The yield rail is only 116pt wide, so this wraps far sooner than its
  /// character count suggests. Measured in that rail: an API-legal 200-char
  /// yield needs 12 lines, so 14 leaves margin. It was 10, which silently ate
  /// 3 words of a 197-char yield the API itself accepts. The corpus's longest
  /// real yield is 69 chars ("MAKES ABOUT ¼ CUP, ENOUGH TO DRESS 8 TO 10 CUPS
  /// LIGHTLY PACKED GREENS"), so no real recipe is close.
  static const _maxMetaValueLines = 14;

  /// Measured: the API's longest legal category (120 chars) needs 3 lines. At
  /// 2 it silently dropped a word. The corpus's longest is 52 chars.
  static const _maxCategoryLines = 3;

  pw.Widget _header() {
    final category = _clean(recipe.category);
    final tags = recipe.tags.map(_clean).nonNulls.toList();
    final meta = _metaEntries();
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _Ink.ink, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (category != null) ...[
                  pw.Text(
                    category.toUpperCase(),
                    style: _eyebrowStyle,
                    maxLines: _maxCategoryLines,
                  ),
                  pw.SizedBox(height: 5),
                ],
                pw.Text(
                  _drawable(recipe.title),
                  style: _titleStyle,
                  maxLines: _maxTitleLines,
                ),
                if (tags.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final tag in tags.take(_maxHeaderChips)) _chip(tag),
                      if (tags.length > _maxHeaderChips)
                        _chip(
                          '+${tags.length - _maxHeaderChips} more',
                          outlined: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (meta.isNotEmpty) ...[pw.SizedBox(width: 16), _meta(meta)],
        ],
      ),
    );
  }

  /// The only yield/time facts the schema actually carries. Nothing here is
  /// derived: an absent time is simply not printed.
  List<(String, String)> _metaEntries() {
    final serves = recipe.serves;
    final servings = _clean(recipe.servings);
    final times = recipe.times;
    return [
      if (serves != null)
        (
          _servesLabel,
          serves.min == serves.max
              ? '${serves.min}'
              : '${serves.min}–${serves.max}',
        )
      else if (servings != null)
        (_yieldLabel, servings),
      if (times.prep case final prep?) ('Prep', '$prep min'),
      if (times.cook case final cook?) ('Cook', '$cook min'),
      if (times.total case final total?) ('Total', '$total min'),
    ];
  }

  pw.Widget _meta(List<(String, String)> entries) => pw.SizedBox(
    // Bounded so a verbose yield string ("Enough for one 9-inch pie") wraps
    // in the right rail rather than crowding the title.
    width: 116,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (final (index, (label, value)) in entries.indexed) ...[
          if (index > 0) pw.SizedBox(height: 6),
          pw.Text(
            label.toUpperCase(),
            style: _metaLabelStyle,
            textAlign: pw.TextAlign.right,
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            value,
            style: label == _servesLabel ? _metaValueStyle : _metaYieldStyle,
            textAlign: pw.TextAlign.right,
            maxLines: _maxMetaValueLines,
          ),
        ],
      ],
    ),
  );

  // -- notes ----------------------------------------------------------------

  /// A labelled prose panel, emitted as one banded widget per paragraph.
  ///
  /// Banding is what makes an unbounded note printable. MultiPage only breaks
  /// *between* its own children, and a Column only breaks between *its*
  /// children — neither ever splits a single child. The one widget that can
  /// split itself is a Text with `overflow: span`, and only when it is
  /// reachable from a MultiPage child through wrappers that delegate
  /// `canSpan` (Container and Padding both do; a Row does not). So each
  /// paragraph is its own MultiPage child wrapped in its own decoration:
  /// a paragraph longer than a page splits, and the fill repaints on each
  /// page it lands on. Packing the paragraphs into one panel instead would
  /// bury the Text under a Column and throw on the first oversized one.
  ///
  /// Bands share edges — padding and radius apply only at the first and last
  /// — so consecutive paragraphs still read as a single panel.
  List<pw.Widget> _notePanel({
    required String label,
    required PdfColor labelColor,
    required String text,
    required pw.TextStyle style,
    required PdfColor fill,
    PdfColor? spine,
    double radius = 0,
  }) {
    final paragraphs = _paragraphs(text);
    if (paragraphs.isEmpty) {
      return const [];
    }
    pw.Widget band({
      required pw.Widget child,
      bool first = false,
      bool last = false,
    }) => pw.Container(
      // MultiPage hands its children loose constraints, so a panel would
      // otherwise shrink-wrap its longest line and end up a different width
      // per note. Panels are page-wide by design.
      width: double.infinity,
      margin: pw.EdgeInsets.only(bottom: last ? 11 : 0),
      padding: pw.EdgeInsets.fromLTRB(9, first ? 8 : 0, 9, last ? 9 : 0),
      decoration: pw.BoxDecoration(
        color: fill,
        // A left-only border rules out a corner radius (the pdf package only
        // rounds uniform borders), which suits a spine anyway.
        border: spine == null
            ? null
            : pw.Border(left: pw.BorderSide(color: spine, width: 3)),
        // Round only the outer edges so the bands read as one panel.
        borderRadius: radius == 0 || spine != null
            ? null
            : pw.BorderRadius.vertical(
                top: first ? pw.Radius.circular(radius) : pw.Radius.zero,
                bottom: last ? pw.Radius.circular(radius) : pw.Radius.zero,
              ),
      ),
      child: child,
    );
    return [
      band(
        first: true,
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            label.toUpperCase(),
            style: _panelLabelStyle(labelColor),
          ),
        ),
      ),
      for (final (index, paragraph) in paragraphs.indexed)
        band(
          last: index == paragraphs.length - 1,
          child: pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: index == paragraphs.length - 1 ? 0 : 5,
            ),
            child: pw.Text(
              paragraph,
              style: style,
              overflow: pw.TextOverflow.span,
            ),
          ),
        ),
    ];
  }

  /// The cookbook's own headnote: the book talking, so it keeps the book's
  /// tinted panel and italic voice.
  List<pw.Widget> _cookbookNote(String text) => _notePanel(
    label: 'Notes',
    labelColor: _Ink.rose,
    text: text,
    style: _cookbookNoteStyle,
    fill: _Ink.chipFill,
    radius: 6,
  );

  /// The reader's own note. Deliberately unlike the panel above — cream fill,
  /// maroon spine, upright ink — so the two voices never blur together.
  List<pw.Widget> _personalNote(String text) => _notePanel(
    label: 'My notes',
    labelColor: _Ink.maroon,
    text: text,
    style: _personalNoteStyle,
    fill: _Ink.panel,
    spine: _Ink.maroon,
  );

  List<pw.Widget> _recipeNotes() {
    final notes = _clean(recipe.notes);
    if (notes == null) {
      return const [];
    }
    return [_sectionHeading('Notes'), ..._prose(notes, style: _headnoteStyle)];
  }

  // -- ingredients ----------------------------------------------------------

  List<pw.Widget> _ingredientBlock(
    List<IngredientGroup>? groups, {
    String? heading,
  }) {
    final filled = (groups ?? const <IngredientGroup>[])
        .where((group) => group.items.isNotEmpty)
        .toList();
    if (filled.isEmpty) {
      return const [];
    }
    return [
      if (heading != null) _sectionHeading(heading),
      for (final group in filled) ...[
        if (_clean(group.group) case final label?) _minorLabel(label),
        for (final (index, item) in group.items.indexed)
          _ingredientRow(item, last: index == group.items.length - 1),
      ],
      pw.SizedBox(height: 4),
    ];
  }

  pw.Widget _ingredientRow(IngredientLine item, {required bool last}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: last
            ? null
            : pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _Ink.hairline, width: 0.5),
                ),
              ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 6,
              height: 6,
              // Nudged down to sit on the first line's x-height rather than
              // its ascender.
              margin: const pw.EdgeInsets.only(top: 3.6),
              decoration: pw.BoxDecoration(
                color: _Ink.rose,
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.SizedBox(width: 7),
            // The publisher's verbatim line — never recomposed from the
            // parsed amounts.
            pw.Expanded(
              child: pw.Text(
                _drawable(item.raw),
                style: _ingredientStyle,
                // Measured: 40 lines of this style is 613.3pt — inside the
                // 720pt page and below the (699.8, 720] band that hangs. 60
                // lines is 920.6pt, which is TALLER than a page and so throws
                // cleanly (multi_page.dart:385) rather than hanging.
                //
                // (Earlier revisions of this comment claimed ~500pt for 40
                // lines and 742pt for 60, and said 60 "hung". All three were
                // invented. The cap is right; the arithmetic behind it was
                // never run.)
                //
                // The API caps `raw` at 1000 chars, so this only bites
                // hand-edited or imported YAML, which nothing validates.
                maxLines: 40,
              ),
            ),
          ],
        ),
      );

  // -- directions -----------------------------------------------------------

  List<pw.Widget> _stepBlock(
    pw.Context context,
    List<RecipeStep>? steps, {
    String? heading,
    bool compact = false,
  }) {
    final all = steps ?? const <RecipeStep>[];
    if (all.isEmpty) {
      return const [];
    }
    final widgets = <pw.Widget>[if (heading != null) _sectionHeading(heading)];
    String? previousLabel;
    for (final step in all) {
      final label = _clean(step.label);
      // Some documents carry the phase label on every step of the phase,
      // others only on its first step; printing it when it changes reads
      // correctly either way.
      if (label != null && label != previousLabel) {
        widgets.add(_minorLabel(label));
      }
      previousLabel = label;
      widgets.add(_stepRow(context, step, compact: compact));
    }
    return widgets;
  }

  /// The most lines a step may print and still keep the hanging indent.
  ///
  /// A page holds 43 lines of [_stepStyle] (699.8pt usable / 15.96pt per
  /// line), so this is the ceiling, not a preference. The corpus's tallest
  /// real step is 1,472 chars — 15 lines — so real recipes clear it by ~3x.
  static const _maxIndentedStepLines = 43;

  /// A step: the number in its own column, the text hanging-indented beside it
  /// (user-approved 2026-07-16).
  ///
  /// TWO layouts, and the choice is forced by MultiPage rather than by taste:
  ///
  ///   * A **Row** cannot span (flex.dart: `canSpan => direction ==
  ///     Axis.vertical`). MultiPage therefore MOVES IT WHOLE to the next page
  ///     when it does not fit the remaining space (multi_page.dart:379), which
  ///     is exactly what a numbered step wants — badge and text together.
  ///   * **Partitions** CAN span (`canSpan => children.any(...)`,
  ///     partitions.dart:116), so a step longer than a page still prints in
  ///     full. But a spanning widget is ALWAYS split, never moved whole
  ///     (multi_page.dart:376-393 falls straight through to the span branch) —
  ///     so a short step at a page boundary had its badge placed on the old
  ///     page and its text on the next, ORPHANING the number. Reported from a
  ///     real export (Basic Double-Crust Pie Dough, step 3).
  ///
  /// So: take the Row whenever the step provably fits a page, and pay for the
  /// span only when it genuinely cannot. Both partitions must span — a
  /// non-spanning one is skipped by `saveContext` but not by `restoreContext`,
  /// which then null-checks a context that was never saved
  /// (partitions.dart:233).
  pw.Widget _stepRow(
    pw.Context context,
    RecipeStep step, {
    required bool compact,
  }) {
    final diameter = compact ? 14.0 : 16.0;
    final text = _drawable(step.text);
    final badge = pw.Container(
      width: diameter,
      height: diameter,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: compact ? _Ink.rose : _Ink.maroon,
        shape: pw.BoxShape.circle,
      ),
      child: pw.Text(
        '${step.number}',
        style: _stepNumberStyle(compact: compact),
      ),
    );
    final style = compact ? _compactStepStyle : _stepStyle;

    // MultiPage hands its children the page width less the margins
    // (multi_page.dart:260-264); the text column is what is left beside the
    // badge.
    final pageWidth = PdfPageFormat.letter.width - PdfPageFormat.inch;
    final columnWidth = pageWidth - (diameter + 8);
    final bound = stepLineBound(
      font: fonts.regular.getFont(context),
      fontSize: style.fontSize!,
      text: text,
      columnWidth: columnWidth,
    );
    final fits = bound != null && bound <= _maxIndentedStepLines;

    if (fits) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Nudged down to sit on the first line's baseline rather than its
            // ascender — a Row aligns boxes, and the circle is taller than the
            // glyphs beside it.
            pw.Container(
              margin: const pw.EdgeInsets.only(right: 8, top: 1.5),
              child: badge,
            ),
            // Expanded, not Flexible: MultiPage gives loose width constraints
            // (no minWidth), so anything that does not deliberately fill
            // shrink-wraps — which once collapsed the ingredient hairlines
            // from 540pt to 107pt.
            pw.Expanded(child: pw.Text(text, style: style)),
          ],
        ),
      );
    }

    // Too tall for one page (or unprovable): span, and keep every word.
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Partitions(
        children: [
          pw.Partition(
            width: diameter + 8,
            child: pw.RichText(
              overflow: pw.TextOverflow.span,
              text: pw.TextSpan(
                children: [
                  pw.WidgetSpan(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(top: 1.5),
                      child: badge,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.Partition(
            child: pw.RichText(
              overflow: pw.TextOverflow.span,
              text: pw.TextSpan(text: text, style: style),
            ),
          ),
        ],
      ),
    );
  }

  // -- subsections ----------------------------------------------------------

  List<pw.Widget> _subsection(pw.Context context, Subsection subsection) {
    final title = _clean(subsection.title);
    final servings = _clean(subsection.servings);
    final body = _clean(subsection.body);
    final prepNotes = _clean(subsection.prepNotes);
    final ingredients = _ingredientBlock(subsection.ingredients);
    final steps = _stepBlock(context, subsection.steps, compact: true);
    if (title == null &&
        body == null &&
        prepNotes == null &&
        ingredients.isEmpty &&
        steps.isEmpty) {
      return const [];
    }
    final isVariation = subsection.kind == 'variation';
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (title != null) ...[
              // Flexible, not Expanded: the chip belongs beside the title, and
              // only a title long enough to need the room pushes it over.
              pw.Flexible(
                child: pw.Text(
                  title,
                  style: _subsectionTitleStyle,
                  maxLines: 8,
                ),
              ),
              pw.SizedBox(width: 7),
            ],
            _chip(
              isVariation ? 'Variation' : 'Extra',
              outlined: !isVariation,
              fontSize: 7,
            ),
          ],
        ),
      ),
      if (servings != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(
            servings.toUpperCase(),
            style: _subsectionMetaStyle,
            overflow: pw.TextOverflow.span,
          ),
        ),
      ..._prose(body, style: _headnoteStyle),
      if (prepNotes != null) ..._cookbookNote(prepNotes),
      ...ingredients,
      ...steps,
    ];
  }

  // -- techniques -----------------------------------------------------------

  /// Text only: the technique photos live outside the document (and behind
  /// the API's auth), so the captions have to carry the sidebar on their own.
  List<pw.Widget> _technique(Technique technique) {
    final heading = _clean(technique.heading);
    final description = _clean(technique.description);
    final steps = technique.steps
        .where((step) => _clean(step.caption) != null)
        .toList();
    if (heading == null && description == null && steps.isEmpty) {
      return const [];
    }
    return [
      if (heading != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 5),
          child: pw.Text(
            heading.toUpperCase(),
            style: _techniqueHeadingStyle,
            overflow: pw.TextOverflow.span,
          ),
        ),
      ..._prose(description, style: _techniqueDescriptionStyle),
      for (final step in steps)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 13,
                child: pw.Text('${step.number}.', style: _compactStepStyle),
              ),
              pw.Expanded(
                child: pw.Text(
                  _drawable(step.caption.trim()),
                  style: _compactStepStyle,
                  // Measured: 40 lines of _compactStepStyle is 601.7pt —
                  // inside the page and below the band that hangs. (Earlier
                  // revisions said ~500pt, then ~613pt; the first was
                  // invented and the second was the INGREDIENT style's figure
                  // copied onto a smaller font.)
                  maxLines: 40,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  // -- attribution ----------------------------------------------------------

  pw.Widget _sourceLine() {
    final source = recipe.source;
    final publisher = _clean(source.publisher);
    final attribution = [
      source.name.trim(),
      if (publisher != null) publisher,
    ].join(' · ');
    return pw.Container(
      // Full width so the rule reads as a rule, not an underline.
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _Ink.hairline, width: 0.5)),
      ),
      child: pw.RichText(
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: 'SOURCE  ', style: _sourceLabelStyle),
            pw.TextSpan(text: attribution, style: _sourceStyle),
          ],
        ),
      ),
    );
  }

  // -- shared pieces --------------------------------------------------------

  pw.Widget _sectionHeading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 8, bottom: 6),
    child: pw.Text(text.toUpperCase(), style: _sectionStyle),
  );

  pw.Widget _minorLabel(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7, bottom: 3),
    child: pw.Text(
      text.toUpperCase(),
      style: _minorLabelStyle,
      overflow: pw.TextOverflow.span,
    ),
  );

  /// [text] shortened to [max] characters with a trailing ellipsis.
  ///
  /// Used where a silent `maxLines` truncation would be indistinguishable from
  /// the text simply ending: pdf's `TextOverflow` has no `ellipsis` member
  /// (text.dart declares clip/visible/span only), so a capped line just stops.
  /// An explicit ellipsis is the difference between STATING that something was
  /// shortened and quietly dropping it.
  static String _ellipsize(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';

  pw.Widget _chip(String text, {bool outlined = false, double fontSize = 8}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
        decoration: pw.BoxDecoration(
          color: outlined ? null : _Ink.chipFill,
          border: outlined
              ? pw.Border.all(color: _Ink.hairline, width: 0.6)
              : null,
          borderRadius: pw.BorderRadius.circular(5),
        ),
        // Exactly one line, always: a chip sits in the header's Wrap inside
        // its Row and so can never span, and its height is one of the terms in
        // the header's page-fit sum. The text is truncated rather than merely
        // line-capped because maxLines alone truncates INVISIBLY — pdf's
        // TextOverflow has no ellipsis (text.dart: clip/visible/span only) —
        // and because a wrapping chip is what put that sum in the hang band.
        child: pw.Text(
          _ellipsize(text, _maxChipChars).toUpperCase(),
          style: _chipStyle(fontSize: fontSize, outlined: outlined),
          maxLines: 1,
        ),
      );

  List<pw.Widget> _prose(
    String? text, {
    required pw.TextStyle style,
    bool justify = false,
  }) => [
    for (final paragraph in _paragraphs(text))
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Text(
          paragraph,
          style: style,
          textAlign: justify ? pw.TextAlign.justify : pw.TextAlign.left,
          // Prose is editor-authored and unbounded: one paragraph can be
          // taller than a page. `span` is the only overflow that makes
          // RichText.canSpan true, which is what lets MultiPage break the
          // text across pages instead of throwing. Padding delegates canSpan
          // to its child, so the break survives the wrapper.
          overflow: pw.TextOverflow.span,
        ),
      ),
  ];

  // -- styles ---------------------------------------------------------------

  pw.TextStyle get _eyebrowStyle => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 8.5,
    color: _Ink.rose,
    letterSpacing: 1.9,
  );

  pw.TextStyle get _titleStyle => pw.TextStyle(
    font: fonts.extraBold,
    fontSize: 25,
    color: _Ink.maroon,
    letterSpacing: -0.3,
  );

  pw.TextStyle get _metaLabelStyle => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 7.4,
    color: _Ink.muted,
    letterSpacing: 1.7,
  );

  pw.TextStyle get _metaValueStyle => pw.TextStyle(
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
    color: _Ink.ink,
  );

  pw.TextStyle get _metaYieldStyle => pw.TextStyle(
    fontSize: 9.5,
    fontWeight: pw.FontWeight.bold,
    color: _Ink.ink,
    lineSpacing: 1,
  );

  pw.TextStyle get _sectionStyle => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 9.5,
    color: _Ink.deepMaroon,
    letterSpacing: 1.4,
  );

  pw.TextStyle get _minorLabelStyle => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 8,
    color: _Ink.muted,
    letterSpacing: 1.3,
  );

  pw.TextStyle _chipStyle({required double fontSize, required bool outlined}) =>
      pw.TextStyle(
        font: fonts.semiBold,
        fontSize: fontSize,
        color: outlined ? _Ink.muted : _Ink.chipInk,
        letterSpacing: 0.7,
      );

  pw.TextStyle get _headnoteStyle =>
      pw.TextStyle(fontSize: 10, color: _Ink.body, lineSpacing: 1.8);

  pw.TextStyle _panelLabelStyle(PdfColor color) => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 7.4,
    color: color,
    letterSpacing: 1.4,
  );

  pw.TextStyle get _cookbookNoteStyle => pw.TextStyle(
    fontSize: 9.5,
    fontStyle: pw.FontStyle.italic,
    color: _Ink.chipInk,
    lineSpacing: 1.5,
  );

  pw.TextStyle get _personalNoteStyle =>
      pw.TextStyle(fontSize: 9.7, color: _Ink.ink, lineSpacing: 1.5);

  pw.TextStyle get _ingredientStyle =>
      pw.TextStyle(fontSize: 10.4, color: _Ink.body, lineSpacing: 1.2);

  pw.TextStyle get _stepStyle =>
      pw.TextStyle(fontSize: 10.4, color: _Ink.body, lineSpacing: 1.8);

  pw.TextStyle get _compactStepStyle =>
      pw.TextStyle(fontSize: 9.9, color: _Ink.body, lineSpacing: 1.6);

  pw.TextStyle _stepNumberStyle({required bool compact}) => pw.TextStyle(
    fontSize: compact ? 8 : 9,
    fontWeight: pw.FontWeight.bold,
    color: _Ink.white,
  );

  pw.TextStyle get _subsectionTitleStyle => pw.TextStyle(
    font: fonts.extraBold,
    fontSize: 12,
    color: _Ink.deepMaroon,
    letterSpacing: -0.1,
  );

  pw.TextStyle get _subsectionMetaStyle => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 7.4,
    color: _Ink.muted,
    letterSpacing: 1.5,
  );

  pw.TextStyle get _techniqueHeadingStyle => pw.TextStyle(
    font: fonts.extraBold,
    fontSize: 9.5,
    color: _Ink.deepMaroon,
    letterSpacing: 1.2,
  );

  pw.TextStyle get _techniqueDescriptionStyle =>
      pw.TextStyle(fontSize: 9.8, color: _Ink.muted, lineSpacing: 1.5);

  pw.TextStyle get _sourceLabelStyle => pw.TextStyle(
    font: fonts.semiBold,
    fontSize: 8,
    color: _Ink.rose,
    letterSpacing: 1.2,
  );

  pw.TextStyle get _sourceStyle =>
      pw.TextStyle(fontSize: 8.2, color: _Ink.muted, lineSpacing: 1.2);
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

const _servesLabel = 'Serves';
const _yieldLabel = 'Yield';

/// The vulgar fractions no bundled font can draw, in the order fractions are
/// spelled by [vulgarFractionAscii] so the two can never drift apart.
///
/// Neither Open Sans nor the Arimo fallback has a glyph for these. An
/// uncovered rune is not skipped — the pdf package draws a crossed-out
/// placeholder box, so `10⅕ ounces` prints as `10[x] ounces`, corrupting the
/// amount. Worse, its warning sits inside an `assert`, so a release build
/// does it silently. Every other fraction (½ ¼ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞) has a real
/// glyph and keeps it.
///
/// Pinned by the corpus glyph test, which fails if the font chain's coverage
/// ever changes underneath this list.
const _undrawableFractions = {'⅕', '⅖', '⅗', '⅘', '⅙', '⅚', '⅐', '⅑', '⅒'};

final Map<String, String> _fractionFallbacks = {
  for (final char in _undrawableFractions)
    if (vulgarFractionAscii[char] case final ascii?) char: ascii,
};

final RegExp _endsInDigit = RegExp(r'\d$');

/// Replaces fractions the font chain cannot draw with their ASCII spelling
/// (`10⅕ ounces` → `10 1/5 ounces`).
///
/// The space matters: `'10' + '1/5'` would read as `101/5`, turning an
/// unreadable amount into a plausible wrong one.
@visibleForTesting
String drawableText(String text) => _drawable(text);

String _drawable(String text) {
  if (!_fractionFallbacks.keys.any(text.contains)) {
    return text;
  }
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final ascii = _fractionFallbacks[char];
    if (ascii == null) {
      buffer.write(char);
      continue;
    }
    if (_endsInDigit.hasMatch(buffer.toString())) {
      buffer.write(' ');
    }
    buffer.write(ascii);
  }
  return buffer.toString();
}

/// Trimmed, drawable text, or null when there is nothing worth printing — the
/// document never renders a heading for absent data.
String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : _drawable(trimmed);
}

/// Splits stored prose into paragraphs on blank lines, folding the newlines
/// inside a paragraph back into spaces: the source text is hard-wrapped, and
/// the pdf package treats a bare newline as a hard break.
List<String> _paragraphs(String? text) {
  final cleaned = _clean(text);
  if (cleaned == null) {
    return const [];
  }
  return cleaned
      .split(RegExp(r'\n[ \t]*\n'))
      .map((paragraph) => paragraph.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();
}
