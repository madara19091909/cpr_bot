import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/library/library_page.dart';
import 'app_controller.dart';
import 'localization.dart';

class McMangerApp extends StatelessWidget {
  const McMangerApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF5DBB63);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        title: 'MC Manger',
        debugShowCheckedModeBanner: false,
        locale: controller.locale,
        supportedLocales: AppStrings.supported,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
              seedColor: green, brightness: Brightness.dark, surface: const Color(0xFF1E2021)),
          scaffoldBackgroundColor: const Color(0xFF151617),
          cardTheme: CardThemeData(
            color: const Color(0xFF232627),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        home: LibraryPage(controller: controller),
      ),
    );
  }
}
