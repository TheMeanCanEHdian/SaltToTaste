import '../../domain/entities/recipe.dart';

class RecipeModel extends Recipe {
  RecipeModel({
    required int id,
    required String title,
    String titleSanitized = '',
  }) : super(
          id: id,
          title: title,
          titleSanitized: titleSanitized,
        );

  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    return RecipeModel(
      id: json['id'],
      title: json['title'],
      titleSanitized: json['title_sanitized'],
    );
  }
}
