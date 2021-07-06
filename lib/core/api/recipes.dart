import 'call_salt_to_taste.dart';

abstract class Recipes {
  Future call();
}

class RecipesImpl implements Recipes {
  final CallSaltToTaste callSaltToTaste;

  RecipesImpl({
    required this.callSaltToTaste,
  });

  @override
  Future call() async {
    final responseJson = await callSaltToTaste(
      endpoint: 'recipes',
    );

    return responseJson;
  }
}
