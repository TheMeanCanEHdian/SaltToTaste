import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/admin/recipe_review_cubit.dart';
import 'package:salt_shared/salt_shared.dart';

/// The whole-library report, filtered to [issue] when set — mirrors the server.
RecipeReviewReport _report(String? issue) {
  RecipeReviewItem item(String id, String check) => RecipeReviewItem(
    id: id,
    slug: id,
    title: id.toUpperCase(),
    source: 'atk',
    issues: [RecipeReviewIssue(check: check, label: check, detail: 'd')],
  );
  final all = [item('r1', 'no_instructions'), item('r2', 'no_servings')];
  final items = issue == null
      ? all
      : all.where((i) => i.issues.any((x) => x.check == issue)).toList();
  return RecipeReviewReport(
    total: all.length,
    categories: const [
      RecipeReviewCategory(
        id: 'no_instructions',
        label: 'No instructions',
        description: 'd',
        count: 1,
      ),
      RecipeReviewCategory(
        id: 'no_servings',
        label: 'No servings',
        description: 'd',
        count: 1,
      ),
    ],
    items: items,
    page: 1,
    limit: RecipeReviewCubit.pageSize,
  );
}

/// Serves the report from the `issue` query param; optionally 500s a filtered
/// request so we can exercise `filter()`'s failure path.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.failFiltered = false});

  final bool failFiltered;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final issue = options.queryParameters['issue'] as String?;
    if (failFiltered && issue != null && issue.isNotEmpty) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'internal', 'message': 'boom'},
        }),
        500,
        headers: _json,
      );
    }
    RecipeReviewReportMapper.ensureInitialized();
    return ResponseBody.fromString(
      jsonEncode(_report(issue == null || issue.isEmpty ? null : issue).toMap()),
      200,
      headers: _json,
    );
  }

  @override
  void close({bool force = false}) {}

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };
}

void main() {
  RecipeReviewCubit cubitWith(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return RecipeReviewCubit(RecipeRepository(dio: dio));
  }

  test('filter() applies the new issue when the fetch succeeds', () async {
    final cubit = cubitWith(_FakeAdapter());
    await cubit.load();
    await cubit.filter('no_instructions');
    final state = cubit.state as RecipeReviewLoaded;
    expect(state.issue, 'no_instructions');
    expect(state.items.map((i) => i.id), ['r1']);
    await cubit.close();
  });

  test('filter() reverts to the previous state when the fetch fails', () async {
    final cubit = cubitWith(_FakeAdapter(failFiltered: true));
    await cubit.load();
    final before = cubit.state as RecipeReviewLoaded;
    expect(before.issue, isNull);
    final itemsBefore = before.items.map((i) => i.id).toList();

    await cubit.filter('no_instructions'); // the filtered fetch 500s

    final after = cubit.state as RecipeReviewLoaded;
    // The chip reverts to match the items still on screen, instead of being
    // left selected over the previous filter's list.
    expect(
      after.issue,
      isNull,
      reason: 'chip reverted so it agrees with the visible items',
    );
    expect(after.items.map((i) => i.id), itemsBefore);
    await cubit.close();
  });
}
