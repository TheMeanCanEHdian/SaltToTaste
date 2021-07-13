import 'call_salt_to_taste.dart';

abstract class RecipeList {
  Future call();
}

class RecipesImpl implements RecipeList {
  final CallSaltToTaste callSaltToTaste;

  RecipesImpl({
    required this.callSaltToTaste,
  });

  @override
  Future call() async {
    final responseJson = await callSaltToTaste(
      endpoint: 'recipe_list',
    );

    return responseJson;
  }
}
