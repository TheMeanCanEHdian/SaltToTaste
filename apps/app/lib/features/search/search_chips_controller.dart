import 'package:flutter/widgets.dart';
import 'package:salt_shared/salt_shared.dart';

/// Keeps a list of search [chips] in sync with a [TextEditingController] that
/// holds only the trailing free text. Both search inputs — the desktop nav-bar
/// field and the mobile search dialog — drive one of these, so their chip
/// behaviour cannot drift apart.
///
/// All the string work (what is a clause, how it serializes) lives in
/// `salt_shared`'s [parseSearchInput] / [serializeSearchInput] / [trailingChip];
/// this is only the controller glue: seed from a query, chip a completed clause
/// when a space lands after it, dissolve chips when an `or` appears (chips are
/// AND-only), pop the last chip back to text on Backspace, and serialize the
/// whole thing back out.
class SearchChipsController {
  SearchChipsController(this.controller);

  final TextEditingController controller;

  /// The committed clauses, in display order (left of the editing text).
  final List<SearchChip> chips = [];

  /// Guards the controller listener from re-entering while we rewrite the text
  /// ourselves (chipping, dissolving, popping all mutate the controller).
  bool _mutating = false;

  /// Seeds chips + text from an initial query (the results page's `?q=`), and
  /// returns the canonical form to compare later resubmits against.
  String seed(String? query) {
    final parsed = parseSearchInput(query ?? '');
    chips
      ..clear()
      ..addAll(parsed.chips);
    controller.text = parsed.text;
    return serializeSearchInput(chips, parsed.text);
  }

  /// The full DSL query for the current chips + editing text.
  String get query => serializeSearchInput(chips, controller.text);

  /// Reacts to a controller change (call from its listener). Returns true when
  /// [chips] changed, so the caller can rebuild.
  bool handleTextChange() {
    if (_mutating) {
      return false;
    }
    final text = controller.text;

    // An `or` makes the query non-conjunctive, which chips can't represent:
    // dissolve them back into the text so the whole thing is one plain query.
    if (chips.isNotEmpty && queryHasOr(text)) {
      final dissolved = serializeSearchInput(chips, text);
      chips.clear();
      _rewrite(dissolved, dissolved.length);
      return true;
    }

    // A space typed right after a completed scoped clause converts it to a chip.
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return false;
    }
    final caret = selection.baseOffset;
    if (caret < 1 || caret > text.length || text[caret - 1] != ' ') {
      return false;
    }
    if (queryHasOr(text)) {
      return false;
    }
    final hit = trailingChip(text.substring(0, caret - 1));
    if (hit == null) {
      return false;
    }
    chips.add(hit.chip);
    _rewrite(text.substring(0, hit.start) + text.substring(caret), hit.start);
    return true;
  }

  /// Backspace at the very start of the editing text pops the last chip back
  /// into the text so it can be corrected. Returns true when one was popped.
  bool popLastChip() {
    if (chips.isEmpty) {
      return false;
    }
    final chip = chips.removeLast();
    final existing = controller.text;
    final glue = existing.isNotEmpty && !existing.startsWith(' ') ? ' ' : '';
    _rewrite('${chip.raw}$glue$existing', chip.raw.length);
    return true;
  }

  /// Removes the chip at [index] (its ✕ was tapped).
  void removeChipAt(int index) => chips.removeAt(index);

  void _rewrite(String text, int caret) {
    _mutating = true;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _mutating = false;
  }
}
