import 'package:flutter/material.dart';

import 'injection_container.dart' as di;
import 'salt_to_taste.dart';

void main() async {
  await di.init();
  runApp(
    SaltToTaste(),
  );
}
