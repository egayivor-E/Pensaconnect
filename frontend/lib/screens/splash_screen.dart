// screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_style.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(seconds: 2));
    // FIX: the previous mounted-check here was mangled duplicate code
    // that didn't actually guard the navigation call.
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.inkDusk, AppColors.emberGold],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                    width: 120,
                    height: 120,
                    decoration: ShapeDecoration(
                      color: Colors.white.withOpacity(0.14),
                      shape: AppShapes.archBorder(top: 40, bottom: 20),
                    ),
                    child: const Hero(
                      tag: 'app-logo',
                      child: Icon(
                        Icons.people_alt_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  )
                  .animate()
                  .scale(
                    duration: 500.ms,
                    curve: Curves.easeOutBack,
                    begin: const Offset(0.7, 0.7),
                    end: const Offset(1, 1),
                  ),
              const SizedBox(height: 28),
              Text(
                'PensaConnect',
                style: Theme.of(
                  context,
                ).textTheme.displayMedium?.copyWith(color: Colors.white),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
              const SizedBox(height: 6),
              Text(
                'Ladies & Gents Wing',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                  letterSpacing: 0.5,
                ),
              ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
              const SizedBox(height: 48),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}
