import 'package:dio/dio.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException, apiGuard;

/// A tag's chip style: a Lucide icon name plus `#RRGGBB` text/background
/// colors, each optional (null = the default 'raspberry' chip look).
class TagStyle {
  const TagStyle({this.icon, this.color, this.bgColor});

  final String? icon;
  final String? color;
  final String? bgColor;

  /// Whether every field is unset (renders as the default chip).
  bool get isEmpty => icon == null && color == null && bgColor == null;
}

/// One row of the tags listing: the tag, how many recipes carry it, and its
/// chip style.
class TagInfo {
  const TagInfo({required this.name, required this.count, required this.style});

  final String name;
  final int count;
  final TagStyle style;
}

/// Access to the tags API (listing for everyone; styling is admin-only
/// server-side).
class TagsRepository {
  TagsRepository(this._dio);

  final Dio _dio;

  /// Every tag with its recipe count and style, as the server orders them
  /// (by name).
  Future<List<TagInfo>> listTags() {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>('/api/v1/tags');
      final data = response.data;
      if (data is! Map<String, dynamic> || data['items'] is! List) {
        throw const RepositoryException(
          'The server returned an unexpected response. Please try again.',
        );
      }
      return [
        for (final raw in data['items'] as List<dynamic>)
          TagInfo(
            name: (raw as Map<String, dynamic>)['name']! as String,
            count: (raw['count']! as num).toInt(),
            style: TagStyle(
              icon: raw['icon'] as String?,
              color: raw['color'] as String?,
              bgColor: raw['bg_color'] as String?,
            ),
          ),
      ];
    });
  }

  /// Sets (or, with all-null fields, clears) a tag's chip style.
  Future<void> setStyle(String name, TagStyle style) {
    return apiGuard(() async {
      await _dio.put<dynamic>(
        '/api/v1/tags/${Uri.encodeComponent(name)}/style',
        data: {
          'icon': style.icon,
          'color': style.color,
          'bg_color': style.bgColor,
        },
      );
    });
  }
}
