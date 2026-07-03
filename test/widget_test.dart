import 'package:flutter_test/flutter_test.dart';
import 'package:lunara_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LunaraApp());

    // Verify that the app starts (MaterialApp is present)
    expect(find.byType(LunaraApp), findsOneWidget);
  });
}
