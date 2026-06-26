import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'widgets/huiyun_visuals.dart';

const appTitle = '绘云轩';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HuiyunxuanApp());
}

class HuiyunxuanApp extends StatelessWidget {
  const HuiyunxuanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const inkColor = Color(0xFF3F3218);
    const seedColor = Color(0xFFC99A25);
    const backgroundColor = Color(0xFFFFFAEA);
    const surfaceColor = Color(0xFFFFF3C4);
    const surfaceQuietColor = Color(0xFFFFFBF0);
    const borderColor = Color(0xFFE7CF83);
    const mistGreen = Color(0xFF8E9278);

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
      builder: (context, child) {
        return _HuiyunAppBackdrop(child: child ?? const SizedBox.shrink());
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          primary: const Color(0xFF8A6500),
          secondary: mistGreen,
          surface: backgroundColor,
          onSurface: inkColor,
          surfaceContainerHighest: const Color(0xFFFFF1C0),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: backgroundColor,
        splashFactory: InkRipple.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _HuiyunPageTransitionsBuilder(),
            TargetPlatform.fuchsia: _HuiyunPageTransitionsBuilder(),
            TargetPlatform.iOS: _HuiyunPageTransitionsBuilder(),
            TargetPlatform.linux: _HuiyunPageTransitionsBuilder(),
            TargetPlatform.macOS: _HuiyunPageTransitionsBuilder(),
            TargetPlatform.windows: _HuiyunPageTransitionsBuilder(),
          },
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: inkColor,
              displayColor: inkColor,
            ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: surfaceColor,
          foregroundColor: inkColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: inkColor,
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceQuietColor,
          elevation: 0,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: borderColor),
          ),
          surfaceTintColor: Colors.transparent,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 10,
          focusElevation: 12,
          hoverElevation: 12,
          highlightElevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          extendedTextStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF5B4314),
            highlightColor: const Color(0xFFD6A934).withOpacity(0.18),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF6F5200),
          textColor: inkColor,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceQuietColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: seedColor, width: 1.6),
          ),
          labelStyle: const TextStyle(color: Color(0xFF725A25)),
          floatingLabelStyle: const TextStyle(color: Color(0xFF7F5E00)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8A6500),
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6F5200),
            minimumSize: const Size(44, 42),
            side: const BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF7F5E00),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFFFFF7E2),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: borderColor),
          ),
          titleTextStyle: const TextStyle(
            color: inkColor,
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
          contentTextStyle: const TextStyle(
            color: inkColor,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFFFFF7E2),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFFFFF9E8),
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: borderColor),
          ),
          textStyle: const TextStyle(
            color: inkColor,
            fontSize: 16,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF4F3B12),
          contentTextStyle: const TextStyle(
            color: Color(0xFFFFF7DB),
            fontSize: 15,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFFFF8E5);
            }
            return const Color(0xFF8C8171);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF8A6500);
            }
            return const Color(0xFFE5DCC8);
          }),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFFFFE7AF);
              }
              return const Color(0xFFFFFBF0);
            }),
            foregroundColor: WidgetStateProperty.all(inkColor),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const BorderSide(color: seedColor, width: 1.2);
              }
              return const BorderSide(color: borderColor);
            }),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontWeight: FontWeight.w600),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE6D59E),
          space: 1,
          thickness: 0.7,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class _HuiyunAppBackdrop extends StatelessWidget {
  const _HuiyunAppBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF7D7),
            Color(0xFFFFFAEA),
            Color(0xFFFFF5DF),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: const _HuiyunBackdropPainter(),
          ),
          const Positioned(
            right: -86,
            bottom: 64,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.075,
                child: Image(
                  image: AssetImage('assets/branding/cloud_mark.png'),
                  width: 330,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _HuiyunBackdropPainter extends CustomPainter {
  const _HuiyunBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paperLine = Paint()
      ..color = const Color(0xFFE9DCA7).withOpacity(0.18)
      ..strokeWidth = 0.7;
    for (var x = 18.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x + 10, size.height), paperLine);
    }

    HuiyunCloudArt.drawCloudWash(
      canvas,
      center: Offset(size.width * 0.78, size.height * 0.15),
      width: size.shortestSide * 0.50,
      color: const Color(0xFFD1A84F),
      opacity: 0.045,
      mirror: true,
    );
    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.74, size.height * 0.16),
      width: size.shortestSide * 0.42,
      color: const Color(0xFFC7A65D),
      opacity: 0.11,
      strokeWidth: 1.1,
      mirror: true,
    );
    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.22, size.height * 0.44),
      width: size.shortestSide * 0.34,
      color: const Color(0xFF8E9278),
      opacity: 0.07,
      strokeWidth: 1.0,
    );
    final mist = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8E9278).withOpacity(0.075),
          const Color(0xFF8E9278).withOpacity(0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.12, size.height * 0.18),
          radius: size.shortestSide * 0.42,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.18),
      size.shortestSide * 0.42,
      mist,
    );

    final warmWash = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE2B345).withOpacity(0.1),
          const Color(0xFFE2B345).withOpacity(0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.88, size.height * 0.82),
          radius: size.shortestSide * 0.38,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.88, size.height * 0.82),
      size.shortestSide * 0.38,
      warmWash,
    );
  }

  @override
  bool shouldRepaint(covariant _HuiyunBackdropPainter oldDelegate) => false;
}

class _HuiyunPageTransitionsBuilder extends PageTransitionsBuilder {
  const _HuiyunPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return _HuiyunAppBackdrop(
      child: FadeTransition(
        opacity: curved,
        child: child,
      ),
    );
  }
}
