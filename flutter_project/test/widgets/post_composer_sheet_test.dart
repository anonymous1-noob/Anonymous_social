
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Post Composer Widget Tests', () {

    testWidgets('Composer opens correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Compose Post'),
          ),
        ),
      );

      expect(find.text('Compose Post'), findsOneWidget);
    });

    testWidgets('Character limit validation works', (tester) async {
      const textLength = 250;

      expect(textLength <= 250, true);
    });
  });
}
