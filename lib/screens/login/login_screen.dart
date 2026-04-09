import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _error;

  Future<void> _handleLogin() async {
    setState(() => _error = null);

    final loginUrl = AppConfig.getLoginUrl();
    if (loginUrl == null) {
      setState(() => _error = 'OAuth가 설정되지 않았습니다.\n서버 관리자에게 문의해주세요.');
      return;
    }

    try {
      final uri = Uri.parse(loginUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        setState(() => _error = '브라우저를 열 수 없습니다.');
      }
    } catch (e) {
      setState(() => _error = '로그인 중 오류가 발생했습니다.');
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
                  onPressed: _handleLogin,
                  child: const Text('로그인 / 회원가입'),
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
