import 'package:flutter_test/flutter_test.dart';
import 'package:lens_elearning/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LensELearningApp());
    await tester.pump();
    expect(find.text('Sign In'), findsOneWidget);
  });
}
