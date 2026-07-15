import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';

final RegExp _colorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _iconPattern = RegExp(r'^[a-z0-9-]{1,50}$');

/// `GET /api/v1/tags` — every tag with its recipe count and chip style.
Map<String, Object?> listTagsHandler(SaltDatabase db) => {
      'items': [
        for (final tag in db.listTags())
          {
            'name': tag.name,
            'count': tag.count,
            'icon': tag.icon,
            'color': tag.color,
            'bg_color': tag.bgColor,
          },
      ],
    };

/// `PUT /api/v1/tags/<name>/style` (admin) — set the chip style: a Lucide
/// [icon] name and `#RRGGBB` colors, each optional (null clears it).
Map<String, Object?> putTagStyleHandler(
  SaltDatabase db,
  String name, {
  String? icon,
  String? color,
  String? bgColor,
}) {
  final tag = name.trim().toLowerCase();
  if (tag.isEmpty || tag.length > 60) {
    throw const ValidationException('Tag name must be 1-60 characters.');
  }
  if (icon != null && !_iconPattern.hasMatch(icon)) {
    throw const ValidationException(
      'Icon must be a Lucide icon name (lowercase letters, digits, dashes).',
    );
  }
  for (final (field, value) in [('color', color), ('bg_color', bgColor)]) {
    if (value != null && !_colorPattern.hasMatch(value)) {
      throw ValidationException("'$field' must be #RRGGBB.");
    }
  }
  db.upsertTagStyle(tag, icon: icon, color: color, bgColor: bgColor);
  return {
    'tag': {
      'name': tag,
      'icon': icon,
      'color': color,
      'bg_color': bgColor,
    },
  };
}
