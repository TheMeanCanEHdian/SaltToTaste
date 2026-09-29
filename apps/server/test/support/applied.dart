import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:test/test.dart';

/// An apply-to-all receipt with these counts, whose `completedRecipes`
/// names exactly [completed] recipes ([completedRecipes] when given).
Matcher appliedIs({
  required int recipes,
  required int lines,
  required int failed,
  required int completed,
  List<String>? completedRecipes,
}) => isA<AppliedToOthers>()
    .having((a) => a.recipes, 'recipes', recipes)
    .having((a) => a.lines, 'lines', lines)
    .having((a) => a.failed, 'failed', failed)
    .having((a) => a.completed, 'completed', completed)
    .having(
      (a) => a.completedRecipes,
      'completedRecipes',
      completedRecipes ?? hasLength(completed),
    );
