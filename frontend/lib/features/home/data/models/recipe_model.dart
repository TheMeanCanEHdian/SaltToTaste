import '../../domain/entities/recipe.dart';
import '../../domain/entities/tag.dart';
import 'tag_model.dart';

class RecipeModel extends Recipe {
  RecipeModel({
    required int id,
    required String title,
    String titleSanitized = '',
    List<Tag> tags = const [],
  }) : super(
          id: id,
          title: title,
          titleSanitized: titleSanitized,
          tags: tags,
        );

  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    List<Tag> tags = [];
    for (var tag in json['tags']) {
      tags.add(TagModel.fromJson(tag));
    }

    return RecipeModel(
      id: json['id'],
      title: json['title'],
      titleSanitized: json['title_sanitized'],
      tags: tags,
    );
  }
}
