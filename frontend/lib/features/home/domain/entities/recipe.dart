import 'package:equatable/equatable.dart';

class Recipe extends Equatable {
  final int id;
  final String title;
  final String titleSanitized;

  Recipe({
    required this.id,
    required this.title,
    this.titleSanitized = '',
  });

  @override
  List<Object?> get props => [
        id,
        title,
        titleSanitized,
      ];
}
