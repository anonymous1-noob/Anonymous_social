class HashtagToken {
  final String text;
  final bool isTag;

  const HashtagToken(this.text, {required this.isTag});
}

/// Matches hashtags that start at the beginning of the string or after a
/// non-word character. Valid tag characters are ASCII letters, numbers, and
/// underscores so the client parser matches the database indexer.
final RegExp hashtagRegex = RegExp(r'(^|[^A-Za-z0-9_])(#[A-Za-z0-9_]+)');

String normalizeHashtag(String tag) {
  final trimmed = tag.trim();
  final withoutPrefix = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  return withoutPrefix.toLowerCase();
}

String displayHashtag(String tag) {
  final normalized = normalizeHashtag(tag);
  return normalized.isEmpty ? '#' : '#$normalized';
}

List<String> extractHashtags(String input) {
  final tags = <String>{};
  for (final match in hashtagRegex.allMatches(input)) {
    final tag = match.group(2);
    if (tag == null || tag.isEmpty) continue;
    final normalized = normalizeHashtag(tag);
    if (normalized.isNotEmpty) tags.add(normalized);
  }
  return tags.toList()..sort();
}

List<HashtagToken> tokenizeHashtags(String input) {
  final tokens = <HashtagToken>[];
  var cursor = 0;

  for (final m in hashtagRegex.allMatches(input)) {
    final fullStart = m.start;
    final tagStart = m.start + (m.group(1)?.length ?? 0);
    final tagEnd = m.end;

    if (fullStart > cursor) {
      tokens.add(HashtagToken(input.substring(cursor, fullStart), isTag: false));
    }

    if (tagStart > fullStart) {
      tokens.add(HashtagToken(input.substring(fullStart, tagStart), isTag: false));
    }

    tokens.add(HashtagToken(input.substring(tagStart, tagEnd), isTag: true));
    cursor = tagEnd;
  }

  if (cursor < input.length) {
    tokens.add(HashtagToken(input.substring(cursor), isTag: false));
  }

  if (tokens.isEmpty) tokens.add(HashtagToken(input, isTag: false));
  return tokens;
}
