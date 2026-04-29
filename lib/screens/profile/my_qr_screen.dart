import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';

class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseService.uid;
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: AppLogoTitle(
          title: '내 출석 QR',
          textStyle: AppText.headline(18, color: Colors.white),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '관리자에게 이 QR 을 보여주세요',
                  style: AppText.body(14, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  '출석 체크 시 사용됩니다',
                  style: AppText.body(12, color: Colors.white38),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (uid != null)
                        QrImageView(
                          data: uid,
                          version: QrVersions.auto,
                          size: 260,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppColors.primary,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        SizedBox(
                          width: 260,
                          height: 260,
                          child: Center(
                            child: Text(
                              '로그인이 필요합니다',
                              style: AppText.body(14, color: AppColors.muted),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      profileAsync.when(
                        loading: () => const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (profile) {
                          if (profile == null) return const SizedBox.shrink();
                          return Column(
                            children: [
                              Text(
                                profile.displayName.isEmpty
                                    ? '멤버'
                                    : profile.displayName,
                                style: AppText.headline(
                                  20,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${profile.generation ?? ''} · ${profile.partLabel}',
                                style: AppText.body(13, color: AppColors.muted),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '화면 밝기를 최대로 올려주세요',
                        style: AppText.body(12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
