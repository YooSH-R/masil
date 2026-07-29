import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7), // Match beige background
      body: GestureDetector(
        onTap: () => context.go('/auto-login'),
        child: Stack(
          children: [
            // Decorative Top Curve (Envelope-like)
            Positioned(
              top: -100,
              left: -50,
              right: -50,
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.elliptical(300, 100)),
                ),
              ),
            ),
            
            Center(
              child: FadeTransition(
                opacity: _animation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    // Main Circular Logo
                    Container(
                      width: 200,
                      height: 200,
                      padding: const EdgeInsets.all(30),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x0D000000),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset('assets/images/mysil_logo.png', fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 120),
                    // Tagline
                    const Text(
                      '반려 로봇과 함께하는',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF8D6E63),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Main Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '건강한 마실',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5D4037),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.pets, color: const Color(0xFF5D4037).withValues(alpha: 0.7), size: 24),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom Instruction
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _animation,
                child: const Text(
                  '탭하고 마실이 만나러 가기',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFBCAAA4),
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
