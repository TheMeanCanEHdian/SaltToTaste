import 'package:flutter/material.dart';

import 'configure_nonweb.dart' if (dart.library.html) 'configure_web.dart';
import 'salt_to_taste.dart';

void main() {
  configureApp();
  runApp(
    SaltToTaste(),
  );
}
