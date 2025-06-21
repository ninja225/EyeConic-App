import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Remove splash screen after a short delay to ensure smooth transition
  Future.delayed(const Duration(milliseconds: 1000), () {
    FlutterNativeSplash.remove();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Set system UI overlay style for consistent theming
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0F0F14),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'Eyeconic Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF1E1E2E),
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF8B5CF6),
          surface: const Color(0xFF1A1A24),
          surfaceContainerHighest: const Color(0xFF252530),
          onPrimary: Colors.white,
          onSurface: const Color(0xFFE4E4E7),
          onSurfaceVariant: const Color(0xFFA1A1AA),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1A1A24),
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isAuthenticated = await _authService.isAuthenticated();
      if (mounted) {
        setState(() {
          _isAuthenticated = isAuthenticated;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const WelcomeScreen(); // Show welcome screen while checking auth
    }

    return _isAuthenticated ? const ChatScreen() : const LoginScreen();
  }
}
