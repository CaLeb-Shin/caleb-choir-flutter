import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
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
    required this.ref,
  });

  final Map<String, dynamic> relay;
  final int order;
  final String part;
  final String partLabel;
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
    final latest = clips.isEmpty ? null : clips.last;
    final singer =
        latest?['userName']?.toString() ??
        relay['completedByName']?.toString() ??
        '';
    final status = completed
        ? (singer.isEmpty ? '완료' : singer)
        : isMyTurn
        ? '내 차례'
        : assigneeName.isEmpty
        ? '대기'
        : assigneeName;

    return Material(
      color: completed
          ? const Color(0xFFEAF5EA)
          : isMyTurn
          ? Colors.white
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openRelayStudio(context, relay, part, partLabel, ref),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: completed || isMyTurn
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
                              color: isMyTurn
                                  ? Colors.white
                                  : AppColors.secondaryContainer,
                            ),
                          ),
                  ),
                  const Spacer(),
                  Icon(
                    completed
                        ? Icons.check_circle_rounded
                        : isMyTurn
                        ? Icons.mic_rounded
                        : Icons.more_horiz_rounded,
                    size: 16,
                    color: completed || isMyTurn
                        ? (completed ? AppColors.success : AppColors.primary)
                        : Colors.white.withValues(alpha: 0.62),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                relay['segmentLabel']?.toString() ?? '$order소절',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: completed || isMyTurn
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
                  color: completed || isMyTurn
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
          lyricsLine: lyricsLine,
          nextLyricsLine: nextLyricsLine,
          lyricsText: lyricsText,
          lyricsTimeline: lyricsTimeline,
          segmentStartSec: (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
          segmentEndSec: (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
          previousClips: clips,
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

void _openRelayStudio(
  BuildContext context,
  Map<String, dynamic> relay,
  String part,
  String partLabel,
  WidgetRef ref,
) {
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
      segmentLabel: relay['segmentLabel']?.toString() ?? '소절',
      lyricsLine: relay['lyricsLine']?.toString() ?? '',
      nextLyricsLine: relay['nextLyricsLine']?.toString() ?? '',
      lyricsText: relay['lyricsText']?.toString() ?? '',
      lyricsTimeline: _lyricsTimelineFromValue(relay['lyricsTimeline']),
      segmentStartSec: (relay['segmentStartSec'] as num?)?.toDouble() ?? 0,
      segmentEndSec: (relay['segmentEndSec'] as num?)?.toDouble() ?? 0,
      previousClips: ((relay['clips'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      ref: ref,
    ),
  );
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
    final guideAudioUrl = relay['guideAudioUrl']?.toString() ?? '';
    final mrAudioUrl = relay['mrAudioUrl']?.toString() ?? '';
    final assigneeId = relay['currentAssigneeId']?.toString() ?? '';
    final assigneeName = relay['currentAssigneeName']?.toString() ?? '';
    final isMyTurn = assigneeId.isNotEmpty && assigneeId == FirebaseService.uid;
    final status = isMyTurn
        ? '내 차례'
        : assigneeName.isEmpty
        ? '대기'
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
                      color: isMyTurn
                          ? AppColors.primary
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      isMyTurn ? Icons.mic_rounded : Icons.play_arrow_rounded,
                      color: isMyTurn ? Colors.white : AppColors.primary,
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
    required this.assigneeName,
  });

  final List<Map<String, dynamic>> clips;
  final bool isMyTurn;
  final String assigneeName;

  @override
  Widget build(BuildContext context) {
    final visibleClips = clips.length > 5
        ? clips.sublist(clips.length - 5)
        : clips;
    final hiddenCount = clips.length - visibleClips.length;
    final currentCaption = isMyTurn
        ? '내 차례'
        : assigneeName.isEmpty
        ? '대기'
        : assigneeName;
    final currentStatus = isMyTurn
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
        label: isMyTurn ? 'REC' : '${clips.length + 1}',
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

class _RelayClipSheetState extends State<_RelayClipSheet> {
  final _noteController = TextEditingController();
  final _recorder = AudioRecorder();
  final _guidePlayer = AudioPlayer();
  final List<int> _recordedBytes = [];
  StreamSubscription<Uint8List>? _recordingSub;
  Timer? _recordingTimer;
  Timer? _playbackTimer;
  Timer? _segmentStopTimer;
  Uint8List? _audioBytes;
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
  int _playbackSeconds = 0;
  double _progress = 0;

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

  int get _remainingAttempts {
    final remaining = _maxRecordAttempts - _recordAttemptCount;
    return remaining < 0 ? 0 : remaining;
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
  void dispose() {
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
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
    final lyricProgress = _lyricProgress;
    final previousClipCount = _playablePreviousClips.length;
    final isBusy =
        _isSubmitting ||
        _isRecording ||
        _isGuidePlaying ||
        _isListeningPrevious ||
        _countdown != null;
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
                    ? '가이드 재생'
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
                            ? '앞소절 $previousClipCount개 후 바로 녹음'
                            : widget.guideAudioUrl.isNotEmpty
                            ? '가이드 후 바로 녹음'
                            : '녹음 기회는 3번',
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
                              onPressed: isBusy || widget.guideAudioUrl.isEmpty
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
                              onPressed: isBusy || !_hasAttemptsLeft
                                  ? null
                                  : _listenThenRecord,
                              icon: const Icon(
                                Icons.graphic_eq_rounded,
                                size: 18,
                              ),
                              label: Text(
                                previousClipCount > 0 ? '듣고 녹음' : '가이드 후 녹음',
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
                          : _isListeningPrevious
                          ? '앞소절 $_listeningClipIndex/$previousClipCount 듣는 중...'
                          : _isGuidePlaying
                          ? (_isGuidedFlow ? '보컬 가이드를 듣는 중...' : '가이드 재생 중...')
                          : _isRecording
                          ? (_isMrRecording
                                ? 'MR에 맞춰 녹음 중 ${_formatDuration(_recordSeconds)}'
                                : '녹음 중 ${_formatDuration(_recordSeconds)}')
                          : !_hasAttemptsLeft && _audioBytes == null
                          ? '3번의 기회를 모두 사용했어요'
                          : _audioBytes == null
                          ? previousClipCount > 0
                                ? '앞소절 듣고 녹음'
                                : '한 소절을 이어 받을 준비가 됐어요'
                          : '녹음 준비 완료',
                      style: AppText.body(16, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _remainingAttempts == 0
                          ? '남은 기회 없음'
                          : '남은 기회 $_remainingAttempts번',
                      style: AppText.body(12, color: AppColors.muted),
                    ),
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
                          : previousClipCount > 0
                          ? _listenThenRecord
                          : _countdownThenStartRecording,
                      icon: Icon(
                        _isRecording ? Icons.check_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _isRecording
                            ? '녹음 완료'
                            : previousClipCount > 0
                            ? '듣고 녹음'
                            : _audioBytes == null
                            ? '녹음 시작'
                            : '다시 녹음',
                      ),
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
      setState(() {
        _isGuidePlaying = true;
        _isGuidedFlow = true;
      });
      final previousClips = _playablePreviousClips;
      if (previousClips.isNotEmpty) {
        setState(() {
          _isListeningPrevious = true;
          _isGuidePlaying = false;
        });
        await _playPreviousClips(previousClips);
      } else if (widget.guideAudioUrl.isNotEmpty) {
        await _playGuideAndWait(widget.guideAudioUrl);
      }
      if (!mounted) return;
      setState(() {
        _isGuidePlaying = false;
        _isListeningPrevious = false;
        _listeningClipIndex = 0;
      });
      await _countdownThenStartRecording(
        backingUrl: widget.mrAudioUrl.isEmpty ? null : widget.mrAudioUrl,
      );
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
      _startPlaybackTimer();
      _segmentStopTimer?.cancel();
      await _guidePlayer.play(UrlSource(audioUrl), position: position);
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
        _showMessage('마이크 권한이 필요합니다.');
        return;
      }
      await _recordingSub?.cancel();
      _recordedBytes.clear();
      _streamRecording = false;
      _contentType = 'audio/webm';
      _audioFileName = 'relay_${DateTime.now().millisecondsSinceEpoch}.webm';
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
      final nextAttemptCount = _recordAttemptCount + 1;
      if (!mounted) {
        await _recorder.stop();
        return;
      }
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds += 1);
      });
      _playbackSeconds = 0;
      setState(() {
        _recordAttemptCount = nextAttemptCount;
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
      _stopPlaybackTimer();
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
            : _wavFromPcmBytes(
                pcmBytes,
                sampleRate: _sampleRate,
                channels: _channels,
              );
      }
      if (recorded.isEmpty) {
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
        _audioBytes = recorded;
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
      _showMessage(_hasAttemptsLeft ? '먼저 소절을 녹음해주세요.' : '3번의 기회를 모두 사용했어요.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _progress = 0;
    });
    try {
      final fileName = _audioFileName.isEmpty
          ? 'relay_${DateTime.now().millisecondsSinceEpoch}.webm'
          : _audioFileName;
      final audioUrl = await FirebaseService.uploadHarmonyAudio(
        bytes,
        fileName: fileName,
        contentType: _contentType,
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

  String get _currentLyricLine {
    final timelineLine = _timelineLyricAt(_absoluteLyricSeconds);
    if (timelineLine.isNotEmpty) return timelineLine;
    final direct = widget.lyricsLine.trim();
    if (direct.isNotEmpty) return direct;
    final parsed = _lyricsFromText;
    if (parsed.isNotEmpty) return parsed.first;
    return widget.segmentLabel;
  }

  String get _nextLyricLine {
    final timelineNext = _nextTimelineLyricAfter(_absoluteLyricSeconds);
    if (timelineNext.isNotEmpty) return timelineNext;
    final direct = widget.nextLyricsLine.trim();
    if (direct.isNotEmpty) return direct;
    final parsed = _lyricsFromText;
    if (parsed.length > 1) return parsed[1];
    return '';
  }

  List<String> get _lyricsFromText {
    return widget.lyricsText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  double get _lyricProgress {
    final duration = _segmentDuration.inSeconds;
    if (duration <= 0) {
      if (_isRecording || _isGuidePlaying) return 0.35;
      return 0;
    }
    final elapsed = _isRecording ? _recordSeconds : _playbackSeconds;
    return (elapsed / duration).clamp(0, 1).toDouble();
  }

  double get _absoluteLyricSeconds {
    final elapsed = _isRecording ? _recordSeconds : _playbackSeconds;
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
    return selected?['text']?.toString().trim() ?? '';
  }

  String _nextTimelineLyricAfter(double seconds) {
    for (final entry in widget.lyricsTimeline) {
      final time = (entry['timeSec'] as num?)?.toDouble() ?? 0;
      final text = entry['text']?.toString().trim() ?? '';
      if (time > seconds && text.isNotEmpty) return text;
    }
    return '';
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    if (mounted) setState(() => _playbackSeconds = 0);
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _playbackSeconds += 1);
    });
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
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
                segmentLabel,
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
          Text(
            currentLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              24,
              weight: FontWeight.w900,
              color: AppColors.secondaryContainer,
              height: 1.16,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            nextLine.isEmpty ? '다음 소절을 이어 받을 준비를 해요' : nextLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              14,
              weight: FontWeight.w700,
              color: Colors.white.withValues(
                alpha: nextLine.isEmpty ? 0.46 : 0.7,
              ),
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
          'text': entry['text']?.toString() ?? '',
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
