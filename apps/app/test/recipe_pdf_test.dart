import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

  // The step layout picks between two structures, and the choice is what keeps
  // the number beside its text. MultiPage MOVES a non-spanning widget whole to
  // the next page when it does not fit (multi_page.dart:379), but ALWAYS SPLITS
  // a spanning one (:376-393) — so a short step laid out as spanning had its
  // badge stranded on the old page and its text on the next. Reported from a
  // real export: Basic Double-Crust Pie Dough, step 3.
  //
  // So a step takes the non-spanning Row whenever it PROVABLY fits a page, and
  // the spanning layout only when it genuinely cannot. These pin both halves.
  group(
    'step layout: the number never leaves its text',
    skip: skipIfNoCorpus,
    () {
      late PdfFont font;
      // The text column: letter width - margins - the badge column.
      final columnWidth = PdfPageFormat.letter.width - PdfPageFormat.inch - 24;
      const fontSize = 10.4; // _stepStyle

      setUpAll(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final doc = pw.Document();
        font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/OpenSans-Regular.ttf'),
        ).getFont(pw.Context(document: doc.document));
      });

      int? bound(String text) => stepLineBound(
        font: font,
        fontSize: fontSize,
        text: text,
        columnWidth: columnWidth,
      );

      test('EVERY real corpus step provably fits a page, so none can split', () {
        // 43 lines is what a page holds (699.8pt / 15.96pt). If any real step
        // failed this it would take the spanning branch and could strand its
        // number — which is exactly the reported bug.
        var checked = 0;
        String? worstText;
        var worst = 0;
        for (final recipe in loadAllCorpusRecipes()) {
          for (final step in recipe.steps) {
            final lines = bound(step.text);
            expect(
              lines,
              isNotNull,
              reason: 'unprovable for a REAL step: ${step.text}',
            );
            expect(
              lines,
              lessThanOrEqualTo(43),
              reason:
                  'a real step would span and could strand its badge: '
                  '${step.text}',
            );
            if (lines! > worst) {
              worst = lines;
              worstText = step.text;
            }
            checked++;
          }
        }
        expect(checked, greaterThan(5000));
        // Headroom is the point: if this ever creeps toward 43, real recipes are
        // about to start spanning.
        expect(
          worst,
          lessThan(35),
          reason:
              'worst real step bounds at $worst lines '
              '(${worstText?.length} chars)',
        );
      });

      test('shapes that cannot fit a page are sent to the spanning layout', () {
        // Each of these reached the hang band when a char-count gate wrongly
        // routed it to the Row.
        expect(bound('a\n' * 44), greaterThan(43), reason: '44 hard breaks');
        expect(
          bound(
            List.generate(
              44,
              (i) => 'Step detail line $i, keep going',
            ).join('\n'),
          ),
          greaterThan(43),
          reason: 'a realistic 44-line checklist, only 1,397 chars',
        );
        expect(
          bound(('MMM ' * 700).trim()),
          greaterThan(43),
          reason: 'wide glyphs',
        );
        expect(
          bound(('stir the pot ' * 769).trim()),
          greaterThan(43),
          reason: 'an API-legal 10,000-char step',
        );
        // A word wider than half the column makes the half-full argument false,
        // so the bound must refuse to certify it rather than guess.
        expect(
          bound('W' * 3000),
          isNull,
          reason: 'one unbreakable 3,000-char word',
        );
      });
    },
  );

  group('recipe PDF', skip: skipIfNoCorpus, () {
    // A plain single-section recipe.
    late Recipe bundt;
    // The stress case: the corpus's largest recipe — sub-recipes, technique
    // sidebars and a long ingredient list, i.e. the multi-page paths that
    // `maxPages: 100` exists for and a single-section fixture cannot reach.
    late Recipe doughnuts;

    // A recipe whose meta rail shows a YIELD rather than a serves count —
    // i.e. `serves == null`, so `_metaEntries` takes its `servings` branch.
    // 173 of the 1,198 corpus recipes are like this; nothing else reaches the
    // yield rail, since `serves` is parsed at decode time and copyWith cannot
    // clear it.
    late Recipe broth;

    setUpAll(() {
      bundt = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      doughnuts = loadCorpusRecipe('1105-yeasted-doughnuts.yaml');
      broth = loadAllCorpusRecipes().firstWhere(
        (recipe) => recipe.serves == null && recipe.servings != null,
      );
    });

    // ---- the layout invariant --------------------------------------------
    //
    // A widget that cannot span a page break, and is taller than the space
    // LEFT on the page but still shorter than a whole page, makes MultiPage
    // retry it forever (multi_page.dart:376-380 `context = null; continue;`).
    // The guard that would stop it lives inside an assert, which
    // `flutter build web --release` strips — so the shipped app HANGS THE TAB
    // rather than throwing. (Taller than a whole page throws cleanly instead:
    // multi_page.dart:385. Only that narrow band hangs, and it exists because
    // the check ignores the footer's height.)
    //
    // Only Flex(vertical), Wrap, Table, GridView, Partition and RichText can
    // span; a pw.Text spans only with `overflow: span`. So every text in the
    // document either spans or is capped — and these prove it on the fields a
    // user can actually make arbitrarily long. The corpus cannot reach any of
    // this (its longest ingredient line is 190 chars), so these inputs are
    // synthesized: they are negative-path values the corpus cannot supply.
    group('no user field can hang the layout', () {
      test('fields the API caps, at and past their caps', () async {
        final cases = <String, Recipe Function(int)>{
          'title (API 250)': (n) => bundt.copyWith(title: 'Cake ' * (n ~/ 5)),
          'category (API 120)': (n) =>
              bundt.copyWith(category: 'Cake ' * (n ~/ 5)),
          // Uses a YIELD-ONLY recipe, and must. `serves` is a stored field
          // (recipe.dart) that the codec derives at DECODE time, so
          // `bundt.copyWith(servings: ...)` leaves the parsed Serves(12,12) in
          // place — and _metaEntries prints the long servings string only in
          // its `else if (servings != null)` branch. The old case passed a
          // 20,000-char string to a recipe that rendered "SERVES 12" and
          // asserted on a byte-identical PDF: it exercised nothing at all.
          'yield (API 200)': (n) =>
              broth.copyWith(servings: 'Makes ' * (n ~/ 6)),
          'ingredient raw (API 1000)': (n) => bundt.copyWith(
            ingredients: [
              IngredientGroup(
                items: [IngredientLine(raw: 'wordy ' * (n ~/ 6))],
              ),
            ],
          ),
          // Step text carries no spanning of its own since the badge moved
          // into its own column for the hanging indent: the step is a Row now,
          // and a Row cannot span a page. Only _maxStepLines keeps it bounded.
          'step text (API 10000)': (n) => bundt.copyWith(
            steps: [RecipeStep(number: 1, text: 'stir ' * (n ~/ 5))],
          ),
        };
        for (final entry in cases.entries) {
          // 4398 and 4091 are measured hang windows; 20000 is past them.
          for (final n in [1000, 4091, 4398, 20000]) {
            final bytes = await buildRecipePdf(recipe: entry.value(n));
            expect(
              String.fromCharCodes(bytes.take(5)),
              '%PDF-',
              reason: '${entry.key} at $n chars',
            );
          }
        }
      });

      // The regression test for the fix's OWN first attempt.
      //
      // Capping each Text in the header individually is not just insufficient,
      // it made one class of input WORSE: the caps summed to ~1004pt, and as a
      // title grows that sum SWEEPS the band (699.8pt, 720pt] where MultiPage
      // neither fits the widget nor rejects it and retries forever. Input that
      // threw a clean PdfException at 0d655dd began hanging instead. Asserts
      // are enabled under `flutter test`, so the retry loop surfaces here as
      // PdfTooBigPageException; `flutter build web --release` strips that
      // assert, and the same input hangs the user's tab with no error at all.
      //
      // One field at a time cannot catch this — each field alone saturates
      // safely. Only the combination does, so this sweeps combinations.
      test(
        'the header always fits one page, whatever the user typed',
        () async {
          for (final tagLength in [60, 69, 100, 200]) {
            for (final tagCount in [12, 13, 50]) {
              for (final titleWords in [12, 13, 16, 30]) {
                final recipe = bundt.copyWith(
                  title: 'Rich Chocolate Cake ' * titleWords,
                  category: 'Weeknight Dinners ' * 12,
                  tags: [
                    for (var i = 0; i < tagCount; i++)
                      'tag$i${'x' * (tagLength - 4)}',
                  ],
                );
                final bytes = await buildRecipePdf(
                  recipe: recipe,
                ).timeout(const Duration(seconds: 20));
                expect(
                  String.fromCharCodes(bytes.take(5)),
                  '%PDF-',
                  reason:
                      '$tagCount tags of $tagLength chars with a '
                      '$titleWords-word title',
                );
              }
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );

      // The yield rail's own cap, which the vacuous 'servings' case above
      // left completely unguarded for as long as it existed.
      test('the longest API-legal yield prints in full', () async {
        Future<int> painted(String servings) async {
          final bytes = await buildRecipePdf(
            recipe: broth.copyWith(servings: servings),
            compress: false,
          );
          return RegExp(
            r'\bTJ\b',
          ).allMatches(String.fromCharCodes(bytes)).length;
        }

        // 33 words, 197 chars — inside the API's 200-char cap.
        final yield197 = ('MAKES ' * 33).trim();
        expect(
          await painted(yield197) - await painted('X'),
          32,
          reason:
              'the 116pt-wide rail wraps early: at maxLines 10 three words '
              'of an API-legal yield vanished, with no ellipsis to show it',
        );
      });

      // The regression test for the step layout's SECOND wrong answer.
      //
      // Gating a non-spanning Row on `text.length > 3000` looked safe and was
      // not: a CHAR COUNT CANNOT BOUND A HEIGHT. Both of these sit inside that
      // gate, so they took the Row, and both landed in the (699.8pt, 720pt]
      // band — a hung tab in a release build, which is worse than the silent
      // truncation the gate was introduced to fix. The newline case is the
      // damning one: 88 chars, and reachable by typing an ordinary multi-line
      // step into the editor's own multiline field.
      test(
        'a step cannot reach the hang band, whatever its shape',
        () async {
          final cases = <String, String>{
            'wide glyphs under the old 3000-char gate': ('MMM ' * 700).trim(),
            'just over it': ('MMM ' * 705).trim(),
            '44 short newline-separated lines (88 chars)': 'a\n' * 44,
            'a realistic 44-line checklist': List.generate(
              44,
              (i) => 'Step detail line $i, keep going',
            ).join('\n'),
          };
          for (final entry in cases.entries) {
            final bytes = await buildRecipePdf(
              recipe: bundt.copyWith(
                steps: [RecipeStep(number: 1, text: entry.value)],
              ),
            ).timeout(const Duration(seconds: 20));
            expect(
              String.fromCharCodes(bytes.take(5)),
              '%PDF-',
              reason: entry.key,
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      // The other half of the bargain: the caps that keep the header on one
      // page must never touch data the API itself accepts.
      test('the longest API-legal title and category print in full', () async {
        Future<int> painted(Recipe recipe) async {
          final bytes = await buildRecipePdf(recipe: recipe, compress: false);
          return RegExp(
            r'\bTJ\b',
          ).allMatches(String.fromCharCodes(bytes)).length;
        }

        // 25 countable words, 249 chars — the API caps a title at 250.
        final title = ('Chocolate ' * 25).trim();
        expect(
          await painted(bundt.copyWith(title: title)) -
              await painted(bundt.copyWith(title: 'X')),
          24,
          reason:
              'a 250-char title needs 9 lines; at _maxTitleLines: 8 two '
              'words vanished with no ellipsis to show for it',
        );

        // 17 words, 118 chars — the API caps a category at 120.
        final category = ('Dinner ' * 17).trim();
        expect(
          await painted(bundt.copyWith(category: category)) -
              await painted(bundt.copyWith(category: 'X')),
          16,
          reason: 'a 120-char category needs 3 lines; 2 dropped a word',
        );
      });

      test('fields the API does NOT validate at all', () async {
        // _validateRecipe only COUNTS subsections/techniques — it never
        // descends into their fields. And it is private to the edit path, so
        // the importer and hand-edited library YAML skip it entirely.
        final cases = <String, Recipe Function(int)>{
          'subsection title': (n) => bundt.copyWith(
            subsections: [
              Subsection(title: 'Glaze ' * (n ~/ 6), kind: 'variation'),
            ],
          ),
          'subsection servings': (n) => bundt.copyWith(
            subsections: [
              Subsection(
                title: 'Glaze',
                kind: 'variation',
                servings: 'Makes ' * (n ~/ 6),
              ),
            ],
          ),
          'subsection group label': (n) => bundt.copyWith(
            subsections: [
              Subsection(
                title: 'Glaze',
                kind: 'variation',
                ingredients: [
                  IngredientGroup(
                    group: 'Group ' * (n ~/ 6),
                    items: const [IngredientLine(raw: '1 cup sugar')],
                  ),
                ],
              ),
            ],
          ),
          'technique heading': (n) => bundt.copyWith(
            techniques: [
              Technique(heading: 'How ' * (n ~/ 4), steps: const []),
            ],
          ),
          'technique caption': (n) => bundt.copyWith(
            techniques: [
              Technique(
                heading: 'How',
                steps: [TechniqueStep(number: 1, caption: 'Roll ' * (n ~/ 5))],
              ),
            ],
          ),
          'source name': (n) => bundt.copyWith(
            source: bundt.source.copyWith(name: 'Book ' * (n ~/ 5)),
          ),
          'a hand-edited tag': (n) => bundt.copyWith(tags: ['t' * n]),
        };
        for (final entry in cases.entries) {
          for (final n in [4091, 5100, 6600, 20000]) {
            final bytes = await buildRecipePdf(recipe: entry.value(n));
            expect(
              String.fromCharCodes(bytes.take(5)),
              '%PDF-',
              reason: '${entry.key} at $n chars',
            );
          }
        }
      });

      test('tags up to and past the API cap of 50', () async {
        for (final count in [12, 13, 50, 200]) {
          final tags = [for (var i = 0; i < count; i++) 'tag-$i-${'x' * 52}'];
          final bytes = await buildRecipePdf(
            recipe: bundt.copyWith(tags: tags),
          );
          expect(
            String.fromCharCodes(bytes.take(5)),
            '%PDF-',
            reason: '$count tags',
          );
        }
      });
    });

    // ---- content is DRAWN, not silently dropped ---------------------------
    //
    // Counted from the uncompressed content stream: `TJ` is the show-text
    // operator, so its count IS the number of text runs painted. Byte length
    // is NOT a proxy — a dropped widget still reserves height, shifting later
    // coordinates and changing the byte count on its own, which is how a
    // height ceiling deleted every tag chip with the tests still green.
    group('header content is drawn', () {
      /// Words painted, counted from the uncompressed content stream.
      ///
      /// `TJ` is the show-text operator and the pdf package emits ONE PER WORD
      /// — measured: 'nospace' -> 1, 'one space' -> 2, 'two more spaces' -> 3.
      /// So every tag below is deliberately single-word, which makes the delta
      /// equal the chip count.
      Future<int> wordsPainted(Recipe recipe) async {
        final bytes = await buildRecipePdf(recipe: recipe, compress: false);
        return RegExp(r'\bTJ\b').allMatches(String.fromCharCodes(bytes)).length;
      }

      test('each tag adds exactly one painted word', () async {
        final none = await wordsPainted(bundt.copyWith(tags: []));
        for (final count in [1, 3, 5, 12]) {
          final tags = [for (var i = 0; i < count; i++) 'chocolate-dessert-$i'];
          expect(
            await wordsPainted(bundt.copyWith(tags: tags)),
            none + count,
            reason: '$count single-word tags must paint $count more words',
          );
        }
      });

      test('a full API-legal header still draws every chip', () async {
        // The exact shape a 420pt ceiling regressed on: every field at its API
        // maximum, header well over 420pt.
        final recipe = bundt.copyWith(
          title: 'Rich Chocolate Bundt Cake ' * 9,
          category: 'A Piece of Cake ' * 7,
          tags: [for (var i = 0; i < 5; i++) 'chocolate-dessert-$i'],
        );
        expect(
          await wordsPainted(recipe),
          await wordsPainted(recipe.copyWith(tags: [])) + 5,
          reason: 'all five chips must be painted in a tall header',
        );
      });

      test('the +N more chip states what it is not showing', () async {
        final tags = [for (var i = 0; i < 20; i++) 'chocolate-dessert-$i'];
        final none = await wordsPainted(bundt.copyWith(tags: []));
        // 12 single-word chips + a "+8 MORE" chip, which is TWO words = 14.
        // Never 20 (the cap holds) and never 12 (the overflow is stated, not
        // silently dropped the way a height ceiling once dropped all of them).
        expect(
          await wordsPainted(bundt.copyWith(tags: tags)),
          none + 14,
          reason: '12 chips plus a two-word "+8 more" chip',
        );
      });
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

    test(
      'every corpus recipe lays out, with every glyph drawable',
      () async {
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
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test(
      'the two real recipes with undrawable fractions still export',
      () async {
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
      },
    );

    group(
      'personal note (synthesized: a note cannot come from the corpus)',
      () {
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
          final blank = await buildRecipePdf(
            recipe: bundt,
            personalNote: '   ',
          );
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
      },
    );

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

      // The badge moved into its own column so a wrapped step hangs-indents
      // (approved 2026-07-16). That makes a step a Row, and a Row cannot span a
      // page — so an over-long step is now CAPPED at _maxStepLines instead of
      // flowing across pages. These two tests pin both halves of that bargain:
      // the cap must never be reached by real data, and must hold for the rest.
      test('a page-long step prints IN FULL, not truncated', () async {
        // The hanging indent makes a step a non-spanning Row, so it must fit a
        // page. Bounding it with maxLines "solved" that by silently deleting
        // 44% of an API-legal step — pdf has no ellipsis, so the directions
        // just stopped. A step too long for the indent now falls back to the
        // spanning layout and prints completely instead.
        final words = wall.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
        final bytes = await buildRecipePdf(
          recipe: bundt.copyWith(steps: [RecipeStep(number: 1, text: wall)]),
          compress: false,
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

        final base = await buildRecipePdf(
          recipe: bundt.copyWith(steps: [RecipeStep(number: 1, text: 'stir')]),
          compress: false,
        );
        int painted(List<int> b) =>
            RegExp(r'\bTJ\b').allMatches(String.fromCharCodes(b)).length;
        int pages(List<int> b) => RegExp(
          r'/Type\s*/Page[^s]',
        ).allMatches(String.fromCharCodes(b)).length;
        // Each page paints a 3-word "N of M" footer that belongs to the page,
        // not the step.
        const footerWords = 3;
        expect(
          painted(bytes) -
              painted(base) -
              footerWords * (pages(bytes) - pages(base)),
          words.length - 1,
          reason:
              'every word of a ${wall.length}-char step must be printed; '
              'maxLines dropped ~44% of it with no ellipsis',
        );
      });

      test('an API-legal 10,000-char step prints in full', () async {
        // recipe_edit_service.dart accepts step text up to 10,000 chars, so
        // this needs no importer bypass — it is what the API itself allows.
        final long = ('stir the pot ' * 769).trim(); // 9,996 chars
        expect(long.length, lessThanOrEqualTo(10000));
        final words = long.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);

        int painted(List<int> b) =>
            RegExp(r'\bTJ\b').allMatches(String.fromCharCodes(b)).length;
        int pages(List<int> b) => RegExp(
          r'/Type\s*/Page[^s]',
        ).allMatches(String.fromCharCodes(b)).length;

        final bytes = await buildRecipePdf(
          recipe: bundt.copyWith(steps: [RecipeStep(number: 1, text: long)]),
          compress: false,
        );
        final base = await buildRecipePdf(
          recipe: bundt.copyWith(steps: [RecipeStep(number: 1, text: 'stir')]),
          compress: false,
        );
        const footerWords = 3;
        expect(
          painted(bytes) -
              painted(base) -
              footerWords * (pages(bytes) - pages(base)),
          words.length - 1,
          reason: 'an API-legal step must not lose a single word',
        );
      });

      test('the longest step the CORPUS holds prints in full', () async {
        // The cap is only honest if no real recipe reaches it. Measured from
        // all 1,198 recipes rather than assumed.
        final longest = loadAllCorpusRecipes()
            .expand((recipe) => recipe.steps)
            .map((step) => step.text)
            .reduce((a, b) => a.length >= b.length ? a : b);

        Future<({int words, int pages})> render(String text) async {
          final bytes = await buildRecipePdf(
            recipe: bundt.copyWith(steps: [RecipeStep(number: 1, text: text)]),
            compress: false,
          );
          final str = String.fromCharCodes(bytes);
          return (
            words: RegExp(r'\bTJ\b').allMatches(str).length,
            pages: RegExp(r'/Type\s*/Page[^s]').allMatches(str).length,
          );
        }

        final long = await render(longest);
        final short = await render('stir');
        // Every page prints a "N of M" footer, which is 3 more painted words
        // that belong to the page rather than to the step — and this step is
        // long enough to push the document onto a second one. Measured, not
        // assumed: 544 vs 291 words across 2 vs 1 pages.
        const footerWords = 3;
        final words = longest.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
        expect(
          long.words - short.words - footerWords * (long.pages - short.pages),
          words.length - 1,
          reason:
              'every word of the longest real step (${longest.length} '
              'chars) must be printed; the cap must not touch real data',
        );
      });
    });
  });
}
