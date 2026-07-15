import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:salt_app/app.dart';

void main() {
  // Clean path URLs on web (`/r/<slug>` instead of `/#/r/<slug>`); a no-op
  // on other platforms.
  usePathUrlStrategy();
  runApp(const SaltApp());
}
