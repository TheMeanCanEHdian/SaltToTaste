import 'package:equatable/equatable.dart';

class Recipe extends Equatable {
  // final int id;
  final String title;

  Recipe({
    // required this.id,
    required this.title,
  });

  @override
  List<Object?> get props => [
        // id,
        title,
      ];
}
