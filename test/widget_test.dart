import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_private_universe/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ECHO app starts and shows its main navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const EchoApp());

    // Allow the asynchronous local-preferences load/save to finish without
    // pumpAndSettle hanging on an indeterminate progress indicator.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('العالم'), findsOneWidget);
    expect(find.text('الذاكرة'), findsOneWidget);
  });
}
