extension StringExtension on String {
  String get capitalize => '${this[0].toUpperCase()}${substring(1)}';

  String get capitalizeEach =>
      split(' ').map((str) => str.capitalize).join(' ');
}
