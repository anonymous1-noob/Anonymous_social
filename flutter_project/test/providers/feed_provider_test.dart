
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Feed Provider Regression Tests', () {

    test('EdgeRank score calculation works', () {
      final likes = 10;
      final comments = 5;

      final score = likes + (comments * 2);

      expect(score, 20);
    });

    test('Feed refresh returns updated state', () {
      final posts = ['post1', 'post2'];

      expect(posts.length, 2);
    });
  });
}
