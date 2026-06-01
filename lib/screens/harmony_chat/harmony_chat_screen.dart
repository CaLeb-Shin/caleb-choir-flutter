import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/user.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import 'relay_backing_audio_web.dart'
    if (dart.library.io) 'relay_backing_audio_mobile.dart'
    as relay_backing_audio;

final _lastSubmittedHarmonyRelayProvider = StateProvider<String?>(
  (ref) => null,
);

const _microphonePermissionGrantedKey = 'harmony_microphone_permission_granted';
bool? _microphonePermissionGrantedInSession;

class HarmonyChatScreen extends ConsumerWidget {
  const HarmonyChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final notesAsync = ref.watch(harmonyNotesProvider);
    final relaysAsync = ref.watch(harmonyRelaysProvider);
    final guideAsync = ref.watch(latestPartGuideProvider);
    final missionAsync = ref.watch(activeHarmonyPracticeMissionProvider);
    final practiceProgressAsync = ref.watch(harmonyPracticeProgressProvider);
    final practiceSubmissionsAsync = ref.watch(
      myHarmonyPracticeSubmissionsProvider,
    );
    final partReviewAsync = ref.watch(partPracticeReviewProvider);
    final part = profile?.partLeaderFor ?? profile?.part ?? '';
    final partLabel = User.partLabels[part] ?? '내 파트';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('하모니챗', style: AppText.headline(28)),
                    const SizedBox(height: 8),
                    _HarmonyLevelPill(
                      profile: profile,
                      progressAsync: practiceProgressAsync,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: part.isEmpty
                    ? null
                    : () => _openComposeSheet(context, ref, part),
                icon: const Icon(Icons.mic_rounded, size: 18),
                label: const Text('녹음'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PersonalPracticeSection(
            part: part,
            partLabel: partLabel,
            profile: profile,
            guideAsync: guideAsync,
            missionAsync: missionAsync,
            progressAsync: practiceProgressAsync,
            submissionsAsync: practiceSubmissionsAsync,
            ref: ref,
          ),
          if (profile?.isPartLeader ?? false) ...[
            const SizedBox(height: 16),
            _PartLeaderReviewSection(
              partLabel: partLabel,
              reviewAsync: partReviewAsync,
              ref: ref,
            ),
          ],
          const SizedBox(height: 16),
          _RelaySection(
            part: part,
            partLabel: partLabel,
            relaysAsync: relaysAsync,
            ref: ref,
          ),
          const SizedBox(height: 16),
          _TodayGuideCard(
            part: part,
            partLabel: partLabel,
            guideAsync: guideAsync,
            ref: ref,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '노트',
                  style: AppText.body(18, weight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          notesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stackTrace) => _EmptyHarmonyState(
              icon: Icons.lock_outline_rounded,
              title: '하모니챗을 불러올 수 없습니다',
              message: '권한이나 네트워크 상태를 확인한 뒤 다시 시도해주세요.',
            ),
            data: (notes) {
              if (part.isEmpty) {
                return const _EmptyHarmonyState(
                  icon: Icons.groups_2_outlined,
                  title: '소속 파트가 필요합니다',
                  message: '관리자가 파트를 지정하면 하모니챗을 사용할 수 있어요.',
                );
              }
              if (notes.isEmpty) {
                return _EmptyHarmonyState(
                  icon: Icons.graphic_eq_rounded,
                  title: '$partLabel 노트가 비어 있습니다',
                  message: '첫 노트를 남겨보세요.',
                );
              }
              return Column(
                children: notes
                    .map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _HarmonyNoteCard(note: note),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openComposeSheet(BuildContext context, WidgetRef ref, String part) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _HarmonyNoteSheet(part: part, ref: ref),
    );
  }
}

class _HarmonyLevelPill extends StatelessWidget {
  const _HarmonyLevelPill({required this.profile, required this.progressAsync});

  final User? profile;
  final AsyncValue<Map<String, dynamic>> progressAsync;

  @override
  Widget build(BuildContext context) {
    final progress = progressAsync.valueOrNull ?? const <String, dynamic>{};
    final xp = (progress['xp'] as num?)?.toInt() ?? 0;
    final level =
        (progress['level'] as num?)?.toInt() ??
        FirebaseService.harmonyLevelForXp(xp);
    final name = _firstText([
      profile?.nickname,
      profile?.name,
      FirebaseService.currentUser?.displayName,
      '나',
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.42)),
      ),
      child: Text(
        '$name · Lv.$level',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(
          12,
          weight: FontWeight.w900,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _PersonalPracticeSection extends StatelessWidget {
  const _PersonalPracticeSection({
    required this.part,
    required this.partLabel,
    required this.profile,
    required this.guideAsync,
    required this.missionAsync,
    required this.progressAsync,
    required this.submissionsAsync,
    required this.ref,
  });

  final String part;
  final String partLabel;
  final User? profile;
  final AsyncValue<Map<String, dynamic>?> guideAsync;
  final AsyncValue<Map<String, dynamic>?> missionAsync;
  final AsyncValue<Map<String, dynamic>> progressAsync;
  final AsyncValue<List<Map<String, dynamic>>> submissionsAsync;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final guide = guideAsync.valueOrNull;
    final mission = missionAsync.valueOrNull;
    final progress = progressAsync.valueOrNull ?? const <String, dynamic>{};
    final submissions = submissionsAsync.valueOrNull ?? const [];
    final mrAudioUrl = guide?['mrAudioUrl']?.toString().trim() ?? '';
    final guideAudioUrl = guide?['guideAudioUrl']?.toString().trim() ?? '';
    // Personal practice now sings along to the admin's per-part guide vocal,
    // falling back to the MR track only when no guide was attached.
    final hasBacking = guideAudioUrl.isNotEmpty || mrAudioUrl.isNotEmpty;
    final xp = (progress['xp'] as num?)?.toInt() ?? 0;
    final level =
        (progress['level'] as num?)?.toInt() ??
        FirebaseService.harmonyLevelForXp(xp);
    final currentLevelXp = FirebaseService.harmonyXpForLevel(level);
    final nextLevelXp = FirebaseService.harmonyXpForLevel(
      (level + 1).clamp(1, 100).toInt(),
    );
    final levelRatio = level >= 100
        ? 1.0
        : ((xp - currentLevelXp) / math.max(1, nextLevelXp - currentLevelXp))
              .clamp(0.0, 1.0);
    final missionTitle = _firstText([
      mission?['title']?.toString(),
      guide?['songTitle']?.toString(),
      '오늘 개인연습',
    ]);
    final missionPrompt = _firstText([
      mission?['prompt']?.toString(),
      guide?['guide']?.toString(),
      'MR을 틀고 한 번 녹음해보세요. 끝나면 파트장에게 피드백을 보낼 수 있어요.',
    ]);
    final xpReward = (mission?['xpReward'] as num?)?.toInt() ?? 25;
    final todayDone = submissions.any(_submissionIsToday);
    final reviewedCount = submissions
        .where((item) => (item['leaderFeedback']?.toString() ?? '').isNotEmpty)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '개인연습',
                      style: AppText.body(18, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      part.isEmpty
                          ? '파트가 지정되면 미션을 시작할 수 있어요.'
                          : '$partLabel · 오늘 ${todayDone ? '완료' : '대기'}',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              _TurnPill(
                label: todayDone ? '완료' : '+$xpReward XP',
                active: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        missionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          17,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Lv.$level',
                      style: AppText.body(
                        12,
                        weight: FontWeight.w900,
                        color: AppColors.secondaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  missionPrompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    12,
                    color: Colors.white.withValues(alpha: 0.74),
                    height: 1.38,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: levelRatio,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    color: AppColors.secondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PracticeMetricChip(
                icon: Icons.local_fire_department_rounded,
                label:
                    '누적 ${(progress['practiceCount'] as num?)?.toInt() ?? 0}회',
              ),
              _PracticeMetricChip(icon: Icons.stars_rounded, label: '$xp XP'),
              _PracticeMetricChip(
                icon: Icons.rate_review_rounded,
                label: '피드백 $reviewedCount개',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '실시간으로 가사 보며 가이드 음원 듣고 따라 부르며 연습해요!',
                    style: AppText.body(
                      13,
                      weight: FontWeight.w800,
                      color: AppColors.primary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: part.isEmpty || !hasBacking
                  ? null
                  : () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _PersonalPracticeSheet(
                        part: part,
                        partLabel: partLabel,
                        guide: guide ?? const {},
                        mission: mission ?? const {},
                        ref: ref,
                      ),
                    ),
              icon: const Icon(Icons.mic_rounded),
              label: Text(hasBacking ? '파트 가이드 연습 시작' : '가이드 준비 필요'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 13, color: AppColors.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '연습 녹음은 나와 파트장만 볼 수 있어요.',
                  style: AppText.body(11, color: AppColors.muted),
                ),
              ),
            ],
          ),
          if (submissions.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...submissions
                .take(2)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PracticeSubmissionCard(submission: item),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  bool _submissionIsToday(Map<String, dynamic> submission) {
    final date = submission['practiceDate']?.toString();
    if (date != null && date.isNotEmpty) return date == _todayKeyLocal();
    final created = DateTime.tryParse(
      submission['createdAt']?.toString() ?? '',
    );
    if (created == null) return false;
    final now = DateTime.now();
    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }
}

class _PracticeMetricChip extends StatelessWidget {
  const _PracticeMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(label, style: AppText.body(11, weight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _PracticeSubmissionCard extends StatelessWidget {
  const _PracticeSubmissionCard({required this.submission});

  final Map<String, dynamic> submission;

  @override
  Widget build(BuildContext context) {
    final feedback = submission['leaderFeedback']?.toString().trim() ?? '';
    final status = feedback.isNotEmpty ? '피드백 도착' : '피드백 대기';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: feedback.isNotEmpty ? AppColors.secondarySoft : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            feedback.isNotEmpty
                ? Icons.mark_chat_read_rounded
                : Icons.hourglass_top_rounded,
            color: feedback.isNotEmpty ? AppColors.secondary : AppColors.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: AppText.body(12, weight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  feedback.isNotEmpty
                      ? feedback
                      : '${submission['missionTitle'] ?? '개인연습'} · ${_relativeTime(submission['createdAt'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(12, color: AppColors.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Member name shown to the part leader as "이름(닉네임)_파트".
String _practiceAuthorLabel(Map<String, dynamic> submission) {
  final name = (submission['userName'] as String?)?.trim() ?? '';
  final nickname = (submission['userNickname'] as String?)?.trim() ?? '';
  final part = (submission['userPart'] as String?)?.trim() ?? '';
  final partLabel = User.partLabels[part] ?? '';
  final buffer = StringBuffer(name.isEmpty ? '익명' : name);
  if (nickname.isNotEmpty) buffer.write('($nickname)');
  if (partLabel.isNotEmpty) buffer.write('_$partLabel');
  return buffer.toString();
}

/// Part-leader-only section that lists the part's practice takes so the leader
/// can listen and leave feedback. Hidden entirely when there's nothing to show.
class _PartLeaderReviewSection extends StatelessWidget {
  const _PartLeaderReviewSection({
    required this.partLabel,
    required this.reviewAsync,
    required this.ref,
  });

  final String partLabel;
  final AsyncValue<List<Map<String, dynamic>>> reviewAsync;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final submissions = reviewAsync.valueOrNull ?? const [];
    final pending = submissions
        .where((s) => (s['leaderFeedback']?.toString() ?? '').trim().isEmpty)
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.rate_review_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '파트원 연습 피드백',
                      style: AppText.body(18, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$partLabel 파트장 · 받은 연습 ${submissions.length}개',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (pending > 0)
                _TurnPill(label: '대기 $pending', active: true),
            ],
          ),
          const SizedBox(height: 14),
          if (reviewAsync.isLoading && submissions.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (submissions.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '아직 도착한 연습 녹음이 없어요. 파트원이 보내면 여기에서 듣고 피드백할 수 있어요.',
                style: AppText.body(12, color: AppColors.muted, height: 1.4),
              ),
            )
          else
            ...submissions.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LeaderReviewCard(submission: item, ref: ref),
              ),
            ),
        ],
      ),
    );
  }
}

class _LeaderReviewCard extends StatefulWidget {
  const _LeaderReviewCard({required this.submission, required this.ref});

  final Map<String, dynamic> submission;
  final WidgetRef ref;

  @override
  State<_LeaderReviewCard> createState() => _LeaderReviewCardState();
}

class _LeaderReviewCardState extends State<_LeaderReviewCard> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlay(String url) async {
    if (url.isEmpty) return;
    try {
      if (_playing) {
        await _player.stop();
        if (mounted) setState(() => _playing = false);
        return;
      }
      await _player.stop();
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _openFeedbackEditor() async {
    final controller = TextEditingController(
      text: widget.submission['leaderFeedback']?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('피드백 남기기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _practiceAuthorLabel(widget.submission),
              style: AppText.body(12, weight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '예) 첫 음 진입이 좋아요. 후렴은 호흡을 한 번 더 채워볼까요?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    try {
      await FirebaseService.submitLeaderFeedback(
        submissionId: widget.submission['id']?.toString() ?? '',
        feedback: text,
      );
      widget.ref.invalidate(partPracticeReviewProvider);
      widget.ref.invalidate(myHarmonyPracticeSubmissionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('피드백을 보냈어요.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('피드백 전송에 실패했어요.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    final audioUrl = submission['audioUrl']?.toString() ?? '';
    final feedback = submission['leaderFeedback']?.toString().trim() ?? '';
    final done = feedback.isNotEmpty;
    final duration = (submission['durationSeconds'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done ? AppColors.secondarySoft : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => _togglePlay(audioUrl),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _practiceAuthorLabel(submission),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(13, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${submission['missionTitle'] ?? '개인연습'} · ${_relativeTime(submission['createdAt'])}${duration > 0 ? ' · ${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.secondary.withValues(alpha: 0.18)
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  done ? '완료' : '대기',
                  style: AppText.body(
                    10,
                    weight: FontWeight.w900,
                    color: done ? AppColors.secondary : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (done) ...[
            const SizedBox(height: 8),
            Text(
              feedback,
              style: AppText.body(12, color: AppColors.ink, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openFeedbackEditor,
              icon: Icon(
                done ? Icons.edit_rounded : Icons.rate_review_rounded,
                size: 18,
              ),
              label: Text(done ? '피드백 수정' : '피드백 남기기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalPracticeSheet extends StatefulWidget {
  const _PersonalPracticeSheet({
    required this.part,
    required this.partLabel,
    required this.guide,
    required this.mission,
    required this.ref,
  });

  final String part;
  final String partLabel;
  final Map<String, dynamic> guide;
  final Map<String, dynamic> mission;
  final WidgetRef ref;

  @override
  State<_PersonalPracticeSheet> createState() => _PersonalPracticeSheetState();
}

class _PersonalPracticeSheetState extends State<_PersonalPracticeSheet>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  final _mrPlayer = AudioPlayer();
  final _takePlayer = AudioPlayer();
  StreamSubscription<void>? _takeCompleteSub;
  final List<int> _recordedBytes = [];
  StreamSubscription<Uint8List>? _recordingSub;
  Timer? _timer;
  late final AnimationController _burstController;
  Uint8List? _audioBytes;
  bool _streamRecording = false;
  bool _isRecording = false;
  bool _isSubmitting = false;
  bool _completed = false;
  bool _isPlayingTake = false;
  int? _countdown;
  int _recordSeconds = 0;
  double _uploadProgress = 0;
  String _contentType = 'audio/webm';
  String _fileName = '';

  static const _sampleRate = 44100;
  static const _channels = 1;

  String get _mrAudioUrl => widget.guide['mrAudioUrl']?.toString().trim() ?? '';
  String get _guideAudioUrl =>
      widget.guide['guideAudioUrl']?.toString().trim() ?? '';
  String get _guideAudioFileName =>
      widget.guide['guideAudioFileName']?.toString().trim() ?? '';
  // Sing along to the part guide vocal when the admin attached one; otherwise
  // fall back to the MR backing track.
  String get _backingUrl =>
      _guideAudioUrl.isNotEmpty ? _guideAudioUrl : _mrAudioUrl;
  String get _backingLabel => _guideAudioUrl.isNotEmpty ? '파트 가이드' : 'MR';
  String get _backingFileName => _guideAudioUrl.isNotEmpty
      ? (_guideAudioFileName.isEmpty ? '파트 가이드' : _guideAudioFileName)
      : (_mrAudioFileName.isEmpty ? 'MR' : _mrAudioFileName);
  String get _mrAudioFileName =>
      widget.guide['mrAudioFileName']?.toString().trim() ?? '';
  String get _missionId => widget.mission['id']?.toString() ?? '';
  String get _missionTitle => _firstText([
    widget.mission['title']?.toString(),
    widget.guide['songTitle']?.toString(),
    '개인연습',
  ]);
  String get _practiceTitle =>
      '${_firstText([widget.guide['songTitle']?.toString(), widget.guide['title']?.toString(), '하모니챗'])} 개인연습';
  int get _xpReward => (widget.mission['xpReward'] as num?)?.toInt() ?? 25;

  @override
  void initState() {
    super.initState();
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _takeCompleteSub = _takePlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingTake = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordingSub?.cancel();
    _takeCompleteSub?.cancel();
    _burstController.dispose();
    unawaited(_recorder.dispose());
    unawaited(_mrPlayer.dispose());
    unawaited(_takePlayer.dispose());
    relay_backing_audio.stopRelayBackingAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit = _audioBytes != null && !_isRecording && !_isSubmitting;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '개인연습',
                        style: AppText.body(20, weight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const _InlineCloseIcon(size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$_missionTitle · ${widget.partLabel}',
                  style: AppText.body(13, color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _completed
                            ? AppColors.secondarySoft
                            : AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color:
                              (_completed
                                      ? AppColors.secondary
                                      : AppColors.border)
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_countdown != null)
                            Text(
                              '$_countdown',
                              style: AppText.headline(
                                46,
                                color: AppColors.primary,
                              ),
                            )
                          else
                            Icon(
                              _completed
                                  ? Icons.celebration_rounded
                                  : _isRecording
                                  ? Icons.graphic_eq_rounded
                                  : Icons.mic_rounded,
                              size: 42,
                              color: _completed
                                  ? AppColors.secondary
                                  : AppColors.primary,
                            ),
                          const SizedBox(height: 10),
                          Text(
                            _countdown != null
                                ? '잠시 후 시작합니다'
                                : _completed
                                ? '오늘 1회 연습 완료!'
                                : _isRecording
                                ? '$_backingLabel에 맞춰 녹음 중 ${_formatDuration(_recordSeconds)}'
                                : '$_backingLabel를 들으며 내 목소리를 녹음합니다',
                            textAlign: TextAlign.center,
                            style: AppText.body(18, weight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _completed
                                ? '+$_xpReward XP가 준비됐어요. 파트장에게 보내면 기록됩니다.'
                                : '녹음이 끝나면 연습 완료 연출이 뜨고 피드백을 요청할 수 있어요.',
                            textAlign: TextAlign.center,
                            style: AppText.body(
                              12,
                              color: AppColors.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_completed)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _PracticeCompletionBurst(
                            animation: _burstController,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '오늘 미션',
                        style: AppText.body(12, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _firstText([
                          widget.mission['prompt']?.toString(),
                          widget.guide['guide']?.toString(),
                          '$_backingLabel를 들으며 한 번 이상 녹음해보세요.',
                        ]),
                        style: AppText.body(
                          13,
                          color: AppColors.onSurfaceVariant,
                          height: 1.38,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PracticeMetricChip(
                            icon: Icons.headphones_rounded,
                            label: _backingFileName,
                          ),
                          _PracticeMetricChip(
                            icon: Icons.stars_rounded,
                            label: '+$_xpReward XP',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_isSubmitting) ...[
                  const SizedBox(height: 14),
                  _UploadProgressPanel(progress: _uploadProgress),
                ],
                const SizedBox(height: 16),
                if (_audioBytes != null &&
                    !_isRecording &&
                    _countdown == null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _toggleTakePlayback,
                      icon: Icon(
                        _isPlayingTake
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(_isPlayingTake ? '재생 멈추기' : '내 녹음 다시 듣기'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySoft.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        size: 15,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '이 녹음은 나와 ${widget.partLabel} 파트장만 들을 수 있어요. 다른 단원에게는 보이지 않아요.',
                          style: AppText.body(
                            11.5,
                            weight: FontWeight.w700,
                            color: AppColors.secondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _isSubmitting || _countdown != null
                            ? null
                            : _isRecording
                            ? _stopRecording
                            : _startRecording,
                        icon: Icon(
                          _isRecording
                              ? Icons.stop_rounded
                              : Icons.fiber_manual_record_rounded,
                        ),
                        label: Text(_isRecording ? '녹음 끝내기' : '녹음하기'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: canSubmit ? _requestFeedback : null,
                        icon: const Icon(Icons.rate_review_rounded),
                        label: const Text('파트장에게 피드백 받기'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runCountdown() async {
    try {
      for (final value in const [3, 2, 1]) {
        if (!mounted) return;
        setState(() => _countdown = value);
        unawaited(HapticFeedback.lightImpact());
        await Future<void>.delayed(const Duration(milliseconds: 760));
      }
    } finally {
      if (mounted) setState(() => _countdown = null);
    }
  }

  Future<void> _toggleTakePlayback() async {
    final bytes = _audioBytes;
    if (bytes == null || bytes.isEmpty) return;
    if (_isPlayingTake) {
      await _takePlayer.stop();
      if (mounted) setState(() => _isPlayingTake = false);
      return;
    }
    try {
      unawaited(HapticFeedback.selectionClick());
      await _mrPlayer.stop();
      relay_backing_audio.stopRelayBackingAudio();
      await _takePlayer.stop();
      await _takePlayer.play(BytesSource(bytes, mimeType: _contentType));
      if (mounted) setState(() => _isPlayingTake = true);
    } catch (_) {
      if (mounted) setState(() => _isPlayingTake = false);
      _showMessage('녹음 재생에 실패했어요.');
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _countdown != null) return;
    try {
      final hasPermission = await _ensureMicrophonePermission(_recorder);
      if (!hasPermission) {
        if (widget.ref.read(localPreviewModeProvider)) {
          _completeWithBytes(_previewPracticeToneBytes(5), 5, 'audio/wav');
          _showMessage('미리보기에서는 테스트 녹음으로 완료 처리했어요.');
          return;
        }
        _showMessage('마이크 권한이 필요합니다.');
        return;
      }

      if (_isPlayingTake) {
        await _takePlayer.stop();
        if (mounted) setState(() => _isPlayingTake = false);
      }

      // Give the singer a 3·2·1 lead-in (same feel as the relay studio) before
      // the MR and recorder start together.
      await _runCountdown();
      if (!mounted) return;

      await _recordingSub?.cancel();
      _recordedBytes.clear();
      _streamRecording = false;
      _contentType = 'audio/webm';
      _fileName = 'practice_${DateTime.now().millisecondsSinceEpoch}.webm';

      final backingUrl = _backingUrl;
      if (backingUrl.isNotEmpty) {
        try {
          if (!kIsWeb ||
              !relay_backing_audio.startRelayBackingAudio(
                backingUrl,
                Duration.zero,
              )) {
            await _mrPlayer.stop();
            await _mrPlayer.setReleaseMode(ReleaseMode.stop);
            unawaited(_mrPlayer.play(UrlSource(backingUrl)));
          }
        } catch (_) {
          _showMessage('$_backingLabel 재생은 실패했지만 녹음은 시작합니다.');
        }
      }

      if (kIsWeb) {
        final stream = await _recorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: _sampleRate,
            numChannels: _channels,
            echoCancel: true,
            noiseSuppress: false,
            autoGain: false,
          ),
        );
        _streamRecording = true;
        _contentType = 'audio/wav';
        _fileName = 'practice_${DateTime.now().millisecondsSinceEpoch}.wav';
        _recordingSub = stream.listen(_recordedBytes.addAll);
      } else {
        await _recorder.start(
          RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 128000,
            sampleRate: _sampleRate,
            numChannels: _channels,
            echoCancel: true,
            noiseSuppress: false,
            autoGain: false,
          ),
          path: '',
        );
      }

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds += 1);
      });
      setState(() {
        _isRecording = true;
        _completed = false;
        _recordSeconds = 0;
        _audioBytes = null;
      });
      unawaited(HapticFeedback.mediumImpact());
    } catch (_) {
      unawaited(_forgetMicrophonePermissionIfRevoked());
      await _mrPlayer.stop();
      relay_backing_audio.stopRelayBackingAudio();
      if (widget.ref.read(localPreviewModeProvider)) {
        _completeWithBytes(_previewPracticeToneBytes(5), 5, 'audio/wav');
        _showMessage('미리보기에서는 테스트 녹음으로 완료 처리했어요.');
        return;
      }
      _showMessage('녹음을 시작할 수 없습니다. 마이크 권한을 확인해주세요.');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      await _mrPlayer.stop();
      relay_backing_audio.stopRelayBackingAudio();
      _timer?.cancel();
      _timer = null;
      final stoppedPath = await _recorder.stop();
      final recordedPath = _streamRecording ? null : stoppedPath;
      await _recordingSub?.cancel();
      _recordingSub = null;
      Uint8List recorded;
      if (recordedPath != null && recordedPath.isNotEmpty) {
        recorded = await _bytesFromRecordedPath(recordedPath);
      } else {
        final pcmBytes = Uint8List.fromList(_recordedBytes);
        recorded = pcmBytes.isEmpty
            ? Uint8List(0)
            : _wavFromPcmBytes(
                pcmBytes,
                sampleRate: _sampleRate,
                channels: _channels,
              );
      }
      if (recorded.isEmpty) {
        if (widget.ref.read(localPreviewModeProvider)) {
          _completeWithBytes(_previewPracticeToneBytes(5), 5, 'audio/wav');
          _showMessage('미리보기에서는 테스트 녹음으로 완료 처리했어요.');
          return;
        }
        setState(() => _isRecording = false);
        _showMessage('녹음된 소리가 없습니다. 다시 시도해주세요.');
        return;
      }
      _completeWithBytes(recorded, math.max(1, _recordSeconds), _contentType);
    } catch (_) {
      setState(() => _isRecording = false);
      await _mrPlayer.stop();
      relay_backing_audio.stopRelayBackingAudio();
      _showMessage('녹음을 마무리하지 못했습니다. 다시 시도해주세요.');
    }
  }

  void _completeWithBytes(Uint8List bytes, int durationSeconds, String type) {
    setState(() {
      _audioBytes = bytes;
      _contentType = type;
      _fileName = type == 'audio/wav'
          ? 'practice_${DateTime.now().millisecondsSinceEpoch}.wav'
          : 'practice_${DateTime.now().millisecondsSinceEpoch}.webm';
      _recordSeconds = durationSeconds;
      _isRecording = false;
      _completed = true;
    });
    _burstController
      ..reset()
      ..forward();
    unawaited(HapticFeedback.mediumImpact());
  }

  Future<void> _requestFeedback() async {
    final bytes = _audioBytes;
    if (bytes == null || bytes.isEmpty) {
      _showMessage('먼저 녹음을 완료해주세요.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0;
    });
    try {
      if (widget.ref.read(localPreviewModeProvider)) {
        final now = DateTime.now();
        final submission = {
          'id': 'preview-practice-${now.millisecondsSinceEpoch}',
          'churchId': 'preview-church',
          'userId': FirebaseService.uid ?? 'preview-user',
          'userName': FirebaseService.currentUser?.displayName ?? '미리보기 단원',
          'part': widget.part,
          'title': _practiceTitle,
          'missionId': _missionId,
          'missionTitle': _missionTitle,
          'audioUrl':
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
          'audioFileName': _fileName,
          'mrAudioUrl': _mrAudioUrl,
          'mrAudioFileName': _mrAudioFileName,
          'durationSeconds': _recordSeconds,
          'xpAwarded': _xpReward,
          'practiceDate': _todayKeyLocal(),
          'status': 'pending_feedback',
          'leaderFeedback': '',
          'createdAt': now.toIso8601String(),
        };
        widget.ref
            .read(previewHarmonyPracticeSubmissionsProvider.notifier)
            .update((items) => [submission, ...items]);
        widget.ref.read(previewHarmonyPracticeProgressProvider.notifier).update(
          (progress) {
            final xp = ((progress['xp'] as num?)?.toInt() ?? 0) + _xpReward;
            final steps = Map<String, dynamic>.from(
              (progress['completedTutorialSteps'] as Map?) ?? const {},
            );
            steps['mrRecording'] = true;
            steps['dailyMission'] = true;
            steps['feedbackRequest'] = true;
            return {
              ...progress,
              'xp': xp,
              'level': FirebaseService.harmonyLevelForXp(xp),
              'practiceCount':
                  ((progress['practiceCount'] as num?)?.toInt() ?? 0) + 1,
              'lastPracticeDate': _todayKeyLocal(),
              'completedTutorialSteps': steps,
            };
          },
        );
      } else {
        final audioUrl = await FirebaseService.uploadHarmonyAudio(
          bytes,
          fileName: _fileName,
          contentType: _contentType,
          onProgress: (value) {
            if (mounted) setState(() => _uploadProgress = value);
          },
        );
        await FirebaseService.createHarmonyPracticeSubmission(
          part: widget.part,
          title: _practiceTitle,
          missionId: _missionId,
          missionTitle: _missionTitle,
          audioUrl: audioUrl,
          audioFileName: _fileName,
          mrAudioUrl: _mrAudioUrl,
          mrAudioFileName: _mrAudioFileName,
          durationSeconds: _recordSeconds,
          xpAwarded: _xpReward,
        );
      }
      widget.ref.invalidate(harmonyPracticeProgressProvider);
      widget.ref.invalidate(myHarmonyPracticeSubmissionsProvider);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('파트장에게 개인연습 녹음을 보냈어요.')),
        );
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PracticeCompletionBurst extends StatelessWidget {
  const _PracticeCompletionBurst({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const colors = [
      AppColors.secondary,
      AppColors.primary,
      AppColors.success,
      Color(0xFFFFD166),
    ];
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Stack(
          children: List.generate(18, (index) {
            final angle = (math.pi * 2 / 18) * index;
            final distance = 18 + t * (42 + (index % 5) * 8);
            final x = math.cos(angle) * distance;
            final y = math.sin(angle) * distance - t * 18;
            return Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: Offset(x, y),
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Container(
                    width: 6 + (index % 3) * 2,
                    height: 6 + (index % 3) * 2,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _UploadProgressPanel extends StatelessWidget {
  const _UploadProgressPanel({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('업로드 중', style: AppText.body(12, weight: FontWeight.w900)),
              const Spacer(),
              Text(
                '$percent%',
                style: AppText.body(12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress.clamp(0, 1).toDouble(),
              color: AppColors.primary,
              backgroundColor: AppColors.border.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayGuideCard extends StatefulWidget {
  const _TodayGuideCard({
    required this.part,
    required this.partLabel,
    required this.guideAsync,
    required this.ref,
  });

  final String part;
  final String partLabel;
  final AsyncValue<Map<String, dynamic>?> guideAsync;
  final WidgetRef ref;

  @override
  State<_TodayGuideCard> createState() => _TodayGuideCardState();
}

class _TodayGuideCardState extends State<_TodayGuideCard> {
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return widget.guideAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (guide) {
        if (widget.part.isEmpty || guide == null) {
          return const SizedBox.shrink();
        }
        final title =
            guide['songTitle']?.toString() ??
            guide['title']?.toString() ??
            '파트 가이드';
        return Material(
          color: const Color(0xFFFFFBF0),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _isCreating ? null : () => _createRelay(guide),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE7D39A)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAD9A8),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Center(
                      child: _RelayStackIcon(
                        size: 25,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '오늘 릴레이',
                          style: AppText.body(
                            12,
                            weight: FontWeight.w900,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$title · ${widget.partLabel}',
                          maxLines: 2,
                          overflow: TextOverflow.clip,
                          softWrap: true,
                          style: AppText.body(
                            16,
                            weight: FontWeight.w900,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '열기',
                                style: AppText.body(
                                  12,
                                  color: Colors.white,
                                  weight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const _InlineChevronRightIcon(
                                color: Colors.white,
                                size: 17,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createRelay(Map<String, dynamic> guide) async {
    setState(() => _isCreating = true);
    try {
      await FirebaseService.createHarmonyRelayFromGuide(
        part: widget.part,
        guide: guide,
      );
      widget.ref.invalidate(harmonyRelaysProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오늘의 릴레이를 열었어요. 다음 사람이 지목됩니다.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}

class _RelaySection extends StatelessWidget {
  const _RelaySection({
    required this.part,
    required this.partLabel,
    required this.relaysAsync,
    required this.ref,
  });

  final String part;
  final String partLabel;
  final AsyncValue<List<Map<String, dynamic>>> relaysAsync;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final highlightedRelayId = ref.watch(_lastSubmittedHarmonyRelayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '릴레이',
                style: AppText.body(18, weight: FontWeight.w900),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: part.isEmpty
                  ? null
                  : () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _CreateRelaySheet(
                        part: part,
                        partLabel: partLabel,
                        ref: ref,
                      ),
                    ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('새 릴레이'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        relaysAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Text(
            '릴레이를 불러올 수 없습니다.',
            style: AppText.body(13, color: AppColors.muted),
          ),
          data: (relays) {
            if (part.isEmpty) {
              return Text(
                '파트가 지정되면 사용할 수 있어요.',
                style: AppText.body(13, color: AppColors.muted),
              );
            }
            if (relays.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '첫 릴레이를 열어보세요.',
                        style: AppText.body(
                          13,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            final missionGroups = _groupMissionRelays(relays);
            return Column(
              children: missionGroups.map((group) {
                if (group.isMission) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RelayMissionCard(
                      relays: group.relays,
                      part: part,
                      partLabel: partLabel,
                      ref: ref,
                      highlightedRelayId: highlightedRelayId,
                    ),
                  );
                }
                final relay = group.relays.first;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RelayCard(
                    relay: relay,
                    part: part,
                    partLabel: partLabel,
                    ref: ref,
                    highlightedRelayId: highlightedRelayId,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _RelayMissionGroup {
  const _RelayMissionGroup({
    required this.key,
    required this.relays,
    required this.isMission,
  });

  final String key;
  final List<Map<String, dynamic>> relays;
  final bool isMission;
}

List<_RelayMissionGroup> _groupMissionRelays(
  List<Map<String, dynamic>> relays,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final legacy = <_RelayMissionGroup>[];
  for (final relay in relays) {
    final key = relay['missionGroupId']?.toString() ?? '';
    if (key.isEmpty ||
        ((relay['missionTotalSegments'] as num?)?.toInt() ?? 1) <= 1) {
      legacy.add(
        _RelayMissionGroup(
          key: relay['id'].toString(),
          relays: [relay],
          isMission: false,
        ),
      );
      continue;
    }
    groups.putIfAbsent(key, () => []).add(relay);
  }
  final missionGroups = groups.entries.map((entry) {
    final sorted = [...entry.value]
      ..sort((a, b) {
        final aOrder = (a['segmentOrder'] as num?)?.toInt() ?? 0;
        final bOrder = (b['segmentOrder'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      });
    return _RelayMissionGroup(key: entry.key, relays: sorted, isMission: true);
  }).toList();
  return [...missionGroups, ...legacy];
}

class _RelayMissionCard extends StatelessWidget {
  const _RelayMissionCard({
    required this.relays,
    required this.part,
    required this.partLabel,
    required this.ref,
    required this.highlightedRelayId,
  });

  final List<Map<String, dynamic>> relays;
  final String part;
  final String partLabel;
  final WidgetRef ref;
  final String? highlightedRelayId;

  @override
  Widget build(BuildContext context) {
    final first = relays.first;
    final title = _firstText([
      first['sourceTitle']?.toString(),
      first['title']?.toString().replaceAll(' 릴레이', ''),
      '하모니 릴레이',
    ]);
    final missionGroupId = first['missionGroupId']?.toString() ?? '';
    final total =
        (first['missionTotalSegments'] as num?)?.toInt() ?? relays.length;
    final completed = relays.where(_relayCompleted).length;
    final ratio = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final isComplete = completed >= total && total > 0;
    final compact = MediaQuery.sizeOf(context).width < 480;
    final highlightedIndex = relays.indexWhere(
      (relay) => relay['id']?.toString() == highlightedRelayId,
    );
    final hasSubmittedHighlight = highlightedIndex >= 0;
    final highlightedLabel = hasSubmittedHighlight
        ? _segmentDisplayLabel(relays[highlightedIndex], highlightedIndex)
        : '';
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role ?? '';
    final canVote =
        role == 'admin' ||
        role == 'church_admin' ||
        (role == 'part_leader' &&
            ((profile?.partLeaderFor ?? profile?.part ?? '') == part));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasSubmittedHighlight
            ? const Color(0xFFFFFCF2)
            : isComplete
            ? const Color(0xFFFFFBF0)
            : AppColors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasSubmittedHighlight
              ? AppColors.secondary
              : isComplete
              ? const Color(0xFFE7D39A)
              : AppColors.border.withValues(alpha: 0.35),
          width: hasSubmittedHighlight ? 1.6 : 1,
        ),
        boxShadow: hasSubmittedHighlight
            ? [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isComplete
                      ? const Color(0xFFEAD9A8)
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: isComplete
                      ? const _InlineAwardIcon(
                          size: 23,
                          color: AppColors.secondary,
                        )
                      : const _InlineRouteIcon(
                          size: 23,
                          color: AppColors.primary,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.body(16, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$partLabel · $completed/$total 소절 완료',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              _TurnPill(
                label: isComplete ? '완주' : '${((ratio) * 100).round()}%',
                active: isComplete,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: ratio,
              backgroundColor: AppColors.border.withValues(alpha: 0.35),
              color: isComplete ? AppColors.secondary : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (hasSubmittedHighlight) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                '$highlightedLabel 업로드 완료. 하모니맵에서 방금 올린 소절을 표시했어요.',
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: AppColors.secondary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (compact) ...[
            _RelayProgressMap(
              relays: relays,
              part: part,
              partLabel: partLabel,
              ref: ref,
              highlightedRelayId: highlightedRelayId,
            ),
            const SizedBox(height: 12),
            _CompactMissionRecordCard(
              title: title,
              relays: relays,
              part: part,
              partLabel: partLabel,
              ref: ref,
            ),
          ] else ...[
            _RelayProgressMap(
              relays: relays,
              part: part,
              partLabel: partLabel,
              ref: ref,
              highlightedRelayId: highlightedRelayId,
            ),
            const SizedBox(height: 12),
            ...relays.map(
              (relay) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MissionSegmentTile(
                  relay: relay,
                  missionRelays: relays,
                  part: part,
                  partLabel: partLabel,
                  ref: ref,
                  highlightedRelayId: highlightedRelayId,
                ),
              ),
            ),
          ],
          if (isComplete) ...[
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 520),
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) => Transform.scale(
                scale: 0.96 + value * 0.04,
                child: Opacity(opacity: value, child: child),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '파트 완주',
                      style: AppText.body(
                        18,
                        weight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '모든 소절이 이어졌어요. 이제 파트장이 가장 꾸준히 참여한 단원을 골라주세요.',
                      style: AppText.body(
                        12,
                        color: Colors.white.withValues(alpha: 0.76),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (canVote && missionGroupId.isNotEmpty) ...[
              const SizedBox(height: 10),
              _HarmonyMvpVotePanel(
                missionGroupId: missionGroupId,
                part: part,
                relays: relays,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CompactMissionRecordCard extends StatelessWidget {
  const _CompactMissionRecordCard({
    required this.title,
    required this.relays,
    required this.part,
    required this.partLabel,
    required this.ref,
  });

  final String title;
  final List<Map<String, dynamic>> relays;
  final String part;
  final String partLabel;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final targetRelay = _focusRelayForMission(relays);
    final completed = relays.where(_relayCompleted).length;
    final total = relays.length;
    final isComplete = completed >= total && total > 0;
    final targetIndex = relays.indexOf(targetRelay);
    final segmentLabel = _cleanDisplayText(
      targetRelay['segmentLabel']?.toString() ??
          (targetIndex >= 0 ? '${targetIndex + 1}소절' : '소절'),
    );
    final currentLine = _firstText([
      targetRelay['lyricsLine']?.toString(),
      _lyricLineFromRelayText(targetRelay, targetIndex),
      isComplete ? '모든 소절이 이어졌어요' : '가사를 보며 이어 불러주세요',
    ]);
    final nextLine = _firstText([
      targetRelay['nextLyricsLine']?.toString(),
      _nextLyricLineFromRelayText(targetRelay, targetIndex),
    ]);
    final assigneeId = targetRelay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = targetRelay['currentAssigneeName']?.toString() ?? '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final targetDone = _relayCompleted(targetRelay);
    final canTestRecord = !targetDone && _canTestRecordRelayForTest(ref, part);
    final canRecordNow =
        !targetDone && (isMyTurn || canTestRecord || assigneeName.isEmpty);
    final status = isComplete
        ? '완주'
        : targetDone
        ? '완료'
        : isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트 녹음'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : '$assigneeName 차례';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openRelayStudio(
          context,
          targetRelay,
          part,
          partLabel,
          ref,
          missionRelays: relays,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.38)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '지금 할 일',
                          style: AppText.body(
                            11,
                            weight: FontWeight.w900,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$title · $partLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(14, weight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _TurnPill(label: status, active: canRecordNow || isComplete),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            segmentLabel,
                            style: AppText.body(
                              11,
                              weight: FontWeight.w900,
                              color: AppColors.secondaryContainer,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$completed/$total',
                          style: AppText.body(
                            12,
                            weight: FontWeight.w900,
                            color: Colors.white.withValues(alpha: 0.84),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _LyricDisplayText(
                        text: currentLine,
                        key: ValueKey(currentLine),
                        style: AppText.body(
                          22,
                          weight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.25,
                        ),
                        minHeight: 30,
                      ),
                    ),
                    if (nextLine.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        nextLine,
                        softWrap: true,
                        style: AppText.body(
                          14,
                          weight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.46),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _CompactRelayStepDots(relays: relays, focusIndex: targetIndex),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openRelayStudio(
                    context,
                    targetRelay,
                    part,
                    partLabel,
                    ref,
                    missionRelays: relays,
                  ),
                  icon: Icon(
                    isComplete ? Icons.play_arrow_rounded : Icons.mic_rounded,
                  ),
                  label: Text(isComplete ? '완주 듣기' : '가사 보며 녹음'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactRelayStepDots extends StatelessWidget {
  const _CompactRelayStepDots({required this.relays, required this.focusIndex});

  final List<Map<String, dynamic>> relays;
  final int focusIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: relays.asMap().entries.map((entry) {
        final index = entry.key;
        final relay = entry.value;
        final done = _relayCompleted(relay);
        final active = index == focusIndex && !done;
        return Container(
          width: active ? 32 : 24,
          height: 24,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success
                : active
                ? AppColors.secondary
                : AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? AppColors.secondary
                  : AppColors.border.withValues(alpha: 0.45),
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: AppText.body(
                      10,
                      weight: FontWeight.w900,
                      color: active ? AppColors.primary : AppColors.muted,
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }
}

class _RelayProgressMap extends StatefulWidget {
  const _RelayProgressMap({
    required this.relays,
    required this.part,
    required this.partLabel,
    required this.ref,
    required this.highlightedRelayId,
  });

  final List<Map<String, dynamic>> relays;
  final String part;
  final String partLabel;
  final WidgetRef ref;
  final String? highlightedRelayId;

  @override
  State<_RelayProgressMap> createState() => _RelayProgressMapState();
}

class _RelayProgressMapState extends State<_RelayProgressMap> {
  final Map<String, GlobalKey> _nodeKeys = {};
  String? _playingRelayId;

  @override
  void didUpdateWidget(covariant _RelayProgressMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final relayIds = widget.relays
        .map((relay) => relay['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    _nodeKeys.removeWhere((id, _) => !relayIds.contains(id));
    if (_playingRelayId != null && !relayIds.contains(_playingRelayId)) {
      _playingRelayId = null;
    }
  }

  void _handleActiveRelayChanged(String? relayId) {
    if (!mounted || relayId == _playingRelayId) return;
    setState(() => _playingRelayId = relayId);
    if (relayId == null || relayId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodeContext = _nodeKeys[relayId]?.currentContext;
      if (nodeContext == null) return;
      Scrollable.ensureVisible(
        nodeContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.34,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  GlobalKey _keyForRelay(String relayId) {
    return _nodeKeys.putIfAbsent(relayId, GlobalKey.new);
  }

  // One-line "where are we" summary shown next to the progress bar so the
  // whole relay status reads at a glance instead of scanning every node.
  String _nextTurnLabel() {
    if (widget.relays.isEmpty) return '아직 소절이 없어요';
    Map<String, dynamic>? nextRelay;
    for (final relay in widget.relays) {
      if (!_relayCompleted(relay)) {
        nextRelay = relay;
        break;
      }
    }
    if (nextRelay == null) return '완주했어요 🎉';
    final assigneeId = nextRelay['currentAssigneeId']?.toString() ?? '';
    if (assigneeId.isNotEmpty && assigneeId == FirebaseService.uid) {
      return '내 차례예요';
    }
    final assigneeName = _cleanDisplayText(
      nextRelay['currentAssigneeName']?.toString() ?? '',
    );
    if (assigneeName.isNotEmpty) return '다음 차례 · $assigneeName';
    return '다음 차례 대기 중';
  }

  @override
  Widget build(BuildContext context) {
    final completed = widget.relays.where(_relayCompleted).length;
    final playbackClips = _relayClipSequenceForRelays(widget.relays);
    final nextTurnLabel = _nextTurnLabel();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: _InlineHarmonyMapIcon(
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '하모니맵',
                      style: AppText.body(
                        15,
                        weight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RelaySequencePlayButton(
                clips: playbackClips,
                dark: true,
                label: '지금까지 재생',
                onActiveRelayChanged: _handleActiveRelayChanged,
              ),
              const SizedBox(width: 8),
              _MapStatPill(
                label: '$completed/${widget.relays.length}',
                dark: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HarmonyProgressBar(
            completed: completed,
            total: widget.relays.length,
            statusLabel: nextTurnLabel,
            dark: true,
          ),
          const SizedBox(height: 10),
          const _HarmonyLegend(dark: true),
          const SizedBox(height: 6),
          _HarmonyPath(
            relays: widget.relays,
            part: widget.part,
            partLabel: widget.partLabel,
            ref: widget.ref,
            highlightedRelayId: widget.highlightedRelayId,
            playingRelayId: _playingRelayId,
            nodeKeyBuilder: (relayId) =>
                relayId.isEmpty ? null : _keyForRelay(relayId),
          ),
        ],
      ),
    );
  }
}

/// A winding "journey path" of relay stops: each segment is a tappable node
/// strung along an S-curve that flows down the card. Travelled legs are drawn
/// solid, upcoming legs stay faint so the eye is pulled toward the next turn.
class _HarmonyPath extends StatelessWidget {
  const _HarmonyPath({
    required this.relays,
    required this.part,
    required this.partLabel,
    required this.ref,
    required this.highlightedRelayId,
    required this.playingRelayId,
    required this.nodeKeyBuilder,
  });

  final List<Map<String, dynamic>> relays;
  final String part;
  final String partLabel;
  final WidgetRef ref;
  final String? highlightedRelayId;
  final String? playingRelayId;
  final GlobalKey? Function(String relayId) nodeKeyBuilder;

  // Index of the first not-yet-recorded stop — the node we nudge people toward.
  int get _nextIndex {
    for (var i = 0; i < relays.length; i++) {
      if (!_relayCompleted(relays[i])) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (relays.isEmpty) return const SizedBox.shrink();
    const nodeRadius = 27.0;
    const vGap = 96.0;
    const topPad = nodeRadius + 4;
    const bottomPad = nodeRadius + 30;
    final nextIndex = _nextIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final centerX = width / 2;
        // Amplitude of the swing — wide enough to read as a curve, capped so it
        // never crowds the labels on large screens.
        final amp = ((width - nodeRadius * 2 - 28) / 2).clamp(0.0, 92.0);
        final centers = <Offset>[
          for (var i = 0; i < relays.length; i++)
            Offset(
              centerX + amp * math.sin(i * math.pi / 2),
              topPad + i * vGap,
            ),
        ];
        final totalHeight = topPad + (relays.length - 1) * vGap + bottomPad;

        return SizedBox(
          width: width,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _HarmonyPathPainter(
                    centers: centers,
                    completed: [
                      for (final relay in relays) _relayCompleted(relay),
                    ],
                    nodeRadius: nodeRadius,
                  ),
                ),
              ),
              for (var i = 0; i < relays.length; i++)
                Positioned(
                  left: centers[i].dx - 70,
                  top: centers[i].dy - nodeRadius,
                  width: 140,
                  child: Column(
                    key: nodeKeyBuilder(relays[i]['id']?.toString() ?? ''),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HarmonyPathNode(
                        relay: relays[i],
                        order: i + 1,
                        part: part,
                        partLabel: partLabel,
                        missionRelays: relays,
                        ref: ref,
                        radius: nodeRadius,
                        isHighlighted:
                            (relays[i]['id']?.toString() ?? '') ==
                            highlightedRelayId,
                        isPlaying:
                            (relays[i]['id']?.toString() ?? '').isNotEmpty &&
                            (relays[i]['id']?.toString() ?? '') ==
                                playingRelayId,
                        isNext: i == nextIndex,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HarmonyPathPainter extends CustomPainter {
  _HarmonyPathPainter({
    required this.centers,
    required this.completed,
    required this.nodeRadius,
  });

  final List<Offset> centers;
  final List<bool> completed;
  final double nodeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.length < 2) return;
    for (var i = 0; i < centers.length - 1; i++) {
      final from = centers[i];
      final to = centers[i + 1];
      // Smooth vertical S between the two stops.
      final midY = (from.dy + to.dy) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy + nodeRadius * 0.7)
        ..cubicTo(
          from.dx,
          midY,
          to.dx,
          midY,
          to.dx,
          to.dy - nodeRadius * 0.7,
        );
      // A leg is "travelled" once the stop it leaves has been recorded.
      final travelled = completed[i];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = travelled ? 4.5 : 3
        ..strokeCap = StrokeCap.round
        ..color = travelled
            ? AppColors.success.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.22);
      if (travelled) {
        canvas.drawPath(path, paint);
      } else {
        _drawDashed(canvas, path, paint);
      }
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const dash = 7.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HarmonyPathPainter oldDelegate) {
    return oldDelegate.centers != centers ||
        oldDelegate.completed != completed;
  }
}

class _HarmonyProgressBar extends StatelessWidget {
  const _HarmonyProgressBar({
    required this.completed,
    required this.total,
    required this.statusLabel,
    required this.dark,
  });

  final int completed;
  final int total;
  final String statusLabel;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final safeTotal = total < 0 ? 0 : total;
    final fraction = safeTotal == 0
        ? 0.0
        : (completed / safeTotal).clamp(0.0, 1.0).toDouble();
    final isDone = safeTotal > 0 && completed >= safeTotal;
    final trackColor = dark
        ? Colors.white.withValues(alpha: 0.16)
        : AppColors.border.withValues(alpha: 0.30);
    final fillColor = isDone
        ? AppColors.success
        : dark
        ? AppColors.secondaryContainer
        : AppColors.primary;
    final countColor = dark ? Colors.white : AppColors.ink;
    final subColor = dark ? Colors.white.withValues(alpha: 0.74) : AppColors.muted;
    final statusColor = isDone
        ? (dark ? AppColors.secondaryContainer : AppColors.success)
        : countColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$completed',
              style: AppText.body(20, weight: FontWeight.w900, color: countColor),
            ),
            Text(
              ' / $safeTotal 소절',
              style: AppText.body(12, weight: FontWeight.w700, color: subColor),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppText.body(
                  12.5,
                  weight: FontWeight.w900,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 12, color: trackColor),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: fraction <= 0 ? 0.001 : fraction,
                ),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return FractionallySizedBox(
                    widthFactor: value.clamp(0.001, 1.0),
                    child: child,
                  );
                },
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One stop on the winding harmony path: a tappable circle plus a short label.
/// The next stop to record gently pulses so it invites a tap ("탭하여 녹음").
class _HarmonyPathNode extends StatefulWidget {
  const _HarmonyPathNode({
    required this.relay,
    required this.order,
    required this.part,
    required this.partLabel,
    required this.missionRelays,
    required this.ref,
    required this.radius,
    required this.isHighlighted,
    required this.isPlaying,
    required this.isNext,
  });

  final Map<String, dynamic> relay;
  final int order;
  final String part;
  final String partLabel;
  final List<Map<String, dynamic>> missionRelays;
  final WidgetRef ref;
  final double radius;
  final bool isHighlighted;
  final bool isPlaying;
  final bool isNext;

  @override
  State<_HarmonyPathNode> createState() => _HarmonyPathNodeState();
}

class _HarmonyPathNodeState extends State<_HarmonyPathNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relay = widget.relay;
    final completed = _relayCompleted(relay);
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final isPlaying = widget.isPlaying;
    // "Open" = waiting at the front of the line, recordable right now.
    final isOpen = !completed && (widget.isNext || isMyTurn);
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final latest = clips.isEmpty ? null : clips.last;
    final singer =
        latest?['userName']?.toString() ??
        relay['completedByName']?.toString() ??
        '';
    final segmentTitle = _segmentDisplayLabel(relay, widget.order - 1);
    final status = completed
        ? (isPlaying ? '재생 중' : (singer.isEmpty ? '완료' : singer))
        : isMyTurn
        ? '내 차례 · 탭하여 녹음'
        : widget.isNext
        ? '탭하여 녹음'
        : assigneeName.isEmpty
        ? '대기'
        : assigneeName;

    final circleColor = isPlaying
        ? AppColors.secondary
        : completed
        ? AppColors.success
        : isOpen
        ? AppColors.primary
        : Colors.white.withValues(alpha: 0.14);
    final ringColor = widget.isHighlighted
        ? AppColors.secondary
        : isPlaying
        ? Colors.white
        : isOpen
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.transparent;
    final labelColor = completed
        ? AppColors.success
        : isOpen || isPlaying
        ? Colors.white
        : Colors.white.withValues(alpha: 0.78);

    final diameter = widget.radius * 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openRelayStudio(
        context,
        relay,
        widget.part,
        widget.partLabel,
        widget.ref,
        missionRelays: widget.missionRelays,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: diameter + 24,
            height: diameter + 24,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pulsing halo that pulls the eye to the next stop to record.
                  if (isOpen)
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final t = _pulse.value;
                        return Container(
                          width: diameter + 6 + t * 18,
                          height: diameter + 6 + t * 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(
                              alpha: (0.28 * (1 - t)).clamp(0.0, 1.0),
                            ),
                          ),
                        );
                      },
                    ),
                  Container(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: circleColor,
                      border: Border.all(
                        color: ringColor,
                        width: ringColor == Colors.transparent ? 0 : 2.5,
                      ),
                      boxShadow: isOpen || isPlaying || completed
                          ? [
                              BoxShadow(
                                color:
                                    (isPlaying
                                            ? AppColors.secondary
                                            : completed
                                            ? AppColors.success
                                            : AppColors.primary)
                                        .withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: isPlaying
                          ? const Icon(
                              Icons.volume_up_rounded,
                              size: 22,
                              color: AppColors.primary,
                            )
                          : completed
                          ? const _InlineCheckIcon(size: 24, color: Colors.white)
                          : isOpen
                          ? const Icon(
                              Icons.mic_rounded,
                              size: 22,
                              color: Colors.white,
                            )
                          : Text(
                              '${widget.order}',
                              style: AppText.body(
                                15,
                                weight: FontWeight.w900,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            segmentTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.body(12.5, weight: FontWeight.w900, color: labelColor),
          ),
          const SizedBox(height: 1),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.body(
              10.5,
              weight: FontWeight.w700,
              color: completed
                  ? AppColors.success.withValues(alpha: 0.9)
                  : isOpen
                  ? AppColors.secondaryContainer
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionSegmentTile extends StatelessWidget {
  const _MissionSegmentTile({
    required this.relay,
    required this.missionRelays,
    required this.part,
    required this.partLabel,
    required this.ref,
    required this.highlightedRelayId,
  });

  final Map<String, dynamic> relay;
  final List<Map<String, dynamic>> missionRelays;
  final String part;
  final String partLabel;
  final WidgetRef ref;
  final String? highlightedRelayId;

  @override
  Widget build(BuildContext context) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final completed = _relayCompleted(relay);
    final latest = clips.isEmpty ? null : clips.last;
    final segmentIndex = missionRelays.indexWhere(
      (item) => item['id']?.toString() == relay['id']?.toString(),
    );
    final segmentTitle = _segmentDisplayLabel(relay, segmentIndex);
    final singer =
        latest?['userName']?.toString() ??
        relay['completedByName']?.toString() ??
        '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final canTestRecord = !completed && _canTestRecordRelayForTest(ref, part);
    final isHighlighted = relay['id']?.toString() == highlightedRelayId;
    final recordStatusLabel = isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트 녹음'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : '다음 $assigneeName';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openRelayStudio(
        context,
        relay,
        part,
        partLabel,
        ref,
        missionRelays: missionRelays,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHighlighted
              ? const Color(0xFFFFF6D8)
              : completed
              ? AppColors.primarySoft
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlighted
                ? AppColors.secondary
                : completed
                ? AppColors.primary.withValues(alpha: 0.20)
                : AppColors.border.withValues(alpha: 0.35),
            width: isHighlighted ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: completed ? AppColors.primary : AppColors.bg,
              child: Icon(
                completed ? Icons.check_rounded : Icons.mic_rounded,
                size: 18,
                color: completed ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segmentTitle,
                    style: AppText.body(13, weight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    completed
                        ? '${singer.isEmpty ? '파트원' : singer} 완료'
                        : recordStatusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (isHighlighted)
              const _TurnPill(label: '방금 업로드', active: true)
            else if ((isMyTurn || canTestRecord) && !completed)
              _TurnPill(label: recordStatusLabel, active: true)
            else
              Icon(
                completed
                    ? Icons.play_circle_outline_rounded
                    : Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _HarmonyMvpVotePanel extends StatelessWidget {
  const _HarmonyMvpVotePanel({
    required this.missionGroupId,
    required this.part,
    required this.relays,
  });

  final String missionGroupId;
  final String part;
  final List<Map<String, dynamic>> relays;

  @override
  Widget build(BuildContext context) {
    final candidates = _relayVoteCandidates(relays);
    if (candidates.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<Map<String, int>>(
      stream: FirebaseService.watchHarmonyMvpVotes(
        missionGroupId: missionGroupId,
        part: part,
      ),
      builder: (context, snapshot) {
        final votes = snapshot.data ?? const <String, int>{};
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '완주 MVP 투표',
                style: AppText.body(14, weight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: candidates.map((candidate) {
                  final count = votes[candidate.id] ?? 0;
                  return ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: AppColors.primarySoft,
                      child: Text(
                        candidate.name.characters.first,
                        style: AppText.body(10, weight: FontWeight.w900),
                      ),
                    ),
                    label: Text('${candidate.name} $count'),
                    onPressed: () async {
                      try {
                        await FirebaseService.voteHarmonyMvp(
                          missionGroupId: missionGroupId,
                          part: part,
                          nomineeUserId: candidate.id,
                          nomineeName: candidate.name,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${candidate.name}님에게 투표했어요.'),
                            ),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                error.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RelayVoteCandidate {
  const _RelayVoteCandidate({required this.id, required this.name});

  final String id;
  final String name;
}

List<_RelayVoteCandidate> _relayVoteCandidates(
  List<Map<String, dynamic>> relays,
) {
  final candidates = <String, _RelayVoteCandidate>{};
  for (final relay in relays) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final clip in clips) {
      final id = clip['userId']?.toString() ?? '';
      final name = clip['userName']?.toString() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) {
        candidates[id] = _RelayVoteCandidate(id: id, name: name);
      }
    }
  }
  return candidates.values.toList();
}

bool _relayCompleted(Map<String, dynamic> relay) {
  final clips = ((relay['clips'] as List?) ?? const []);
  return clips.isNotEmpty || relay['status']?.toString() == 'completed';
}

bool _isHarmonyRelayAdminProfile(User? profile) {
  return profile?.isPlatformAdmin == true || profile?.isAdmin == true;
}

bool _canAdminModifyHarmonyRelay(WidgetRef ref) {
  return _isHarmonyRelayAdminProfile(ref.watch(profileProvider).valueOrNull);
}

bool _canAdminModifyHarmonyRelayNow(WidgetRef ref) {
  return _isHarmonyRelayAdminProfile(ref.read(profileProvider).valueOrNull);
}

List<Map<String, dynamic>> _relayClipSequenceForRelays(
  List<Map<String, dynamic>> relays,
) {
  final sortedRelays = [...relays]
    ..sort((a, b) {
      final aOrder = (a['segmentOrder'] as num?)?.toInt() ?? 0;
      final bOrder = (b['segmentOrder'] as num?)?.toInt() ?? 0;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return _dateTimeAsc(a['createdAt'], b['createdAt']);
    });
  final clips = <Map<String, dynamic>>[];
  for (var index = 0; index < sortedRelays.length; index += 1) {
    final relay = sortedRelays[index];
    final mrAudioUrl = relay['mrAudioUrl']?.toString().trim() ?? '';
    final segmentStartSec = (relay['segmentStartSec'] as num?)?.toDouble() ?? 0;
    final segmentEndSec = (relay['segmentEndSec'] as num?)?.toDouble() ?? 0;
    final segmentLabel = _segmentDisplayLabel(relay, index);
    final relayClips =
        ((relay['clips'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) => _dateTimeAsc(a['createdAt'], b['createdAt']));
    for (final clip in relayClips) {
      clips.add({
        ...clip,
        'relayId': relay['id']?.toString() ?? '',
        'mrAudioUrl': mrAudioUrl,
        'segmentOrder': (relay['segmentOrder'] as num?)?.toInt() ?? index + 1,
        'segmentStartSec': segmentStartSec,
        'segmentEndSec': segmentEndSec,
        'segmentLabel': segmentLabel,
      });
    }
  }
  return _playableRelayClips(clips);
}

List<Map<String, dynamic>> _playableRelayClips(
  List<Map<String, dynamic>> clips,
) {
  return clips
      .where((clip) {
        final url = clip['audioUrl']?.toString().trim() ?? '';
        return url.isNotEmpty;
      })
      .toList(growable: false);
}

String _clipSequenceKey(List<Map<String, dynamic>> clips) {
  return _playableRelayClips(clips)
      .map((clip) {
        final url = clip['audioUrl']?.toString().trim() ?? '';
        final mrUrl = clip['mrAudioUrl']?.toString().trim() ?? '';
        final start = (clip['segmentStartSec'] as num?)?.toDouble() ?? 0;
        final end = (clip['segmentEndSec'] as num?)?.toDouble() ?? 0;
        return '$url@$mrUrl@$start@$end';
      })
      .join('|');
}

int _dateTimeAsc(dynamic a, dynamic b) {
  final left = _dateTimeFromValue(a);
  final right = _dateTimeFromValue(b);
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}

DateTime? _dateTimeFromValue(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class _DecodedAudioData {
  const _DecodedAudioData({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Resolves a relay clip URL to the audioplayers [Source] used to play it,
/// decoding inline `data:` payloads to bytes. Lets callers preload via
/// `setSource` before the playback cue so layered voices start on time.
Source _relayAudioSource(String audioUrl) {
  final decoded = _decodeDataAudioUrl(audioUrl);
  if (decoded != null) {
    return BytesSource(decoded.bytes, mimeType: decoded.mimeType);
  }
  return UrlSource(audioUrl);
}

Future<void> _playRelayAudioSource(
  AudioPlayer player,
  String audioUrl, {
  Duration position = Duration.zero,
}) async {
  final decoded = _decodeDataAudioUrl(audioUrl);
  if (decoded != null) {
    final source = BytesSource(decoded.bytes, mimeType: decoded.mimeType);
    try {
      if (position > Duration.zero) {
        await player.play(source, position: position);
      } else {
        await player.play(source);
      }
      return;
    } catch (_) {
      await player.play(UrlSource(audioUrl), position: position);
    }
    return;
  }
  await player.play(UrlSource(audioUrl), position: position);
}

_DecodedAudioData? _decodeDataAudioUrl(String value) {
  if (!value.startsWith('data:')) return null;
  final commaIndex = value.indexOf(',');
  if (commaIndex < 0) return null;
  final metadata = value.substring(5, commaIndex);
  final payload = Uri.decodeComponent(value.substring(commaIndex + 1));
  final mimeType = metadata
      .split(';')
      .firstWhere((part) => part.contains('/'), orElse: () => 'audio/wav');
  try {
    final bytes = metadata.toLowerCase().contains(';base64')
        ? base64Decode(payload)
        : Uint8List.fromList(utf8.encode(payload));
    return _DecodedAudioData(bytes: bytes, mimeType: mimeType);
  } catch (_) {
    return null;
  }
}

Future<bool> _ensureMicrophonePermission(AudioRecorder recorder) async {
  if (_microphonePermissionGrantedInSession == true) return true;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_microphonePermissionGrantedKey) == true) {
    _microphonePermissionGrantedInSession = true;
    return true;
  }

  // On web, ask the browser silently whether the mic is already granted. If it
  // is, skip every recorder permission call so we never surface a prompt the
  // user already answered for this site.
  if (kIsWeb && await relay_backing_audio.microphonePermissionGranted()) {
    await _rememberMicrophonePermissionGranted();
    return true;
  }

  final alreadyGranted = await recorder.hasPermission(request: false);
  if (alreadyGranted) {
    await _rememberMicrophonePermissionGranted();
    return true;
  }

  final granted = await recorder.hasPermission();
  if (granted) await _rememberMicrophonePermissionGranted();
  return granted;
}

Future<void> _rememberMicrophonePermissionGranted() async {
  _microphonePermissionGrantedInSession = true;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_microphonePermissionGrantedKey, true);
}

Future<void> _forgetMicrophonePermissionGranted() async {
  _microphonePermissionGrantedInSession = false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_microphonePermissionGrantedKey);
}

/// Recording can fail for reasons unrelated to permission (MR playback, encoder,
/// transient device hiccup). Only drop the cached grant when the browser
/// actually reports the mic is no longer granted, so a one-off error doesn't
/// force a fresh permission prompt on the next take.
Future<void> _forgetMicrophonePermissionIfRevoked() async {
  if (kIsWeb && await relay_backing_audio.microphonePermissionGranted()) {
    return;
  }
  await _forgetMicrophonePermissionGranted();
}

bool _canTestRecordRelayForTest(WidgetRef ref, String part) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final role = profile?.role ?? '';
  final leaderPart = _firstText([profile?.partLeaderFor, profile?.part]);
  return role == 'admin' ||
      role == 'church_admin' ||
      (role == 'part_leader' && leaderPart == part);
}

class _PreviewAssignee {
  const _PreviewAssignee(this.id, this.name);

  final String id;
  final String name;
}

_PreviewAssignee _previewNextAssignee(
  String part, {
  Set<String> excludedUserIds = const {},
}) {
  final queues = <String, List<_PreviewAssignee>>{
    'soprano': const [
      _PreviewAssignee('preview-soprano-2', '오높음'),
      _PreviewAssignee('preview-soprano-3', '정소절'),
      _PreviewAssignee('preview-soprano-1', '윤소프'),
    ],
    'alto': const [
      _PreviewAssignee('preview-alto-2', '정화음'),
      _PreviewAssignee('preview-alto-3', '한중음'),
      _PreviewAssignee('preview-alto-1', '최알토'),
    ],
    'bass': const [
      _PreviewAssignee('preview-bass-2', '박저음'),
      _PreviewAssignee('preview-bass-3', '이든든'),
      _PreviewAssignee('preview-bass-1', '김베이스'),
    ],
    'tenor': const [
      _PreviewAssignee('preview-tenor-2', '서맑음'),
      _PreviewAssignee('preview-tenor-3', '남울림'),
      _PreviewAssignee('preview-tenor-1', '강테너'),
    ],
  };
  final queue = queues[part] ?? queues['soprano']!;
  return queue.firstWhere(
    (assignee) => !excludedUserIds.contains(assignee.id),
    orElse: () => queue.first,
  );
}

Map<String, dynamic> _focusRelayForMission(List<Map<String, dynamic>> relays) {
  if (relays.isEmpty) return const {};
  for (final relay in relays) {
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    if (!_relayCompleted(relay) &&
        assigneeId.isNotEmpty &&
        assigneeId == FirebaseService.uid) {
      return relay;
    }
  }
  for (final relay in relays) {
    if (!_relayCompleted(relay)) return relay;
  }
  return relays.last;
}

String _lyricLineFromRelayText(Map<String, dynamic> relay, int index) {
  final timeline = _lyricsTimelineFromValue(relay['lyricsTimeline']);
  if (timeline.isNotEmpty) {
    final start = (relay['segmentStartSec'] as num?)?.toDouble() ?? 0;
    final byStart = timeline.cast<Map<String, dynamic>?>().lastWhere(
      (entry) => ((entry?['timeSec'] as num?)?.toDouble() ?? 0) <= start + 0.4,
      orElse: () => null,
    );
    final textByStart = byStart?['text']?.toString().trim() ?? '';
    if (textByStart.isNotEmpty) return textByStart;
    if (index >= 0 && index < timeline.length) {
      return timeline[index]['text']?.toString().trim() ?? '';
    }
  }
  final lines = _plainLyricLines(relay['lyricsText']?.toString() ?? '');
  if (index >= 0 && index < lines.length) return lines[index];
  return lines.isNotEmpty ? lines.first : '';
}

String _nextLyricLineFromRelayText(Map<String, dynamic> relay, int index) {
  final timeline = _lyricsTimelineFromValue(relay['lyricsTimeline']);
  if (timeline.isNotEmpty) {
    final end = (relay['segmentEndSec'] as num?)?.toDouble() ?? 0;
    if (end > 0) {
      for (final entry in timeline) {
        final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
        final text = entry['text']?.toString().trim() ?? '';
        if (time > end + 0.2 && text.isNotEmpty) return text;
      }
    }
    final nextIndex = index + 1;
    if (nextIndex >= 0 && nextIndex < timeline.length) {
      return timeline[nextIndex]['text']?.toString().trim() ?? '';
    }
  }
  final lines = _plainLyricLines(relay['lyricsText']?.toString() ?? '');
  final nextIndex = index + 1;
  if (nextIndex >= 0 && nextIndex < lines.length) return lines[nextIndex];
  return '';
}

List<String> _plainLyricLines(String text) {
  return text
      .split(RegExp(r'\r?\n'))
      .map(
        (line) => _cleanDisplayText(line.replaceAll(RegExp(r'\[[^\]]+\]'), '')),
      )
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

void _openRelayClipsSheet(
  BuildContext context,
  List<Map<String, dynamic>> clips,
  String title,
) {
  if (clips.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('아직 들을 수 있는 녹음이 없어요.')));
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RelayClipsSheet(title: title, clips: clips),
  );
}

void _openRelayStudio(
  BuildContext context,
  Map<String, dynamic> relay,
  String part,
  String partLabel,
  WidgetRef ref, {
  List<Map<String, dynamic>>? missionRelays,
}) {
  final relayClips = ((relay['clips'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (_relayCompleted(relay) && !_canAdminModifyHarmonyRelayNow(ref)) {
    if (relayClips.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('완료된 녹음은 관리자만 수정할 수 있어요.')));
    } else {
      _openRelayClipsSheet(
        context,
        relayClips,
        relay['title']?.toString() ?? '완료된 릴레이',
      );
    }
    return;
  }
  final segmentIndex =
      missionRelays?.indexWhere(
        (item) => item['id']?.toString() == relay['id']?.toString(),
      ) ??
      ((relay['segmentOrder'] as num?)?.toInt() ?? 1) - 1;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RelayClipSheet(
      relayId: relay['id'].toString(),
      part: part,
      partLabel: partLabel,
      relayTitle: relay['title']?.toString() ?? '릴레이',
      guideAudioUrl: relay['guideAudioUrl']?.toString() ?? '',
      mrAudioUrl: relay['mrAudioUrl']?.toString() ?? '',
      segmentLabel: _segmentDisplayLabel(relay, segmentIndex),
      lyricsLine: relay['lyricsLine']?.toString() ?? '',
      nextLyricsLine: relay['nextLyricsLine']?.toString() ?? '',
      lyricsText: relay['lyricsText']?.toString() ?? '',
      lyricsTimeline: _lyricsTimelineFromValue(relay['lyricsTimeline']),
      segmentStartSec: (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
      segmentEndSec: (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
      previousClips: missionRelays == null
          ? relayClips
          : _previousMissionClipsFor(relay, missionRelays),
      ref: ref,
    ),
  );
}

List<Map<String, dynamic>> _previousMissionClipsFor(
  Map<String, dynamic> relay,
  List<Map<String, dynamic>> missionRelays,
) {
  final sorted = [...missionRelays]
    ..sort((a, b) {
      final aOrder = (a['segmentOrder'] as num?)?.toInt() ?? 0;
      final bOrder = (b['segmentOrder'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });
  final currentId = relay['id']?.toString() ?? '';
  final currentIndex = sorted.indexWhere(
    (item) => item['id']?.toString() == currentId,
  );
  if (currentIndex <= 0) return const [];
  final previousClips = <Map<String, dynamic>>[];
  for (var index = 0; index < currentIndex; index += 1) {
    final clips = ((sorted[index]['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (clips.isNotEmpty) {
      final previousRelay = sorted[index];
      previousClips.add({
        ...clips.last,
        'segmentStartSec':
            (previousRelay['segmentStartSec'] as num?)?.toDouble() ?? 0,
        'segmentEndSec':
            (previousRelay['segmentEndSec'] as num?)?.toDouble() ?? 0,
        'segmentLabel': _segmentDisplayLabel(previousRelay, index),
        'lyricsLine': _firstText([
          previousRelay['lyricsLine']?.toString(),
          _lyricLineFromRelayText(previousRelay, index),
        ]),
        'nextLyricsLine': _firstText([
          previousRelay['nextLyricsLine']?.toString(),
          _nextLyricLineFromRelayText(previousRelay, index),
        ]),
        'lyricsText': previousRelay['lyricsText']?.toString() ?? '',
        'lyricsTimeline': _lyricsTimelineFromValue(
          previousRelay['lyricsTimeline'],
        ),
      });
    }
  }
  return previousClips;
}

String _segmentDisplayLabel(Map<String, dynamic> relay, int index) {
  final fallbackOrder = index >= 0 ? index + 1 : 1;
  final order = (relay['segmentOrder'] as num?)?.toInt() ?? fallbackOrder;
  final rawLabel = relay['segmentLabel']?.toString().trim() ?? '';
  final lyric = _firstText([
    relay['lyricsLine']?.toString(),
    _lyricLineFromRelayText(relay, index),
  ]);
  if (lyric.isNotEmpty && _isGenericSegmentLabel(rawLabel)) {
    return '$order소절 · $lyric';
  }
  return _firstText([rawLabel, lyric, '$order소절']);
}

bool _isGenericSegmentLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty || trimmed == '소절') return true;
  return RegExp(r'^\d+\s*소절$').hasMatch(trimmed);
}

String _cleanDisplayText(String value) {
  return value
      .replaceAll(_emojiDisplayPattern, '')
      .replaceAll(_emojiControlPattern, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _songTitleFromRelayTitle(String value) {
  final cleaned = _cleanDisplayText(value);
  final withoutRelay = cleaned.replaceFirst(RegExp(r'\s*릴레이$'), '').trim();
  return withoutRelay.isEmpty ? cleaned : withoutRelay;
}

final _emojiDisplayPattern = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]',
  unicode: true,
);
final _emojiControlPattern = RegExp(r'[\u200D\uFE0E\uFE0F]');

String _firstText(List<String?> values) {
  for (final value in values) {
    final trimmed = _cleanDisplayText(value ?? '');
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

class _RelayCard extends StatelessWidget {
  const _RelayCard({
    required this.relay,
    required this.part,
    required this.partLabel,
    required this.ref,
    required this.highlightedRelayId,
  });

  final Map<String, dynamic> relay;
  final String part;
  final String partLabel;
  final WidgetRef ref;
  final String? highlightedRelayId;

  @override
  Widget build(BuildContext context) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final title = relay['title']?.toString() ?? '릴레이';
    final segmentLabel = relay['segmentLabel']?.toString() ?? '소절';
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final completed = _relayCompleted(relay);
    final canAdminModify = _canAdminModifyHarmonyRelay(ref);
    final canAdminModifyCompleted = completed && canAdminModify;
    final canOpenStudio = !completed || canAdminModify;
    final canTestRecord = !completed && _canTestRecordRelayForTest(ref, part);
    final canRecordNow =
        !completed && (isMyTurn || canTestRecord || assigneeName.isEmpty);
    final latest = clips.isEmpty ? null : clips.last;
    final singer =
        latest?['userName']?.toString() ??
        relay['completedByName']?.toString() ??
        '';
    final status = completed
        ? canAdminModify
              ? '관리자 수정 가능'
              : (singer.isEmpty ? '완료됨' : '$singer 완료')
        : isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트 녹음'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : '$assigneeName 차례';
    final hasClips = clips.isNotEmpty;
    final isHighlighted = relay['id']?.toString() == highlightedRelayId;

    void openStudio() {
      _openRelayStudio(context, relay, part, partLabel, ref);
    }

    return Material(
      color: isHighlighted ? const Color(0xFFFFFCF2) : AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: openStudio,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHighlighted
                  ? AppColors.secondary
                  : AppColors.border.withValues(alpha: 0.35),
              width: isHighlighted ? 1.6 : 1,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: 0.16),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: canRecordNow
                          ? AppColors.primary
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      canRecordNow
                          ? Icons.mic_rounded
                          : Icons.play_arrow_rounded,
                      color: canRecordNow ? Colors.white : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(16, weight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 7,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _RelayInfoPill(label: segmentLabel),
                            _RelayInfoPill(label: status),
                            if (hasClips)
                              _RelayInfoPill(label: '${clips.length}명'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isHighlighted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    '업로드 완료. 하모니맵에 방금 올린 녹음을 표시했어요.',
                    style: AppText.body(
                      12,
                      weight: FontWeight.w900,
                      color: AppColors.secondary,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _SingleHarmonyMap(
                clips: clips,
                isMyTurn: isMyTurn,
                canTestRecord: canTestRecord,
                assigneeName: assigneeName,
              ),
              const SizedBox(height: 12),
              if (hasClips)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openRelayClipsSheet(context, clips, title),
                        icon: const Icon(Icons.queue_music_rounded, size: 18),
                        label: const Text('듣기'),
                      ),
                    ),
                    if (canOpenStudio) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: openStudio,
                          icon: Icon(
                            canAdminModifyCompleted
                                ? Icons.admin_panel_settings_rounded
                                : Icons.mic_rounded,
                            size: 18,
                          ),
                          label: Text(
                            canAdminModifyCompleted ? '관리자 수정' : '녹음',
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canOpenStudio ? openStudio : null,
                    icon: const Icon(Icons.mic_rounded, size: 18),
                    label: Text(canOpenStudio ? '녹음하기' : '완료됨'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HarmonyStepStatus { done, mine, waiting }

class _SingleHarmonyMap extends StatelessWidget {
  const _SingleHarmonyMap({
    required this.clips,
    required this.isMyTurn,
    required this.canTestRecord,
    required this.assigneeName,
  });

  final List<Map<String, dynamic>> clips;
  final bool isMyTurn;
  final bool canTestRecord;
  final String assigneeName;

  @override
  Widget build(BuildContext context) {
    final visibleClips = clips.length > 5
        ? clips.sublist(clips.length - 5)
        : clips;
    final hiddenCount = clips.length - visibleClips.length;
    final currentCaption = isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트 녹음'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : assigneeName;
    final currentStatus = isMyTurn || canTestRecord
        ? _HarmonyStepStatus.mine
        : _HarmonyStepStatus.waiting;

    final steps = <Widget>[];
    if (hiddenCount > 0) {
      steps.add(_HarmonyOverflowNode(count: hiddenCount));
      steps.add(const _HarmonyConnector(done: true));
    }
    for (final entry in visibleClips.asMap().entries) {
      final clipIndex = hiddenCount + entry.key + 1;
      final author = entry.value['userName']?.toString() ?? '완료';
      steps.add(
        _HarmonyStepNode(
          label: '$clipIndex',
          caption: author,
          status: _HarmonyStepStatus.done,
        ),
      );
      steps.add(const _HarmonyConnector(done: true));
    }
    steps.add(
      _HarmonyStepNode(
        label: isMyTurn || canTestRecord ? 'REC' : '${clips.length + 1}',
        caption: currentCaption,
        status: currentStatus,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 7),
              Text('하모니맵', style: AppText.body(13, weight: FontWeight.w900)),
              const Spacer(),
              _RelaySequencePlayButton(clips: clips, dark: false, label: '재생'),
              const SizedBox(width: 8),
              _MapStatPill(label: '${clips.length}명', dark: false),
            ],
          ),
          const SizedBox(height: 9),
          const _HarmonyLegend(dark: false),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(children: steps),
          ),
        ],
      ),
    );
  }
}

class _RelaySequencePlayButton extends StatefulWidget {
  const _RelaySequencePlayButton({
    required this.clips,
    required this.dark,
    required this.label,
    this.onActiveRelayChanged,
  });

  final List<Map<String, dynamic>> clips;
  final bool dark;
  final String label;
  final ValueChanged<String?>? onActiveRelayChanged;

  @override
  State<_RelaySequencePlayButton> createState() =>
      _RelaySequencePlayButtonState();
}

class _RelaySequencePlayButtonState extends State<_RelaySequencePlayButton> {
  final _player = AudioPlayer();
  final _backingPlayer = AudioPlayer();
  final _sequenceStopwatch = Stopwatch();
  StreamSubscription<void>? _completeSub;
  Timer? _sequenceDelayTimer;
  Completer<void>? _sequenceDelayCompleter;
  int _playingIndex = -1;
  int _playbackRunId = 0;
  bool _isLoading = false;
  String _activeBackingUrl = '';
  Duration _sequenceBasePosition = Duration.zero;

  List<Map<String, dynamic>> get _playableClips =>
      _playableRelayClips(widget.clips);

  bool get _isPlaying => _playingIndex >= 0;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      unawaited(_playNextOrStop());
    });
  }

  @override
  void didUpdateWidget(covariant _RelaySequencePlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isPlaying &&
        _clipSequenceKey(oldWidget.clips) != _clipSequenceKey(widget.clips)) {
      unawaited(_stopPlayback());
    }
  }

  @override
  void dispose() {
    _playbackRunId += 1;
    _sequenceDelayTimer?.cancel();
    if (_sequenceDelayCompleter?.isCompleted == false) {
      _sequenceDelayCompleter?.complete();
    }
    _completeSub?.cancel();
    unawaited(_player.dispose());
    unawaited(_backingPlayer.dispose());
    relay_backing_audio.stopRelayBackingAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playable = _playableClips;
    final enabled = playable.isNotEmpty;
    final foreground = widget.dark ? const Color(0xFF2F2508) : Colors.white;
    final disabledForeground = widget.dark
        ? Colors.white.withValues(alpha: 0.58)
        : AppColors.muted;
    final background = widget.dark
        ? enabled
              ? AppColors.secondaryContainer
              : Colors.white.withValues(alpha: 0.12)
        : enabled
        ? AppColors.primary
        : AppColors.card.withValues(alpha: 0.58);
    final borderColor = widget.dark
        ? Colors.white.withValues(alpha: enabled ? 0.72 : 0.18)
        : AppColors.border.withValues(alpha: 0.38);
    final shadowColor = widget.dark
        ? Colors.black.withValues(alpha: enabled ? 0.16 : 0)
        : AppColors.primary.withValues(alpha: enabled ? 0.22 : 0);
    final label = !enabled
        ? '녹음 없음'
        : _isPlaying
        ? '${_playingSegmentLabel(playable)} 재생 중'
        : widget.label;

    return Tooltip(
      message: enabled
          ? '${playable.length}개 릴레이 녹음 이어 듣기'
          : '녹음이 쌓이면 이어 들을 수 있어요',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: shadowColor,
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
          ],
        ),
        child: TextButton.icon(
          onPressed: enabled ? _togglePlayback : null,
          style: TextButton.styleFrom(
            foregroundColor: enabled ? foreground : disabledForeground,
            backgroundColor: background,
            disabledForegroundColor: disabledForeground,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            minimumSize: Size(widget.dark ? 116 : 82, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(color: borderColor, width: enabled ? 1.2 : 1),
            ),
          ),
          icon: Icon(
            _isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
            size: 19,
          ),
          label: Text(
            _isLoading ? '준비 중' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(12, weight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying || _isLoading) {
      await _stopPlayback();
      return;
    }
    _playbackRunId += 1;
    await _playAt(0, _playbackRunId);
  }

  Future<void> _playAt(int index, int runId) async {
    final clips = _playableClips;
    if (runId != _playbackRunId) return;
    if (index < 0 || index >= clips.length) {
      await _stopPlayback();
      return;
    }
    final url = clips[index]['audioUrl']?.toString().trim() ?? '';
    if (url.isEmpty) {
      await _playAt(index + 1, runId);
      return;
    }
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      // Preload (buffer) the voice clip BEFORE we wait for its cue, so the moment
      // the MR clock reaches this segment we can start it instantly with
      // resume() instead of paying network/decode latency after the cue — that
      // lag is what made layered voices trail the backing track.
      var preloaded = false;
      try {
        await _player.stop();
        await _player.setSource(_relayAudioSource(url));
        preloaded = true;
      } catch (_) {
        preloaded = false;
      }
      await _ensureSequenceBacking(clips, index, runId);
      await _waitForClipStart(clips[index], runId);
      if (!mounted || runId != _playbackRunId) return;
      setState(() => _playingIndex = index);
      widget.onActiveRelayChanged?.call(_relayIdForClip(clips[index]));
      if (preloaded) {
        await _player.resume();
      } else {
        await _player.stop();
        await _playRelayAudioSource(_player, url);
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (index + 1 < clips.length) {
        await _playAt(index + 1, runId);
        return;
      }
      if (!mounted) return;
      setState(() {
        _playingIndex = -1;
        _isLoading = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      widget.onActiveRelayChanged?.call(null);
      await _stopSequenceBacking();
      messenger.showSnackBar(
        const SnackBar(content: Text('릴레이 녹음을 재생할 수 없습니다.')),
      );
    }
  }

  Future<void> _playNextOrStop() async {
    if (!_isPlaying) return;
    final nextIndex = _playingIndex + 1;
    if (nextIndex >= _playableClips.length) {
      await _finishPlayback();
      return;
    }
    await _playAt(nextIndex, _playbackRunId);
  }

  Future<void> _stopPlayback() async {
    _playbackRunId += 1;
    _sequenceDelayTimer?.cancel();
    if (_sequenceDelayCompleter?.isCompleted == false) {
      _sequenceDelayCompleter?.complete();
    }
    if (mounted) {
      setState(() {
        _playingIndex = -1;
        _isLoading = false;
      });
    }
    await _player.stop();
    widget.onActiveRelayChanged?.call(null);
    await _stopSequenceBacking();
  }

  Future<void> _finishPlayback() async {
    _sequenceDelayTimer?.cancel();
    if (_sequenceDelayCompleter?.isCompleted == false) {
      _sequenceDelayCompleter?.complete();
    }
    if (mounted) {
      setState(() {
        _playingIndex = -1;
        _isLoading = false;
      });
    }
    widget.onActiveRelayChanged?.call(null);
    await _stopSequenceBacking();
  }

  Future<void> _ensureSequenceBacking(
    List<Map<String, dynamic>> clips,
    int index,
    int runId,
  ) async {
    final backingUrl = _backingUrlForSequence(clips, index);
    if (backingUrl.isEmpty) return;
    final basePosition = _segmentStartForClip(clips.first);
    if (_activeBackingUrl == backingUrl &&
        _sequenceBasePosition == basePosition &&
        _sequenceStopwatch.isRunning) {
      return;
    }
    try {
      await _stopSequenceBacking();
      if (!mounted || runId != _playbackRunId) return;
      _sequenceBasePosition = basePosition;
      _sequenceStopwatch
        ..reset()
        ..start();
      if (kIsWeb &&
          relay_backing_audio.startRelayBackingAudio(
            backingUrl,
            basePosition,
          )) {
        _activeBackingUrl = backingUrl;
        return;
      }
      await _backingPlayer.setReleaseMode(ReleaseMode.stop);
      await _backingPlayer.setVolume(0.82);
      await _backingPlayer.play(UrlSource(backingUrl), position: basePosition);
      _activeBackingUrl = backingUrl;
    } catch (_) {
      await _stopSequenceBacking();
    }
  }

  String _backingUrlForSequence(List<Map<String, dynamic>> clips, int index) {
    final current = clips[index]['mrAudioUrl']?.toString().trim() ?? '';
    if (current.isNotEmpty) return current;
    for (final clip in clips) {
      final url = clip['mrAudioUrl']?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  Future<void> _waitForClipStart(Map<String, dynamic> clip, int runId) async {
    if (_activeBackingUrl.isEmpty) return;
    final clipStart = _segmentStartForClip(clip);
    // Poll the MR master clock and release exactly when the backing track
    // reaches this clip's segment start, so the layered voice lines up with the
    // MR the same way it did at record time (instead of trusting a timer that
    // ignores the element's real startup latency).
    while (mounted && runId == _playbackRunId) {
      final position = _currentBackingPosition();
      if (position == null) return;
      final remaining = clipStart - position;
      if (remaining <= const Duration(milliseconds: 45)) return;
      final step = remaining > const Duration(milliseconds: 160)
          ? const Duration(milliseconds: 90)
          : remaining;
      final completer = Completer<void>();
      _sequenceDelayCompleter = completer;
      _sequenceDelayTimer?.cancel();
      _sequenceDelayTimer = Timer(step, () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
      if (_sequenceDelayCompleter == completer) {
        _sequenceDelayCompleter = null;
      }
    }
  }

  Duration? _currentBackingPosition() {
    if (kIsWeb && relay_backing_audio.relayBackingAudioPlaying()) {
      final seconds = relay_backing_audio.relayBackingAudioSeconds();
      if (seconds >= 0) {
        return Duration(milliseconds: (seconds * 1000).round());
      }
    }
    if (_sequenceStopwatch.isRunning) {
      return _sequenceBasePosition + _sequenceStopwatch.elapsed;
    }
    return null;
  }

  Duration _segmentStartForClip(Map<String, dynamic> clip) {
    final seconds = (clip['segmentStartSec'] as num?)?.toDouble() ?? 0;
    if (seconds <= 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  String _relayIdForClip(Map<String, dynamic> clip) {
    return clip['relayId']?.toString() ?? '';
  }

  String _playingSegmentLabel(List<Map<String, dynamic>> clips) {
    if (_playingIndex < 0 || _playingIndex >= clips.length) {
      return '${_playingIndex + 1}/${clips.length}';
    }
    final clip = clips[_playingIndex];
    final label = clip['segmentLabel']?.toString().trim() ?? '';
    if (label.isNotEmpty) return label;
    final order = (clip['segmentOrder'] as num?)?.toInt();
    if (order != null && order > 0) return '$order번';
    return '${_playingIndex + 1}/${clips.length}';
  }

  Future<void> _stopSequenceBacking() async {
    _sequenceStopwatch.stop();
    _sequenceStopwatch.reset();
    _activeBackingUrl = '';
    _sequenceBasePosition = Duration.zero;
    relay_backing_audio.stopRelayBackingAudio();
    await _backingPlayer.stop();
  }
}

class _HarmonyStepNode extends StatelessWidget {
  const _HarmonyStepNode({
    required this.label,
    required this.caption,
    required this.status,
  });

  final String label;
  final String caption;
  final _HarmonyStepStatus status;

  @override
  Widget build(BuildContext context) {
    final isDone = status == _HarmonyStepStatus.done;
    final isMine = status == _HarmonyStepStatus.mine;
    final color = isDone
        ? AppColors.success
        : isMine
        ? AppColors.primary
        : AppColors.muted;
    final bg = isDone
        ? const Color(0xFFEAF5EA)
        : isMine
        ? AppColors.card
        : AppColors.surfaceLow;
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: isMine ? 2 : 1.2),
            ),
            child: Center(
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.success,
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      style: AppText.body(
                        label.length > 2 ? 8 : 10,
                        weight: FontWeight.w900,
                        color: color,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.body(
              10,
              weight: isMine ? FontWeight.w900 : FontWeight.w700,
              color: isMine ? AppColors.primary : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _HarmonyConnector extends StatelessWidget {
  const _HarmonyConnector({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 2,
      margin: const EdgeInsets.only(bottom: 21),
      color: done
          ? AppColors.success.withValues(alpha: 0.68)
          : AppColors.border.withValues(alpha: 0.6),
    );
  }
}

class _HarmonyOverflowNode extends StatelessWidget {
  const _HarmonyOverflowNode({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                '+$count',
                style: AppText.body(
                  10,
                  weight: FontWeight.w900,
                  color: AppColors.success,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text('완료', style: AppText.body(10, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _HarmonyLegend extends StatelessWidget {
  const _HarmonyLegend({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final textColor = dark
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.muted;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        _HarmonyLegendItem(
          color: AppColors.success,
          label: '완료',
          textColor: textColor,
        ),
        _HarmonyLegendItem(
          color: dark ? AppColors.secondaryContainer : AppColors.primary,
          label: '진행',
          textColor: textColor,
        ),
        _HarmonyLegendItem(
          color: dark ? Colors.white.withValues(alpha: 0.42) : AppColors.muted,
          label: '대기',
          textColor: textColor,
        ),
      ],
    );
  }
}

class _HarmonyLegendItem extends StatelessWidget {
  const _HarmonyLegendItem({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.body(11, weight: FontWeight.w700, color: textColor)),
      ],
    );
  }
}

class _MapStatPill extends StatelessWidget {
  const _MapStatPill({required this.label, required this.dark});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : AppColors.card.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.border.withValues(alpha: 0.32),
        ),
      ),
      child: Text(
        label,
        style: AppText.body(
          11,
          weight: FontWeight.w900,
          color: dark ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }
}

class _RelayInfoPill extends StatelessWidget {
  const _RelayInfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(
          11,
          weight: FontWeight.w800,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AttemptPill extends StatelessWidget {
  const _AttemptPill({required this.used, required this.max});

  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final exhausted = used >= max;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: exhausted ? const Color(0xFFFFE8E8) : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: exhausted
              ? AppColors.error.withValues(alpha: 0.28)
              : AppColors.border.withValues(alpha: 0.32),
        ),
      ),
      child: Text(
        '기회 $used/$max',
        style: AppText.body(
          11,
          weight: FontWeight.w900,
          color: exhausted ? AppColors.error : AppColors.primary,
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        score <= 0 ? '체크' : '$score',
        style: AppText.body(
          11,
          weight: FontWeight.w900,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _TurnPill extends StatelessWidget {
  const _TurnPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.secondary : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(
          11,
          weight: FontWeight.w900,
          color: active ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }
}

class _HarmonyNoteCard extends StatelessWidget {
  const _HarmonyNoteCard({required this.note});

  final Map<String, dynamic> note;

  @override
  Widget build(BuildContext context) {
    final title = note['title']?.toString() ?? '음성 노트';
    final prompt = note['prompt']?.toString() ?? '';
    final author = note['userName']?.toString();
    final part = note['userPart']?.toString();
    final partLabel = User.partLabels[part] ?? '';
    final url = note['audioUrl']?.toString() ?? '';
    final fileName = note['audioFileName']?.toString() ?? '';
    final createdAt = _relativeTime(note['createdAt']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  (author?.isNotEmpty ?? false) ? author![0] : '?',
                  style: AppText.body(
                    14,
                    weight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        author?.isNotEmpty == true ? author! : '단원',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(14, weight: FontWeight.w800),
                      ),
                    ),
                    if (partLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _MiniTag(label: partLabel),
                    ],
                  ],
                ),
              ),
              Text(createdAt, style: AppText.body(11, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: AppText.body(17, weight: FontWeight.w900)),
          if (prompt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              prompt,
              style: AppText.body(
                13,
                color: AppColors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: url.isEmpty
                ? null
                : () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fileName.isNotEmpty ? fileName : '음성 듣기',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(13, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '듣기',
                    style: AppText.body(
                      12,
                      weight: FontWeight.w900,
                      color: AppColors.secondary,
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
}

class _HarmonyNoteSheet extends StatefulWidget {
  const _HarmonyNoteSheet({required this.part, required this.ref});

  final String part;
  final WidgetRef ref;

  @override
  State<_HarmonyNoteSheet> createState() => _HarmonyNoteSheetState();
}

class _CreateRelaySheet extends StatefulWidget {
  const _CreateRelaySheet({
    required this.part,
    required this.partLabel,
    required this.ref,
  });

  final String part;
  final String partLabel;
  final WidgetRef ref;

  @override
  State<_CreateRelaySheet> createState() => _CreateRelaySheetState();
}

class _CreateRelaySheetState extends State<_CreateRelaySheet> {
  final _titleController = TextEditingController();
  final _segmentController = TextEditingController();
  final _guideController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLaunched = false;
  String _launchedTitle = '';
  String _launchedSegment = '';
  String _launchedGuide = '';

  @override
  void dispose() {
    _titleController.dispose();
    _segmentController.dispose();
    _guideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _isLaunched
            ? _RelayLaunchCelebration(
                key: const ValueKey('relay-launched'),
                title: _launchedTitle,
                segmentLabel: _launchedSegment,
                guide: _launchedGuide,
                partLabel: widget.partLabel,
                onClose: () => Navigator.pop(context),
              )
            : Container(
                key: const ValueKey('relay-form'),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.partLabel} 릴레이 만들기',
                              style: AppText.body(20, weight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '릴레이 제목',
                          hintText: '예: 주만 바라볼지라 후렴',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _segmentController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '소절 / 구간',
                          hintText: '예: 후렴 1마디, 2절 첫 줄',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _guideController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '이어 부를 포인트',
                          hintText: '진입음, 호흡, 가사 느낌을 짧게 적어주세요',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isSubmitting ? null : _submit,
                          child: Text(
                            _isSubmitting ? '퀘스트 여는 중...' : '릴레이 시작하기',
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

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final segment = _segmentController.text.trim();
    final guide = _guideController.text.trim();
    if (title.isEmpty || segment.isEmpty) {
      _showMessage('제목과 소절을 입력해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      if (widget.ref.read(localPreviewModeProvider)) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      } else {
        await FirebaseService.createHarmonyRelay(
          part: widget.part,
          title: title,
          segmentLabel: segment,
          guide: guide,
        );
        widget.ref.invalidate(harmonyRelaysProvider);
      }
      if (!mounted) return;
      setState(() {
        _isLaunched = true;
        _isSubmitting = false;
        _launchedTitle = title;
        _launchedSegment = segment;
        _launchedGuide = guide;
      });
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RelayLaunchCelebration extends StatelessWidget {
  const _RelayLaunchCelebration({
    super.key,
    required this.title,
    required this.segmentLabel,
    required this.guide,
    required this.partLabel,
    required this.onClose,
  });

  final String title;
  final String segmentLabel;
  final String guide;
  final String partLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF000916), Color(0xFF00234B), Color(0xFF171005)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondaryContainer.withValues(
                          alpha: 0.45,
                        ),
                        blurRadius: 28,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QUEST OPEN',
                        style: AppText.body(
                          12,
                          weight: FontWeight.w900,
                          color: AppColors.secondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '릴레이가 시작됐어요',
                        style: AppText.body(
                          22,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  color: Colors.white,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: value,
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        color: AppColors.secondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value < 1 ? 'MISSION LOADING' : 'FIRST TURN READY',
                      style: AppText.body(
                        11,
                        weight: FontWeight.w900,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.secondaryContainer.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      20,
                      weight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _RelayLaunchBadge(
                        icon: Icons.groups_rounded,
                        label: partLabel,
                      ),
                      _RelayLaunchBadge(
                        icon: Icons.flag_rounded,
                        label: segmentLabel,
                      ),
                      const _RelayLaunchBadge(
                        icon: Icons.graphic_eq_rounded,
                        label: 'Combo x1',
                      ),
                    ],
                  ),
                  if (guide.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      guide,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        13,
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _RelayLaunchStat(
                    icon: Icons.mic_rounded,
                    value: '1',
                    label: '첫 소절',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RelayLaunchStat(
                    icon: Icons.auto_awesome_motion_rounded,
                    value: 'LIVE',
                    label: '상태',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onClose,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondaryContainer,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.sports_esports_rounded, size: 19),
                label: const Text('릴레이 방으로 이동'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelayLaunchBadge extends StatelessWidget {
  const _RelayLaunchBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.secondaryContainer, size: 15),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                12,
                weight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayLaunchStat extends StatelessWidget {
  const _RelayLaunchStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.secondaryContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    14,
                    weight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    11,
                    color: Colors.white.withValues(alpha: 0.64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayClipSheet extends StatefulWidget {
  const _RelayClipSheet({
    required this.relayId,
    required this.part,
    required this.partLabel,
    required this.relayTitle,
    required this.guideAudioUrl,
    required this.mrAudioUrl,
    required this.segmentLabel,
    required this.lyricsLine,
    required this.nextLyricsLine,
    required this.lyricsText,
    required this.lyricsTimeline,
    required this.segmentStartSec,
    required this.segmentEndSec,
    required this.previousClips,
    required this.ref,
  });

  final String relayId;
  final String part;
  final String partLabel;
  final String relayTitle;
  final String guideAudioUrl;
  final String mrAudioUrl;
  final String segmentLabel;
  final String lyricsLine;
  final String nextLyricsLine;
  final String lyricsText;
  final List<Map<String, dynamic>> lyricsTimeline;
  final double segmentStartSec;
  final double segmentEndSec;
  final List<Map<String, dynamic>> previousClips;
  final WidgetRef ref;

  @override
  State<_RelayClipSheet> createState() => _RelayClipSheetState();
}

class _RelayRecordingAttempt {
  const _RelayRecordingAttempt({
    required this.number,
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.durationSeconds,
  });

  final int number;
  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int durationSeconds;
}

class _RelayClipSheetState extends State<_RelayClipSheet> {
  final _recorder = AudioRecorder();
  final _guidePlayer = AudioPlayer();
  final _backingPlayer = AudioPlayer();
  final _countdownPlayer = AudioPlayer();
  String? _primedBackingUrl;
  final List<_RelayRecordingAttempt> _attempts = [];
  final List<int> _recordedBytes = [];
  StreamSubscription<Uint8List>? _recordingSub;
  StreamSubscription<void>? _playerCompleteSub;
  Timer? _recordingTimer;
  Timer? _playbackTimer;
  Timer? _segmentStopTimer;
  String _audioFileName = '';
  String _contentType = 'audio/webm';
  bool _streamRecording = false;
  int? _countdown;
  bool _isRecording = false;
  bool _isSubmitting = false;
  bool _isGuidePlaying = false;
  bool _isHandoffPlaying = false;
  bool _isMrRecording = false;
  int _recordAttemptCount = 0;
  int _recordSeconds = 0;
  double _recordElapsedSeconds = 0;
  double _playbackElapsedSeconds = 0;
  double _playbackLyricBaseSeconds = 0;
  double _playbackLyricDurationSeconds = 0;
  int _handoffPlaybackIndex = 0;
  int? _selectedAttemptNumber;
  int? _playingAttemptNumber;
  double _progress = 0;
  String _submitError = '';
  int _lastWaveformByteCount = 0;
  List<double> _waveformLevels = List<double>.filled(28, 0.08);
  final _recordingStopwatch = Stopwatch();
  final _playbackStopwatch = Stopwatch();

  static const _sampleRate = 44100;
  static const _channels = 1;
  static const _maxRecordAttempts = 3;
  static const _countdownStep = Duration(milliseconds: 760);
  static const _countdownTotalDuration = Duration(milliseconds: 2280);
  static Uint8List? _countdownBeepBytes;
  static Uint8List? _countdownStartBeepBytes;
  static Uint8List? _previewAttemptBytes;

  List<Map<String, dynamic>> get _playablePreviousClips {
    return widget.previousClips
        .where((clip) {
          final url = clip['audioUrl']?.toString().trim() ?? '';
          return url.isNotEmpty;
        })
        .toList(growable: false);
  }

  bool get _hasAttemptsLeft => _recordAttemptCount < _maxRecordAttempts;

  String? get _recordingBackingUrl {
    final url = widget.mrAudioUrl.trim();
    return url.isEmpty ? null : url;
  }

  int get _remainingAttempts {
    final remaining = _maxRecordAttempts - _recordAttemptCount;
    return remaining < 0 ? 0 : remaining;
  }

  _RelayRecordingAttempt? get _selectedAttempt {
    if (_attempts.isEmpty) return null;
    for (final attempt in _attempts) {
      if (attempt.number == _selectedAttemptNumber) return attempt;
    }
    return _attempts.last;
  }

  Duration get _segmentStart {
    final milliseconds = (widget.segmentStartSec * 1000).round();
    return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
  }

  Duration get _segmentDuration {
    if (widget.segmentEndSec <= widget.segmentStartSec) return Duration.zero;
    final milliseconds =
        ((widget.segmentEndSec - widget.segmentStartSec) * 1000).round();
    return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
  }

  @override
  void initState() {
    super.initState();
    _playbackLyricBaseSeconds = widget.segmentStartSec;
    _playbackLyricDurationSeconds = _segmentDuration.inMilliseconds / 1000;
    _playerCompleteSub = _guidePlayer.onPlayerComplete.listen((_) {
      if (!mounted || _playingAttemptNumber == null) return;
      setState(() => _playingAttemptNumber = null);
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _segmentStopTimer?.cancel();
    _recordingStopwatch.stop();
    _playbackStopwatch.stop();
    _recordingSub?.cancel();
    _playerCompleteSub?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_guidePlayer.dispose());
    unawaited(_backingPlayer.dispose());
    unawaited(_countdownPlayer.dispose());
    relay_backing_audio.stopRelayBackingAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final lyricProgress = _lyricProgress;
    final previousClipCount = _playablePreviousClips.length;
    final hasArGuide = widget.guideAudioUrl.trim().isNotEmpty;
    final hasMrBacking = _recordingBackingUrl != null;
    final selectedAttempt = _selectedAttempt;
    final isBusy =
        _isSubmitting ||
        _isRecording ||
        _isGuidePlaying ||
        _isHandoffPlaying ||
        _countdown != null ||
        _playingAttemptNumber != null;
    final activeSegmentLabel = _activeLyricSegmentLabel;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '릴레이 스튜디오',
                        style: AppText.body(20, weight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const _InlineCloseIcon(size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.relayTitle} · ${widget.partLabel}',
                  style: AppText.body(13, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                _KaraokeLyricsPanel(
                  title: _songTitleFromRelayTitle(widget.relayTitle),
                  currentLine: _currentLyricLine,
                  nextLine: _nextLyricLine,
                  segmentLabel: activeSegmentLabel,
                  progress: lyricProgress,
                  isActive:
                      _isRecording ||
                      _isGuidePlaying ||
                      _isHandoffPlaying ||
                      _countdown != null,
                  statusText: _countdown != null
                      ? '곧 시작'
                      : _isRecording
                      ? '녹음 중'
                      : _isGuidePlaying
                      ? 'AR 재생'
                      : _isHandoffPlaying
                      ? '릴레이 재생'
                      : '가사 대기',
                ),
                if (widget.guideAudioUrl.isNotEmpty ||
                    widget.mrAudioUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.segmentLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(
                                  12,
                                  color: AppColors.secondary,
                                  weight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _AttemptPill(
                              used: _recordAttemptCount,
                              max: _maxRecordAttempts,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          previousClipCount > 0
                              ? hasMrBacking
                                    ? '앞선 $previousClipCount개 릴레이를 듣고 내 소절부터 MR에 녹음'
                                    : '앞선 $previousClipCount개 릴레이를 듣고 내 소절부터 바로 녹음'
                              : hasArGuide && hasMrBacking
                              ? '내 파트 AR 확인 후 MR에 바로 녹음'
                              : hasArGuide
                              ? '내 파트 AR을 따로 듣고 바로 녹음'
                              : hasMrBacking
                              ? 'MR에 맞춰 녹음'
                              : 'AR/MR 음원이 없습니다',
                          style: AppText.body(
                            12,
                            color: AppColors.muted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.secondarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const _InlineInfoIcon(
                                color: AppColors.secondary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '녹음 기회는 총 3번이에요. 각 테이크를 들어보고 마음에 드는 것만 골라 올릴 수 있어요.',
                                  style: AppText.body(
                                    12,
                                    weight: FontWeight.w700,
                                    color: AppColors.secondary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    isBusy || widget.guideAudioUrl.isEmpty
                                    ? null
                                    : _playGuideOnce,
                                icon: const _InlinePlayIcon(size: 18),
                                label: const Text('내 파트 AR'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: isBusy || !_hasAttemptsLeft
                                    ? null
                                    : _recordFromRelayLeadIn,
                                icon: const _InlineWaveIcon(size: 18),
                                label: Text(
                                  previousClipCount > 0
                                      ? hasMrBacking
                                            ? '이어듣고 MR 녹음'
                                            : '이어듣고 녹음'
                                      : hasMrBacking
                                      ? 'MR 녹음'
                                      : '바로 녹음',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? AppColors.secondarySoft
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          (_isRecording
                                  ? AppColors.secondary
                                  : AppColors.border)
                              .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      _RelayStudioStateIcon(
                        countdown: _countdown,
                        isRecording: _isRecording,
                      ),
                      const SizedBox(height: 8),
                      if (_countdown != null) ...[
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                          child: Text(
                            '$_countdown',
                            key: ValueKey(_countdown),
                            style: AppText.headline(
                              46,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        _countdown != null
                            ? (_isHandoffPlaying
                                  ? '앞 릴레이 위에 카운트 중'
                                  : '숨을 고르고 바로 시작합니다')
                            : _isHandoffPlaying
                            ? '앞 릴레이 듣는 중 $_handoffPlaybackIndex/$previousClipCount'
                            : _isGuidePlaying
                            ? 'AR 재생 중...'
                            : _isRecording
                            ? (_isMrRecording
                                  ? 'MR에 맞춰 녹음 중 ${_formatDuration(_recordSeconds)}'
                                  : '녹음 중 ${_formatDuration(_recordSeconds)}')
                            : !_hasAttemptsLeft && selectedAttempt == null
                            ? '3번의 기회를 모두 사용했어요'
                            : selectedAttempt == null
                            ? hasMrBacking
                                  ? 'MR 반주에 맞춰 이어 부를 준비가 됐어요'
                                  : '한 소절을 바로 녹음할 준비가 됐어요'
                            : '${selectedAttempt.number}번 테이크가 선택됐어요',
                        style: AppText.body(16, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _countdown != null && _isHandoffPlaying
                            ? '끊기지 않게 바로 이어서 녹음돼요.'
                            : _isHandoffPlaying
                            ? '내 소절이 오면 카운트다운 후 녹음이 시작돼요.'
                            : _remainingAttempts == 0
                            ? '3번 모두 녹음했어요. 아래에서 하나를 골라 올려주세요.'
                            : '총 3번 중 $_recordAttemptCount번 사용, $_remainingAttempts번 남음',
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                      if (_isRecording) ...[
                        const SizedBox(height: 14),
                        _RecordingWaveform(
                          levels: _waveformLevels,
                          active: _isRecording,
                          label: _isMrRecording ? 'MR 재생 중' : '마이크 입력 중',
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed:
                            _isSubmitting ||
                                _countdown != null ||
                                _isGuidePlaying ||
                                (!_isRecording && !_hasAttemptsLeft)
                            ? null
                            : _isRecording
                            ? _stopRecording
                            : _recordFromRelayLeadIn,
                        icon: _isRecording
                            ? const _InlineCheckIcon(size: 18)
                            : const _InlineMicIcon(size: 18),
                        label: Text(
                          _isRecording
                              ? '녹음 완료'
                              : selectedAttempt == null
                              ? (previousClipCount > 0
                                    ? hasMrBacking
                                          ? '이어듣고 MR 녹음하기'
                                          : '이어듣고 녹음하기'
                                    : hasMrBacking
                                    ? 'MR에 녹음하기'
                                    : '녹음하기')
                              : (hasMrBacking ? 'MR에 다시 녹음' : '다시 녹음'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_attempts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _RelayRecordingAttemptsPanel(
                    attempts: _attempts,
                    selectedNumber: selectedAttempt?.number,
                    playingNumber: _playingAttemptNumber,
                    isBusy: isBusy,
                    onSelect: (number) {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() => _selectedAttemptNumber = number);
                    },
                    onPlay: _toggleAttemptPlayback,
                  ),
                ],
                if (_isSubmitting) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                  ),
                ],
                if (_submitError.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _submitError,
                      style: AppText.body(
                        12,
                        weight: FontWeight.w800,
                        color: AppColors.error,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _isSubmitting ||
                            (selectedAttempt == null && !_isRecording)
                        ? null
                        : _submit,
                    child: Text(
                      _isSubmitting
                          ? '릴레이에 붙이는 중...'
                          : selectedAttempt == null && !_isRecording
                          ? '테이크 녹음 후 올리기'
                          : '릴레이에 올리기',
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

  Future<void> _countdownThenStartRecording({
    String? backingUrl,
    bool primeBacking = false,
    bool permissionReady = false,
  }) async {
    if (_isRecording ||
        _isSubmitting ||
        _isGuidePlaying ||
        _countdown != null) {
      return;
    }
    if (!_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    if (!permissionReady && !await _ensureRecordingPermissionReady()) return;
    if (primeBacking && backingUrl != null && backingUrl.isNotEmpty) {
      await _primeRecordingBacking(backingUrl);
    }
    await _runCountdown();
    if (!mounted) return;
    await _startRecordingInternal(
      backingUrl: backingUrl,
      permissionReady: true,
    );
  }

  Future<void> _runCountdown() async {
    try {
      for (final value in const [3, 2, 1]) {
        if (!mounted) return;
        setState(() => _countdown = value);
        unawaited(_playCountdownBeep(value));
        unawaited(HapticFeedback.lightImpact());
        await Future<void>.delayed(_countdownStep);
      }
    } finally {
      if (mounted) setState(() => _countdown = null);
    }
  }

  Future<void> _runCountdownAfter(
    Duration delay, {
    bool Function()? shouldRun,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (shouldRun != null && !shouldRun()) return;
    if (!mounted) return;
    await _runCountdown();
  }

  Duration _countdownDelayForHandoff(Duration handoffDuration) {
    if (handoffDuration <= Duration.zero) return Duration.zero;
    final delay = handoffDuration - _countdownTotalDuration;
    return delay.isNegative ? Duration.zero : delay;
  }

  Future<void> _playCountdownBeep(int value) async {
    try {
      final bytes = value == 1
          ? (_countdownStartBeepBytes ??= _countdownToneBytes(
              frequency: 1320,
              durationMs: 170,
            ))
          : (_countdownBeepBytes ??= _countdownToneBytes(
              frequency: 880,
              durationMs: 130,
            ));
      await _countdownPlayer.stop();
      await _countdownPlayer.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (_) {
      // 카운트 소리는 보조 피드백이라 실패해도 녹음 흐름은 유지합니다.
    }
  }

  static Uint8List _countdownToneBytes({
    required double frequency,
    required int durationMs,
  }) {
    const sampleRate = 44100;
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final pcmBytes = Uint8List(sampleCount * 2);
    final data = ByteData.sublistView(pcmBytes);
    final fadeSamples = math.min(
      (sampleRate * 0.012).round(),
      sampleCount ~/ 2,
    );
    for (var index = 0; index < sampleCount; index += 1) {
      final fadeIn = fadeSamples == 0 ? 1.0 : index / fadeSamples;
      final fadeOut = fadeSamples == 0
          ? 1.0
          : (sampleCount - index - 1) / fadeSamples;
      final envelope = math.min(1.0, math.min(fadeIn, fadeOut)).clamp(0.0, 1.0);
      final sample =
          math.sin(2 * math.pi * frequency * index / sampleRate) *
          0.34 *
          envelope;
      data.setInt16((index * 2), (sample * 32767).round(), Endian.little);
    }
    return _wavFromPcmBytes(pcmBytes, sampleRate: sampleRate, channels: 1);
  }

  static Uint8List _previewAttemptToneBytes(int durationSeconds) {
    final cached = durationSeconds == 3 ? _previewAttemptBytes : null;
    if (cached != null) return cached;

    final frameCount = _sampleRate * durationSeconds;
    final pcmBytes = Uint8List(frameCount * _channels * 2);
    final data = ByteData.sublistView(pcmBytes);
    final fadeSamples = math.min(
      (_sampleRate * 0.045).round(),
      frameCount ~/ 2,
    );
    const melody = [392.0, 440.0, 493.88, 523.25];
    for (var frame = 0; frame < frameCount; frame += 1) {
      final seconds = frame / _sampleRate;
      final note = melody[((seconds / 0.75).floor()) % melody.length];
      final fadeIn = fadeSamples == 0 ? 1.0 : frame / fadeSamples;
      final fadeOut = fadeSamples == 0
          ? 1.0
          : (frameCount - frame - 1) / fadeSamples;
      final envelope = math.min(1.0, math.min(fadeIn, fadeOut)).clamp(0.0, 1.0);
      final sample =
          (math.sin(2 * math.pi * note * seconds) * 0.26 +
              math.sin(2 * math.pi * note * 2 * seconds) * 0.06) *
          envelope;
      final intSample = (sample * 32767).round();
      for (var channel = 0; channel < _channels; channel += 1) {
        data.setInt16(
          ((frame * _channels + channel) * 2),
          intSample,
          Endian.little,
        );
      }
    }

    final wav = _wavFromPcmBytes(
      pcmBytes,
      sampleRate: _sampleRate,
      channels: _channels,
    );
    if (durationSeconds == 3) _previewAttemptBytes = wav;
    return wav;
  }

  Future<void> _recordFromRelayLeadIn() async {
    final hasMrBacking = _recordingBackingUrl != null;
    final previousClips = _playablePreviousClips;
    if (_isRecording ||
        _isSubmitting ||
        _isGuidePlaying ||
        _isHandoffPlaying ||
        _countdown != null) {
      return;
    }
    if (!_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    if (!await _ensureRecordingPermissionReady()) return;
    if (previousClips.isEmpty) {
      await _countdownThenStartRecording(
        backingUrl: _recordingBackingUrl,
        primeBacking: hasMrBacking,
        permissionReady: true,
      );
      return;
    }

    final firstHandoffStart = _clipSegmentStartSeconds(previousClips.first);
    final firstHandoffDuration = _handoffStopAfterFor(
      previousClips,
      0,
      alignToBackingTimeline: false,
    );
    setState(() {
      _isHandoffPlaying = true;
      _handoffPlaybackIndex = 0;
      _playbackLyricBaseSeconds = firstHandoffStart;
      _playbackLyricDurationSeconds =
          firstHandoffDuration.inMilliseconds / 1000;
      _playbackElapsedSeconds = 0;
    });
    var handoffCountdownCompleted = false;
    var handoffBackingStarted = false;
    try {
      final backingUrl = _recordingBackingUrl;
      if (hasMrBacking && backingUrl != null) {
        await _startHandoffBacking(
          backingUrl,
          Duration(milliseconds: (firstHandoffStart * 1000).round()),
        );
        handoffBackingStarted = true;
      }
      for (var index = 0; index < previousClips.length; index += 1) {
        if (!mounted) return;
        final clip = previousClips[index];
        final audioUrl = clip['audioUrl']?.toString().trim() ?? '';
        if (audioUrl.isEmpty) continue;
        final segmentStart = (clip['segmentStartSec'] as num?)?.toDouble() ?? 0;
        final duration = hasMrBacking
            ? _handoffTimelineStopAfterFor(previousClips, index)
            : _handoffStopAfterFor(
                previousClips,
                index,
                alignToBackingTimeline: false,
              );
        setState(() => _handoffPlaybackIndex = index + 1);
        final isLastPreviousClip = index == previousClips.length - 1;
        if (hasMrBacking) {
          Future<void>? countdownFuture;
          var cancelCountdown = false;
          if (isLastPreviousClip) {
            countdownFuture = _runCountdownAfter(
              _countdownDelayForHandoff(duration),
              shouldRun: () => !cancelCountdown,
            );
          }
          try {
            await _playAudioAndWait(
              audioUrl,
              stopAfter: duration,
              timeout: duration > Duration.zero
                  ? duration + const Duration(seconds: 3)
                  : const Duration(seconds: 45),
              lyricBaseSeconds: segmentStart,
              waitForStopAfter: true,
            );
            if (countdownFuture != null) {
              await countdownFuture;
            }
          } finally {
            cancelCountdown = true;
          }
        } else {
          await _playHandoffAudioAndWait(
            audioUrl: audioUrl,
            backingUrl: null,
            backingPosition: Duration.zero,
            stopAfter: duration,
            countdownBeforeEnd: isLastPreviousClip,
          );
        }
        if (isLastPreviousClip) handoffCountdownCompleted = true;
      }
    } catch (_) {
      _showMessage('앞 릴레이 녹음을 재생하지 못했어요. 내 녹음으로 넘어갑니다.');
    } finally {
      if (mounted) {
        setState(() {
          _isHandoffPlaying = false;
          _handoffPlaybackIndex = 0;
        });
      }
      if (handoffBackingStarted && !handoffCountdownCompleted) {
        await _stopHandoffBacking();
      }
    }
    if (!mounted) return;
    if (handoffCountdownCompleted) {
      await _startRecordingInternal(
        backingUrl: _recordingBackingUrl,
        continueExistingBacking: hasMrBacking,
        permissionReady: true,
      );
    } else {
      await _countdownThenStartRecording(
        backingUrl: _recordingBackingUrl,
        primeBacking: hasMrBacking,
        permissionReady: true,
      );
    }
  }

  Future<bool> _ensureRecordingPermissionReady() async {
    final hasPermission = await _ensureMicrophonePermission(_recorder);
    if (hasPermission) return true;
    if (widget.ref.read(localPreviewModeProvider)) {
      _addPreviewGeneratedAttempt();
      _showMessage('이 미리보기 브라우저는 마이크가 막혀 있어 테스트용 테이크를 만들었어요.');
      return false;
    }
    _showMessage('마이크 권한을 먼저 허용한 뒤 이어듣기를 시작해주세요.');
    return false;
  }

  double _clipSegmentStartSeconds(Map<String, dynamic> clip) {
    final seconds = (clip['segmentStartSec'] as num?)?.toDouble() ?? 0;
    return seconds < 0 ? 0 : seconds;
  }

  double _clipSegmentEndSeconds(Map<String, dynamic> clip) {
    final seconds = (clip['segmentEndSec'] as num?)?.toDouble() ?? 0;
    return seconds < 0 ? 0 : seconds;
  }

  Duration _durationFromSeconds(double seconds) {
    if (seconds <= 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration _recordedClipDuration(Map<String, dynamic> clip) {
    final seconds = (clip['durationSeconds'] as num?)?.toDouble() ?? 0;
    return _durationFromSeconds(seconds <= 0 ? 0 : seconds + 1);
  }

  Duration _handoffStopAfterFor(
    List<Map<String, dynamic>> clips,
    int index, {
    required bool alignToBackingTimeline,
  }) {
    if (index < 0 || index >= clips.length) return Duration.zero;
    final clip = clips[index];
    final segmentStart = _clipSegmentStartSeconds(clip);
    final segmentEnd = _clipSegmentEndSeconds(clip);
    final segmentDuration = _durationFromSeconds(segmentEnd - segmentStart);
    final recordedDuration = _recordedClipDuration(clip);

    if (alignToBackingTimeline) {
      final nextStart = index + 1 < clips.length
          ? _clipSegmentStartSeconds(clips[index + 1])
          : widget.segmentStartSec;
      final boundary = nextStart > segmentStart
          ? nextStart
          : segmentEnd > segmentStart
          ? segmentEnd
          : 0.0;
      final timelineDuration = _durationFromSeconds(boundary - segmentStart);
      if (timelineDuration > Duration.zero) return timelineDuration;
    }

    if (recordedDuration > Duration.zero && segmentDuration > Duration.zero) {
      return recordedDuration > segmentDuration
          ? recordedDuration
          : segmentDuration;
    }
    if (recordedDuration > Duration.zero) return recordedDuration;
    return segmentDuration;
  }

  Duration _handoffTimelineStopAfterFor(
    List<Map<String, dynamic>> clips,
    int index,
  ) {
    if (index < 0 || index >= clips.length) return Duration.zero;
    final clip = clips[index];
    final segmentStart = _clipSegmentStartSeconds(clip);
    final segmentEnd = _clipSegmentEndSeconds(clip);
    final nextStart = index + 1 < clips.length
        ? _clipSegmentStartSeconds(clips[index + 1])
        : widget.segmentStartSec;
    final boundary = nextStart > segmentStart
        ? nextStart
        : segmentEnd > segmentStart
        ? segmentEnd
        : 0.0;
    final timelineDuration = _durationFromSeconds(boundary - segmentStart);
    if (timelineDuration > Duration.zero) return timelineDuration;
    return _handoffStopAfterFor(clips, index, alignToBackingTimeline: false);
  }

  Future<void> _playHandoffAudioAndWait({
    required String audioUrl,
    required String? backingUrl,
    required Duration backingPosition,
    required Duration stopAfter,
    bool countdownBeforeEnd = false,
    bool keepBackingPlaying = false,
  }) async {
    final timeout = stopAfter > Duration.zero
        ? stopAfter + const Duration(seconds: 3)
        : const Duration(seconds: 45);
    final hasBacking = backingUrl != null && backingUrl.isNotEmpty;
    Future<void>? countdownFuture;
    var cancelCountdown = false;
    var playbackCompleted = false;
    try {
      if (hasBacking) {
        await _startHandoffBacking(backingUrl, backingPosition);
      }
      if (countdownBeforeEnd) {
        countdownFuture = _runCountdownAfter(
          _countdownDelayForHandoff(stopAfter),
          shouldRun: () => !cancelCountdown,
        );
      }
      await _playAudioAndWait(
        audioUrl,
        stopAfter: stopAfter,
        timeout: timeout,
        lyricBaseSeconds: backingPosition.inMilliseconds / 1000,
      );
      if (countdownFuture != null) {
        await countdownFuture;
      }
      playbackCompleted = true;
    } finally {
      if (!playbackCompleted) cancelCountdown = true;
      if (hasBacking && !(keepBackingPlaying && playbackCompleted)) {
        await _stopHandoffBacking();
      } else if (hasBacking) {
        _primedBackingUrl = backingUrl;
      }
    }
  }

  Future<void> _playGuideOnce() async {
    if (widget.guideAudioUrl.isEmpty) return;
    try {
      setState(() => _isGuidePlaying = true);
      await _playGuideAndWait(widget.guideAudioUrl);
    } catch (_) {
      _showMessage('가이드 음원을 재생할 수 없습니다.');
    } finally {
      if (mounted) setState(() => _isGuidePlaying = false);
    }
  }

  Future<void> _playGuideAndWait(String audioUrl) async {
    final segmentDuration = _segmentDuration;
    await _playAudioAndWait(
      audioUrl,
      position: _segmentStart,
      stopAfter: segmentDuration,
      timeout: segmentDuration > Duration.zero
          ? segmentDuration + const Duration(seconds: 3)
          : const Duration(seconds: 45),
    );
  }

  Future<void> _playAudioAndWait(
    String audioUrl, {
    Duration position = Duration.zero,
    Duration stopAfter = Duration.zero,
    Duration timeout = const Duration(seconds: 45),
    double? lyricBaseSeconds,
    bool waitForStopAfter = false,
  }) async {
    final completer = Completer<void>();
    final sub = _guidePlayer.onPlayerComplete.listen((_) {
      if (waitForStopAfter && stopAfter > Duration.zero) return;
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _guidePlayer.stop();
      _segmentStopTimer?.cancel();
      // Buffer the clip first, then resume(), so the karaoke voice starts the
      // instant we begin timing the lyric instead of trailing it by the
      // network/decode delay. Falls back to a direct play if preloading fails.
      var started = false;
      if (position <= Duration.zero) {
        try {
          await _guidePlayer.setSource(_relayAudioSource(audioUrl));
          await _guidePlayer.resume();
          started = true;
        } catch (_) {
          started = false;
        }
      }
      if (!started) {
        await _playRelayAudioSource(_guidePlayer, audioUrl, position: position);
      }
      _startPlaybackTimer(
        lyricBaseSeconds: lyricBaseSeconds ?? position.inMilliseconds / 1000,
        lyricDurationSeconds: stopAfter > Duration.zero
            ? stopAfter.inMilliseconds / 1000
            : _segmentDuration.inMilliseconds / 1000,
      );
      if (stopAfter > Duration.zero) {
        _segmentStopTimer = Timer(stopAfter, () async {
          await _guidePlayer.stop();
          if (!completer.isCompleted) completer.complete();
        });
      }
      await completer.future.timeout(
        timeout,
        onTimeout: () async {
          await _guidePlayer.stop();
        },
      );
    } finally {
      _segmentStopTimer?.cancel();
      _segmentStopTimer = null;
      _stopPlaybackTimer();
      await sub.cancel();
    }
  }

  Future<void> _startRecordingInternal({
    String? backingUrl,
    bool continueExistingBacking = false,
    bool permissionReady = false,
  }) async {
    if (!_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    try {
      final hasBacking = backingUrl != null && backingUrl.isNotEmpty;
      final hasPermission =
          permissionReady || await _ensureMicrophonePermission(_recorder);
      if (!hasPermission) {
        if (widget.ref.read(localPreviewModeProvider)) {
          _addPreviewGeneratedAttempt();
          _showMessage('이 미리보기 브라우저는 마이크가 막혀 있어 테스트용 테이크를 만들었어요.');
          return;
        }
        _showMessage('마이크 권한이 필요합니다.');
        return;
      }
      await _recordingSub?.cancel();
      _recordedBytes.clear();
      _streamRecording = false;
      _contentType = 'audio/webm';
      _audioFileName = 'relay_${DateTime.now().millisecondsSinceEpoch}.webm';
      _playingAttemptNumber = null;
      await _guidePlayer.stop();
      if (!hasBacking) {
        await _backingPlayer.stop();
        relay_backing_audio.stopRelayBackingAudio();
        _primedBackingUrl = null;
      }
      var backingStarted = false;
      if (hasBacking) {
        if (continueExistingBacking && _primedBackingUrl == backingUrl) {
          await _continueRecordingBacking(backingUrl);
          backingStarted = true;
        } else {
          try {
            await _startRecordingBacking(backingUrl);
            backingStarted = true;
          } catch (_) {
            _primedBackingUrl = null;
            unawaited(_backingPlayer.stop());
            _showMessage('MR 반주를 재생하지 못했어요. 녹음은 계속 진행됩니다.');
          }
        }
      }
      if (kIsWeb) {
        final stream = await _recorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: _sampleRate,
            numChannels: _channels,
            echoCancel: true,
            noiseSuppress: false,
            autoGain: false,
          ),
        );
        _streamRecording = true;
        _contentType = 'audio/wav';
        _audioFileName = 'relay_${DateTime.now().millisecondsSinceEpoch}.wav';
        _recordingSub = stream.listen(_recordedBytes.addAll);
      } else {
        try {
          if (!await _recorder.isEncoderSupported(AudioEncoder.opus)) {
            throw StateError('Opus recorder is not supported.');
          }
          await _recorder.start(
            RecordConfig(
              encoder: AudioEncoder.opus,
              bitRate: 128000,
              sampleRate: _sampleRate,
              numChannels: _channels,
              echoCancel: true,
              noiseSuppress: false,
              autoGain: false,
            ),
            path: '',
          );
        } catch (_) {
          final stream = await _recorder.startStream(
            RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: _sampleRate,
              numChannels: _channels,
              echoCancel: true,
              noiseSuppress: false,
              autoGain: false,
            ),
          );
          _streamRecording = true;
          _contentType = 'audio/wav';
          _audioFileName = 'relay_${DateTime.now().millisecondsSinceEpoch}.wav';
          _recordingSub = stream.listen(_recordedBytes.addAll);
        }
      }
      final nextAttemptCount = _recordAttemptCount + 1;
      if (!mounted) {
        await _recorder.stop();
        if (backingStarted) {
          await _backingPlayer.stop();
          relay_backing_audio.stopRelayBackingAudio();
        }
        return;
      }
      _startRecordingTicker();
      setState(() {
        _recordAttemptCount = nextAttemptCount;
        _isRecording = true;
        _isMrRecording = hasBacking;
      });
      unawaited(HapticFeedback.mediumImpact());
    } catch (_) {
      unawaited(_forgetMicrophonePermissionIfRevoked());
      unawaited(_backingPlayer.stop());
      relay_backing_audio.stopRelayBackingAudio();
      _primedBackingUrl = null;
      _stopRecordingTicker();
      if (widget.ref.read(localPreviewModeProvider)) {
        _addPreviewGeneratedAttempt();
        _showMessage('이 미리보기 브라우저는 마이크가 막혀 있어 테스트용 테이크를 만들었어요.');
        return;
      }
      _showMessage('녹음을 시작할 수 없습니다. 마이크 권한을 확인해주세요.');
    }
  }

  Future<void> _continueRecordingBacking(String backingUrl) async {
    _scheduleRecordingSegmentStop();
    if (!kIsWeb) {
      await _backingPlayer.setReleaseMode(ReleaseMode.stop);
      await _backingPlayer.setVolume(1);
    }
    _primedBackingUrl = backingUrl;
  }

  Future<void> _startHandoffBacking(
    String backingUrl,
    Duration position,
  ) async {
    try {
      if (kIsWeb &&
          relay_backing_audio.startRelayBackingAudio(backingUrl, position)) {
        _primedBackingUrl = backingUrl;
        return;
      }
    } catch (_) {
      _primedBackingUrl = null;
    }

    await _backingPlayer.stop();
    await _backingPlayer.setReleaseMode(ReleaseMode.stop);
    await _backingPlayer.setVolume(0.82);
    unawaited(
      _backingPlayer
          .play(UrlSource(backingUrl), position: position)
          .catchError((_) {}),
    );
    _primedBackingUrl = backingUrl;
  }

  Future<void> _stopHandoffBacking() async {
    relay_backing_audio.stopRelayBackingAudio();
    await _backingPlayer.stop();
    _primedBackingUrl = null;
  }

  Future<void> _startRecordingBacking(String backingUrl) async {
    _scheduleRecordingSegmentStop();
    if (kIsWeb &&
        relay_backing_audio.startRelayBackingAudio(backingUrl, _segmentStart)) {
      _primedBackingUrl = backingUrl;
      return;
    }
    await _backingPlayer.setReleaseMode(ReleaseMode.stop);
    await _backingPlayer.setVolume(1);
    if (_primedBackingUrl == backingUrl) {
      await _backingPlayer.seek(_segmentStart);
      await _backingPlayer.resume();
    } else {
      await _backingPlayer.stop();
      unawaited(
        _backingPlayer
            .play(UrlSource(backingUrl), position: _segmentStart)
            .catchError((_) {}),
      );
      _primedBackingUrl = backingUrl;
    }
  }

  void _scheduleRecordingSegmentStop() {
    final segmentDuration = _segmentDuration;
    _segmentStopTimer?.cancel();
    if (segmentDuration > Duration.zero) {
      _segmentStopTimer = Timer(segmentDuration, () {
        unawaited(_stopRecording());
      });
    }
  }

  Future<void> _primeRecordingBacking(String backingUrl) async {
    try {
      if (kIsWeb &&
          relay_backing_audio.primeRelayBackingAudio(
            backingUrl,
            _segmentStart,
          )) {
        _primedBackingUrl = backingUrl;
        return;
      }
      if (_primedBackingUrl != backingUrl) {
        await _backingPlayer.stop();
        await _backingPlayer.setReleaseMode(ReleaseMode.loop);
        await _backingPlayer.setVolume(0);
        unawaited(
          _backingPlayer
              .play(UrlSource(backingUrl), position: _segmentStart)
              .catchError((_) {}),
        );
        _primedBackingUrl = backingUrl;
        return;
      }
      await _backingPlayer.setVolume(0);
      await _backingPlayer.seek(_segmentStart);
    } catch (_) {
      await _backingPlayer.setVolume(1);
      _primedBackingUrl = null;
    }
  }

  void _addPreviewGeneratedAttempt({int? number}) {
    if (number == null && !_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    final attemptNumber = number ?? _recordAttemptCount + 1;
    const durationSeconds = 3;
    final attempt = _RelayRecordingAttempt(
      number: attemptNumber,
      bytes: _previewAttemptToneBytes(durationSeconds),
      fileName: 'relay_${DateTime.now().millisecondsSinceEpoch}.wav',
      contentType: 'audio/wav',
      durationSeconds: durationSeconds,
    );
    setState(() {
      _isRecording = false;
      _isMrRecording = false;
      _recordAttemptCount = attemptNumber;
      _recordSeconds = durationSeconds;
      _recordElapsedSeconds = durationSeconds.toDouble();
      _attempts.removeWhere((item) => item.number == attempt.number);
      _attempts.add(attempt);
      _selectedAttemptNumber = attempt.number;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      _segmentStopTimer?.cancel();
      _segmentStopTimer = null;
      await _guidePlayer.stop();
      await _backingPlayer.stop();
      relay_backing_audio.stopRelayBackingAudio();
      _primedBackingUrl = null;
      _stopPlaybackTimer();
      _stopRecordingTicker();
      final stoppedPath = await _recorder.stop();
      final recordedPath = _streamRecording ? null : stoppedPath;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _recordingSub?.cancel();
      _recordingSub = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final attemptNumber = _recordAttemptCount;
      final durationSeconds = math.max(1, _recordElapsedSeconds.ceil());
      final fileName = _audioFileName;
      final contentType = _contentType;
      Uint8List recorded;
      if (recordedPath != null && recordedPath.isNotEmpty) {
        recorded = await _bytesFromRecordedPath(recordedPath);
      } else {
        final pcmBytes = Uint8List.fromList(_recordedBytes);
        recorded = pcmBytes.isEmpty
            ? Uint8List(0)
            : _wavFromPcmBytes(
                pcmBytes,
                sampleRate: _sampleRate,
                channels: _channels,
              );
      }
      if (recorded.isEmpty) {
        if (widget.ref.read(localPreviewModeProvider)) {
          _addPreviewGeneratedAttempt(number: attemptNumber);
          _showMessage('이 미리보기 브라우저는 실제 음성이 들어오지 않아 테스트용 테이크를 만들었어요.');
          return;
        }
        setState(() {
          _isRecording = false;
          _isMrRecording = false;
          _recordAttemptCount = (_recordAttemptCount - 1)
              .clamp(0, _maxRecordAttempts)
              .toInt();
        });
        _showMessage('녹음된 소리가 없습니다. 다시 시도해주세요.');
        return;
      }
      final attempt = _RelayRecordingAttempt(
        number: attemptNumber,
        bytes: recorded,
        fileName: fileName,
        contentType: contentType,
        durationSeconds: durationSeconds,
      );
      setState(() {
        _isRecording = false;
        _isMrRecording = false;
        _recordElapsedSeconds = durationSeconds.toDouble();
        _attempts.removeWhere((item) => item.number == attempt.number);
        _attempts.add(attempt);
        _selectedAttemptNumber = attempt.number;
      });
    } catch (_) {
      setState(() {
        _isRecording = false;
        _isMrRecording = false;
        _recordAttemptCount = (_recordAttemptCount - 1)
            .clamp(0, _maxRecordAttempts)
            .toInt();
      });
      unawaited(_backingPlayer.stop());
      relay_backing_audio.stopRelayBackingAudio();
      _primedBackingUrl = null;
      _stopRecordingTicker();
      _showMessage('녹음을 마무리하지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _submit() async {
    if (_isRecording) await _stopRecording();
    final attempt = _selectedAttempt;
    if (attempt == null) {
      _showMessage(_hasAttemptsLeft ? '먼저 소절을 녹음해주세요.' : '3번의 기회를 모두 사용했어요.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _progress = 0;
      _submitError = '';
    });
    try {
      final fileName = attempt.fileName.isEmpty
          ? 'relay_${DateTime.now().millisecondsSinceEpoch}.webm'
          : attempt.fileName;
      if (widget.ref.read(localPreviewModeProvider)) {
        _completePreviewRelayAttempt(attempt, fileName);
        widget.ref.read(_lastSubmittedHarmonyRelayProvider.notifier).state =
            widget.relayId;
        await Future<void>.delayed(const Duration(milliseconds: 450));
        _refreshHarmonyRelays();
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text('${attempt.number}번 테이크를 올렸어요. 하모니맵에 표시했어요.'),
            ),
          );
        }
        return;
      }
      final audioUrl = await FirebaseService.uploadHarmonyAudio(
        attempt.bytes,
        fileName: fileName,
        contentType: attempt.contentType,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await FirebaseService.addHarmonyRelayClip(
        relayId: widget.relayId,
        part: widget.part,
        audioUrl: audioUrl,
        audioFileName: fileName,
        durationSeconds: attempt.durationSeconds,
      );
      widget.ref.read(_lastSubmittedHarmonyRelayProvider.notifier).state =
          widget.relayId;
      _refreshHarmonyRelays();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(content: Text('${attempt.number}번 테이크를 올렸어요. 하모니맵에 표시했어요.')),
        );
      }
    } catch (error) {
      _refreshHarmonyRelays();
      final message = _friendlySubmitError(error);
      if (mounted) setState(() => _submitError = message);
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _progress = 0;
        });
      }
    }
  }

  void _refreshHarmonyRelays() {
    widget.ref.invalidate(harmonyRelaysProvider);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 900)).then((_) {
        widget.ref.invalidate(harmonyRelaysProvider);
      }),
    );
  }

  String _friendlySubmitError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    if (raw.contains('firebase_storage/unauthorized')) {
      return '녹음 파일 업로드 권한이 막혀 있어요. 교회 승인 상태와 Firebase Storage 규칙 배포를 확인해주세요.';
    }
    return raw;
  }

  void _completePreviewRelayAttempt(
    _RelayRecordingAttempt attempt,
    String fileName,
  ) {
    final profile = widget.ref.read(profileProvider).valueOrNull;
    final userId = profile?.id ?? FirebaseService.uid ?? 'preview-user';
    final userName = _firstText([profile?.name, profile?.displayName, '파트원']);
    final now = DateTime.now().toIso8601String();
    final audioUrl =
        'data:${attempt.contentType};base64,${base64Encode(attempt.bytes)}';
    final clip = {
      'id': 'preview-clip-${DateTime.now().microsecondsSinceEpoch}',
      'userId': userId,
      'userName': userName,
      'userPart': widget.part,
      'audioUrl': audioUrl,
      'audioFileName': fileName,
      'durationSeconds': attempt.durationSeconds,
      'autoScore': 88,
      'autoFeedback': '미리보기 녹음이 연결됐어요. 다음 소절로 넘길 수 있습니다.',
      'createdAt': now,
    };

    widget.ref.read(previewHarmonyRelaysProvider.notifier).update((relays) {
      final nextRelays = relays.map((relay) {
        return {
          ...relay,
          'lyricsTimeline': ((relay['lyricsTimeline'] as List?) ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
          'clips': ((relay['clips'] as List?) ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(),
        };
      }).toList();
      final currentIndex = nextRelays.indexWhere(
        (relay) => relay['id']?.toString() == widget.relayId,
      );
      if (currentIndex < 0) return nextRelays;

      final current = nextRelays[currentIndex];
      final clips = ((current['clips'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      clips.add(clip);
      current
        ..['clips'] = clips
        ..['clipCount'] = clips.length
        ..['status'] = 'completed'
        ..['completedBy'] = userId
        ..['completedByName'] = userName
        ..['completedAt'] = now
        ..['lastClipAt'] = now
        ..['updatedAt'] = now;

      final missionGroupId = current['missionGroupId']?.toString() ?? '';
      if (missionGroupId.isEmpty) {
        final previousAssigneeId =
            current['currentAssigneeId']?.toString() ?? '';
        final nextAssignee = _previewNextAssignee(
          widget.part,
          excludedUserIds: {
            userId,
            if (previousAssigneeId.isNotEmpty) previousAssigneeId,
          },
        );
        current
          ..['currentAssigneeId'] = nextAssignee.id
          ..['currentAssigneeName'] = nextAssignee.name
          ..['assignedAt'] = now;
        return nextRelays;
      }

      final missionIndexes =
          nextRelays
              .asMap()
              .entries
              .where(
                (entry) =>
                    entry.value['missionGroupId']?.toString() == missionGroupId,
              )
              .toList()
            ..sort((a, b) {
              final aOrder = (a.value['segmentOrder'] as num?)?.toInt() ?? 0;
              final bOrder = (b.value['segmentOrder'] as num?)?.toInt() ?? 0;
              return aOrder.compareTo(bOrder);
            });
      final sortedCurrentIndex = missionIndexes.indexWhere(
        (entry) => entry.key == currentIndex,
      );
      if (sortedCurrentIndex < 0) return nextRelays;
      final recordedUserIds = <String>{userId};
      final previousAssigneeId = current['currentAssigneeId']?.toString() ?? '';
      if (previousAssigneeId.isNotEmpty) {
        recordedUserIds.add(previousAssigneeId);
      }
      for (final entry in missionIndexes.take(sortedCurrentIndex + 1)) {
        final completedBy = entry.value['completedBy']?.toString() ?? '';
        if (completedBy.isNotEmpty) recordedUserIds.add(completedBy);
      }
      for (var i = sortedCurrentIndex + 1; i < missionIndexes.length; i += 1) {
        final relay = nextRelays[missionIndexes[i].key];
        if (_relayCompleted(relay)) continue;
        final existingAssignee = relay['currentAssigneeId']?.toString() ?? '';
        if (existingAssignee.isEmpty) {
          final nextAssignee = _previewNextAssignee(
            widget.part,
            excludedUserIds: recordedUserIds,
          );
          relay
            ..['currentAssigneeId'] = nextAssignee.id
            ..['currentAssigneeName'] = nextAssignee.name
            ..['assignedAt'] = now
            ..['updatedAt'] = now;
        }
        break;
      }
      return nextRelays;
    });
  }

  Future<void> _toggleAttemptPlayback(_RelayRecordingAttempt attempt) async {
    if (_isRecording ||
        _isSubmitting ||
        _isGuidePlaying ||
        _countdown != null) {
      return;
    }
    try {
      if (_playingAttemptNumber == attempt.number) {
        await _guidePlayer.stop();
        if (mounted) setState(() => _playingAttemptNumber = null);
        return;
      }
      await _guidePlayer.stop();
      setState(() => _playingAttemptNumber = attempt.number);
      await _guidePlayer.play(
        BytesSource(attempt.bytes, mimeType: attempt.contentType),
      );
    } catch (_) {
      if (mounted) setState(() => _playingAttemptNumber = null);
      _showMessage('녹음 후보를 재생할 수 없습니다.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic>? get _activeHandoffClip {
    if (!_isHandoffPlaying) return null;
    final clips = _playablePreviousClips;
    if (clips.isEmpty) return null;
    final rawIndex = _handoffPlaybackIndex <= 0 ? 0 : _handoffPlaybackIndex - 1;
    final index = rawIndex.clamp(0, clips.length - 1).toInt();
    return clips[index];
  }

  int get _activeHandoffClipIndex {
    final clips = _playablePreviousClips;
    if (!_isHandoffPlaying || clips.isEmpty) return -1;
    final rawIndex = _handoffPlaybackIndex <= 0 ? 0 : _handoffPlaybackIndex - 1;
    return rawIndex.clamp(0, clips.length - 1).toInt();
  }

  String get _activeLyricSegmentLabel {
    final handoffClip = _activeHandoffClip;
    final handoffLabel = _cleanDisplayText(
      handoffClip?['segmentLabel']?.toString() ?? '',
    );
    if (handoffLabel.isNotEmpty) return handoffLabel;
    return widget.segmentLabel;
  }

  String get _handoffCurrentLyricLine {
    final clip = _activeHandoffClip;
    if (clip == null) return '';
    return _firstText([
      clip['lyricsLine']?.toString(),
      _lyricFromSegmentLabel(clip['segmentLabel']?.toString() ?? ''),
    ]);
  }

  String get _handoffNextLyricLine {
    final clip = _activeHandoffClip;
    if (clip == null) return '';
    final direct = _cleanDisplayText(clip['nextLyricsLine']?.toString() ?? '');
    if (direct.isNotEmpty) return direct;
    final clips = _playablePreviousClips;
    final index = _activeHandoffClipIndex;
    if (index >= 0 && index + 1 < clips.length) {
      return _firstText([
        clips[index + 1]['lyricsLine']?.toString(),
        _lyricFromSegmentLabel(
          clips[index + 1]['segmentLabel']?.toString() ?? '',
        ),
      ]);
    }
    return _cleanDisplayText(widget.lyricsLine);
  }

  String _lyricFromSegmentLabel(String label) {
    final cleaned = _cleanDisplayText(label);
    if (cleaned.isEmpty) return '';
    final parts = cleaned.split('·');
    if (parts.length <= 1) return '';
    return _cleanDisplayText(parts.sublist(1).join('·'));
  }

  String get _currentLyricLine {
    if (_isHandoffPlaying) {
      final timelineLine = _timelineLyricAt(
        _absoluteLyricSeconds,
        timeline: _activeHandoffLyricsTimeline,
      );
      if (timelineLine.isNotEmpty) return timelineLine;
      final handoffLine = _handoffCurrentLyricLine;
      if (handoffLine.isNotEmpty) return handoffLine;
    }
    final timelineLine = _timelineLyricAt(_absoluteLyricSeconds);
    if (timelineLine.isNotEmpty) return timelineLine;
    final direct = _cleanDisplayText(widget.lyricsLine);
    if (direct.isNotEmpty) return direct;
    final parsed = _lyricsFromText;
    if (parsed.isNotEmpty) return parsed.first;
    return _cleanDisplayText(widget.segmentLabel);
  }

  String get _nextLyricLine {
    if (_isHandoffPlaying) {
      final timelineNext = _nextTimelineLyricAfter(
        _absoluteLyricSeconds,
        timeline: _activeHandoffLyricsTimeline,
      );
      if (timelineNext.isNotEmpty) return timelineNext;
      final handoffLine = _handoffNextLyricLine;
      if (handoffLine.isNotEmpty) return handoffLine;
    }
    final timelineNext = _nextTimelineLyricAfter(_absoluteLyricSeconds);
    if (timelineNext.isNotEmpty) return timelineNext;
    final direct = _cleanDisplayText(widget.nextLyricsLine);
    if (direct.isNotEmpty) return direct;
    final parsed = _lyricsFromText;
    if (parsed.length > 1) return parsed[1];
    return '';
  }

  List<String> get _lyricsFromText {
    return widget.lyricsText
        .split(RegExp(r'\r?\n'))
        .map((line) => _cleanDisplayText(line))
        .where((line) => line.isNotEmpty)
        .toList();
  }

  double get _lyricProgress {
    final duration = _isRecording
        ? _segmentDuration.inMilliseconds / 1000
        : _playbackLyricDurationSeconds;
    if (duration <= 0) {
      if (_isRecording || _isGuidePlaying) return 0.35;
      return 0;
    }
    final elapsed = _isRecording
        ? _recordElapsedSeconds
        : _playbackElapsedSeconds;
    return (elapsed / duration).clamp(0, 1).toDouble();
  }

  double get _absoluteLyricSeconds {
    if (_isRecording) {
      return widget.segmentStartSec + _recordElapsedSeconds;
    }
    return _playbackLyricBaseSeconds + _playbackElapsedSeconds;
  }

  List<Map<String, dynamic>> get _activeHandoffLyricsTimeline {
    final clip = _activeHandoffClip;
    if (clip == null) return const [];
    return _lyricsTimelineFromValue(clip['lyricsTimeline']);
  }

  String _timelineLyricAt(
    double seconds, {
    List<Map<String, dynamic>>? timeline,
  }) {
    final activeTimeline = timeline ?? widget.lyricsTimeline;
    if (activeTimeline.isEmpty) return '';
    Map<String, dynamic>? selected;
    for (final entry in activeTimeline) {
      final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
      if (time > seconds) break;
      selected = entry;
    }
    return _cleanDisplayText(selected?['text']?.toString() ?? '');
  }

  String _nextTimelineLyricAfter(
    double seconds, {
    List<Map<String, dynamic>>? timeline,
  }) {
    final activeTimeline = timeline ?? widget.lyricsTimeline;
    for (final entry in activeTimeline) {
      final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
      final text = _cleanDisplayText(entry['text']?.toString() ?? '');
      if (time > seconds && text.isNotEmpty) return text;
    }
    return '';
  }

  void _startPlaybackTimer({
    required double lyricBaseSeconds,
    required double lyricDurationSeconds,
  }) {
    _playbackTimer?.cancel();
    _playbackStopwatch
      ..reset()
      ..start();
    if (mounted) {
      setState(() {
        _playbackLyricBaseSeconds = lyricBaseSeconds;
        _playbackLyricDurationSeconds = lyricDurationSeconds;
        _playbackElapsedSeconds = 0;
      });
    }
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      var elapsed = _playbackStopwatch.elapsedMilliseconds / 1000;
      // Prefer the MR element's real clock so the karaoke line tracks the audio
      // the listener actually hears, not a timer that started before playback.
      if (kIsWeb && relay_backing_audio.relayBackingAudioPlaying()) {
        final backingSeconds = relay_backing_audio.relayBackingAudioSeconds();
        if (backingSeconds >= 0) {
          final fromBacking = backingSeconds - _playbackLyricBaseSeconds;
          if (fromBacking >= 0) elapsed = fromBacking;
        }
      }
      setState(() {
        _playbackElapsedSeconds = elapsed;
      });
    });
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStopwatch.stop();
  }

  void _startRecordingTicker() {
    _recordingTimer?.cancel();
    _recordingStopwatch
      ..reset()
      ..start();
    _lastWaveformByteCount = _recordedBytes.length;
    _waveformLevels = List<double>.filled(28, 0.08);
    _playbackLyricBaseSeconds = widget.segmentStartSec;
    _playbackLyricDurationSeconds = _segmentDuration.inMilliseconds / 1000;
    _recordElapsedSeconds = 0;
    _recordSeconds = 0;
    _playbackElapsedSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      final elapsed = _recordingStopwatch.elapsedMilliseconds / 1000;
      setState(() {
        _recordElapsedSeconds = elapsed;
        _recordSeconds = elapsed.floor();
        _pushWaveformLevel(_nextWaveformLevel());
      });
    });
  }

  void _stopRecordingTicker() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStopwatch.stop();
  }

  void _pushWaveformLevel(double level) {
    final clamped = level.clamp(0.06, 1).toDouble();
    _waveformLevels = [..._waveformLevels.skip(1), clamped];
  }

  double _nextWaveformLevel() {
    final length = _recordedBytes.length;
    if (length - _lastWaveformByteCount >= 4) {
      final start = math.max(_lastWaveformByteCount, length - 4096);
      var sum = 0.0;
      var count = 0;
      for (var index = start; index + 1 < length; index += 2) {
        final low = _recordedBytes[index];
        final high = _recordedBytes[index + 1];
        var sample = (high << 8) | low;
        if (sample >= 0x8000) sample -= 0x10000;
        final normalized = sample / 32768.0;
        sum += normalized * normalized;
        count += 1;
      }
      _lastWaveformByteCount = length;
      if (count > 0) {
        final rms = math.sqrt(sum / count);
        return (rms * 7).clamp(0.08, 1).toDouble();
      }
    }
    final tick = _recordingStopwatch.elapsedMilliseconds / 1000;
    return 0.12 + (math.sin(tick * 7) + 1) * 0.08;
  }
}

class _KaraokeLyricsPanel extends StatelessWidget {
  const _KaraokeLyricsPanel({
    required this.title,
    required this.currentLine,
    required this.nextLine,
    required this.segmentLabel,
    required this.progress,
    required this.isActive,
    required this.statusText,
  });

  final String title;
  final String currentLine;
  final String nextLine;
  final String segmentLabel;
  final double progress;
  final bool isActive;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final safeTitle = _cleanDisplayText(title);
    final safeCurrentLine = _cleanDisplayText(currentLine);
    final safeNextLine = _cleanDisplayText(nextLine);
    final safeSegmentLabel = _cleanDisplayText(segmentLabel);
    final showTitleBeforePlayback = !isActive && safeTitle.isNotEmpty;
    final mainLine = showTitleBeforePlayback ? safeTitle : safeCurrentLine;
    final fallbackNextLine = '다음 소절을 이어 받을 준비를 해요';
    final supportingLine =
        showTitleBeforePlayback &&
            safeCurrentLine.isNotEmpty &&
            safeCurrentLine != safeTitle
        ? safeCurrentLine
        : safeNextLine.isEmpty
        ? fallbackNextLine
        : safeNextLine;
    final supportingLineIsFallback = supportingLine == fallbackNextLine;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.secondaryContainer.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    isActive
                        ? const _InlineWaveIcon(
                            size: 14,
                            color: AppColors.primary,
                          )
                        : const _InlineMusicNoteIcon(
                            size: 14,
                            color: AppColors.primary,
                          ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: AppText.body(
                        11,
                        weight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  safeSegmentLabel,
                  softWrap: true,
                  textAlign: TextAlign.end,
                  style: AppText.body(
                    11,
                    weight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.62),
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0, 0.18),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: _LyricDisplayText(
              text: mainLine,
              key: ValueKey('current-$mainLine'),
              style: AppText.body(
                24,
                weight: FontWeight.w900,
                color: AppColors.secondaryContainer,
                height: 1.16,
              ),
              minHeight: 32,
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: _LyricDisplayText(
              text: supportingLine,
              key: ValueKey('next-$supportingLine'),
              style: AppText.body(
                14,
                weight: FontWeight.w700,
                color: Colors.white.withValues(
                  alpha: supportingLineIsFallback ? 0.36 : 0.52,
                ),
                height: 1.28,
              ),
              minHeight: 20,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              color: AppColors.secondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricDisplayText extends StatelessWidget {
  const _LyricDisplayText({
    super.key,
    required this.text,
    required this.style,
    required this.minHeight,
  });

  final String text;
  final TextStyle style;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSize = style.fontSize ?? 14;
        final direction = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 2,
          textDirection: direction,
        )..layout(maxWidth: constraints.maxWidth);
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : painter.width;
        final lineWidth = painter.width;
        final scale = lineWidth <= 0 || availableWidth <= 0
            ? 1.0
            : math.min(1.0, availableWidth / lineWidth);
        final nextStyle = style.copyWith(
          fontSize: math.max(11, baseSize * scale),
        );

        return SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(text, softWrap: true, style: nextStyle),
            ),
          ),
        );
      },
    );
  }
}

class _RelayStudioStateIcon extends StatelessWidget {
  const _RelayStudioStateIcon({
    required this.countdown,
    required this.isRecording,
  });

  final int? countdown;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    if (countdown != null) {
      return const _InlineTimerIcon(size: 38, color: AppColors.secondary);
    }
    if (isRecording) {
      return const _InlineStopCircleIcon(size: 38, color: AppColors.secondary);
    }
    return const _InlineMicIcon(size: 38, color: AppColors.primary);
  }
}

class _InlineRouteIcon extends StatelessWidget {
  const _InlineRouteIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineRoutePainter(resolvedColor)),
    );
  }
}

class _InlineRoutePainter extends CustomPainter {
  const _InlineRoutePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.24, h * 0.25), w * 0.12, stroke);
    canvas.drawCircle(Offset(w * 0.76, h * 0.75), w * 0.12, stroke);
    final path = Path()
      ..moveTo(w * 0.30, h * 0.31)
      ..cubicTo(w * 0.78, h * 0.28, w * 0.22, h * 0.70, w * 0.70, h * 0.70);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(w * 0.50, h * 0.50), w * 0.055, fill);
  }

  @override
  bool shouldRepaint(covariant _InlineRoutePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineAwardIcon extends StatelessWidget {
  const _InlineAwardIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.secondary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineAwardPainter(resolvedColor)),
    );
  }
}

class _InlineAwardPainter extends CustomPainter {
  const _InlineAwardPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.5, h * 0.35), w * 0.25, stroke);
    final star = Path()
      ..moveTo(w * 0.5, h * 0.22)
      ..lineTo(w * 0.55, h * 0.33)
      ..lineTo(w * 0.67, h * 0.34)
      ..lineTo(w * 0.58, h * 0.42)
      ..lineTo(w * 0.61, h * 0.54)
      ..lineTo(w * 0.5, h * 0.48)
      ..lineTo(w * 0.39, h * 0.54)
      ..lineTo(w * 0.42, h * 0.42)
      ..lineTo(w * 0.33, h * 0.34)
      ..lineTo(w * 0.45, h * 0.33)
      ..close();
    canvas.drawPath(star, fill);
    canvas.drawLine(
      Offset(w * 0.38, h * 0.58),
      Offset(w * 0.28, h * 0.86),
      stroke,
    );
    canvas.drawLine(
      Offset(w * 0.62, h * 0.58),
      Offset(w * 0.72, h * 0.86),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _InlineAwardPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineHarmonyMapIcon extends StatelessWidget {
  const _InlineHarmonyMapIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineHarmonyMapPainter(resolvedColor)),
    );
  }
}

class _InlineHarmonyMapPainter extends CustomPainter {
  const _InlineHarmonyMapPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final nodes = [
      Offset(w * 0.25, h * 0.30),
      Offset(w * 0.68, h * 0.30),
      Offset(w * 0.68, h * 0.72),
    ];
    canvas.drawLine(nodes[0], nodes[1], stroke);
    canvas.drawLine(nodes[1], nodes[2], stroke);
    for (final node in nodes) {
      canvas.drawCircle(node, w * 0.105, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _InlineHarmonyMapPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RelayStackIcon extends StatelessWidget {
  const _RelayStackIcon({this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _RelayStackPainter(resolvedColor)),
    );
  }
}

class _RelayStackPainter extends CustomPainter {
  const _RelayStackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.16, w * 0.44, h * 0.52),
        Radius.circular(w * 0.08),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.38, h * 0.32, w * 0.44, h * 0.52),
        Radius.circular(w * 0.08),
      ),
      stroke,
    );
    canvas.drawCircle(Offset(w * 0.42, h * 0.42), w * 0.055, fill);
    canvas.drawLine(
      Offset(w * 0.48, h * 0.42),
      Offset(w * 0.66, h * 0.42),
      stroke,
    );
    canvas.drawCircle(Offset(w * 0.58, h * 0.58), w * 0.055, fill);
    canvas.drawLine(
      Offset(w * 0.64, h * 0.58),
      Offset(w * 0.72, h * 0.58),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RelayStackPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineChevronRightIcon extends StatelessWidget {
  const _InlineChevronRightIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineChevronRightPainter(resolvedColor)),
    );
  }
}

class _InlineChevronRightPainter extends CustomPainter {
  const _InlineChevronRightPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.36, size.height * 0.24)
      ..lineTo(size.width * 0.64, size.height * 0.5)
      ..lineTo(size.width * 0.36, size.height * 0.76);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InlineChevronRightPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineCloseIcon extends StatelessWidget {
  const _InlineCloseIcon({this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineClosePainter(resolvedColor)),
    );
  }
}

class _InlineClosePainter extends CustomPainter {
  const _InlineClosePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.22, size.height * 0.22),
      Offset(size.width * 0.78, size.height * 0.78),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.78, size.height * 0.22),
      Offset(size.width * 0.22, size.height * 0.78),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _InlineClosePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlinePlayIcon extends StatelessWidget {
  const _InlinePlayIcon({this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlinePlayPainter(resolvedColor)),
    );
  }
}

class _InlinePlayPainter extends CustomPainter {
  const _InlinePlayPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.32, size.height * 0.22)
      ..lineTo(size.width * 0.32, size.height * 0.78)
      ..lineTo(size.width * 0.78, size.height * 0.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _InlinePlayPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineCheckIcon extends StatelessWidget {
  const _InlineCheckIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineCheckPainter(resolvedColor)),
    );
  }
}

class _InlineCheckPainter extends CustomPainter {
  const _InlineCheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.28);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InlineCheckPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineInfoIcon extends StatelessWidget {
  const _InlineInfoIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineInfoPainter(resolvedColor)),
    );
  }
}

class _InlineInfoPainter extends CustomPainter {
  const _InlineInfoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: size.height * 0.62,
      fontWeight: FontWeight.w900,
      height: 1,
    );
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.5, fill);
    final painter = TextPainter(
      text: TextSpan(text: 'i', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _InlineInfoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineMusicNoteIcon extends StatelessWidget {
  const _InlineMusicNoteIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineMusicNotePainter(resolvedColor)),
    );
  }
}

class _InlineMusicNotePainter extends CustomPainter {
  const _InlineMusicNotePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * 0.26),
      Offset(size.width * 0.34, size.height * 0.72),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * 0.26),
      Offset(size.width * 0.72, size.height * 0.18),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.72, size.height * 0.18),
      Offset(size.width * 0.72, size.height * 0.62),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.74),
      size.width * 0.13,
      fill,
    );
    canvas.drawCircle(
      Offset(size.width * 0.63, size.height * 0.64),
      size.width * 0.13,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _InlineMusicNotePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineTimerIcon extends StatelessWidget {
  const _InlineTimerIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineTimerPainter(resolvedColor)),
    );
  }
}

class _InlineTimerPainter extends CustomPainter {
  const _InlineTimerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height * 0.56);
    final radius = size.width * 0.32;
    canvas.drawCircle(center, radius, stroke);
    canvas.drawLine(
      Offset(size.width * 0.4, size.height * 0.12),
      Offset(size.width * 0.6, size.height * 0.12),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.12),
      Offset(size.width / 2, size.height * 0.22),
      stroke,
    );
    canvas.drawLine(
      center,
      Offset(size.width * 0.62, size.height * 0.42),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _InlineTimerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineStopCircleIcon extends StatelessWidget {
  const _InlineStopCircleIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineStopCirclePainter(resolvedColor)),
    );
  }
}

class _InlineStopCirclePainter extends CustomPainter {
  const _InlineStopCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09;
    final fill = Paint()..color = color;
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.42, stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: size.center(Offset.zero),
          width: size.width * 0.34,
          height: size.height * 0.34,
        ),
        Radius.circular(size.width * 0.06),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _InlineStopCirclePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InlineWaveIcon extends StatelessWidget {
  const _InlineWaveIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    final widths = size / 7.8;
    final heights = [0.38, 0.72, 0.48, 0.88, 0.58];

    return SizedBox(
      width: size,
      height: size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: heights
            .map((factor) {
              return Container(
                width: widths,
                height: size * factor,
                margin: EdgeInsets.symmetric(horizontal: size / 38),
                decoration: BoxDecoration(
                  color: resolvedColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _InlineMicIcon extends StatelessWidget {
  const _InlineMicIcon({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? AppColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InlineMicPainter(resolvedColor)),
    );
  }
}

class _InlineMicPainter extends CustomPainter {
  const _InlineMicPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.38),
        width: size.width * 0.38,
        height: size.height * 0.54,
      ),
      Radius.circular(size.width * 0.19),
    );
    canvas.drawRRect(body, fill);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.48),
        width: size.width * 0.74,
        height: size.height * 0.68,
      ),
      0.18,
      math.pi - 0.36,
      false,
      stroke,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.75),
      Offset(size.width / 2, size.height * 0.9),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * 0.9),
      Offset(size.width * 0.66, size.height * 0.9),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _InlineMicPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RecordingWaveform extends StatelessWidget {
  const _RecordingWaveform({
    required this.levels,
    required this.active,
    required this.label,
  });

  final List<double> levels;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          _InlineWaveIcon(
            size: 18,
            color: active ? AppColors.secondary : AppColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: levels.map((level) {
                  final height = 6 + (level * 28);
                  return Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 90),
                        margin: const EdgeInsets.symmetric(horizontal: 1.2),
                        height: height,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(
                            alpha: active ? 0.82 : 0.24,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppText.body(
              11,
              weight: FontWeight.w900,
              color: active ? AppColors.secondary : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayRecordingAttemptsPanel extends StatelessWidget {
  const _RelayRecordingAttemptsPanel({
    required this.attempts,
    required this.selectedNumber,
    required this.playingNumber,
    required this.isBusy,
    required this.onSelect,
    required this.onPlay,
  });

  final List<_RelayRecordingAttempt> attempts;
  final int? selectedNumber;
  final int? playingNumber;
  final bool isBusy;
  final ValueChanged<int> onSelect;
  final ValueChanged<_RelayRecordingAttempt> onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '녹음 후보',
                  style: AppText.body(14, weight: FontWeight.w900),
                ),
              ),
              Text(
                '${attempts.length}/3',
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '듣기 버튼으로 확인하고, 올릴 테이크를 선택해주세요.',
            style: AppText.body(12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          ...attempts.map(
            (attempt) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RelayRecordingAttemptTile(
                attempt: attempt,
                isSelected: attempt.number == selectedNumber,
                isPlaying: attempt.number == playingNumber,
                isBusy: isBusy,
                onSelect: () => onSelect(attempt.number),
                onPlay: () => onPlay(attempt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayRecordingAttemptTile extends StatelessWidget {
  const _RelayRecordingAttemptTile({
    required this.attempt,
    required this.isSelected,
    required this.isPlaying,
    required this.isBusy,
    required this.onSelect,
    required this.onPlay,
  });

  final _RelayRecordingAttempt attempt;
  final bool isSelected;
  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onSelect;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final canPlay = !isBusy || isPlaying;
    return Material(
      color: isSelected ? AppColors.primarySoft : AppColors.bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isBusy ? null : onSelect,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.border.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${attempt.number}번 테이크',
                      style: AppText.body(13, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDuration(attempt.durationSeconds),
                      style: AppText.body(11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: canPlay ? onPlay : null,
                icon: Icon(
                  isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 18,
                ),
                label: Text(isPlaying ? '정지' : '듣기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelayClipsSheet extends StatelessWidget {
  const _RelayClipsSheet({required this.title, required this.clips});

  final String title;
  final List<Map<String, dynamic>> clips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppText.body(20, weight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (clips.isNotEmpty) ...[
              _ClipMindMap(clips: clips),
              const SizedBox(height: 12),
            ],
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: clips.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final clip = clips[index];
                  final author = clip['userName']?.toString() ?? '단원';
                  final url = clip['audioUrl']?.toString() ?? '';
                  final feedback = clip['autoFeedback']?.toString() ?? '';
                  final note = clip['note']?.toString() ?? '';
                  final score = (clip['autoScore'] as num?)?.toInt() ?? 0;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: AppColors.primary,
                              child: Text(
                                '${index + 1}',
                                style: AppText.body(
                                  11,
                                  color: Colors.white,
                                  weight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                author,
                                style: AppText.body(
                                  14,
                                  weight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (score > 0) _ScorePill(score: score),
                          ],
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            note,
                            style: AppText.body(12, color: AppColors.ink),
                          ),
                        ],
                        if (feedback.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            feedback,
                            style: AppText.body(
                              12,
                              color: AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: url.isEmpty
                              ? null
                              : () => launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                ),
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: const Text('소절 듣기'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipMindMap extends StatelessWidget {
  const _ClipMindMap({required this.clips});

  final List<Map<String, dynamic>> clips;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('녹음 연결 맵', style: AppText.body(14, weight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: clips.asMap().entries.map((entry) {
              final index = entry.key;
              final clip = entry.value;
              final author = clip['userName']?.toString() ?? '단원';
              final score = (clip['autoScore'] as num?)?.toInt() ?? 0;
              return Container(
                constraints: const BoxConstraints(minWidth: 116, maxWidth: 170),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.36),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        '${index + 1}',
                        style: AppText.body(
                          10,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(12, weight: FontWeight.w900),
                          ),
                          Text(
                            score <= 0 ? '녹음 완료' : '체크 $score',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(10, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _HarmonyNoteSheetState extends State<_HarmonyNoteSheet> {
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _recorder = AudioRecorder();
  final List<int> _recordedBytes = [];
  StreamSubscription<Uint8List>? _recordingSub;
  Timer? _recordingTimer;
  Uint8List? _audioBytes;
  String? _audioName;
  String _contentType = 'audio/webm';
  bool _streamRecording = false;
  bool _isRecording = false;
  bool _isSubmitting = false;
  double _progress = 0;
  int _recordSeconds = 0;

  static const _recordSampleRate = 44100;
  static const _recordChannels = 1;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingSub?.cancel();
    unawaited(_recorder.dispose());
    _titleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final partLabel = User.partLabels[widget.part] ?? '내 파트';
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$partLabel 음성 노트',
                      style: AppText.body(20, weight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '제목',
                  hintText: '예: 후렴 시작 호흡 맞추기',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promptController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '짧은 코멘트',
                  hintText: '파트원에게 남길 연습 포인트를 적어주세요',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isRecording
                      ? AppColors.secondarySoft
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        (_isRecording ? AppColors.secondary : AppColors.border)
                            .withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: _isRecording
                            ? AppColors.secondary
                            : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isRecording
                                ? '녹음 중 ${_formatDuration(_recordSeconds)}'
                                : _audioName?.startsWith('harmony_') == true
                                ? '방금 녹음한 음성 준비 완료'
                                : '앱에서 바로 녹음',
                            style: AppText.body(14, weight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isRecording
                                ? '마치면 녹음 완료를 눌러주세요'
                                : '짧게 남긴 뒤 바로 하모니챗에 올릴 수 있어요',
                            style: AppText.body(
                              12,
                              color: AppColors.muted,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : _isRecording
                          ? _stopRecording
                          : _startRecording,
                      child: Text(_isRecording ? '녹음 완료' : '녹음 시작'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _isSubmitting ? null : _pickAudio,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.secondarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.audio_file_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _audioName ?? 'MP3, M4A, WAV 음성 파일 선택',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            14,
                            weight: FontWeight.w700,
                            color: _audioName == null
                                ? AppColors.muted
                                : AppColors.ink,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
              if (_isSubmitting) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Text(_isSubmitting ? '업로드 중...' : '하모니챗에 남기기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAudio() async {
    if (_isRecording) {
      await _stopRecording();
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'webm'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (file.bytes == null) {
      _showMessage('파일을 읽을 수 없습니다. 다시 선택해주세요.');
      return;
    }
    setState(() {
      _audioBytes = file.bytes;
      _audioName = file.name;
      _contentType = _contentTypeFor(file.extension);
    });
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _ensureMicrophonePermission(_recorder);
      if (!hasPermission) {
        _showMessage('마이크 권한이 필요합니다.');
        return;
      }

      await _recordingSub?.cancel();
      _recordedBytes.clear();
      _streamRecording = false;
      _contentType = 'audio/webm';
      try {
        if (!await _recorder.isEncoderSupported(AudioEncoder.opus)) {
          throw StateError('Opus recorder is not supported.');
        }
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 128000,
            sampleRate: _recordSampleRate,
            numChannels: _recordChannels,
            echoCancel: true,
            noiseSuppress: false,
            autoGain: false,
          ),
          path: '',
        );
      } catch (_) {
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: _recordSampleRate,
            numChannels: _recordChannels,
            echoCancel: true,
            noiseSuppress: false,
            autoGain: false,
          ),
        );
        _streamRecording = true;
        _contentType = 'audio/wav';
        _recordingSub = stream.listen(
          _recordedBytes.addAll,
          onError: (_) {
            if (mounted) _showMessage('녹음 중 문제가 생겼습니다. 다시 시도해주세요.');
          },
        );
      }
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds += 1);
      });

      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _audioBytes = null;
        _audioName = null;
      });
    } catch (_) {
      unawaited(_forgetMicrophonePermissionIfRevoked());
      _showMessage('녹음을 시작할 수 없습니다. 브라우저의 마이크 권한을 확인해주세요.');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final stoppedPath = await _recorder.stop();
      final recordedPath = _streamRecording ? null : stoppedPath;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _recordingSub?.cancel();
      _recordingSub = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;

      Uint8List recorded;
      if (recordedPath != null && recordedPath.isNotEmpty) {
        recorded = await _bytesFromRecordedPath(recordedPath);
      } else {
        final pcmBytes = Uint8List.fromList(_recordedBytes);
        recorded = pcmBytes.isEmpty
            ? Uint8List(0)
            : _wavFromPcm(
                pcmBytes,
                sampleRate: _recordSampleRate,
                channels: _recordChannels,
              );
      }
      if (recorded.isEmpty) {
        setState(() => _isRecording = false);
        _showMessage('녹음된 소리가 없습니다. 다시 시도해주세요.');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _isRecording = false;
        _audioBytes = recorded;
        _audioName = _streamRecording
            ? 'harmony_$now.wav'
            : 'harmony_$now.webm';
      });
    } catch (_) {
      setState(() => _isRecording = false);
      _showMessage('녹음을 마무리하지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _submit() async {
    if (_isRecording) {
      await _stopRecording();
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('제목을 입력해주세요.');
      return;
    }
    final bytes = _audioBytes;
    final fileName = _audioName;
    if (bytes == null || fileName == null) {
      _showMessage('음성 파일을 선택해주세요.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _progress = 0;
    });
    try {
      final audioUrl = await FirebaseService.uploadHarmonyAudio(
        bytes,
        fileName: fileName,
        contentType: _contentType,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await FirebaseService.createHarmonyNote(
        part: widget.part,
        title: title,
        prompt: _promptController.text,
        audioUrl: audioUrl,
        audioFileName: fileName,
      );
      widget.ref.invalidate(harmonyNotesProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _progress = 0;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _contentTypeFor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'webm':
        return 'audio/webm';
      case 'm4a':
        return 'audio/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Uint8List _wavFromPcm(
    Uint8List pcmBytes, {
    required int sampleRate,
    required int channels,
  }) {
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final builder = BytesBuilder();

    void addString(String value) => builder.add(ascii.encode(value));
    void addUint16(int value) {
      final data = ByteData(2)..setUint16(0, value, Endian.little);
      builder.add(data.buffer.asUint8List());
    }

    void addUint32(int value) {
      final data = ByteData(4)..setUint32(0, value, Endian.little);
      builder.add(data.buffer.asUint8List());
    }

    addString('RIFF');
    addUint32(36 + pcmBytes.length);
    addString('WAVE');
    addString('fmt ');
    addUint32(16);
    addUint16(1);
    addUint16(channels);
    addUint32(sampleRate);
    addUint32(byteRate);
    addUint16(blockAlign);
    addUint16(16);
    addString('data');
    addUint32(pcmBytes.length);
    builder.add(pcmBytes);

    return builder.toBytes();
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.secondarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppText.body(
          10,
          weight: FontWeight.w900,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}

class _EmptyHarmonyState extends StatelessWidget {
  const _EmptyHarmonyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: AppColors.subtle),
          const SizedBox(height: 12),
          Text(title, style: AppText.body(16, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.body(13, color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

Future<Uint8List> _bytesFromRecordedPath(String path) async {
  final uri = Uri.tryParse(path);
  if (uri == null) return Uint8List(0);
  final response = await http.get(uri);
  if (response.statusCode >= 400) return Uint8List(0);
  return response.bodyBytes;
}

String _todayKeyLocal() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

Uint8List _previewPracticeToneBytes(int durationSeconds) {
  const sampleRate = 44100;
  const channels = 1;
  final frameCount = sampleRate * durationSeconds;
  final pcmBytes = Uint8List(frameCount * channels * 2);
  final data = ByteData.sublistView(pcmBytes);
  final fadeSamples = math.min((sampleRate * 0.05).round(), frameCount ~/ 2);
  const melody = [329.63, 392.0, 440.0, 493.88, 523.25];
  for (var frame = 0; frame < frameCount; frame += 1) {
    final seconds = frame / sampleRate;
    final note = melody[((seconds / 0.7).floor()) % melody.length];
    final fadeIn = fadeSamples == 0 ? 1.0 : frame / fadeSamples;
    final fadeOut = fadeSamples == 0
        ? 1.0
        : (frameCount - frame - 1) / fadeSamples;
    final envelope = math.min(1.0, math.min(fadeIn, fadeOut)).clamp(0.0, 1.0);
    final sample =
        (math.sin(2 * math.pi * note * seconds) * 0.22 +
            math.sin(2 * math.pi * note * 2 * seconds) * 0.05) *
        envelope;
    data.setInt16((frame * 2), (sample * 32767).round(), Endian.little);
  }
  return _wavFromPcmBytes(pcmBytes, sampleRate: sampleRate, channels: channels);
}

String _relativeTime(dynamic value) {
  final parsed = value is DateTime
      ? value
      : value is String
      ? DateTime.tryParse(value)
      : null;
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${parsed.month}/${parsed.day}';
}

String _formatDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> _lyricsTimelineFromValue(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) {
        return {
          'timeSec': (entry['timeSec'] as num?)?.toDouble() ?? 0,
          'text': _cleanDisplayText(entry['text']?.toString() ?? ''),
        };
      })
      .where((entry) => (entry['text']?.toString() ?? '').trim().isNotEmpty)
      .toList()
    ..sort((a, b) {
      final at = (a['timeSec'] as num?)?.toDouble() ?? 0;
      final bt = (b['timeSec'] as num?)?.toDouble() ?? 0;
      return at.compareTo(bt);
    });
}

Uint8List _wavFromPcmBytes(
  Uint8List pcmBytes, {
  required int sampleRate,
  required int channels,
}) {
  final byteRate = sampleRate * channels * 2;
  final blockAlign = channels * 2;
  final builder = BytesBuilder();

  void addString(String value) => builder.add(ascii.encode(value));
  void addUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    builder.add(data.buffer.asUint8List());
  }

  void addUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    builder.add(data.buffer.asUint8List());
  }

  addString('RIFF');
  addUint32(36 + pcmBytes.length);
  addString('WAVE');
  addString('fmt ');
  addUint32(16);
  addUint16(1);
  addUint16(channels);
  addUint32(sampleRate);
  addUint32(byteRate);
  addUint16(blockAlign);
  addUint16(16);
  addString('data');
  addUint32(pcmBytes.length);
  builder.add(pcmBytes);

  return builder.toBytes();
}
