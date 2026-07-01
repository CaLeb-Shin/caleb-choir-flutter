import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'firebase_options.dart';
import 'config/feature_flags.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'providers/refresh_coordinator.dart';
import 'screens/login/login_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/approval/pending_approval_screen.dart';
import 'screens/approval/rejected_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/community/community_screen.dart';
import 'screens/harmony_chat/harmony_chat_development_screen.dart';
import 'screens/harmony_chat/harmony_chat_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/sheet_music/sheet_music_screen.dart';
import 'screens/polls/polls_screen.dart';
import 'widgets/app_bottom_nav_bar.dart';
import 'widgets/app_logo_title.dart';
import 'widgets/caleb_logo_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KakaoSdk.init(nativeAppKey: '7dac8af45e9ebf4c81284e72bb1b7ebb');
  // warmCachedProfile only reads SharedPreferences, so start it in parallel with
  // Firebase init rather than serializing it onto the first-frame critical path.
  final cachedProfileWarm = FirebaseService.warmCachedProfile();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    // On web, on-disk persistence is single-tab: a second tab of the same origin
    // can't get the persistence lock, which left secondary tabs hanging forever
    // on the splash (profile snapshot never arrived). Memory cache avoids the
    // lock; native platforms keep full offline persistence.
    persistenceEnabled: !kIsWeb,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await cachedProfileWarm;
  runApp(const ProviderScope(child: CalebChoirApp()));

  unawaited(_initializeNotifications());
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }
}

class CalebChoirApp extends ConsumerWidget {
  const CalebChoirApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPreviewMode = ref.watch(localPreviewModeProvider);
    final localLoginMode = ref.watch(loginPreviewModeProvider);
    final loggedOut = ref.watch(loggedOutProvider);
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
      title: 'C.C Note',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (!kIsWeb || child == null) return child ?? const SizedBox.shrink();
        final media = MediaQuery.of(context);
        final isWidePreview = media.size.width >= 700;
        if (!isWidePreview) return child;

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
                  data: media.copyWith(size: const Size(430, 932)),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      home: loggedOut
          ? const LoginScreen()
          : localPreviewMode
          ? const MainShell()
          : loginPreviewMode
          ? const LoginScreen()
          : onboardingPreviewMode
          ? const OnboardingScreen()
          : authState.when(
              loading: () => const AppLoadingScreen(),
              error: (error, stackTrace) => const LoginScreen(),
              data: (user) {
                if (user == null) {
                  return const LoginScreen();
                }
                // 승인 상태 실시간 스트림 (관리자 승인 시 자동 전환)
                final myProfileStream = ref.watch(myProfileStreamProvider);
                return myProfileStream.when(
                  loading: () => const AppLoadingScreen(),
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
    AttendanceScreen(),
    PollsScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];
  // Tabs are built lazily on first visit, then kept alive in the IndexedStack so
  // switching back is instant and each tab's scroll position survives.
  final _loadedTabs = <int>{};
  bool _openedPreviewSection = false;

  static const _titles = ['홈', '악보&음원', '출석', '투표', '소통', '마이'];

  // Refresh reference data when the app returns from a long background, so a
  // reopened app isn't showing yesterday's sheet music / announcements. Streams
  // reconnect on their own; only the cache-class FutureProviders need a nudge.
  AppLifecycleListener? _lifecycleListener;
  DateTime? _backgroundedAt;
  static const _resumeRefreshThreshold = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: () => _backgroundedAt = DateTime.now(),
      onResume: _handleResume,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialPreviewSection();
    });
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _handleResume() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return;
    if (DateTime.now().difference(since) < _resumeRefreshThreshold) return;
    if (!mounted) return;
    invalidateCacheProviders(ref);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabIndexProvider);
    _loadedTabs.add(index);

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
      body: SafeArea(
        child: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _loadedTabs.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: index,
        popToRootOnTap: false,
      ),
    );
  }

  void _openInitialPreviewSection() {
    if (_openedPreviewSection || !mounted) return;
    if (!ref.read(localPreviewModeProvider)) return;
    if (Uri.base.queryParameters['section'] != 'harmony') return;
    _openedPreviewSection = true;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _PreviewSectionScreen(
          title: '하모니챗',
          child: FeatureFlags.harmonyChatEnabled
              ? HarmonyChatScreen()
              : HarmonyChatDevelopmentScreen(),
        ),
      ),
    );
  }
}

class _PreviewSectionScreen extends StatelessWidget {
  const _PreviewSectionScreen({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: '뒤로가기',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: AppLogoTitle(title: title),
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: const AppBottomNavBar(),
    );
  }
}
