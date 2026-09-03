import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// Names the browser tab (and the platform task switcher) after the page
/// that is CURRENT — the recipe's name on a recipe, "Favorites", and so on.
///
/// Flutter's own [Title] sets the name when it BUILDS, which is the wrong
/// moment for a routed app: coming back from an edit page, the recipe page
/// underneath is not rebuilt, so the tab kept saying "Edit". This one also
/// re-asserts its name whenever its route becomes current again —
/// [ModalRoute.of] registers a dependency that fires on that change — and
/// stays quiet while another route is on top.
class DocumentTitle extends StatefulWidget {
  const DocumentTitle({required this.child, this.title, super.key});

  /// The page's own name; null for the bare app name.
  final String? title;
  final Widget child;

  static const String appName = 'Salt to Taste';

  /// What the tab reads for [title]: "Favorites · Salt to Taste".
  static String label(String? title) =>
      title == null || title.isEmpty ? appName : '$title · $appName';

  @override
  State<DocumentTitle> createState() => _DocumentTitleState();
}

class _DocumentTitleState extends State<DocumentTitle> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  @override
  void didUpdateWidget(DocumentTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _apply();
    }
  }

  void _apply() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return; // another page is on top; its own title stands
    }

    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: DocumentTitle.label(widget.title),
        primaryColor: SaltColors.maroon.toARGB32(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
