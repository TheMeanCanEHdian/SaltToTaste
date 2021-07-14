import 'call_salt_to_taste.dart';

abstract class Recipe {
  Future call({
    required String titleSanitized,
  });
}

class RecipeImpl implements Recipe {
  final CallSaltToTaste callSaltToTaste;

  RecipeImpl({
    required this.callSaltToTaste,
  });

  @override
  Future call({
    required String titleSanitized,
  }) async {
    final responseJson = await callSaltToTaste(
      endpoint: 'recipe/$titleSanitized',
    );

    return responseJson;
  }
}
