import 'package:flutter_test/flutter_test.dart';
import 'package:echo_private_universe/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ECHO app starts and shows its main navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const EchoApp());
    await tester.pumpAndSettle();
    expect(find.text('العالم'), findsOneWidget);
    expect(find.text('الذاكرة'), findsOneWidget);
  });
}
