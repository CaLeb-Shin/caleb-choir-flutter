import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../qr_scan/qr_scan_screen.dart';

class AttendanceScreen extends ConsumerWidget {
  final String? initialPollId;
  final String? initialTargetDate;
  final String? initialTitle;

  const AttendanceScreen({
    super.key,
    this.initialPollId,
    this.initialTargetDate,
    this.initialTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final sessionAsync = ref.watch(activeSessionProvider);
    final historyAsync = ref.watch(myHistoryProvider);
    final pollsAsync = ref.watch(pollsProvider);

    final profile = profileAsync.valueOrNull;
    final session = sessionAsync.valueOrNull;
    final history = historyAsync.valueOrNull ?? [];
    final total = history.length;
    final viewAsMember = ref.watch(viewAsMemberProvider);
    final canOperateSession =
        ((profile?.isAdmin ?? false) || (profile?.isOfficer ?? false)) &&
        !viewAsMember;
    final canScanAttendance =
        (profile?.hasManagePermission ?? false) && !viewAsMember;
    final scannerPart = profile?.isPartLeader == true
        ? profile?.partLeaderFor
        : null;
    final scannerPartLabel = scannerPart == null
        ? null
        : User.partLabels[scannerPart] ?? scannerPart;
    final qrTitle = session != null
        ? '${_dateLabel(session['attendanceDate'] ?? session['openedAt'])} 출석 QR'
        : '출석 QR';
    final qrSubtitle = session != null
        ? (session['title'] ?? '열린 출석')
        : '관리자가 출석을 열면 오늘 QR로 갱신됩니다';
    final qrData = profile == null
        ? ''
        : session != null
        ? 'ccnote:attendance:${profile.churchId ?? ''}:${session['id']}:${profile.id}'
        : 'ccnote:member:${profile.churchId ?? ''}:${profile.id}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('출석&투표', style: AppText.headline(28)),
          const SizedBox(height: 4),
          Text(
            'QR 출석과 참석 투표를 한 화면에서 확인하세요',
            style: AppText.body(14, color: AppColors.muted),
          ),
          const SizedBox(height: 20),

          if (session != null) ...[
            _ActiveAttendanceCard(session: session),
            const SizedBox(height: 14),
          ],

          _AttendancePollSection(
            pollsAsync: pollsAsync,
            profile: profile,
            initialPollId: initialPollId,
            initialTargetDate: initialTargetDate,
            initialTitle: initialTitle,
            onVote: (pollId, choice) async {
              try {
                await FirebaseService.vote(pollId, choice);
                ref.invalidate(pollsProvider);
                ref.invalidate(pollVotesProvider(pollId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        choice == 'attend' ? '참석으로 투표했습니다' : '불참으로 투표했습니다',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('투표 실패: $e')));
                }
              }
            },
          ),
          const SizedBox(height: 14),

          // ── Attendance operator controls
          if (canOperateSession || canScanAttendance) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    canOperateSession ? '출석 운영' : '파트장 스캐너',
                    style: AppText.label(),
                  ),
                  if (scannerPartLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$scannerPartLabel 파트 단원 QR만 출석 처리됩니다',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (canOperateSession) ...[
                        Expanded(
                          child: session != null
                              ? ElevatedButton.icon(
                                  onPressed: () async {
                                    await FirebaseService.closeSession(
                                      session['id'],
                                    );
                                    ref.invalidate(activeSessionProvider);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(
                                    Icons.stop_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('출석 마감'),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () =>
                                      _showOpenSessionDialog(context, ref),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.secondary,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('출석 열기'),
                                ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: session == null
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => QrScanScreen(
                                        title: scannerPartLabel == null
                                            ? '출석 QR 스캔'
                                            : '$scannerPartLabel 파트 스캔',
                                        instruction: scannerPartLabel == null
                                            ? '단원의 출석 QR을 카메라에 비춰주세요'
                                            : '$scannerPartLabel 파트 단원의 출석 QR을 비춰주세요',
                                        onScanned: (code) async {
                                          final parsed = _attendanceQrFromCode(
                                            code,
                                          );
                                          final userId = parsed?.userId;
                                          if (parsed == null ||
                                              userId == null) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    '올바르지 않은 QR 코드입니다',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (parsed.churchId != null &&
                                              profile?.churchId != null &&
                                              parsed.churchId !=
                                                  profile?.churchId) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    '다른 교회 출석 QR입니다',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (parsed.sessionId != null &&
                                              session['id'] != null &&
                                              parsed.sessionId !=
                                                  session['id']) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    '현재 열린 출석 QR이 아닙니다',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          try {
                                            final result =
                                                await FirebaseService.adminCheckIn(
                                                  userId,
                                                  allowedPart: scannerPart,
                                                  scannerMode:
                                                      scannerPart == null
                                                      ? 'mobile_admin'
                                                      : 'mobile_part_leader',
                                                );
                                            if (context.mounted) {
                                              final name =
                                                  result['userName'] ?? '';
                                              final already =
                                                  result['alreadyCheckedIn'] ==
                                                  true;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    already
                                                        ? '$name님은 이미 출석했습니다'
                                                        : '$name님 출석 완료!',
                                                  ),
                                                  backgroundColor: already
                                                      ? null
                                                      : AppColors.success,
                                                ),
                                              );
                                            }
                                            ref.invalidate(
                                              activeSessionProvider,
                                            );
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text('출석 실패: $e'),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryContainer,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 18,
                          ),
                          label: Text(scannerPart == null ? 'QR 스캔' : '파트 스캔'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── My QR Code
          if (profile != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.qr_code_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(qrTitle, style: AppText.headline(18))),
                if (session != null) ...[
                  const SizedBox(width: 10),
                  const _LiveAttendanceBadge(),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 168,
                      eyeStyle: const QrEyeStyle(color: Color(0xFF000E24)),
                      dataModuleStyle: const QrDataModuleStyle(
                        color: Color(0xFF000E24),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(profile.displayName, style: AppText.headline(16)),
                    const SizedBox(height: 2),
                    Text(
                      qrSubtitle,
                      style: AppText.body(12, color: AppColors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Profile meta row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  _metaItem('파트', profile.partLabel),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                  _metaItem('기수', profile.generation ?? '-'),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                  _metaItem('총 출석', '$total회'),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Export button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final h = ref.read(myHistoryProvider).valueOrNull ?? [];
                final csv = h
                    .map((r) => '${r['sessionTitle']},${r['checkedInAt']}')
                    .join('\n');
                if (csv.isNotEmpty) {
                  await Share.share(csv, subject: 'C.C Note 출석기록');
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('출석 내보내기'),
            ),
          ),
          const SizedBox(height: 24),

          // History
          Text('출석 기록', style: AppText.headline(18)),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '아직 출석 기록이 없습니다',
                  style: AppText.body(14, color: AppColors.muted),
                ),
              ),
            )
          else
            ...history
                .take(10)
                .map(
                  (record) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record['sessionTitle'] ?? '',
                                style: AppText.body(
                                  14,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _fmt(record['checkedInAt']),
                                style: AppText.body(12, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: AppText.body(
              10,
              weight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: AppText.body(16, weight: FontWeight.w800)),
        ],
      ),
    );
  }

  void _showOpenSessionDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('출석 열기'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '연습 제목 (예: 주일 연습)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              if (ctrl.text.trim().isNotEmpty) {
                await FirebaseService.openSession(ctrl.text.trim());
                ref.invalidate(activeSessionProvider);
              }
            },
            child: const Text('열기'),
          ),
        ],
      ),
    );
  }

  static String _fmt(dynamic s) {
    if (s == null) return '';
    try {
      final d = DateTime.parse(s.toString());
      return '${d.year}.${d.month}.${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  static String _dateLabel(dynamic value) {
    if (value == null) return '오늘';
    try {
      final date = DateTime.parse(value.toString());
      return '${date.month}월 ${date.day}일';
    } catch (_) {
      return value.toString();
    }
  }

  static _AttendanceQr? _attendanceQrFromCode(String code) {
    final trimmed = code.trim();
    final sessionQr = RegExp(
      r'^ccnote:attendance:([^:]*):([^:]+):(.+)$',
    ).firstMatch(trimmed);
    if (sessionQr != null) {
      return _AttendanceQr(
        churchId: sessionQr.group(1),
        sessionId: sessionQr.group(2),
        userId: sessionQr.group(3),
      );
    }
    final memberQr = RegExp(
      r'^ccnote:member:([^:]*):(.+)$',
    ).firstMatch(trimmed);
    if (memberQr != null) {
      return _AttendanceQr(
        churchId: memberQr.group(1),
        userId: memberQr.group(2),
      );
    }
    final legacyQr = RegExp(r'^caleb-choir:(.+)$').firstMatch(trimmed);
    if (legacyQr != null) return _AttendanceQr(userId: legacyQr.group(1));
    return trimmed.isEmpty ? null : _AttendanceQr(userId: trimmed);
  }

  static String? _dateKeyFrom(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
    return parsed.toIso8601String().split('T').first;
  }
}

class _LiveAttendanceBadge extends StatefulWidget {
  const _LiveAttendanceBadge();

  @override
  State<_LiveAttendanceBadge> createState() => _LiveAttendanceBadgeState();
}

class _LiveAttendanceBadgeState extends State<_LiveAttendanceBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = 0.26 + (_controller.value * 0.34);
        final dotSize = 7.0 + (_controller.value * 2);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: glow),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE',
                style: AppText.body(
                  11,
                  weight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '출석 진행 중',
                style: AppText.body(
                  11,
                  weight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttendancePollSection extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> pollsAsync;
  final User? profile;
  final String? initialPollId;
  final String? initialTargetDate;
  final String? initialTitle;
  final Future<void> Function(String pollId, String choice) onVote;

  const _AttendancePollSection({
    required this.pollsAsync,
    required this.profile,
    required this.initialPollId,
    required this.initialTargetDate,
    required this.initialTitle,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    return pollsAsync.when(
      loading: () => _sectionShell(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (error, _) => _sectionShell(
        child: Text(
          '투표를 불러오지 못했습니다',
          style: AppText.body(14, color: AppColors.error),
        ),
      ),
      data: (polls) {
        final visible = polls.where((poll) {
          if (poll['isOpen'] != true) return false;
          if (profile?.isAdmin == true) return true;
          final scope = poll['scopePart'];
          return scope == null || scope == profile?.part;
        }).toList();

        visible.sort((a, b) {
          final aScore = _matchScore(a);
          final bScore = _matchScore(b);
          if (aScore != bScore) return bScore.compareTo(aScore);
          return (a['targetDate']?.toString() ?? '').compareTo(
            b['targetDate']?.toString() ?? '',
          );
        });

        return _sectionShell(
          child: visible.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.how_to_vote_rounded,
                        size: 28,
                        color: AppColors.subtle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '진행 중인 투표가 없습니다',
                        style: AppText.body(14, color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final poll in visible) ...[
                      _InlinePollCard(
                        poll: poll,
                        profile: profile,
                        highlighted: _matchScore(poll) > 0,
                        onVote: onVote,
                      ),
                      if (poll != visible.last) const SizedBox(height: 10),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _sectionShell({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.how_to_vote_rounded,
              size: 20,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 8),
            Text('참석 투표', style: AppText.headline(18)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  int _matchScore(Map<String, dynamic> poll) {
    if (initialPollId != null && poll['id']?.toString() == initialPollId) {
      return 3;
    }
    final targetDate = AttendanceScreen._dateKeyFrom(initialTargetDate);
    if (targetDate != null &&
        AttendanceScreen._dateKeyFrom(poll['targetDate']) == targetDate) {
      return 2;
    }
    final title = initialTitle?.trim();
    final pollTitle = poll['title']?.toString().trim() ?? '';
    if (title != null &&
        title.isNotEmpty &&
        pollTitle.isNotEmpty &&
        (pollTitle.contains(title) || title.contains(pollTitle))) {
      return 1;
    }
    return 0;
  }
}

class _ActiveAttendanceCard extends StatelessWidget {
  final Map<String, dynamic> session;
  const _ActiveAttendanceCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final date = AttendanceScreen._dateLabel(
      session['attendanceDate'] ?? session['openedAt'],
    );
    final title = session['title']?.toString().trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const Icon(
              Icons.qr_code_rounded,
              color: AppColors.secondaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '출석 진행 중',
                      style: AppText.body(
                        11,
                        weight: FontWeight.w900,
                        color: AppColors.secondaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title == null || title.isEmpty ? '$date 출석' : title,
                  style: AppText.body(
                    16,
                    weight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · 아래 QR이 현재 열린 출석용으로 갱신되었습니다',
                  style: AppText.body(
                    12,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlinePollCard extends ConsumerWidget {
  final Map<String, dynamic> poll;
  final User? profile;
  final bool highlighted;
  final Future<void> Function(String pollId, String choice) onVote;

  const _InlinePollCard({
    required this.poll,
    required this.profile,
    required this.highlighted,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pollId = poll['id']?.toString() ?? '';
    final votes = ref.watch(pollVotesProvider(pollId)).valueOrNull ?? [];
    final members = ref.watch(membersProvider).valueOrNull ?? [];
    final attend = votes.where((vote) => vote['choice'] == 'attend').length;
    final absent = votes.where((vote) => vote['choice'] == 'absent').length;
    final voted = attend + absent;
    final myVote = votes
        .where((vote) => vote['userId'] == profile?.id)
        .firstOrNull;
    final myChoice = myVote?['choice']?.toString();
    final scopePart = poll['scopePart']?.toString();
    final scopeLabel = scopePart == null
        ? '전체'
        : '${User.partLabels[scopePart] ?? scopePart} 파트';
    final eligible = _eligibleCount(members, scopePart, voted);
    final notVoted = eligible > voted ? eligible - voted : 0;
    final targetDate = AttendanceScreen._dateLabel(poll['targetDate']);
    final pollTitle = poll['title']?.toString() ?? '참석 투표';
    final attendNames = _voteNames(votes, members, 'attend');
    final absentNames = _voteNames(votes, members, 'absent');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.secondarySoft : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? AppColors.secondaryContainer.withValues(alpha: 0.8)
              : AppColors.border.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                targetDate,
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  scopeLabel,
                  style: AppText.body(
                    11,
                    weight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (myChoice != null)
                Text(
                  myChoice == 'attend' ? '내 투표: 참석' : '내 투표: 불참',
                  style: AppText.body(
                    12,
                    weight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pollTitle,
            style: AppText.body(16, weight: FontWeight.w900),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _choiceButton(
                  label: '참석',
                  count: attend,
                  choice: 'attend',
                  selected: myChoice == 'attend',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choiceButton(
                  label: '불참',
                  count: absent,
                  choice: 'absent',
                  selected: myChoice == 'absent',
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _voterNames(attendNames, AppColors.success)),
              const SizedBox(width: 10),
              Expanded(child: _voterNames(absentNames, AppColors.error)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            myChoice == null
                ? '$voted명 투표 · $notVoted명 미투표 · 내 투표: 아직 미투표'
                : '$voted명 투표 · $notVoted명 미투표',
            style: AppText.body(11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  int _eligibleCount(
    List<Map<String, dynamic>> members,
    String? scopePart,
    int votedCount,
  ) {
    final explicit = _intValue(
      poll['eligibleCount'] ??
          poll['targetCount'] ??
          poll['memberCount'] ??
          poll['totalMembers'],
    );
    if (explicit > 0) return explicit;

    final eligible = members.where((member) {
      final status = member['status']?.toString().toLowerCase();
      if (member['approved'] == false ||
          status == 'pending' ||
          status == 'rejected') {
        return false;
      }
      if (scopePart == null) return true;
      return member['part']?.toString() == scopePart;
    }).length;

    return eligible > 0 ? eligible : votedCount;
  }

  String _voteNames(
    List<Map<String, dynamic>> votes,
    List<Map<String, dynamic>> members,
    String choice,
  ) {
    final memberNames = <String, String>{
      for (final member in members)
        if (member['id'] != null)
          member['id'].toString():
              (member['name'] ?? member['displayName'] ?? '').toString(),
    };
    final names = <String>[];

    for (final vote in votes.where((vote) => vote['choice'] == choice)) {
      final userId = vote['userId']?.toString();
      final name =
          (vote['userName'] ??
                  vote['name'] ??
                  vote['displayName'] ??
                  (userId == null ? null : memberNames[userId]) ??
                  '')
              .toString()
              .trim();
      if (name.isNotEmpty && !names.contains(name)) {
        names.add(name);
      }
    }

    if (names.isEmpty) {
      return choice == 'attend' ? '아직 참석자 없음' : '아직 불참자 없음';
    }
    if (names.length > 4) {
      return '${names.take(4).join(', ')} 외 ${names.length - 4}명';
    }
    return names.join(', ');
  }

  Widget _voterNames(String names, Color accent) {
    return Text(
      names,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppText.body(
        10,
        weight: FontWeight.w700,
        color: accent.withValues(alpha: 0.58),
      ),
    );
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _choiceButton({
    required String label,
    required int count,
    required String choice,
    required bool selected,
    required Color color,
  }) {
    final foreground = selected ? Colors.white : color;
    final subColor = selected
        ? Colors.white.withValues(alpha: 0.72)
        : color.withValues(alpha: 0.68);

    return ElevatedButton(
      onPressed: () => onVote(poll['id'].toString(), choice),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? color : Colors.white,
        foregroundColor: foreground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.55)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppText.body(14, weight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            '$count명',
            style: AppText.body(10, weight: FontWeight.w800, color: subColor),
          ),
        ],
      ),
    );
  }
}

class _AttendanceQr {
  final String? churchId;
  final String? sessionId;
  final String? userId;

  const _AttendanceQr({this.churchId, this.sessionId, this.userId});
}
