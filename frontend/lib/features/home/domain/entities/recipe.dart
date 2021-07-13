import 'package:equatable/equatable.dart';

import 'tag.dart';

class Recipe extends Equatable {
  final int id;
  final String title;
  final String titleSanitized;
  final List<Tag> tags;

  Recipe({
    required this.id,
    required this.title,
    this.titleSanitized = '',
    this.tags = const [],
  });

  @override
  List<Object?> get props => [
        id,
        title,
        titleSanitized,
        tags,
      ];
}
