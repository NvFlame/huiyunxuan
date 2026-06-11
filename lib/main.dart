import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';

const appTitle = '绘云轩';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HuiyunxuanApp());
}

class HuiyunxuanApp extends StatelessWidget {
  const HuiyunxuanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFFD8A935);
    const backgroundColor = Color(0xFFFFFAEA);
    const surfaceColor = Color(0xFFFFF4C7);

    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          surface: backgroundColor,
        ),
        scaffoldBackgroundColor: backgroundColor,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: surfaceColor,
          foregroundColor: Color(0xFF4F3B12),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFEEDC9A)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2CA7A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2CA7A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: seedColor, width: 1.6),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
