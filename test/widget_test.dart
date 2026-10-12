import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_private_universe/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ECHO app starts and shows its main navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const EchoApp());

    // لا نستخدم pumpAndSettle لأنه ممكن يعلق مع CircularProgressIndicator
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ✅ التحقق من الـ NavigationBar (مو نص عربي)
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // ✅ عدد الـ destinations = 5
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.destinations.length, 5);
  });
}