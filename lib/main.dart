import 'package:flutter/material.dart';

import 'configure_nonweb.dart' if (dart.library.html) 'configure_web.dart';
import 'injection_container.dart' as di;
import 'salt_to_taste.dart';

void main() async {
  configureApp();
  await di.init();
  runApp(
    SaltToTaste(),
  );
}
