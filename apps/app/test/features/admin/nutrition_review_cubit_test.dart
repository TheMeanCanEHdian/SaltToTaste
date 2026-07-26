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
}) => {
  'recipe': {'id': slug, 'slug': slug, 'title': slug.toUpperCase()},
  'position': position,
  'raw': '$position of $slug',
  'bucket': bucket,
  'match': description == null
      ? null
      : {
          'fdc_id': position,
          'description': description,
          'data_type': 'SR Legacy',
          'confidence': confidence,
          'grams': bucket == 'no_grams' ? null : 5,
          'gram_source': 'density',
          'status': 'auto',
        },
};

/// Serves `GET /api/v1/admin/nutrition_review` from a mutable line set, honoring
/// the `bucket` filter and paging — so a test can "fix" a line by removing it
/// and re-fetch, exactly as the queue does.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.lines);

  /// Worst-first, like the server. Tests mutate this to simulate fixes.
  List<Map<String, dynamic>> lines;

  static const _flagged = {'no_match', 'no_grams', 'check'};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bucket = options.queryParameters['bucket'] as String?;
    final page = int.parse(options.queryParameters['page'] as String? ?? '1');
    final limit = int.parse(
      options.queryParameters['limit'] as String? ?? '50',
    );

    int count(String b) => lines.where((l) => l['bucket'] == b).length;
    final total = lines.where((l) => _flagged.contains(l['bucket'])).length;

    final filtered = bucket == null || bucket.isEmpty
        ? lines.where((l) => _flagged.contains(l['bucket'])).toList()
        : lines.where((l) => l['bucket'] == bucket).toList();
    final offset = (page - 1) * limit;
    final items = filtered.skip(offset).take(limit).toList();

    return ResponseBody.fromString(
      jsonEncode({
        'total': total,
        'buckets': [
          {'id': 'no_match', 'label': 'No match', 'count': count('no_match')},
          {'id': 'no_grams', 'label': 'No grams', 'count': count('no_grams')},
          {'id': 'check', 'label': 'Low confidence', 'count': count('check')},
          {'id': 'skipped', 'label': 'Skipped', 'count': count('skipped')},
        ],
        'items': items,
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
    _line('risotto', 6, 'no_grams', confidence: 0.49, description: 'Rice flour'),
  ];

  NutritionReviewCubit cubitWith(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return NutritionReviewCubit(RecipeRepository(dio: dio));
  }

  test('load() fills the queue and auto-selects the worst (first) line', () async {
    final cubit = cubitWith(_FakeAdapter(seed()));
    await cubit.load();
    final state = cubit.state as NutritionReviewLoaded;
    expect(state.total, 3);
    expect(state.items.map((l) => l.key), ['soup#2', 'tatin#5', 'risotto#6']);
    // The fix pane is never blank while there is work: the first line is chosen.
    expect(state.selectedKey, 'soup#2');
    expect(state.selected?.recipe.slug, 'soup');
    await cubit.close();
  });

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

  test('completeFix() clamps to the new last line when the end was fixed', () async {
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
  });

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
}
