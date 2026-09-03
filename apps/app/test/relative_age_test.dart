import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/util/relative_age.dart';

void main() {
  final now = DateTime.utc(2026, 9, 3, 12);
  test('reads as a person says it', () {
    String age(Duration ago) => relativeAge(now.subtract(ago), now: now);
    expect(age(const Duration(seconds: 5)), 'just now');
    expect(age(const Duration(minutes: 5)), '5 min ago');
    expect(age(const Duration(hours: 3)), '3 h ago');
    expect(age(const Duration(days: 2)), '2 d ago');
    expect(age(const Duration(days: 21)), '3 wk ago');
    expect(age(const Duration(days: 65)), '2 mo ago');
    expect(age(const Duration(days: 400)), '1 yr ago');
  });
}
