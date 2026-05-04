class HashtagToken {
  final String text;
  final bool isTag;

  const HashtagToken(this.text, {required this.isTag});
}

final RegExp hashtagRegex = RegExp(r'(^|\s)(#[A-Za-z0-9_]+)');

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
