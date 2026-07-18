import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// The search-DSL cheat sheet, opened from the `?` button inside the nav bar's
/// search field (desktop) and the mobile search dialog. The semantics follow
/// modern search conventions (documented decisions): a scope binds one term,
/// and adjacent terms all narrow the results.
void showSearchHelp(BuildContext context) {
  showFDialog<void>(
    context: context,
    builder: (context, _, animation) => FDialog(
      animation: animation,
      builder: (context, style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text('Search syntax', style: style.titleTextStyle),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _HelpRow('chicken soup', 'recipes containing both words'),
                  _HelpRow('"sweet potato"', 'exact phrase'),
                  _HelpRow('title:cake', 'scoped to the title (one word)'),
                  _HelpRow('title:"bundt cake"', 'scoped phrase'),
                  _HelpRow('tag:dessert or title:pie', 'either side'),
                  _HelpRow(
                    'ingredient:ginger and direction:"dutch oven"',
                    'combine scopes',
                  ),
                  _HelpRow('calories:<400', 'calorie filter (needs nutrition)'),
                  SizedBox(height: 10),
                  Text(
                    'Scopes: title, tag, ingredient, direction, note. '
                    'Words next to each other all need to match; use "or" to '
                    'broaden. Scopes apply to the single word or "quoted '
                    'phrase" after them.',
                    style: TextStyle(fontSize: 13, color: SaltColors.muted),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HelpRow extends StatelessWidget {
  const _HelpRow(this.example, this.meaning);

  final String example;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE9),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              example,
              style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              meaning,
              style: const TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
