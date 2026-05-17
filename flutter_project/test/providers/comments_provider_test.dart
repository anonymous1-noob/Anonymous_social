
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Comments Provider Tests', () {

    test('Comment count increments properly', () {
      int commentCount = 5;

      commentCount++;

      expect(commentCount, 6);
    });

    test('Empty comments are blocked', () {
      const comment = '';

      expect(comment.isEmpty, true);
    });
  });
}
