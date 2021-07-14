import 'package:equatable/equatable.dart';

class Tag extends Equatable {
  final int id;
  final String name;

  Tag({
    required this.id,
    required this.name,
  });

  @override
  List<Object?> get props => [
        id,
        name,
      ];
}
