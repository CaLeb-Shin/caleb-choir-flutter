import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
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
    final totalAttendance = history.length;
    final attendanceRate = totalAttendance > 0
        ? (totalAttendance / (totalAttendance + 2).clamp(10, 999) * 100).round().clamp(0, 100)
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Text('공동체와 리듬', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
          const SizedBox(height: 8),
          const Text('연습 일정', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 8),
          const Text('당신의 참여는 우리 합창의 심장박동입니다.', style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 16),

          // Action Buttons: QR Scan + Export
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => QrScanScreen(onScanned: (code) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('QR 스캔 완료: $code')),
                      );
                    }),
                  ));
                },
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('QR 스캔'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final api = ref.read(apiServiceProvider);
                  final result = await api.getAttendanceCsv();
                  final csv = result['csv'] as String?;
                  if (csv != null && csv.isNotEmpty) {
                    await Share.share(csv, subject: '갈렙찬양대 출석기록');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('출석 데이터 ${result['count']}건 내보내기')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text('엑셀 내보내기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // Active Session / Check-in
          if (session != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF66BB6A))),
                    const SizedBox(width: 6),
                    Text('출석 진행 중', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.8))),
                  ]),
                ),
                const SizedBox(height: 12),
                Text(session['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.schedule, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(_formatDate(session['openedAt']), style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final api = ref.read(apiServiceProvider);
                      await api.checkIn(session['id']);
                      ref.invalidate(myHistoryProvider);
                    },
                    icon: const Icon(Icons.check_circle, size: 20),
                    label: const Text('출석 체크하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryContainer,
                      foregroundColor: AppColors.primaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.1)),
                  child: const Icon(Icons.event_note, size: 32, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                const Text('현재 열린 출석이 없습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 6),
                const Text('관리자가 출석을 열면 여기서 출석할 수 있습니다', style: TextStyle(fontSize: 13, color: AppColors.muted), textAlign: TextAlign.center),
              ]),
            ),
          const SizedBox(height: 16),

          // Stats Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('출석 현황', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 2)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('$attendanceRate%', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 8),
                Text(attendanceRate >= 80 ? '우수함' : attendanceRate >= 50 ? '양호' : '시작',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.secondaryContainer)),
              ]),
              const SizedBox(height: 4),
              Text('이번 시즌에 총 $totalAttendance번 출석하셨습니다.',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 20),
              Row(children: List.generate(5, (i) => Expanded(
                child: Container(
                  height: 4, margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i < (attendanceRate / 20).ceil() ? AppColors.secondaryContainer : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ))),
            ]),
          ),
          const SizedBox(height: 16),

          // QR Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              Row(children: [
                Icon(Icons.qr_code_2, size: 20, color: AppColors.secondary),
                const SizedBox(width: 8),
                const Text('내 출석 카드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ]),
              const SizedBox(height: 16),
              Container(
                width: 140, height: 140,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border.withValues(alpha: 0.3))),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.qr_code_2, size: 80, color: AppColors.primary),
                  Text('ID: ${profile?.id ?? "---"}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                ]),
              ),
              const SizedBox(height: 12),
              Text(profile?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
              Text('${profile?.generation ?? ''} · ${profile?.partLabel ?? ''}', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ]),
          ),
          const SizedBox(height: 20),

          // History
          Row(children: [
            Icon(Icons.event_available, size: 20, color: AppColors.secondary),
            const SizedBox(width: 8),
            const Text('출석 기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            ),
            child: history.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('아직 출석 기록이 없습니다', style: TextStyle(color: AppColors.muted))))
                : Column(children: history.take(10).toList().asMap().entries.map((entry) {
                    final i = entry.key;
                    final record = entry.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(border: i < history.length - 1 && i < 9 ? Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.15))) : null),
                      child: Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: i == 0 ? AppColors.secondary : AppColors.border)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(record['sessionTitle'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          const SizedBox(height: 2),
                          Text(_formatDate(record['checkedInAt']), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ])),
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.1)),
                          child: const Center(child: Text('✓', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryContainer))),
                        ),
                      ]),
                    );
                  }).toList()),
          ),
        ],
      ),
    );
  }

  static String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString());
      return '${d.year}.${d.month}.${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
