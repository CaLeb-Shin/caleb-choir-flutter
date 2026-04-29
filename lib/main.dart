import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'screens/login/login_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/approval/pending_approval_screen.dart';
import 'screens/approval/rejected_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/videos/videos_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/community/community_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/sheet_music/sheet_music_screen.dart';
import 'screens/community/post_compose_sheet.dart';
import 'widgets/app_bottom_nav_bar.dart';
import 'widgets/app_logo_title.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KakaoSdk.init(nativeAppKey: 'YOUR_KAKAO_NATIVE_APP_KEY');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }
  runApp(const ProviderScope(child: CalebChoirApp()));
}

class CalebChoirApp extends ConsumerWidget {
  const CalebChoirApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPreviewMode = ref.watch(localPreviewModeProvider);
    final localLoginMode = ref.watch(loginPreviewModeProvider);
    final onboardingPreviewDismissed = ref.watch(
      onboardingPreviewDismissedProvider,
    );
    final authState = ref.watch(authStateProvider);
    final isLocalWeb =
        kIsWeb &&
        (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1');
    final loginPreviewMode =
        localLoginMode ||
        (isLocalWeb && Uri.base.queryParameters['login'] == '1');
    final onboardingPreviewMode =
        isLocalWeb &&
        Uri.base.queryParameters['onboarding'] == '1' &&
        !onboardingPreviewDismissed;

    return MaterialApp(
      title: 'C.C',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (!kIsWeb || child == null) return child ?? const SizedBox.shrink();
        return Scaffold(
          backgroundColor: const Color(0xFF000E24),
          body: Center(
            child: Container(
              width: 430,
              height: 932,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 60,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(size: const Size(430, 932)),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      home: localPreviewMode
          ? const MainShell()
          : loginPreviewMode
          ? const LoginScreen()
          : onboardingPreviewMode
          ? const OnboardingScreen()
          : authState.when(
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => const LoginScreen(),
              data: (user) {
                if (user == null) {
                  return const LoginScreen();
                }
                // 승인 상태 실시간 스트림 (관리자 승인 시 자동 전환)
                final myProfileStream = ref.watch(myProfileStreamProvider);
                return myProfileStream.when(
                  loading: () => const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => const OnboardingScreen(),
                  data: (profile) {
                    // 1) Firestore users 문서가 아직 없음 → 최초 가입 경로
                    if (profile == null) {
                      return const OnboardingScreen();
                    }
                    // 2) 교회 미선택 + 승인 스코프도 없음 → 가입 플로우 재진입
                    //    (플랫폼 관리자도 교회 소속/프로필 완성 후 앱 사용 가능)
                    if (profile.needsChurchSelection) {
                      return const OnboardingScreen();
                    }
                    // 4) 프로필이 미완성 상태 (에지) → 재선택 유도
                    if (!profile.profileCompleted) {
                      return const OnboardingScreen();
                    }
                    // 5) 거부됨
                    if (profile.isRejected) {
                      return const RejectedScreen();
                    }
                    // 6) 승인 대기 (church/platform scope 둘 다)
                    if (profile.isPending) {
                      return const PendingApprovalScreen();
                    }
                    // 7) 승인 완료 (또는 approvalStatus null인 레거시) → 메인
                    return const MainShell();
                  },
                );
              },
            ),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final _screens = const [
    HomeScreen(),
    SheetMusicScreen(),
    VideosScreen(),
    AttendanceScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];

  static const _titles = ['홈', '악보', '영상', '출석', '소통', '마이'];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabIndexProvider);

    return Scaffold(
      appBar: index == 0
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: '뒤로가기',
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).maybePop();
                  } else {
                    ref.read(tabIndexProvider.notifier).state = 0;
                  }
                },
              ),
              title: AppLogoTitle(
                title: _titles[index],
                textStyle: AppText.headline(20),
              ),
            ),
      body: SafeArea(child: _screens[index]),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: index,
        popToRootOnTap: false,
      ),
      floatingActionButton: index == 4
          ? FloatingActionButton(
              onPressed: () => _openComposeSheet(context),
              backgroundColor: AppColors.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.edit_rounded, color: Colors.white),
            )
          : null,
    );
  }

  void _openComposeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PostComposeSheet(),
    );
  }
}
