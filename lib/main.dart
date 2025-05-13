import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eyeconic Chat',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF1E1E2E),
        scaffoldBackgroundColor: const Color(0xFF13131A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E2E),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF7C4DFF),
          secondary: Colors.deepPurple.shade300,
          surface: const Color(0xFF1E1E2E),
          background: const Color(0xFF13131A),
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}
