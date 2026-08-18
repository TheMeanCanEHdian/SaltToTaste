import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/http/method_guard.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/services/import_job.dart';

/// `GET /api/v1/import/candidates` (admin) — the import directory's
/// absolute path and the source folders detected inside it (depth ≤ 1):
/// `{import_dir, items: [{path, kind: "v1"|"legacy", file_count}]}`.
Response onRequest(RequestContext context) {
  requireGet(context);
  requireAdmin(context);
  // Not cross-site drivable: the walk below reads the import directory and
  // every direct child SYNCHRONOUSLY on the serving isolate, counting every
  // YAML file in each (~1,200 dirents for a real corpus root), and
  // requireCsrf gates mutating METHODS only. Above every line below it,
  // because the guard exists to stop the COST — a refusal thrown after the
  // walk has run is not a guard, it is a receipt.
  requireNotCrossSite(context);
  final config = context.read<ServerConfig>();
  return Response.json(
    body: {
      'import_dir': config.importDir,
      'items': [
        for (final candidate in importCandidates(config)) candidate.toJson(),
      ],
    },
  );
}
