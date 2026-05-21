import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/caleb_score_surface.dart';
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
        ((profile?.isAdmin ?? false) || (profile?.isPartLeader ?? false)) &&
        !viewAsMember;
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
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('투표 실패: $e')));
                }
                rethrow;
              }
            },
          ),
          const SizedBox(height: 14),

          // ── Attendance operator controls
          if (canOperateSession || canScanAttendance) ...[
            _AttendanceOperatorPanel(
              title: canOperateSession ? '출석 운영' : '파트장 스캐너',
              subtitle: scannerPartLabel == null
                  ? (session == null
                        ? '출석을 열면 QR 스캔을 시작할 수 있습니다'
                        : '열린 출석 세션의 QR을 스캔합니다')
                  : '$scannerPartLabel 파트 단원 QR만 출석 처리됩니다',
              actions: [
                if (canOperateSession)
                  _AttendanceControlAction(
                    label: session != null ? '출석 마감' : '출석 열기',
                    icon: session != null
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    tone: session != null
                        ? _AttendanceControlTone.danger
                        : _AttendanceControlTone.warm,
                    filled: session == null,
                    onTap: session != null
                        ? () async {
                            await FirebaseService.closeSession(session['id']);
                            ref.invalidate(activeSessionProvider);
                          }
                        : () => _showOpenSessionDialog(context, ref),
                  ),
                _AttendanceControlAction(
                  label: scannerPart == null ? 'QR 스캔' : '파트 스캔',
                  icon: Icons.qr_code_scanner_rounded,
                  tone: _AttendanceControlTone.primary,
                  filled: true,
                  onTap: session == null
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
                                  final parsed = _attendanceQrFromCode(code);
                                  final userId = parsed?.userId;
                                  if (parsed == null || userId == null) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('올바르지 않은 QR 코드입니다'),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  if (parsed.churchId != null &&
                                      profile?.churchId != null &&
                                      parsed.churchId != profile?.churchId) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('다른 교회 출석 QR입니다'),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  if (parsed.sessionId != null &&
                                      session['id'] != null &&
                                      parsed.sessionId != session['id']) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('현재 열린 출석 QR이 아닙니다'),
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
                                          scannerMode: scannerPart == null
                                              ? 'mobile_admin'
                                              : 'mobile_part_leader',
                                        );
                                    if (context.mounted) {
                                      final name = result['userName'] ?? '';
                                      final already =
                                          result['alreadyCheckedIn'] == true;
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
                                    ref.invalidate(activeSessionProvider);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '출석 실패: ${_cleanErrorMessage(e)}',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          );
                        },
                ),
              ],
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

class _AttendanceOperatorPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_AttendanceControlAction> actions;

  const _AttendanceOperatorPanel({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CalebScoreSurface(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
        spineColor: AppColors.secondary,
        staffOpacity: 0.34,
        showVerticalMarks: false,
        showFold: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 2,
                  height: 24,
                  color: AppColors.secondary.withValues(alpha: 0.64),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.body(
                          14,
                          weight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < actions.length; i += 1) ...[
                  Expanded(child: _AttendanceControlButton(action: actions[i])),
                  if (i != actions.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceControlAction {
  final String label;
  final IconData icon;
  final _AttendanceControlTone tone;
  final bool filled;
  final VoidCallback? onTap;

  const _AttendanceControlAction({
    required this.label,
    required this.icon,
    required this.tone,
    required this.filled,
    required this.onTap,
  });
}

enum _AttendanceControlTone { primary, warm, danger }

class _AttendanceControlButton extends StatelessWidget {
  final _AttendanceControlAction action;

  const _AttendanceControlButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final color = switch (action.tone) {
      _AttendanceControlTone.primary => AppColors.primary,
      _AttendanceControlTone.warm => AppColors.secondary,
      _AttendanceControlTone.danger => AppColors.error,
    };
    final foreground = action.filled ? Colors.white : color;
    final background = action.filled
        ? color
        : enabled
        ? Colors.white
        : AppColors.surfaceLow;
    final borderColor = enabled
        ? color.withValues(alpha: action.filled ? 0 : 0.42)
        : AppColors.border.withValues(alpha: 0.34);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: 17,
                color: enabled ? foreground : AppColors.muted,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    action.label,
                    maxLines: 1,
                    style: AppText.body(
                      13,
                      weight: FontWeight.w800,
                      color: enabled ? foreground : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: AppColors.secondaryContainer.withValues(alpha: 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 5),
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
              borderRadius: BorderRadius.circular(8),
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

class _InlinePollCard extends ConsumerStatefulWidget {
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
  ConsumerState<_InlinePollCard> createState() => _InlinePollCardState();
}

class _InlinePollCardState extends ConsumerState<_InlinePollCard> {
  String? _pendingChoice;
  String? _optimisticChoice;

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final pollId = poll['id']?.toString() ?? '';
    final votes = ref.watch(pollVotesProvider(pollId)).valueOrNull ?? [];
    final members = ref.watch(membersProvider).valueOrNull ?? [];
    final myVote = votes
        .where((vote) => vote['userId'] == widget.profile?.id)
        .firstOrNull;
    final myChoice = myVote?['choice']?.toString();
    final effectiveChoice = _optimisticChoice ?? myChoice;
    var attend = votes.where((vote) => vote['choice'] == 'attend').length;
    var absent = votes.where((vote) => vote['choice'] == 'absent').length;
    if (_optimisticChoice != null && _optimisticChoice != myChoice) {
      if (myChoice == 'attend') attend--;
      if (myChoice == 'absent') absent--;
      if (_optimisticChoice == 'attend') attend++;
      if (_optimisticChoice == 'absent') absent++;
      attend = attend < 0 ? 0 : attend;
      absent = absent < 0 ? 0 : absent;
    }
    final voted = attend + absent;
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

    return SizedBox(
      width: double.infinity,
      child: CalebScoreSurface(
        padding: const EdgeInsets.all(12),
        backgroundColor: widget.highlighted
            ? AppColors.secondarySoft
            : AppColors.paper,
        borderColor: widget.highlighted
            ? AppColors.secondaryContainer.withValues(alpha: 0.78)
            : AppColors.paperLine,
        spineColor: widget.highlighted
            ? AppColors.secondary
            : AppColors.primary,
        staffOpacity: widget.highlighted ? 0.34 : 0.42,
        showFold: widget.highlighted,
        showVerticalMarks: false,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                if (effectiveChoice != null)
                  Text(
                    effectiveChoice == 'attend' ? '내 투표: 참석' : '내 투표: 불참',
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
                    selected: effectiveChoice == 'attend',
                    color: AppColors.success,
                    names: attendNames,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _choiceButton(
                    label: '불참',
                    count: absent,
                    choice: 'absent',
                    selected: effectiveChoice == 'absent',
                    color: AppColors.error,
                    names: absentNames,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              effectiveChoice == null
                  ? '$voted명 투표 · $notVoted명 미투표 · 내 투표: 아직 미투표'
                  : '$voted명 투표 · $notVoted명 미투표',
              style: AppText.body(11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  int _eligibleCount(
    List<Map<String, dynamic>> members,
    String? scopePart,
    int votedCount,
  ) {
    final poll = widget.poll;
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

  List<String> _voteNames(
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

    return names;
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
    required List<String> names,
  }) {
    final pending = _pendingChoice == choice;
    final disabled = _pendingChoice != null;
    final icon = choice == 'attend'
        ? Icons.event_available_rounded
        : Icons.event_busy_rounded;
    final background = selected ? color : color.withValues(alpha: 0.055);
    final borderColor = selected
        ? color
        : color.withValues(alpha: disabled ? 0.14 : 0.26);
    final labelColor = selected ? Colors.white : AppColors.ink;
    final metaColor = selected
        ? Colors.white.withValues(alpha: 0.78)
        : color.withValues(alpha: disabled ? 0.44 : 0.7);
    final iconBackground = selected
        ? Colors.white.withValues(alpha: 0.18)
        : color.withValues(alpha: 0.1);
    final iconColor = selected ? Colors.white : color;
    final metaText = selected ? '$count명 · 명단 보기' : '$count명';

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $metaText',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled
              ? null
              : selected
              ? () => _showVoteListSheet(label, names, color)
              : () => _handleVote(choice),
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: pending
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: iconColor,
                            ),
                          )
                        : Icon(icon, size: 17, color: iconColor),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          13,
                          weight: FontWeight.w900,
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          10,
                          weight: FontWeight.w800,
                          color: metaColor,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          key: const ValueKey('selected'),
                          size: 18,
                          color: Colors.white,
                        )
                      : Container(
                          key: const ValueKey('idle'),
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color.withValues(alpha: 0.28),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVoteListSheet(String label, List<String> names, Color color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.border.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        label == '참석'
                            ? Icons.event_available_rounded
                            : Icons.event_busy_rounded,
                        size: 20,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label 명단',
                            style: AppText.body(17, weight: FontWeight.w900),
                          ),
                          Text(
                            '${names.length}명',
                            style: AppText.body(12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (names.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      label == '참석' ? '아직 참석자 없음' : '아직 불참자 없음',
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in names)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Text(
                            name,
                            style: AppText.body(
                              12,
                              weight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleVote(String choice) async {
    final pollId = widget.poll['id']?.toString();
    if (pollId == null || pollId.isEmpty || _pendingChoice != null) return;
    setState(() {
      _pendingChoice = choice;
      _optimisticChoice = choice;
    });
    try {
      await widget.onVote(pollId, choice);
      if (mounted) setState(() => _pendingChoice = null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingChoice = null;
        _optimisticChoice = null;
      });
    }
  }
}

class _AttendanceQr {
  final String? churchId;
  final String? sessionId;
  final String? userId;

  const _AttendanceQr({this.churchId, this.sessionId, this.userId});
}

String _cleanErrorMessage(Object error) {
  final text = error.toString().trim();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) return text.substring(prefix.length);
  return text;
}
