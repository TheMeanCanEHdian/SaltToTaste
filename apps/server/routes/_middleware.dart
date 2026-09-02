import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/bootstrap.dart';

/// dart_frog's fixed entry point. Delegates to [buildAppMiddleware] (which
/// lives in `lib/` so a test can drive the real chain) with the process-wide
/// singletons created at startup by `initServer`. The chain order and its
/// security-relevant properties are documented and pinned there.
Handler middleware(Handler handler) => buildAppMiddleware(
  handler,
  config: serverConfig,
  database: saltDatabase,
  authRuntime: authRuntime,
  nutritionProvider: nutritionProvider,
  bulkNutritionProvider: bulkNutritionProvider,
  searchRateLimiter: searchRateLimiter,
  // A thunk, not a value: this chain is built before initSearchService() runs,
  // so reading the getter eagerly here would freeze the InlineSearchService
  // fallback into the provider and never use the isolate pool (#48 review).
  searchService: () => searchService,
  logStore: logStore,
);
