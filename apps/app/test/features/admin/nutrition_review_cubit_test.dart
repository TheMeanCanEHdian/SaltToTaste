import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/admin/nutrition_review_cubit.dart';

/// One flagged line, as the server would emit it.
Map<String, dynamic> _line(
  String slug,
  int position,
  String bucket, {
  double? confidence,
  String? description,
  String? itemKey,
  String? item,
  String? raw,
  double? grams,
}) => {
  'recipe': {'id': slug, 'slug': slug, 'title': slug.toUpperCase()},
  'position': position,
  'raw': raw ?? '$position of $slug',
  'bucket': bucket,
  if (itemKey != null) 'item_key': itemKey,
  if (item != null) 'item': item,
  'match': description == null
      ? null
      : {
          'fdc_id': position,
          'description': description,
          'data_type': 'SR Legacy',
          'confidence': confidence,
          'grams': bucket == 'no_grams' ? null : (grams ?? 5),
          'gram_source': 'density',
          'status': 'auto',
        },
};

double _confidenceOf(Map<String, dynamic> line) {
  final match = line['match'] as Map<String, dynamic>?;
  // A no-match row stores 0.0, not null — so no-food groups interleave with
  // the 0% weak ones instead of leading as a block.
  return (match?['confidence'] as num?)?.toDouble() ?? 0;
}

double? _gramsOf(Map<String, dynamic> line) =>
    ((line['match'] as Map<String, dynamic>?)?['grams'] as num?)?.toDouble();

/// The server's grouping, in miniature: `item_key` joins the members (a null
/// or empty key is a group of one keyed by its own recipe#position), the
/// example is the lowest-confidence member, and the aggregates come off the
/// same members. Kept faithful so the cubit is exercised against the real
/// shape rather than a hand-written one.
List<Map<String, dynamic>> _groupsOf(List<Map<String, dynamic>> lines) {
  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final line in lines) {
    final key = line['item_key'] as String? ?? '';
    final gkey = key.isEmpty
        ? '${(line['recipe']! as Map)['slug']}#${line['position']}'
        : key;
    byKey.putIfAbsent(gkey, () => []).add(line);
  }
  final groups = <Map<String, dynamic>>[];
  for (final entry in byKey.entries) {
    final members = [...entry.value]
      ..sort((a, b) => _confidenceOf(a).compareTo(_confidenceOf(b)));
    final example = members.first;
    final grams = members.map(_gramsOf).toList();
    final present = grams.whereType<double>().toList()..sort();
    groups.add({
      ...example,
      'item_key': example['item_key'] as String? ?? '',
      'lines': members.length,
      'recipes': members
          .map((m) => (m['recipe']! as Map)['slug'])
          .toSet()
          .length,
      'decided': example['decided'] ?? false,
      'grams': {
        'min': present.isEmpty ? null : present.first,
        'max': present.isEmpty ? null : present.last,
        'missing': grams.length - present.length,
      },
    });
  }
  groups.sort((a, b) {
    final worst = _confidenceOf(a).compareTo(_confidenceOf(b));
    if (worst != 0) {
      return worst;
    }
    return (b['lines']! as int).compareTo(a['lines']! as int);
  });
  return groups;
}

/// Serves `GET /api/v1/admin/nutrition_review` from a mutable line set,
/// honoring the `bucket` filter, `group=item` and paging — so a test can "fix"
/// a line by removing it and re-fetch, exactly as the queue does.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.lines);

  /// Worst-first, like the server. Tests mutate this to simulate fixes.
  List<Map<String, dynamic>> lines;

  /// Every request, so a test can assert on the query the repository built.
  final List<Map<String, dynamic>> queries = [];

  static const _flagged = {'no_match', 'no_grams', 'check'};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    queries.add(options.queryParameters);
    final bucket = options.queryParameters['bucket'] as String?;
    final grouped = options.queryParameters['group'] == 'item';
    final page = int.parse(options.queryParameters['page'] as String? ?? '1');
    final limit = int.parse(
      options.queryParameters['limit'] as String? ?? '50',
    );

    List<Map<String, dynamic>> inBucket(String b) =>
        lines.where((l) => l['bucket'] == b).toList();
    final flagged = lines.where((l) => _flagged.contains(l['bucket'])).toList();

    final filtered = bucket == null || bucket.isEmpty
        ? flagged
        : inBucket(bucket);
    // `item_key` / `item` / `decided` are the seed's grouping bookkeeping —
    // in line mode the server emits none of them.
    final rows = grouped
        ? _groupsOf(filtered)
        : [
            for (final l in filtered)
              {...l}
                ..remove('item_key')
                ..remove('item')
                ..remove('decided'),
          ];
    final offset = (page - 1) * limit;

    return ResponseBody.fromString(
      jsonEncode({
        'total': flagged.length,
        'groups': _groupsOf(flagged).length,
        'buckets': [
          for (final id in ['no_match', 'no_grams', 'check', 'skipped'])
            {
              'id': id,
              'label': switch (id) {
                'no_match' => 'No match',
                'no_grams' => 'No grams',
                'check' => 'Low confidence',
                _ => 'Skipped',
              },
              'count': inBucket(id).length,
              'groups': _groupsOf(inBucket(id)).length,
            },
        ],
        'items': rows.skip(offset).take(limit).toList(),
        'page': page,
        'limit': limit,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // Three flagged lines, worst-first, spanning three recipes/buckets.
  List<Map<String, dynamic>> seed() => [
    _line('soup', 2, 'no_match'),
    _line('tatin', 5, 'check', confidence: 0.41, description: 'Candy bar'),
    _line(
      'risotto',
      6,
      'no_grams',
      confidence: 0.49,
      description: 'Rice flour',
    ),
  ];

  /// Real flagged lines from the approved mockup (the 69-recipe diagnostic
  /// sweep): one five-line ingredient group, one two-line group, one single.
  List<Map<String, dynamic>> corpusSeed() => [
    for (final (slug, position, raw, grams) in [
      (
        'cheesy-nachos',
        2,
        '2 large jalapeño chiles, sliced thin (about ¼ cup)',
        28.0,
      ),
      (
        'chili-con-carne',
        10,
        '4–5 small jalapeño chiles, stemmed, seeded, and minced',
        63.0,
      ),
      (
        'crispy-salt-and-pepper-shrimp',
        9,
        '2 jalapeño chiles, stemmed, seeded, and sliced into ⅛-inch-thick rings',
        28.0,
      ),
      (
        'steak-tacos',
        2,
        '1 medium jalapeño chile, stemmed and roughly chopped',
        14.0,
      ),
      ('white-chicken-chili', 3, '3 medium jalapeño chiles', 42.0),
    ])
      _line(
        slug,
        position,
        'check',
        confidence: 0.495,
        description: 'Peppers, jalapeno, seeded, raw',
        itemKey: 'jalapeno chile',
        item: 'jalapeño chiles',
        raw: raw,
        grams: grams,
      ),
    for (final (slug, position) in [
      ('sous-vide-creme-brulee', 4),
      ('pear-crisp', 11),
    ])
      _line(
        slug,
        position,
        'no_grams',
        confidence: 1,
        description: 'Salt, table',
        itemKey: 'table salt',
        item: 'table salt',
        raw: 'Pinch table salt',
      ),
    _line(
      'dakgangjeong',
      5,
      'no_match',
      raw: '2–3 tablespoons gochujang',
      itemKey: 'gochujang',
      item: 'gochujang',
    ),
  ];

  NutritionReviewCubit cubitWith(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return NutritionReviewCubit(RecipeRepository(dio: dio));
  }

  test(
    'load() fills the queue and auto-selects the worst (first) line',
    () async {
      final cubit = cubitWith(_FakeAdapter(seed()));
      await cubit.load();
      final state = cubit.state as NutritionReviewLoaded;
      expect(state.total, 3);
      expect(state.items.map((l) => l.key), ['soup#2', 'tatin#5', 'risotto#6']);
      // The fix pane is never blank while there is work: the first line is chosen.
      expect(state.selectedKey, 'soup#2');
      expect(state.selected?.recipe.slug, 'soup');
      await cubit.close();
    },
  );

  test('filter() narrows to one bucket and selects its first line', () async {
    final cubit = cubitWith(_FakeAdapter(seed()));
    await cubit.load();
    await cubit.filter('check');
    final state = cubit.state as NutritionReviewLoaded;
    expect(state.bucket, 'check');
    expect(state.items.map((l) => l.key), ['tatin#5']);
    expect(state.selectedKey, 'tatin#5');
    // Bucket counts stay whole-library so the chips are stable across filters.
    expect(state.total, 3);
    await cubit.close();
  });

  test('select() moves the fix pane to another line', () async {
    final cubit = cubitWith(_FakeAdapter(seed()));
    await cubit.load();
    cubit.select('risotto#6');
    expect((cubit.state as NutritionReviewLoaded).selected?.position, 6);
    await cubit.close();
  });

  test('completeFix() drops the fixed line and advances to the next', () async {
    final adapter = _FakeAdapter(seed());
    final cubit = cubitWith(adapter);
    await cubit.load();
    expect((cubit.state as NutritionReviewLoaded).selectedKey, 'soup#2');

    // Simulate the fix: the server no longer flags soup#2.
    adapter.lines = adapter.lines
        .where((l) => l['recipe']['slug'] != 'soup')
        .toList();
    await cubit.completeFix();

    final state = cubit.state as NutritionReviewLoaded;
    expect(state.items.map((l) => l.key), ['tatin#5', 'risotto#6']);
    expect(state.total, 2);
    // The line that took the fixed one's place is now selected.
    expect(state.selectedKey, 'tatin#5');
    await cubit.close();
  });

  test(
    'completeFix() clamps to the new last line when the end was fixed',
    () async {
      final adapter = _FakeAdapter(seed());
      final cubit = cubitWith(adapter);
      await cubit.load();
      cubit.select('risotto#6'); // the last line

      adapter.lines = adapter.lines
          .where((l) => l['recipe']['slug'] != 'risotto')
          .toList();
      await cubit.completeFix();

      final state = cubit.state as NutritionReviewLoaded;
      // Index 2 no longer exists → clamp to the new last (tatin#5).
      expect(state.selectedKey, 'tatin#5');
      await cubit.close();
    },
  );

  test('completeFix() clears the selection when the queue empties', () async {
    final adapter = _FakeAdapter(seed());
    final cubit = cubitWith(adapter);
    await cubit.load();

    adapter.lines = [];
    await cubit.completeFix();

    final state = cubit.state as NutritionReviewLoaded;
    expect(state.items, isEmpty);
    expect(state.selectedKey, isNull);
    await cubit.close();
  });

  test('the repository parses a group item and asks for group=item', () async {
    // The jalapeño group, already decided (the offer was declined once).
    final adapter = _FakeAdapter([
      for (final l in corpusSeed())
        if (l['item_key'] == 'jalapeno chile') {...l, 'decided': true} else l,
    ]);
    final repo = RecipeRepository(
      dio: Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter,
    );
    final report = await repo.getNutritionReview(
      page: 1,
      bucket: 'check',
      grouped: true,
    );
    expect(adapter.queries.last['group'], 'item');
    expect(report.groups, 3);
    expect(report.buckets.firstWhere((b) => b.id == 'check').groups, 1);
    expect(report.buckets.firstWhere((b) => b.id == 'check').count, 5);

    final group = report.items.single;
    expect(group.itemKey, 'jalapeno chile');
    expect(group.item, 'jalapeño chiles');
    expect(group.lines, 5);
    expect(group.recipes, 5);
    expect(group.decided, isTrue);
    expect(group.gramsMin, 14);
    expect(group.gramsMax, 63);
    expect(group.gramsMissing, 0);
    // The key is still the EXAMPLE line's, so select() and the fix pane are
    // untouched by grouping.
    expect(group.key, 'cheesy-nachos#2');
    expect(group.raw, startsWith('2 large jalapeño chiles'));

    // A line item carries the single-line defaults, so one row widget serves
    // both views.
    final lines = await repo.getNutritionReview(page: 1, bucket: 'check');
    expect(lines.items, hasLength(5));
    expect(lines.items.first.lines, 1);
    expect(lines.items.first.recipes, 1);
    expect(lines.items.first.decided, isFalse);
    expect(lines.items.first.gramsMissing, 0);
    expect(lines.items.first.gramsMin, isNull);
  });

  group('grouped view', () {
    test(
      'the food buckets open grouped, the amount buckets open in lines',
      () async {
        final adapter = _FakeAdapter(corpusSeed());
        final cubit = cubitWith(adapter);
        await cubit.load();
        var state = cubit.state as NutritionReviewLoaded;
        expect(state.grouped, isTrue, reason: 'all flagged is a food view');
        expect(adapter.queries.last['group'], 'item');
        // 8 flagged lines are 3 ingredients; the chips keep counting lines.
        expect(state.total, 8);
        expect(state.groups, 3);
        expect(state.items, hasLength(3));

        await cubit.filter('no_grams');
        state = cubit.state as NutritionReviewLoaded;
        expect(state.grouped, isFalse, reason: 'an amount is per line');
        expect(adapter.queries.last.containsKey('group'), isFalse);
        expect(state.items, hasLength(2));

        await cubit.filter('skipped');
        expect((cubit.state as NutritionReviewLoaded).grouped, isFalse);
        await cubit.close();
      },
    );

    test(
      'a flip is remembered for that bucket, and Skipped never groups',
      () async {
        final cubit = cubitWith(_FakeAdapter(corpusSeed()));
        await cubit.load();
        await cubit.filter('no_grams');
        await cubit.setGrouped(true);
        expect((cubit.state as NutritionReviewLoaded).grouped, isTrue);
        expect((cubit.state as NutritionReviewLoaded).items, hasLength(1));

        // Away and back: the flip survives the trip through another chip.
        await cubit.filter('check');
        expect((cubit.state as NutritionReviewLoaded).grouped, isTrue);
        await cubit.filter('no_grams');
        expect((cubit.state as NutritionReviewLoaded).grouped, isTrue);

        // …and the default is untouched for a bucket nobody flipped.
        expect(cubit.groupedFor('skipped'), isFalse);
        await cubit.setGrouped(true);
        await cubit.filter('skipped');
        expect((cubit.state as NutritionReviewLoaded).grouped, isFalse);
        await cubit.close();
      },
    );

    test('setGrouped(false) swaps the unit and reloads from page 1', () async {
      final adapter = _FakeAdapter(corpusSeed());
      final cubit = cubitWith(adapter);
      await cubit.load();
      await cubit.setGrouped(false);
      final state = cubit.state as NutritionReviewLoaded;
      expect(state.grouped, isFalse);
      expect(state.items, hasLength(8));
      expect(adapter.queries.last['page'], '1');
      expect(adapter.queries.last.containsKey('group'), isFalse);
      await cubit.close();
    });

    test('hasMore compares against GROUPS in the grouped view', () async {
      final adapter = _FakeAdapter(corpusSeed());
      final cubit = cubitWith(adapter);
      await cubit.load();
      final state = cubit.state as NutritionReviewLoaded;
      // 3 of 3 groups on screen — but 3 of 8 LINES, which is what the old
      // comparison saw, and it offered a "Load more" that returned nothing.
      expect(state.filteredTotal, 3);
      expect(state.groupsTotal, 3);
      expect(state.linesTotal, 8);
      expect(state.hasMore, isFalse);
      await cubit.close();
    });

    test('a filtered grouped view counts that bucket only', () async {
      final cubit = cubitWith(_FakeAdapter(corpusSeed()));
      await cubit.load();
      await cubit.filter('check');
      final state = cubit.state as NutritionReviewLoaded;
      expect(state.grouped, isTrue);
      expect(state.groupsTotal, 1);
      expect(state.linesTotal, 5);
      expect(state.items.single.itemKey, 'jalapeno chile');
      expect(state.items.single.lines, 5);
      expect(state.items.single.recipes, 5);
      // The example is a real member, so selection still keys slug#position.
      expect(state.selectedKey, state.items.single.key);
      await cubit.close();
    });
  });
}
