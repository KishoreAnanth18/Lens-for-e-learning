import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lens_elearning/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LensELearningApp());
    expect(find.text('Welcome to Lens for E-Learning'), findsOneWidget);
  });
}
