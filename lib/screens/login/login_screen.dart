import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _error;
  bool _loading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() { _error = null; _loading = true; });

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return; // cancelled
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      // Auth state listener in main.dart will handle navigation
    } catch (e) {
      setState(() => _error = '로그인에 실패했습니다.\n다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/images/icon.png', width: 140, height: 140),
              ),
              const SizedBox(height: 24),
              const Text('갈렙찬양대',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              const Text('Caleb Choir',
                style: TextStyle(fontSize: 16, color: AppColors.muted, letterSpacing: 2)),
              const Spacer(),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error, fontSize: 13, height: 1.4)),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleGoogleSignIn,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Google로 로그인'),
                ),
              ),
              const SizedBox(height: 12),
              const Text('간편하게 로그인하고 갈렙찬양대에 참여하세요',
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}
