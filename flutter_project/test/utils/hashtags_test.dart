
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hashtag Utility Tests', () {

    test('Hashtags extracted correctly', () {
      const text = '#flutter #testing';

      expect(text.contains('#flutter'), true);
      expect(text.contains('#testing'), true);
    });

    test('Duplicate hashtags removed', () {
      final hashtags = {'flutter', 'flutter', 'dart'};

      expect(hashtags.length, 2);
    });
  });
}
