import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/tags_repository.dart';

/// App-wide tag chip styles, keyed by tag name.
///
/// Loaded once after sign-in and refreshed whenever the tag editor saves;
/// chips render with defaults until (and unless) the load completes, so a
/// failed load degrades gracefully instead of blocking anything.
class TagStylesCubit extends Cubit<Map<String, TagStyle>> {
  TagStylesCubit(this._tags) : super(const {});

  final TagsRepository _tags;

  /// Fetches the styles; failures are swallowed (chips keep defaults).
  Future<void> load() async {
    try {
      final tags = await _tags.listTags();
      if (isClosed) {
        return;
      }
      emit({
        for (final tag in tags)
          if (!tag.style.isEmpty) tag.name: tag.style,
      });
    } on Exception {
      // Styling is progressive enhancement — never break the UI over it.
    }
  }

  /// Forgets everything (sign-out).
  void clear() => emit(const {});
}
