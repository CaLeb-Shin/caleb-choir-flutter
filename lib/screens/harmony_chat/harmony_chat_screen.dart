import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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
                label: const Text('녹음'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _TodayGuideCard(
            part: part,
            partLabel: partLabel,
            guideAsync: guideAsync,
            ref: ref,
          ),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(17, weight: FontWeight.w900),
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
                              const Icon(
                                Icons.chevron_right_rounded,
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
    final compact = MediaQuery.sizeOf(context).width < 480;
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
          if (compact)
            _CompactMissionRecordCard(
              title: title,
              relays: relays,
              part: part,
              partLabel: partLabel,
              ref: ref,
            )
          else ...[
            _RelayProgressMap(
              relays: relays,
              part: part,
              partLabel: partLabel,
              ref: ref,
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
                      child: Text(
                        currentLine,
                        key: ValueKey(currentLine),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          22,
                          weight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (nextLine.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        nextLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

class _RelayProgressMap extends StatelessWidget {
  const _RelayProgressMap({
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
    final completed = relays.where(_relayCompleted).length;
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
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: AppColors.primary,
                  size: 20,
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
              _MapStatPill(label: '$completed/${relays.length}', dark: true),
            ],
          ),
          const SizedBox(height: 10),
          const _HarmonyLegend(dark: true),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 420
                  ? (constraints.maxWidth - 16) / 3
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: relays.asMap().entries.map((entry) {
                  final index = entry.key;
                  final relay = entry.value;
                  return SizedBox(
                    width: itemWidth,
                    child: _RelayMapNode(
                      relay: relay,
                      order: index + 1,
                      part: part,
                      partLabel: partLabel,
                      missionRelays: relays,
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

class _RelayMapNode extends StatelessWidget {
  const _RelayMapNode({
    required this.relay,
    required this.order,
    required this.part,
    required this.partLabel,
    required this.missionRelays,
    required this.ref,
  });

  final Map<String, dynamic> relay;
  final int order;
  final String part;
  final String partLabel;
  final List<Map<String, dynamic>> missionRelays;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final completed = _relayCompleted(relay);
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final canTestRecord = !completed && _canTestRecordRelayForTest(ref, part);
    final active = completed || isMyTurn || canTestRecord;
    final latest = clips.isEmpty ? null : clips.last;
    final segmentTitle = _segmentDisplayLabel(relay, order - 1);
    final singer =
        latest?['userName']?.toString() ??
        relay['completedByName']?.toString() ??
        '';
    final status = completed
        ? (singer.isEmpty ? '완료' : singer)
        : isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : assigneeName;

    return Material(
      color: completed
          ? const Color(0xFFEAF5EA)
          : active
          ? Colors.white
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openRelayStudio(
          context,
          relay,
          part,
          partLabel,
          ref,
          missionRelays: missionRelays,
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: active
                        ? (completed ? AppColors.success : AppColors.primary)
                        : Colors.white.withValues(alpha: 0.16),
                    child: completed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : Text(
                            '$order',
                            style: AppText.body(
                              10,
                              weight: FontWeight.w900,
                              color: active
                                  ? Colors.white
                                  : AppColors.secondaryContainer,
                            ),
                          ),
                  ),
                  const Spacer(),
                  Icon(
                    completed
                        ? Icons.check_circle_rounded
                        : active
                        ? Icons.mic_rounded
                        : Icons.more_horiz_rounded,
                    size: 16,
                    color: active
                        ? (completed ? AppColors.success : AppColors.primary)
                        : Colors.white.withValues(alpha: 0.62),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                segmentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: active
                      ? (completed ? AppColors.success : AppColors.primary)
                      : Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  10,
                  color: active
                      ? AppColors.onSurfaceVariant
                      : Colors.white.withValues(alpha: 0.66),
                ),
              ),
            ],
          ),
        ),
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
  });

  final Map<String, dynamic> relay;
  final List<Map<String, dynamic>> missionRelays;
  final String part;
  final String partLabel;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final clips = ((relay['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final title = relay['title']?.toString() ?? '릴레이';
    final lyricsLine = relay['lyricsLine']?.toString() ?? '';
    final nextLyricsLine = relay['nextLyricsLine']?.toString() ?? '';
    final lyricsText = relay['lyricsText']?.toString() ?? '';
    final lyricsTimeline = _lyricsTimelineFromValue(relay['lyricsTimeline']);
    final guideAudioUrl = relay['guideAudioUrl']?.toString() ?? '';
    final mrAudioUrl = relay['mrAudioUrl']?.toString() ?? '';
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
    final recordStatusLabel = isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트 녹음'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : '다음 $assigneeName';

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
          segmentLabel: segmentTitle,
          lyricsLine: lyricsLine,
          nextLyricsLine: nextLyricsLine,
          lyricsText: lyricsText,
          lyricsTimeline: lyricsTimeline,
          segmentStartSec: (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
          segmentEndSec: (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
          previousClips: _previousMissionClipsFor(relay, missionRelays),
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
            if ((isMyTurn || canTestRecord) && !completed)
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

void _openRelayStudio(
  BuildContext context,
  Map<String, dynamic> relay,
  String part,
  String partLabel,
  WidgetRef ref, {
  List<Map<String, dynamic>>? missionRelays,
}) {
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
          ? ((relay['clips'] as List?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList()
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
  for (var index = currentIndex - 1; index >= 0; index -= 1) {
    final clips = ((sorted[index]['clips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (clips.isNotEmpty) return [clips.last];
  }
  return const [];
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

final _emojiDisplayPattern = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]',
  unicode: true,
);
final _emojiControlPattern = RegExp(r'[\u200D\uFE0E\uFE0F]');

String _cleanDisplayText(String value) {
  return value
      .replaceAll(_emojiDisplayPattern, '')
      .replaceAll(_emojiControlPattern, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

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
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final canTestRecord = _canTestRecordRelayForTest(ref, part);
    final canRecordNow = isMyTurn || canTestRecord || assigneeName.isEmpty;
    final status = isMyTurn
        ? '내 차례'
        : canTestRecord
        ? '테스트 녹음'
        : assigneeName.isEmpty
        ? '녹음 가능'
        : '$assigneeName 차례';
    final hasClips = clips.isNotEmpty;

    void openStudio() {
      showModalBottomSheet(
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
          lyricsLine: relay['lyricsLine']?.toString() ?? '',
          nextLyricsLine: relay['nextLyricsLine']?.toString() ?? '',
          lyricsText: relay['lyricsText']?.toString() ?? '',
          lyricsTimeline: _lyricsTimelineFromValue(relay['lyricsTimeline']),
          segmentStartSec: (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
          segmentEndSec: (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
          previousClips: clips,
          ref: ref,
        ),
      );
    }

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: openStudio,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
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
                        onPressed: () => _openRelayClips(context, clips, title),
                        icon: const Icon(Icons.queue_music_rounded, size: 18),
                        label: const Text('듣기'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: openStudio,
                        icon: const Icon(Icons.mic_rounded, size: 18),
                        label: const Text('녹음'),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: openStudio,
                    icon: const Icon(Icons.mic_rounded, size: 18),
                    label: const Text('녹음하기'),
                  ),
                ),
            ],
          ),
        ),
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
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppText.body(10, color: textColor)),
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
  final _noteController = TextEditingController();
  final _recorder = AudioRecorder();
  final _guidePlayer = AudioPlayer();
  final _backingPlayer = AudioPlayer();
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
  bool _isGuidedFlow = false;
  bool _isListeningPrevious = false;
  bool _isMrRecording = false;
  int _listeningClipIndex = 0;
  int _recordAttemptCount = 0;
  int _recordSeconds = 0;
  double _recordElapsedSeconds = 0;
  double _playbackElapsedSeconds = 0;
  int? _selectedAttemptNumber;
  int? _playingAttemptNumber;
  double _progress = 0;
  int _lastWaveformByteCount = 0;
  List<double> _waveformLevels = List<double>.filled(28, 0.08);
  final _recordingStopwatch = Stopwatch();
  final _playbackStopwatch = Stopwatch();

  static const _sampleRate = 44100;
  static const _channels = 1;
  static const _maxRecordAttempts = 3;

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
    _noteController.dispose();
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
        _isListeningPrevious ||
        _countdown != null ||
        _playingAttemptNumber != null;
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
                      icon: const Icon(Icons.close_rounded),
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
                  currentLine: _currentLyricLine,
                  nextLine: _nextLyricLine,
                  segmentLabel: widget.segmentLabel,
                  progress: lyricProgress,
                  isActive:
                      _isRecording ||
                      _isGuidePlaying ||
                      _isListeningPrevious ||
                      _countdown != null,
                  statusText: _countdown != null
                      ? '곧 시작'
                      : _isListeningPrevious
                      ? '앞소절 재생'
                      : _isRecording
                      ? '녹음 중'
                      : _isGuidePlaying
                      ? 'AR 재생'
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
                              ? hasArGuide
                                    ? 'AR과 앞소절을 듣고 이어 녹음'
                                    : hasMrBacking
                                    ? '앞소절 $previousClipCount개를 듣고 MR로 녹음'
                                    : '앞소절 $previousClipCount개를 듣고 녹음'
                              : hasArGuide && hasMrBacking
                              ? 'AR로 먼저 듣고 MR에 맞춰 녹음'
                              : hasArGuide
                              ? 'AR로 먼저 듣고 녹음'
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
                              const Icon(
                                Icons.info_rounded,
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
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                                label: const Text('AR 듣기'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: isBusy || !_hasAttemptsLeft
                                    ? null
                                    : _listenThenRecord,
                                icon: const Icon(
                                  Icons.graphic_eq_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  previousClipCount > 0
                                      ? (hasMrBacking ? '듣고 MR 녹음' : '듣고 녹음')
                                      : hasArGuide
                                      ? (hasMrBacking
                                            ? 'AR 듣고 MR 녹음'
                                            : 'AR 듣고 녹음')
                                      : (hasMrBacking ? 'MR 녹음' : '녹음'),
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
                            : _isListeningPrevious
                            ? '앞소절 $_listeningClipIndex/$previousClipCount 듣는 중...'
                            : _isGuidePlaying
                            ? (_isGuidedFlow ? 'AR 가이드를 듣는 중...' : 'AR 재생 중...')
                            : _isRecording
                            ? (_isMrRecording
                                  ? 'MR에 맞춰 녹음 중 ${_formatDuration(_recordSeconds)}'
                                  : '녹음 중 ${_formatDuration(_recordSeconds)}')
                            : !_hasAttemptsLeft && selectedAttempt == null
                            ? '3번의 기회를 모두 사용했어요'
                            : selectedAttempt == null
                            ? previousClipCount > 0
                                  ? '앞소절 듣고 녹음'
                                  : hasMrBacking
                                  ? 'MR 반주에 맞춰 이어 부를 준비가 됐어요'
                                  : '한 소절을 이어 받을 준비가 됐어요'
                            : '${selectedAttempt.number}번 테이크가 선택됐어요',
                        style: AppText.body(16, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _remainingAttempts == 0
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
                                _isListeningPrevious ||
                                (!_isRecording && !_hasAttemptsLeft)
                            ? null
                            : _isRecording
                            ? _stopRecording
                            : previousClipCount > 0 || hasArGuide
                            ? _listenThenRecord
                            : () => _countdownThenStartRecording(
                                backingUrl: _recordingBackingUrl,
                                primeBacking: true,
                              ),
                        icon: Icon(
                          _isRecording
                              ? Icons.check_rounded
                              : Icons.mic_rounded,
                        ),
                        label: Text(
                          _isRecording
                              ? '녹음 완료'
                              : previousClipCount > 0
                              ? (hasMrBacking ? '듣고 MR 녹음' : '듣고 녹음')
                              : hasArGuide
                              ? (hasMrBacking ? 'AR 듣고 MR 녹음' : 'AR 듣고 녹음')
                              : selectedAttempt == null
                              ? (hasMrBacking ? 'MR로 녹음 시작' : '녹음 시작')
                              : (hasMrBacking ? '다른 테이크 녹음' : '다시 녹음'),
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
                      setState(() => _selectedAttemptNumber = number);
                    },
                    onPlay: _toggleAttemptPlayback,
                  ),
                ],
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
      ),
    );
  }

  Future<void> _countdownThenStartRecording({
    String? backingUrl,
    bool primeBacking = false,
  }) async {
    if (_isRecording ||
        _isSubmitting ||
        _isGuidePlaying ||
        _isListeningPrevious ||
        _countdown != null) {
      return;
    }
    if (!_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    if (primeBacking && backingUrl != null && backingUrl.isNotEmpty) {
      await _primeRecordingBacking(backingUrl);
    }
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
    if (_isRecording ||
        _isSubmitting ||
        _isGuidePlaying ||
        _isListeningPrevious ||
        _countdown != null) {
      return;
    }
    if (!_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    try {
      setState(() => _isGuidedFlow = true);
      final backingUrl = _recordingBackingUrl;
      if (backingUrl != null && backingUrl.isNotEmpty) {
        await _primeRecordingBacking(backingUrl);
      }
      final previousClips = _playablePreviousClips;
      var playbackHadIssue = false;
      if (previousClips.isNotEmpty) {
        setState(() {
          _isListeningPrevious = true;
        });
        try {
          await _playPreviousClips(previousClips);
        } catch (_) {
          playbackHadIssue = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _isListeningPrevious = false;
        _listeningClipIndex = 0;
        _isGuidePlaying = widget.guideAudioUrl.isNotEmpty;
      });
      if (widget.guideAudioUrl.isNotEmpty) {
        try {
          await _playGuideAndWait(widget.guideAudioUrl);
        } catch (_) {
          playbackHadIssue = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _isGuidePlaying = false;
        _isListeningPrevious = false;
        _listeningClipIndex = 0;
      });
      if (playbackHadIssue) {
        _showMessage('일부 음원을 끝까지 재생하지 못했지만 녹음으로 넘어갈게요.');
      }
      if (backingUrl != null && backingUrl.isNotEmpty) {
        await _primeRecordingBacking(backingUrl);
      }
      await _countdownThenStartRecording(backingUrl: backingUrl);
    } catch (_) {
      _showMessage('듣고 녹음을 시작하지 못했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          _isGuidePlaying = false;
          _isGuidedFlow = false;
          _isListeningPrevious = false;
          _listeningClipIndex = 0;
        });
      }
    }
  }

  Future<void> _playPreviousClips(List<Map<String, dynamic>> clips) async {
    for (var index = 0; index < clips.length; index += 1) {
      if (!mounted) return;
      final url = clips[index]['audioUrl']?.toString().trim() ?? '';
      if (url.isEmpty) continue;
      setState(() => _listeningClipIndex = index + 1);
      await _playAudioAndWait(url, timeout: const Duration(seconds: 90));
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
  }) async {
    final completer = Completer<void>();
    final sub = _guidePlayer.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _guidePlayer.stop();
      _segmentStopTimer?.cancel();
      await _guidePlayer.play(UrlSource(audioUrl), position: position);
      _startPlaybackTimer();
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

  Future<void> _startRecordingInternal({String? backingUrl}) async {
    if (!_hasAttemptsLeft) {
      _showMessage('녹음 기회는 3번까지예요.');
      return;
    }
    try {
      final hasBacking = backingUrl != null && backingUrl.isNotEmpty;
      final hasPermission = await _recorder.hasPermission();
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
        _primedBackingUrl = null;
      }
      var backingStarted = false;
      if (hasBacking) {
        try {
          await _startRecordingBacking(backingUrl);
          backingStarted = true;
        } catch (_) {
          _primedBackingUrl = null;
          unawaited(_backingPlayer.stop());
          _showMessage('MR 반주를 재생하지 못했어요. 녹음은 계속 진행됩니다.');
        }
      }
      if (kIsWeb) {
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
              echoCancel: !hasBacking,
              noiseSuppress: true,
              autoGain: true,
            ),
            path: '',
          );
        } catch (_) {
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
          _streamRecording = true;
          _contentType = 'audio/wav';
          _audioFileName = 'relay_${DateTime.now().millisecondsSinceEpoch}.wav';
          _recordingSub = stream.listen(_recordedBytes.addAll);
        }
      }
      final nextAttemptCount = _recordAttemptCount + 1;
      if (!mounted) {
        await _recorder.stop();
        if (backingStarted) await _backingPlayer.stop();
        return;
      }
      _startRecordingTicker();
      setState(() {
        _recordAttemptCount = nextAttemptCount;
        _isRecording = true;
        _isMrRecording = hasBacking;
      });
    } catch (_) {
      unawaited(_backingPlayer.stop());
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

  Future<void> _startRecordingBacking(String backingUrl) async {
    final segmentDuration = _segmentDuration;
    _segmentStopTimer?.cancel();
    await _backingPlayer.setReleaseMode(ReleaseMode.stop);
    await _backingPlayer.setVolume(1);
    if (_primedBackingUrl == backingUrl) {
      await _backingPlayer.seek(_segmentStart);
    } else {
      await _backingPlayer.stop();
      await _backingPlayer.play(UrlSource(backingUrl), position: _segmentStart);
      _primedBackingUrl = backingUrl;
    }
    if (segmentDuration > Duration.zero) {
      _segmentStopTimer = Timer(segmentDuration, () {
        unawaited(_stopRecording());
      });
    }
  }

  Future<void> _primeRecordingBacking(String backingUrl) async {
    try {
      if (_primedBackingUrl != backingUrl) {
        await _backingPlayer.stop();
        await _backingPlayer.setReleaseMode(ReleaseMode.loop);
        await _backingPlayer.setVolume(0);
        await _backingPlayer.play(
          UrlSource(backingUrl),
          position: _segmentStart,
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
    final pcm = Uint8List(_sampleRate * _channels * 2 * durationSeconds);
    final attempt = _RelayRecordingAttempt(
      number: attemptNumber,
      bytes: _wavFromPcmBytes(
        pcm,
        sampleRate: _sampleRate,
        channels: _channels,
      ),
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
      final durationSeconds = _recordSeconds;
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
    });
    try {
      final fileName = attempt.fileName.isEmpty
          ? 'relay_${DateTime.now().millisecondsSinceEpoch}.webm'
          : attempt.fileName;
      if (widget.ref.read(localPreviewModeProvider)) {
        _completePreviewRelayAttempt(attempt, fileName);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        widget.ref.invalidate(harmonyRelaysProvider);
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(
            SnackBar(content: Text('${attempt.number}번 테이크를 올리는 흐름까지 확인했어요.')),
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
        _isListeningPrevious ||
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

  String get _currentLyricLine {
    final timelineLine = _timelineLyricAt(_absoluteLyricSeconds);
    if (timelineLine.isNotEmpty) return timelineLine;
    final direct = _cleanDisplayText(widget.lyricsLine);
    if (direct.isNotEmpty) return direct;
    final parsed = _lyricsFromText;
    if (parsed.isNotEmpty) return parsed.first;
    return _cleanDisplayText(widget.segmentLabel);
  }

  String get _nextLyricLine {
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
    final duration = _segmentDuration.inMilliseconds / 1000;
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
    final elapsed = _isRecording
        ? _recordElapsedSeconds
        : _playbackElapsedSeconds;
    return widget.segmentStartSec + elapsed;
  }

  String _timelineLyricAt(double seconds) {
    if (widget.lyricsTimeline.isEmpty) return '';
    Map<String, dynamic>? selected;
    for (final entry in widget.lyricsTimeline) {
      final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
      if (time > seconds) break;
      selected = entry;
    }
    return _cleanDisplayText(selected?['text']?.toString() ?? '');
  }

  String _nextTimelineLyricAfter(double seconds) {
    for (final entry in widget.lyricsTimeline) {
      final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
      final text = _cleanDisplayText(entry['text']?.toString() ?? '');
      if (time > seconds && text.isNotEmpty) return text;
    }
    return '';
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackStopwatch
      ..reset()
      ..start();
    if (mounted) {
      setState(() {
        _playbackElapsedSeconds = 0;
      });
    }
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      final elapsed = _playbackStopwatch.elapsedMilliseconds / 1000;
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
    required this.currentLine,
    required this.nextLine,
    required this.segmentLabel,
    required this.progress,
    required this.isActive,
    required this.statusText,
  });

  final String currentLine;
  final String nextLine;
  final String segmentLabel;
  final double progress;
  final bool isActive;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final safeCurrentLine = _cleanDisplayText(currentLine);
    final safeNextLine = _cleanDisplayText(nextLine);
    final safeSegmentLabel = _cleanDisplayText(segmentLabel);
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
                    Icon(
                      isActive
                          ? Icons.graphic_eq_rounded
                          : Icons.queue_music_rounded,
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
              Text(
                safeSegmentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  11,
                  weight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.62),
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
            child: _SingleLineLyricText(
              text: safeCurrentLine,
              key: ValueKey('current-$safeCurrentLine'),
              style: AppText.body(
                24,
                weight: FontWeight.w900,
                color: AppColors.secondaryContainer,
                height: 1.16,
              ),
              height: 32,
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
            child: _SingleLineLyricText(
              text: safeNextLine.isEmpty ? '다음 소절을 이어 받을 준비를 해요' : safeNextLine,
              key: ValueKey('next-$safeNextLine'),
              style: AppText.body(
                14,
                weight: FontWeight.w700,
                color: Colors.white.withValues(
                  alpha: safeNextLine.isEmpty ? 0.36 : 0.52,
                ),
              ),
              height: 20,
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

class _SingleLineLyricText extends StatelessWidget {
  const _SingleLineLyricText({
    super.key,
    required this.text,
    required this.style,
    required this.height,
  });

  final String text;
  final TextStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: style,
          ),
        ),
      ),
    );
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
          Icon(
            Icons.graphic_eq_rounded,
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
      final hasPermission = await _recorder.hasPermission();
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
            noiseSuppress: true,
            autoGain: true,
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
            noiseSuppress: true,
            autoGain: true,
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
