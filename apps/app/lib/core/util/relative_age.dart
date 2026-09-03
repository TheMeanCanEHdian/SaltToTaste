/// How long ago [then] was, as a person says it: "just now", "5 min ago",
/// "3 h ago", "2 d ago", "3 wk ago", "2 mo ago", "1 yr ago". Coarse on
/// purpose — the exact instant belongs in a tooltip, not in the sentence.
String relativeAge(DateTime then, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(then);
  if (delta.inSeconds < 60) {
    return 'just now';
  }
  if (delta.inMinutes < 60) {
    return '${delta.inMinutes} min ago';
  }
  if (delta.inHours < 24) {
    return '${delta.inHours} h ago';
  }
  if (delta.inDays < 7) {
    return '${delta.inDays} d ago';
  }
  if (delta.inDays < 30) {
    return '${delta.inDays ~/ 7} wk ago';
  }
  if (delta.inDays < 365) {
    return '${delta.inDays ~/ 30} mo ago';
  }
  return '${delta.inDays ~/ 365} yr ago';
}
