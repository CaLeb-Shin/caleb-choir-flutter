import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/user.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';

class HarmonyChatScreen extends ConsumerWidget {
  const HarmonyChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final notesAsync = ref.watch(harmonyNotesProvider);
    final relaysAsync = ref.watch(harmonyRelaysProvider);
    final guideAsync = ref.watch(latestPartGuideProvider);
    final part = profile?.partLeaderFor ?? profile?.part ?? '';
    final partLabel = User.partLabels[part] ?? '내 파트';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('하모니챗', style: AppText.headline(28))),
              FilledButton.icon(
                onPressed: part.isEmpty
                    ? null
                    : () => _openComposeSheet(context, ref, part),
                icon: const Icon(Icons.mic_rounded, size: 18),
                label: const Text('음성 남기기'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '파트별 목소리로 연습 포인트를 짧게 나눠요',
            style: AppText.body(14, color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          _TodayGuideCard(
            part: part,
            partLabel: partLabel,
            guideAsync: guideAsync,
            ref: ref,
          ),
          const SizedBox(height: 16),
          _PartRoomHeader(partLabel: partLabel),
          const SizedBox(height: 16),
          _RelaySection(
            part: part,
            partLabel: partLabel,
            relaysAsync: relaysAsync,
            ref: ref,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '음성 노트',
                  style: AppText.body(18, weight: FontWeight.w900),
                ),
              ),
              Text(
                '파트 연습 포인트',
                style: AppText.body(12, color: AppColors.muted),
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
                  title: '$partLabel 하모니챗이 비어 있습니다',
                  message: '첫 음성 노트를 남겨 파트의 연습 흐름을 열어보세요.',
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

class _PartRoomHeader extends StatelessWidget {
  const _PartRoomHeader({required this.partLabel});

  final String partLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$partLabel 룸',
                  style: AppText.body(
                    18,
                    weight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '짧은 음성 노트로 입장음, 호흡, 가사 뉘앙스를 맞춰요',
                  style: AppText.body(
                    13,
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.35,
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
        final date = guide['sheetDate']?.toString() ?? '';
        final comment = guide['guide']?.toString() ?? '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF0),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAD9A8),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_motion_rounded,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '오늘의 릴레이',
                          style: AppText.body(
                            12,
                            weight: FontWeight.w900,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$title · ${widget.partLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(17, weight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                date.isEmpty
                    ? '파트 가이드 음원으로 한 소절씩 이어 불러요'
                    : '$date 가이드 음원으로 한 소절씩 이어 불러요',
                style: AppText.body(13, color: AppColors.onSurfaceVariant),
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  comment,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(12, color: AppColors.muted, height: 1.35),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isCreating ? null : () => _createRelay(guide),
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: Text(_isCreating ? '릴레이 준비 중...' : '가이드로 릴레이 열기'),
                ),
              ),
            ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
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
                      '파트별 릴레이',
                      style: AppText.body(18, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '소절마다 이어 부르고 서로 연결감을 맞춰요',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
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
                label: const Text('릴레이'),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                  '파트가 지정되면 릴레이를 사용할 수 있어요.',
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
                          '첫 릴레이를 열어 파트원들이 한 소절씩 이어 부르게 해보세요.',
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
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
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
  });

  final List<Map<String, dynamic>> relays;
  final String part;
  final String partLabel;
  final WidgetRef ref;

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
        color: isComplete ? const Color(0xFFFFFBF0) : AppColors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isComplete
              ? const Color(0xFFE7D39A)
              : AppColors.border.withValues(alpha: 0.35),
        ),
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
                child: Icon(
                  isComplete
                      ? Icons.workspace_premium_rounded
                      : Icons.route_rounded,
                  color: isComplete ? AppColors.secondary : AppColors.primary,
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
          ...relays.map(
            (relay) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MissionSegmentTile(
                relay: relay,
                part: part,
                partLabel: partLabel,
                ref: ref,
              ),
            ),
          ),
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

class _MissionSegmentTile extends StatelessWidget {
  const _MissionSegmentTile({
    required this.relay,
    required this.part,
    required this.partLabel,
    required this.ref,
  });

  final Map<String, dynamic> relay;
  final String part;
  final String partLabel;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final title = relay['title']?.toString() ?? '릴레이';
    final segmentLabel = relay['segmentLabel']?.toString() ?? '소절';
    final guideAudioUrl = relay['guideAudioUrl']?.toString() ?? '';
    final mrAudioUrl = relay['mrAudioUrl']?.toString() ?? '';
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final completed = _relayCompleted(relay);
    final latest = clips.isEmpty ? null : clips.last;
    final singer =
        latest?['userName']?.toString() ??
        relay['completedByName']?.toString() ??
        '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RelayClipSheet(
          relayId: relay['id'].toString(),
          part: part,
          partLabel: partLabel,
          relayTitle: title,
          guideAudioUrl: guideAudioUrl,
          mrAudioUrl: mrAudioUrl,
          segmentLabel: segmentLabel,
          segmentStartSec: (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
          segmentEndSec: (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
          ref: ref,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: completed ? AppColors.primarySoft : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: completed
                ? AppColors.primary.withValues(alpha: 0.20)
                : AppColors.border.withValues(alpha: 0.35),
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
                    segmentLabel,
                    style: AppText.body(13, weight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    completed
                        ? '${singer.isEmpty ? '파트원' : singer} 완료'
                        : assigneeName.isEmpty
                        ? '다음 주자 대기'
                        : '다음 $assigneeName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (isMyTurn && !completed)
              _TurnPill(label: '내 차례', active: true)
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

String _firstText(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
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
  });

  final Map<String, dynamic> relay;
  final String part;
  final String partLabel;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final title = relay['title']?.toString() ?? '릴레이';
    final segmentLabel = relay['segmentLabel']?.toString() ?? '소절';
    final guide = relay['guide']?.toString() ?? '';
    final guideAudioUrl = relay['guideAudioUrl']?.toString() ?? '';
    final mrAudioUrl = relay['mrAudioUrl']?.toString() ?? '';
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final latest = clips.isEmpty ? null : clips.last;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  segmentLabel,
                  style: AppText.body(
                    11,
                    weight: FontWeight.w900,
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${clips.length}명 참여',
                style: AppText.body(12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppText.body(16, weight: FontWeight.w900),
                ),
              ),
              if (assigneeName.isNotEmpty)
                _TurnPill(
                  label: isMyTurn ? '내 차례' : '$assigneeName 지목',
                  active: isMyTurn,
                ),
            ],
          ),
          if (guide.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              guide,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(12, color: AppColors.muted, height: 1.35),
            ),
          ],
          if (latest != null) ...[
            const SizedBox(height: 12),
            _RelayClipPreview(clip: latest, order: clips.length),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: clips.isEmpty
                      ? null
                      : () => _openRelayClips(context, clips, title),
                  icon: const Icon(Icons.queue_music_rounded, size: 18),
                  label: const Text('이어보기'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _RelayClipSheet(
                      relayId: relay['id'].toString(),
                      part: part,
                      partLabel: partLabel,
                      relayTitle: title,
                      guideAudioUrl: guideAudioUrl,
                      mrAudioUrl: mrAudioUrl,
                      segmentLabel: segmentLabel,
                      segmentStartSec:
                          (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
                      segmentEndSec:
                          (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
                      ref: ref,
                    ),
                  ),
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: const Text('내 소절'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openRelayClips(
    BuildContext context,
    List<Map<String, dynamic>> clips,
    String title,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RelayClipsSheet(title: title, clips: clips),
    );
  }
}

class _RelayClipPreview extends StatelessWidget {
  const _RelayClipPreview({required this.clip, required this.order});

  final Map<String, dynamic> clip;
  final int order;

  @override
  Widget build(BuildContext context) {
    final score = (clip['autoScore'] as num?)?.toInt() ?? 0;
    final author = clip['userName']?.toString() ?? '단원';
    final feedback = clip['autoFeedback']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.primary,
            child: Text(
              '$order',
              style: AppText.body(
                11,
                color: Colors.white,
                weight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(author, style: AppText.body(13, weight: FontWeight.w900)),
                if (feedback.isNotEmpty)
                  Text(
                    feedback,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(11, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          _ScorePill(score: score),
        ],
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
                  child: Text(_isSubmitting ? '만드는 중...' : '릴레이 시작하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final segment = _segmentController.text.trim();
    if (title.isEmpty || segment.isEmpty) {
      _showMessage('제목과 소절을 입력해주세요.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await FirebaseService.createHarmonyRelay(
        part: widget.part,
        title: title,
        segmentLabel: segment,
        guide: _guideController.text,
      );
      widget.ref.invalidate(harmonyRelaysProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    required this.segmentStartSec,
    required this.segmentEndSec,
    required this.ref,
  });

  final String relayId;
  final String part;
  final String partLabel;
  final String relayTitle;
  final String guideAudioUrl;
  final String mrAudioUrl;
  final String segmentLabel;
  final double segmentStartSec;
  final double segmentEndSec;
  final WidgetRef ref;

  @override
  State<_RelayClipSheet> createState() => _RelayClipSheetState();
}

class _RelayClipSheetState extends State<_RelayClipSheet> {
  final _noteController = TextEditingController();
  final _recorder = AudioRecorder();
  final _guidePlayer = AudioPlayer();
  final List<int> _recordedBytes = [];
  StreamSubscription<Uint8List>? _recordingSub;
  Timer? _recordingTimer;
  Timer? _segmentStopTimer;
  Uint8List? _audioBytes;
  int? _countdown;
  bool _isRecording = false;
  bool _isSubmitting = false;
  bool _isGuidePlaying = false;
  bool _isGuidedFlow = false;
  bool _isMrRecording = false;
  int _recordSeconds = 0;
  double _progress = 0;

  static const _sampleRate = 44100;
  static const _channels = 1;

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
  void dispose() {
    _recordingTimer?.cancel();
    _segmentStopTimer?.cancel();
    _recordingSub?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_guidePlayer.dispose());
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
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
                      '릴레이 스튜디오',
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
              const SizedBox(height: 4),
              Text(
                '${widget.relayTitle} · ${widget.partLabel}',
                style: AppText.body(13, color: AppColors.muted),
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
                      Text(
                        widget.segmentLabel,
                        style: AppText.body(
                          12,
                          color: AppColors.secondary,
                          weight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.mrAudioUrl.isNotEmpty
                            ? '가이드 보컬로 구간을 익히고, 녹음할 때는 MR만 재생돼요.'
                            : '가이드 보컬은 듣기용이에요. 녹음 MR이 등록되면 반주에 맞춰 녹음할 수 있어요.',
                        style: AppText.body(
                          12,
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isRecording ||
                                      _isGuidePlaying ||
                                      _countdown != null
                                  ? null
                                  : _playGuideOnce,
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: const Text('보컬 가이드'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed:
                                  _isSubmitting ||
                                      _isRecording ||
                                      _isGuidePlaying ||
                                      _countdown != null
                                  ? null
                                  : _listenThenRecord,
                              icon: const Icon(
                                Icons.graphic_eq_rounded,
                                size: 18,
                              ),
                              label: const Text('MR 녹음'),
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
                        (_isRecording ? AppColors.secondary : AppColors.border)
                            .withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _countdown != null
                          ? Icons.timer_rounded
                          : _isRecording
                          ? Icons.stop_circle_rounded
                          : Icons.mic_rounded,
                      color: _countdown != null
                          ? AppColors.secondary
                          : _isRecording
                          ? AppColors.secondary
                          : AppColors.primary,
                      size: 38,
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
                          ? '숨을 고르고 바로 시작합니다'
                          : _isGuidePlaying
                          ? (_isGuidedFlow ? '보컬 가이드를 듣는 중...' : '가이드 재생 중...')
                          : _isRecording
                          ? (_isMrRecording
                                ? 'MR에 맞춰 녹음 중 ${_formatDuration(_recordSeconds)}'
                                : '녹음 중 ${_formatDuration(_recordSeconds)}')
                          : _audioBytes == null
                          ? '한 소절을 이어 받을 준비가 됐어요'
                          : '녹음 준비 완료',
                      style: AppText.body(16, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: _isSubmitting || _countdown != null
                          ? null
                          : _isRecording
                          ? _stopRecording
                          : _countdownThenStartRecording,
                      icon: Icon(
                        _isRecording ? Icons.check_rounded : Icons.mic_rounded,
                      ),
                      label: Text(_isRecording ? '녹음 완료' : '녹음 시작'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '짧은 메모 (선택)',
                  hintText: '내가 신경쓴 포인트를 남겨주세요',
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
                  child: Text(_isSubmitting ? '릴레이에 붙이는 중...' : '릴레이에 올리기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _countdownThenStartRecording({String? backingUrl}) async {
    if (_isRecording || _isSubmitting || _countdown != null) return;
    try {
      for (final value in const [3, 2, 1]) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(milliseconds: 760));
      }
    } finally {
      if (mounted) setState(() => _countdown = null);
    }
    if (!mounted) return;
    await _startRecordingInternal(backingUrl: backingUrl);
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

  Future<void> _listenThenRecord() async {
    if (widget.mrAudioUrl.isEmpty) {
      _showMessage('녹음용 MR이 아직 등록되지 않았어요.');
      return;
    }
    try {
      setState(() {
        _isGuidePlaying = true;
        _isGuidedFlow = true;
      });
      if (widget.guideAudioUrl.isNotEmpty) {
        await _playGuideAndWait(widget.guideAudioUrl);
      }
      if (!mounted) return;
      setState(() => _isGuidePlaying = false);
      await _countdownThenStartRecording(backingUrl: widget.mrAudioUrl);
    } catch (_) {
      _showMessage('MR 녹음을 시작하지 못했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          _isGuidePlaying = false;
          _isGuidedFlow = false;
        });
      }
    }
  }

  Future<void> _playGuideAndWait(String audioUrl) async {
    final completer = Completer<void>();
    StreamSubscription<void>? sub;
    sub = _guidePlayer.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    await _guidePlayer.stop();
    final segmentDuration = _segmentDuration;
    _segmentStopTimer?.cancel();
    await _guidePlayer.play(UrlSource(audioUrl), position: _segmentStart);
    if (segmentDuration > Duration.zero) {
      _segmentStopTimer = Timer(segmentDuration, () async {
        await _guidePlayer.stop();
        if (!completer.isCompleted) completer.complete();
      });
    }
    await completer.future.timeout(
      segmentDuration > Duration.zero
          ? segmentDuration + const Duration(seconds: 3)
          : const Duration(seconds: 45),
      onTimeout: () async {
        await _guidePlayer.stop();
      },
    );
    _segmentStopTimer?.cancel();
    await sub.cancel();
  }

  Future<void> _startRecordingInternal({String? backingUrl}) async {
    try {
      final hasBacking = backingUrl != null && backingUrl.isNotEmpty;
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showMessage('마이크 권한이 필요합니다.');
        return;
      }
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channels,
          echoCancel: !hasBacking,
          noiseSuppress: true,
          autoGain: true,
        ),
      );
      await _recordingSub?.cancel();
      _recordedBytes.clear();
      _recordingSub = stream.listen(_recordedBytes.addAll);
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds += 1);
      });
      setState(() {
        _isRecording = true;
        _isMrRecording = hasBacking;
        _recordSeconds = 0;
        _audioBytes = null;
      });
      if (hasBacking) {
        await _guidePlayer.stop();
        final segmentDuration = _segmentDuration;
        _segmentStopTimer?.cancel();
        unawaited(
          _guidePlayer.play(UrlSource(backingUrl), position: _segmentStart),
        );
        if (segmentDuration > Duration.zero) {
          _segmentStopTimer = Timer(segmentDuration, () {
            unawaited(_stopRecording());
          });
        }
      }
    } catch (_) {
      _showMessage('녹음을 시작할 수 없습니다. 마이크 권한을 확인해주세요.');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      _segmentStopTimer?.cancel();
      _segmentStopTimer = null;
      await _guidePlayer.stop();
      await _recorder.stop();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _recordingSub?.cancel();
      _recordingSub = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final pcmBytes = Uint8List.fromList(_recordedBytes);
      if (pcmBytes.isEmpty) {
        setState(() {
          _isRecording = false;
          _isMrRecording = false;
        });
        _showMessage('녹음된 소리가 없습니다. 다시 시도해주세요.');
        return;
      }
      setState(() {
        _isRecording = false;
        _isMrRecording = false;
        _audioBytes = _wavFromPcmBytes(
          pcmBytes,
          sampleRate: _sampleRate,
          channels: _channels,
        );
      });
    } catch (_) {
      setState(() {
        _isRecording = false;
        _isMrRecording = false;
      });
      _showMessage('녹음을 마무리하지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _submit() async {
    if (_isRecording) await _stopRecording();
    final bytes = _audioBytes;
    if (bytes == null) {
      _showMessage('먼저 소절을 녹음해주세요.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _progress = 0;
    });
    try {
      final fileName = 'relay_${DateTime.now().millisecondsSinceEpoch}.wav';
      final audioUrl = await FirebaseService.uploadHarmonyAudio(
        bytes,
        fileName: fileName,
        contentType: 'audio/wav',
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await FirebaseService.addHarmonyRelayClip(
        relayId: widget.relayId,
        part: widget.part,
        audioUrl: audioUrl,
        audioFileName: fileName,
        durationSeconds: _recordSeconds,
        note: _noteController.text,
      );
      widget.ref.invalidate(harmonyRelaysProvider);
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
                            _ScorePill(score: score),
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

class _HarmonyNoteSheetState extends State<_HarmonyNoteSheet> {
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _recorder = AudioRecorder();
  final List<int> _recordedBytes = [];
  StreamSubscription<Uint8List>? _recordingSub;
  Timer? _recordingTimer;
  Uint8List? _audioBytes;
  String? _audioName;
  String _contentType = 'audio/mp4';
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
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showMessage('마이크 권한이 필요합니다.');
        return;
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _recordSampleRate,
          numChannels: _recordChannels,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
      );

      await _recordingSub?.cancel();
      _recordedBytes.clear();
      _recordingSub = stream.listen(
        _recordedBytes.addAll,
        onError: (_) {
          if (mounted) _showMessage('녹음 중 문제가 생겼습니다. 다시 시도해주세요.');
        },
      );
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds += 1);
      });

      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _audioBytes = null;
        _audioName = null;
        _contentType = 'audio/wav';
      });
    } catch (_) {
      _showMessage('녹음을 시작할 수 없습니다. 브라우저의 마이크 권한을 확인해주세요.');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.stop();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _recordingSub?.cancel();
      _recordingSub = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;

      final pcmBytes = Uint8List.fromList(_recordedBytes);
      if (pcmBytes.isEmpty) {
        setState(() => _isRecording = false);
        _showMessage('녹음된 소리가 없습니다. 다시 시도해주세요.');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _isRecording = false;
        _audioBytes = _wavFromPcm(
          pcmBytes,
          sampleRate: _recordSampleRate,
          channels: _recordChannels,
        );
        _audioName = 'harmony_$now.wav';
        _contentType = 'audio/wav';
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
