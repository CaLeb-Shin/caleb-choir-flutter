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
import 'screens/profile_setup/profile_setup_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/videos/videos_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/community/community_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/sheet_music/sheet_music_screen.dart';
import 'services/firebase_service.dart';

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
    final authState = ref.watch(authStateProvider);

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
                  BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 60),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: const Size(430, 932)),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      home: authState.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const LoginScreen(),
        data: (user) {
          if (user == null) return const LoginScreen();
          final profileAsync = ref.watch(profileProvider);
          return profileAsync.when(
            loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (_, __) => const ProfileSetupScreen(),
            data: (profile) {
              if (profile == null || !profile.profileCompleted) {
                return const ProfileSetupScreen();
              }
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

  static const _items = [
    (Icons.home_rounded, '홈'),
    (Icons.music_note_rounded, '악보'),
    (Icons.play_circle_rounded, '영상'),
    (Icons.calendar_today_rounded, '출석'),
    (Icons.chat_bubble_rounded, '소통'),
    (Icons.person_rounded, '마이'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabIndexProvider);

    return Scaffold(
      body: SafeArea(child: _screens[index]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_items.length, (i) {
                final active = index == i;
                final (icon, label) = _items[i];
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => ref.read(tabIndexProvider.notifier).state = i,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedScale(
                          scale: active ? 1.15 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(icon, size: 24, color: active ? AppColors.primary : AppColors.muted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(height: 3),
                          Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.secondaryContainer)),
                        ],
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      floatingActionButton: index == 4
          ? FloatingActionButton(
              onPressed: () => _showPostDialog(context, ref),
              backgroundColor: AppColors.primaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.edit_rounded, color: Colors.white),
            )
          : null,
    );
  }

  void _showPostDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (dialogCtx) => AlertDialog(
      title: const Text('게시물 작성'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '내용을 입력하세요'), maxLines: 4),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          Navigator.pop(dialogCtx);
          if (ctrl.text.trim().isNotEmpty) {
            await FirebaseService.createPost(ctrl.text.trim());
            ref.invalidate(postsProvider);
          }
        }, child: const Text('게시')),
      ],
    ));
  }
}
