import '../../domain/entities/tag.dart';

class TagModel extends Tag {
  TagModel({
    required int id,
    required String name,
  }) : super(
          id: id,
          name: name,
        );

  factory TagModel.fromJson(Map<String, dynamic> json) {
    return TagModel(
      id: json['id'],
      name: json['name'],
    );
  }
}
