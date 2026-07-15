/// Deep-converts a `package:yaml` node tree (`YamlMap`/`YamlList` and
/// wrapped scalars) into plain Dart `Map<String, Object?>` / `List<Object?>`
/// / scalar values, so the result is safe to `jsonEncode` and to hand to a
/// `dart_mappable` `fromMap`.
///
/// Map keys are stringified. This is the single definition shared by the
/// recipe codec and the server's `source.yaml` reader.
Object? yamlToPlain(Object? node) {
  if (node is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in node.entries)
        entry.key.toString(): yamlToPlain(entry.value),
    };
  }
  if (node is List) {
    return <Object?>[for (final Object? item in node) yamlToPlain(item)];
  }
  return node;
}
