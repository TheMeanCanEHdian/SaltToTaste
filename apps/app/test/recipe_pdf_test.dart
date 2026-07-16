import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/features/recipes/pdf/recipe_pdf.dart';
import 'package:salt_shared/salt_shared.dart';

import 'support/corpus.dart';

/// The PDF export, laid out from real corpus recipes.
///
/// Recipes come from the ATK corpus (project convention: real data only).
/// Personal notes are synthesized because they cannot: a note is authored by
/// the reader and lives in the DB, never in the corpus YAML.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('undrawable-fraction fallback', () {
    test('spells out only the fractions the fonts cannot draw', () {
      // Real corpus amounts (0879 and 0942 respectively).
      expect(
        drawableText('1½ cups (10⅕ ounces) granulated sugar'),
        '1½ cups (10 1/5 ounces) granulated sugar',
      );
      expect(
        drawableText('½ cup plus 2 tablespoons (4⅖ ounces) sugar'),
        '½ cup plus 2 tablespoons (4 2/5 ounces) sugar',
      );
    });

    test('never fuses the fraction onto the whole number', () {
      // '10' + '1/5' = '101/5' would be a plausible WRONG amount, which is
      // worse than an obviously broken one.
      expect(drawableText('10⅕'), '10 1/5');
      expect(drawableText('4⅖'), '4 2/5');
      // No preceding digit: no inserted space.
      expect(drawableText('⅕ teaspoon'), '1/5 teaspoon');
      expect(drawableText('about ⅚ cup'), 'about 5/6 cup');
    });

    test('leaves drawable fractions as glyphs', () {
      // These have real glyphs (Open Sans or the Arimo fallback) and must
      // keep them — spelling them out would be a visual regression.
      for (final glyph in ['½', '¼', '¾', '⅓', '⅔', '⅛', '⅜', '⅝', '⅞']) {
        expect(drawableText('1$glyph cups'), '1$glyph cups');
      }
    });
  });

  group('recipe PDF', skip: skipIfNoCorpus, () {
    // A plain single-section recipe.
    late Recipe bundt;
    // The stress case: the corpus's largest recipe — sub-recipes, technique
    // sidebars and a long ingredient list, i.e. the multi-page paths that
    // `maxPages: 100` exists for and a single-section fixture cannot reach.
    late Recipe doughnuts;

    setUpAll(() {
      bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      doughnuts = loadCorpusRecipe('1105-yeasted-doughnuts.yaml');
    });

    test('builds a PDF for a real corpus recipe', () async {
      final bytes = await buildRecipePdf(recipe: bundt);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('lays out a recipe with subsections and techniques', () async {
      // Guards the paths a hand-built single-section fixture cannot reach.
      expect(
        doughnuts.subsections,
        isNotEmpty,
        reason: 'fixture drifted: this test needs a sub-recipe recipe',
      );
      expect(
        doughnuts.techniques,
        isNotEmpty,
        reason: 'fixture drifted: this test needs a technique sidebar',
      );
      final bytes = await buildRecipePdf(recipe: doughnuts);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('every corpus recipe lays out, with every glyph drawable', () async {
      // The whole-corpus gate: 1,198 real recipes must each produce a PDF,
      // and none may hit a rune the bundled fonts cannot draw.
      //
      // A missing glyph does not throw — the pdf package draws a crossed-out
      // box and warns via `print` inside an `assert`, so it is invisible in
      // release and silently corrupts an amount (`10⅕` -> `10[x]`). Trapping
      // that print is the only way to see it, and it asserts the symptom
      // rather than the fix, so it still holds if the font chain changes.
      final failures = <String>[];
      final glyphWarnings = <String>{};
      await runZoned(
        () async {
          for (final recipe in loadAllCorpusRecipes()) {
            try {
              await buildRecipePdf(recipe: recipe);
            } catch (error) {
              failures.add('${recipe.id}: $error');
            }
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            if (line.contains('Unable to find a font')) {
              glyphWarnings.add(line);
            } else {
              parent.print(zone, line);
            }
          },
        ),
      );
      expect(failures, isEmpty, reason: 'recipes that failed to export');
      expect(
        glyphWarnings,
        isEmpty,
        reason:
            'runes with no glyph in the bundled fonts; each prints as a '
            'crossed-out box. Add the fraction to _undrawableFractions or '
            'bundle a font that covers it',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('the two real recipes with undrawable fractions still export', () async {
      // 0879 has '1½ cups (10⅕ ounces) granulated sugar' and 0942 has
      // '½ cup plus 2 tablespoons (4⅖ ounces) sugar' — the only two ⅕/⅖ uses
      // in the corpus, and the ones that printed as '10[x] ounces'.
      for (final name in [
        '0879-easy-caramel-cake.yaml',
        '0942-homemade-vanilla-ice-cream.yaml',
      ]) {
        final recipe = loadCorpusRecipe(name);
        final raw = recipe.ingredients
            .expand((group) => group.items)
            .map((item) => item.raw)
            .join('\n');
        expect(
          raw,
          anyOf(contains('⅕'), contains('⅖')),
          reason: 'fixture drifted: $name no longer carries the fraction',
        );
        final bytes = await buildRecipePdf(recipe: recipe);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });

    group('personal note (synthesized: a note cannot come from the corpus)', () {
      // ONE paragraph, no blank lines — a pasted wall of text. This is the
      // shape that throws when prose cannot span a page break; splitting it
      // into paragraphs would let the layout break between them and hide the
      // bug.
      final wall = 'Chill the dough the full hour. ' * 300;

      test('a note longer than a page flows instead of throwing', () async {
        final bytes = await buildRecipePdf(recipe: bundt, personalNote: wall);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });

      test('a multi-paragraph note flows instead of throwing', () async {
        final note = List.generate(
          30,
          (i) => 'Paragraph $i. ${'Chill the dough the full hour. ' * 10}',
        ).join('\n\n');
        final bytes = await buildRecipePdf(recipe: bundt, personalNote: note);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });

      test('a blank note renders no panel', () async {
        // The claim is "no panel", so compare against the no-note build:
        // identical bytes mean nothing was emitted for the blank note.
        // (A %PDF- header would pass even if a stray empty panel rendered.)
        final blank = await buildRecipePdf(recipe: bundt, personalNote: '   ');
        final none = await buildRecipePdf(recipe: bundt);
        expect(blank.length, none.length);
      });

      test('a note renders a panel (the blank-note test can fail)', () async {
        // Pins that the comparison above is capable of failing: a real note
        // must change the output.
        final withNote = await buildRecipePdf(
          recipe: bundt,
          personalNote: 'Chill the dough the full hour.',
        );
        final none = await buildRecipePdf(recipe: bundt);
        expect(withNote.length, isNot(none.length));
      });
    });

    group('long free-text fields (synthesized: editor-authored prose)', () {
      // prepNotes/background/notes/steps are all free-text in the editor, so
      // each can be an unbounded single paragraph.
      final wall = 'Chill the dough the full hour. ' * 300;

      test('a page-long prepNotes flows instead of throwing', () async {
        final bytes = await buildRecipePdf(
          recipe: bundt.copyWith(prepNotes: wall),
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });

      test('a page-long background flows instead of throwing', () async {
        final bytes = await buildRecipePdf(
          recipe: bundt.copyWith(background: wall),
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });

      test('page-long notes flow instead of throwing', () async {
        final bytes = await buildRecipePdf(recipe: bundt.copyWith(notes: wall));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });

      test('a page-long step flows instead of throwing', () async {
        final bytes = await buildRecipePdf(
          recipe: bundt.copyWith(
            steps: [RecipeStep(number: 1, text: wall)],
          ),
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });
    });
  });
}
