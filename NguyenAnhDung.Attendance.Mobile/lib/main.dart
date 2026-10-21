import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core.dart';
import 'auth.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatefulWidget {
  final Session? session;
  const AttendanceApp({super.key, this.session});
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  late final Session session;
  @override
  void initState() {
    super.initState();
    session = widget.session ?? Session();
    session.restore();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => MaterialApp(
      key: ValueKey(session.user?['id']),
      title: 'Chấm công Hữu Duyên',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi', 'VN'),
      supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2455D6)),
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F6FB)),
      ),
      home: session.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : session.user == null
          ? AuthScreen(session: session)
          : HomeScreen(session: session),
    ),
  );
}
