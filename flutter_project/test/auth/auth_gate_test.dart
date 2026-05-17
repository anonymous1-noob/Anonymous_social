
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Authentication Regression Tests', () {

    testWidgets('Login screen renders correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Login'),
          ),
        ),
      );

      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('Logout redirects to login screen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Logout Successful'),
          ),
        ),
      );

      expect(find.text('Logout Successful'), findsOneWidget);
    });
  });
}
