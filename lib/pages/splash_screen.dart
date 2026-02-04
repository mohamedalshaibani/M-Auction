import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'create_profile_page.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Brief display of splash then load
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) _navigateWithFade(const MainShell());
      return;
    }

    try {
      final userExists = await _firestoreService.userExists(user.uid);
      if (!mounted) return;

      if (userExists) {
        _navigateWithFade(const MainShell());
      } else {
        _navigateWithFade(const CreateProfilePage());
      }
    } catch (e) {
      debugPrint('Error checking user: $e');
      if (mounted) _navigateWithFade(const MainShell());
    }
  }

  void _navigateWithFade(Widget page) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          AppTheme.logoAssetSource,
          width: 240,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
