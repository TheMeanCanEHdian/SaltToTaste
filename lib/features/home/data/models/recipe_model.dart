import '../../domain/entities/recipe.dart';

class RecipeModel extends Recipe {
  RecipeModel({
    // required int id,
    required String title,
  }) : super(
          // id: id,
          title: title,
        );

  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    return RecipeModel(
      // id: json['id'],
      title: json['title'],
    );
  }
}
