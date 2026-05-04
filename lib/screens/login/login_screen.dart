import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/social_login_logos.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

import 'kakao_sign_in_stub.dart'
    if (dart.library.io) 'kakao_sign_in_mobile.dart'
    as kakao_helper;
import 'naver_sign_in_stub.dart'
    if (dart.library.io) 'naver_sign_in_mobile.dart'
    as naver_helper;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String? _error;
  bool _loading = false;
  String? _loadingProvider;
  bool _rememberLogin = true;

  bool get _showLocalPreview {
    if (!kIsWeb) return false;
    return Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';
  }

  bool get _isMobileWeb {
    if (!kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  GoogleAuthProvider _googleProvider() {
    return GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
  }

  @override
  void initState() {
    super.initState();
    _loadRememberLogin();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _completeGoogleRedirectSignIn();
        _completeKakaoRedirectSignIn();
        _completeNaverRedirectSignIn();
      });
    }
  }

  Future<void> _loadRememberLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rememberLogin = prefs.getBool('remember_login') ?? true;
    });
  }

  Future<void> _setRememberLogin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_login', value);
    if (!mounted) return;
    setState(() => _rememberLogin = value);
  }

  Future<void> _applyAuthPersistence() async {
    if (!kIsWeb) return;
    await FirebaseAuth.instance.setPersistence(
      _rememberLogin ? Persistence.LOCAL : Persistence.SESSION,
    );
  }

  Future<void> _completeGoogleRedirectSignIn() async {
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user != null) {
        debugPrint('Google redirect sign-in completed: ${result.user!.uid}');
        await _afterSuccessfulSignIn();
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Google redirect sign-in error: $e');
      if (!mounted) return;
      setState(() => _error = _googleErrorMessage(e));
    } catch (e) {
      debugPrint('Google redirect result error: $e');
    }
  }

  Future<void> _completeNaverRedirectSignIn() async {
    try {
      final callback = naver_helper.consumeNaverRedirectResult();
      if (callback == null) return;
      await _applyAuthPersistence();
      setState(() {
        _error = null;
        _loading = true;
        _loadingProvider = 'naver';
      });
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createNaverCustomToken',
      );
      final result = await callable.call<Map<String, dynamic>>(callback);
      final customToken = result.data['token'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      await _afterSuccessfulSignIn();
    } catch (e) {
      debugPrint('Naver redirect sign-in error: $e');
      if (!mounted) return;
      setState(() => _error = _naverErrorMessage(e));
    } finally {
      if (mounted && _loadingProvider == 'naver') {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _completeKakaoRedirectSignIn() async {
    try {
      final callback = kakao_helper.consumeKakaoRedirectResult();
      if (callback == null) return;
      await _applyAuthPersistence();
      setState(() {
        _error = null;
        _loading = true;
        _loadingProvider = 'kakao';
      });
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createKakaoCustomToken',
      );
      final result = await callable.call<Map<String, dynamic>>(callback);
      final customToken = result.data['token'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      await _afterSuccessfulSignIn();
    } catch (e) {
      debugPrint('Kakao redirect sign-in error: $e');
      if (!mounted) return;
      final detail = e is StateError ? e.message : '다시 시도해주세요.';
      setState(() => _error = '카카오 로그인에 실패했습니다.\n$detail');
    } finally {
      if (mounted && _loadingProvider == 'kakao') {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _afterSuccessfulSignIn() async {
    try {
      await FirebaseService.ensurePlatformAdminRole();
    } catch (e) {
      debugPrint('Platform admin bootstrap skipped: $e');
    }
    if (!mounted) return;
    ref.read(loggedOutProvider.notifier).state = false;
    ref.invalidate(authStateProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(myProfileStreamProvider);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _error = null;
      _loading = true;
      _loadingProvider = 'google';
    });
    try {
      if (kIsWeb) {
        await _applyAuthPersistence();
        final provider = _googleProvider();
        if (_isMobileWeb) {
          await FirebaseAuth.instance.signInWithRedirect(provider);
          return;
        }
        try {
          final result = await FirebaseAuth.instance
              .signInWithPopup(provider)
              .timeout(const Duration(seconds: 18));
          if (result.user != null) {
            await _afterSuccessfulSignIn();
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'popup-blocked' ||
              e.code == 'popup-closed-by-user' ||
              e.code == 'cancelled-popup-request') {
            await FirebaseAuth.instance.signInWithRedirect(provider);
            return;
          }
          rethrow;
        } on TimeoutException {
          await FirebaseAuth.instance.signInWithRedirect(provider);
          return;
        }
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() {
            _loading = false;
            _loadingProvider = null;
          });
          return;
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
        await _afterSuccessfulSignIn();
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign-in error: $e');
      setState(() => _error = _googleErrorMessage(e));
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      setState(() => _error = 'Google 로그인에 실패했습니다.\n다시 시도해주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _handleKakaoSignIn() async {
    setState(() {
      _error = null;
      _loading = true;
      _loadingProvider = 'kakao';
    });
    try {
      await _applyAuthPersistence();
      final accessToken = await kakao_helper.signInWithKakao();
      if (accessToken == null) {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
        return;
      }
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createKakaoCustomToken',
      );
      final result = await callable.call<Map<String, dynamic>>({
        'accessToken': accessToken,
      });
      final customToken = result.data['token'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      await _afterSuccessfulSignIn();
    } catch (e) {
      debugPrint('Kakao sign-in error: $e');
      final detail = e is StateError ? e.message : '다시 시도해주세요.';
      setState(() => _error = '카카오 로그인에 실패했습니다.\n$detail');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _handleNaverSignIn() async {
    setState(() {
      _error = null;
      _loading = true;
      _loadingProvider = 'naver';
    });
    try {
      await _applyAuthPersistence();
      await naver_helper.startSignInWithNaver();
    } catch (e) {
      debugPrint('Naver sign-in error: $e');
      setState(() => _error = _naverErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  String _googleErrorMessage(FirebaseAuthException e) {
    if (e.code == 'unauthorized-domain') {
      return '현재 주소가 Firebase 로그인 허용 도메인에 없습니다.\nFirebase Auth에 이 도메인을 추가해주세요.';
    }
    if (e.code == 'popup-closed-by-user') {
      return 'Google 로그인 창이 닫혔습니다.\n다시 시도해주세요.';
    }
    return 'Google 로그인에 실패했습니다.\n다시 시도해주세요.';
  }

  String _naverErrorMessage(Object e) {
    final message = e.toString();
    if (message.contains('NAVER_CLIENT_ID')) {
      return '네이버 로그인 키가 아직 설정되지 않았습니다.\n네이버 개발자센터 Client ID를 연결해주세요.';
    }
    if (message.contains('UnsupportedError')) {
      return '모바일 네이버 로그인은 앱 키와 URL scheme 설정 후 사용할 수 있습니다.';
    }
    return '네이버 로그인에 실패했습니다.\n다시 시도해주세요.';
  }

  @override
  Widget build(BuildContext context) {
    final loggedOut = ref.watch(loggedOutProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              if (loggedOut)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '로그아웃되었습니다',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            ref.read(loggedOutProvider.notifier).state = false,
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(flex: 3),
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: 100,
                    height: 100,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'C.C Note',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '(Church Choir Note)',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(flex: 2),

              // Error
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),

              // Kakao
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _handleKakaoSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF191919),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading && _loadingProvider == 'kakao'
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF191919),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              KakaoTalkLogo(size: 22),
                              SizedBox(width: 10),
                              Text(
                                '카카오로 시작하기',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              // Naver
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _handleNaverSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF03C75A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading && _loadingProvider == 'naver'
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              NaverLogo(size: 20),
                              SizedBox(width: 10),
                              Text(
                                '네이버로 시작하기',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              // Google
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    backgroundColor: AppColors.card,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    overlayColor: const Color(0xFF4285F4),
                  ),
                  child: _loading && _loadingProvider == 'google'
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GoogleGLogo(size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Google로 시작하기',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _loading
                    ? null
                    : () => _setRememberLogin(!_rememberLogin),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _rememberLogin,
                          onChanged: _loading
                              ? null
                              : (value) => _setRememberLogin(value ?? true),
                          activeColor: AppColors.ink,
                          checkColor: Colors.white,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        '로그인 정보 저장',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '다음부터 자동 로그인',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showLocalPreview) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      ref.read(loginPreviewModeProvider.notifier).state = false;
                      ref.read(localPreviewModeProvider.notifier).state = true;
                      ref.read(loggedOutProvider.notifier).state = false;
                    },
                    child: const Text('인앱 미리보기로 보기'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '간편하게 로그인하고 참여하세요',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
