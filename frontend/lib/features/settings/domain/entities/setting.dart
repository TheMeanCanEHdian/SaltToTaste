import 'package:equatable/equatable.dart';

class Setting extends Equatable {
  final String section;
  final String name;
  final String value;

  Setting({
    required this.section,
    required this.name,
    required this.value,
  });

  Setting copyWith({
    String? section,
    String? name,
    String? value,
  }) {
    return Setting(
      section: section ?? this.section,
      name: name ?? this.name,
      value: value ?? this.value,
    );
  }

  @override
  List<Object?> get props => [section, name, value];
}
