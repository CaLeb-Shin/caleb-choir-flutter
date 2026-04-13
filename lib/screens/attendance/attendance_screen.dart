import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/interactive.dart';
import '../qr_scan/qr_scan_screen.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final sessionAsync = ref.watch(activeSessionProvider);
    final historyAsync = ref.watch(myHistoryProvider);

    final profile = profileAsync.valueOrNull;
    final session = sessionAsync.valueOrNull;
    final history = historyAsync.valueOrNull ?? [];
    final total = history.length;
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('출석', style: AppText.headline(28)),
          const SizedBox(height: 4),
          Text('연습 출석을 관리하세요', style: AppText.body(14, color: AppColors.muted)),
          const SizedBox(height: 20),

          // Action buttons
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => QrScanScreen(onScanned: (code) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('QR 스캔 완료: $code')));
                    }),
                  ));
                },
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('QR 스캔'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final h = ref.read(myHistoryProvider).valueOrNull ?? [];
                  final csv = h.map((r) => '${r['sessionTitle']},${r['checkedInAt']}').join('\n');
                  if (csv.isNotEmpty) await Share.share(csv, subject: '갈렙찬양대 출석기록');
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('내보내기'),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Admin: 출석 열기/닫기
          if (isAdmin) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('관리자', style: AppText.label()),
                const SizedBox(height: 10),
                if (session != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseService.closeSession(session['id']);
                        ref.invalidate(activeSessionProvider);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('출석 마감'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showOpenSessionDialog(context, ref),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('출석 열기'),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // Active session
          if (session != null)
            Tappable(
              onTap: () {},
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF000E24), Color(0xFF00234B)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4ADE80))),
                    const SizedBox(width: 8),
                    Text('출석 진행 중', style: AppText.body(13, weight: FontWeight.w600, color: Colors.white70)),
                  ]),
                  const SizedBox(height: 12),
                  Text(session['title'] ?? '', style: AppText.headline(20, color: Colors.white)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await FirebaseService.checkIn(session['id']);
                        ref.invalidate(myHistoryProvider);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondaryContainer, foregroundColor: AppColors.primary, elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('출석 체크하기'),
                    ),
                  ),
                ]),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                Icon(Icons.calendar_today_rounded, size: 32, color: AppColors.subtle),
                const SizedBox(height: 10),
                Text('현재 열린 출석이 없습니다', style: AppText.body(15, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('관리자가 출석을 열면 여기에 표시됩니다', style: AppText.body(13, color: AppColors.muted)),
              ]),
            ),
          const SizedBox(height: 20),

          // Stats
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('총 $total회 출석', style: AppText.headline(18)),
                Text(profile?.partLabel ?? '', style: AppText.body(13, color: AppColors.muted)),
              ]),
            ]),
          ),
          const SizedBox(height: 24),

          // History
          Text('출석 기록', style: AppText.headline(18)),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('아직 출석 기록이 없습니다', style: AppText.body(14, color: AppColors.muted))),
            )
          else
            ...history.take(10).map((record) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(record['sessionTitle'] ?? '', style: AppText.body(14, weight: FontWeight.w600)),
                  Text(_fmt(record['checkedInAt']), style: AppText.body(12, color: AppColors.muted)),
                ])),
              ]),
            )),
        ],
      ),
    );
  }

  void _showOpenSessionDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (dialogCtx) => AlertDialog(
      title: const Text('출석 열기'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '연습 제목 (예: 주일 연습)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          Navigator.pop(dialogCtx);
          if (ctrl.text.trim().isNotEmpty) {
            await FirebaseService.openSession(ctrl.text.trim());
            ref.invalidate(activeSessionProvider);
          }
        }, child: const Text('열기')),
      ],
    ));
  }

  static String _fmt(dynamic s) {
    if (s == null) return '';
    try {
      final d = DateTime.parse(s.toString());
      return '${d.year}.${d.month}.${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }
}
