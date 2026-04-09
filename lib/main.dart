import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'providers/app_providers.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/videos/videos_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/community/community_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/sheet_music/sheet_music_screen.dart';
import 'screens/events/events_screen.dart';

void main() {
  runApp(const ProviderScope(child: CalebChoirApp()));
}

// Auth state provider
final isLoggedInProvider = StateProvider<bool>((ref) => false);

class CalebChoirApp extends ConsumerStatefulWidget {
  const CalebChoirApp({super.key});

  @override
  ConsumerState<CalebChoirApp> createState() => _CalebChoirAppState();
}

class _CalebChoirAppState extends ConsumerState<CalebChoirApp> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
    _handleDeepLink();
  }

  Future<void> _checkAuth() async {
    final api = ref.read(apiServiceProvider);
    final token = await api.getToken();
    if (token != null && token.isNotEmpty) {
      ref.read(isLoggedInProvider.notifier).state = true;
    }
  }

  void _handleDeepLink() {
    // Handle deep link: calebchoir://auth?token=TOKEN
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Deep link handling will work via platform channels
      // For initial launch deep link, we check window
    });
  }

  void handleAuthToken(String token) async {
    final api = ref.read(apiServiceProvider);
    await api.setToken(token);
    ref.read(isLoggedInProvider.notifier).state = true;
    ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return MaterialApp(
      title: '갈렙 찬양대',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: isLoggedIn ? const MainShell() : const LoginScreen(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    SheetMusicScreen(),
    VideosScreen(),
    AttendanceScreen(),
    CommunityScreen(),
    EventsScreen(),
    ProfileScreen(),
  ];

  static const _navItems = [
    {'icon': Icons.dashboard, 'label': '홈'},
    {'icon': Icons.music_note, 'label': '악보'},
    {'icon': Icons.play_circle_filled, 'label': '영상'},
    {'icon': Icons.event_note, 'label': '출석'},
    {'icon': Icons.forum, 'label': '커뮤니티'},
    {'icon': Icons.emoji_events, 'label': '이벤트'},
    {'icon': Icons.person, 'label': '마이'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _screens[_currentIndex]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.15))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_navItems.length, (i) {
                final isActive = _currentIndex == i;
                final item = _navItems[i];
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = i),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 52,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(horizontal: isActive ? 14 : 0, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primaryContainer : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item['icon'] as IconData, size: 22, color: isActive ? Colors.white : AppColors.muted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item['label'] as String,
                        style: TextStyle(
                          fontSize: 9, fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                          color: isActive ? AppColors.primaryContainer : AppColors.muted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      floatingActionButton: _currentIndex == 4
          ? FloatingActionButton(
              onPressed: () {},
              backgroundColor: AppColors.primaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.edit, color: Colors.white),
            )
          : null,
    );
  }
}
