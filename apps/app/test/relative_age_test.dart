import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/util/relative_age.dart';

void main() {
  final now = DateTime.utc(2026, 9, 3, 12);
  test('each tier starts exactly at its boundary', () {
    String age(Duration ago) => relativeAge(now.subtract(ago), now: now);
    expect(age(const Duration(seconds: 59)), 'just now');
    expect(age(const Duration(seconds: 60)), '1 min ago');
    expect(age(const Duration(minutes: 59)), '59 min ago');
    expect(age(const Duration(minutes: 60)), '1 h ago');
    expect(age(const Duration(hours: 23)), '23 h ago');
    expect(age(const Duration(hours: 24)), '1 d ago');
    expect(age(const Duration(days: 6)), '6 d ago');
    expect(age(const Duration(days: 7)), '1 wk ago');
    expect(age(const Duration(days: 29)), '4 wk ago');
    expect(age(const Duration(days: 30)), '1 mo ago');
    expect(age(const Duration(days: 62)), '2 mo ago');
    expect(age(const Duration(days: 364)), '12 mo ago');
    expect(age(const Duration(days: 365)), '1 yr ago');
    expect(age(const Duration(days: 731)), '2 yr ago');
  });

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
