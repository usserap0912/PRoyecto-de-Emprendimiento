import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/app.dart';

void main() {
  testWidgets('SafeZone app loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeZoneApp());
    expect(find.text('SafeZone'), findsOneWidget);
  });
}
