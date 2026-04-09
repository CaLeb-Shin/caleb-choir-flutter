import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

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
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/images/icon.png', width: 140, height: 140),
              ),
              const SizedBox(height: 24),
              const Text(
                '갈렙찬양대',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              const Text(
                'Caleb Choir',
                style: TextStyle(fontSize: 16, color: AppColors.muted, letterSpacing: 2),
              ),
              const Spacer(),
              // Error message placeholder
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: const Text(
                  'OAuth가 설정되지 않았습니다.\n.env 파일에 서버 URL을 설정해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.error, fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              // Login Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Implement OAuth login
                  },
                  child: const Text('로그인 / 회원가입'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '간편하게 로그인하고 갈렙찬양대에 참여하세요',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}
