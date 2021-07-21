import 'call_salt_to_taste.dart';

abstract class RecipeList {
  Future call();
}

class RecipeListImpl implements RecipeList {
  final CallSaltToTaste callSaltToTaste;

  RecipeListImpl({
    required this.callSaltToTaste,
  });

  @override
  Future call() async {
    final responseJson = await callSaltToTaste(
      requestMethod: RequestMethod.get,
      endpoint: 'recipe_list',
    );

    return responseJson;
  }
}
