import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../models/user.dart' show User;
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';

const _seatingPartOrder = ['bass', 'alto', 'soprano', 'tenor'];
const _seatingRows = 10;
const _seatingCols = 4;

class SeatingScreen extends ConsumerStatefulWidget {
  final String? initialChartId;
  final Map<String, dynamic>? initialChart;

  const SeatingScreen({super.key, this.initialChartId, this.initialChart});

  @override
  ConsumerState<SeatingScreen> createState() => _SeatingScreenState();
}

class _SeatingScreenState extends ConsumerState<SeatingScreen> {
  String? _selectedChartId;
  Map<String, dynamic>? _selectedChart;
  String? _visiblePart;
  Map<String, dynamic>? _selectedCandidate;
  bool _editing = false;
  bool _focusMySeatOnOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedChartId = widget.initialChartId;
    _selectedChart = widget.initialChart;
    _focusMySeatOnOpen = widget.initialChartId != null;
  }

  @override
  Widget build(BuildContext context) {
    final chartsAsync = ref.watch(seatingChartsProvider);
    ref.watch(pollsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final isAdmin = ref.watch(effectiveIsAdminProvider);

    if (_selectedChartId != null) {
      return _chartDetail(context, profile, isAdmin);
    }

    return Scaffold(
      appBar: AppBar(
        title: AppLogoTitle(title: '배치판', textStyle: AppText.headline(20)),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _showCreateDialog(context),
            ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(),
      body: chartsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (charts) {
          if (charts.isEmpty) {
            return Center(
              child: Text(
                '아직 배치판이 없습니다',
                style: AppText.body(14, color: AppColors.muted),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: charts.length,
            itemBuilder: (_, i) {
              final c = charts[i];
              final published = c['isPublished'] == true;
              return _SeatingChartCard(
                chart: c,
                published: published,
                isAdmin: isAdmin,
                onTap: () => setState(() {
                  _selectedChartId = c['id'];
                  _selectedChart = c;
                  _focusMySeatOnOpen = true;
                }),
                onAction: (v) => _handleChartAction(v, c),
              );
            },
          );
        },
      ),
    );
  }

  Widget _chartDetail(BuildContext context, User? profile, bool isAdmin) {
    final chart = _selectedChart ?? const <String, dynamic>{};
    final sourcePollId = chart['sourcePollId'] as String?;
    final assignmentsAsync = ref.watch(
      seatAssignmentsProvider(_selectedChartId!),
    );
    ref.watch(seatingPresetsProvider);
    final membersAsync = ref.watch(membersProvider);
    final pollVotesAsync = sourcePollId == null
        ? const AsyncValue<List<Map<String, dynamic>>>.data([])
        : ref.watch(pollVotesProvider(sourcePollId));
    final canEdit = isAdmin || (profile?.isPartLeader ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            _selectedChartId = null;
            _selectedChart = null;
            _visiblePart = null;
            _selectedCandidate = null;
            _editing = false;
            _focusMySeatOnOpen = false;
          }),
        ),
        title: AppLogoTitle(title: '배치판', textStyle: AppText.headline(18)),
        actions: [
          if (canEdit)
            TextButton(
              onPressed: () => setState(() {
                _editing = !_editing;
                _selectedCandidate = null;
                _visiblePart ??= profile?.partLeaderFor ?? profile?.part;
              }),
              child: Text(
                _editing ? '완료' : '편집',
                style: TextStyle(
                  color: _editing ? AppColors.secondary : AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(),
      body: assignmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (assignments) {
          final members = membersAsync.valueOrNull ?? [];
          final votes = pollVotesAsync.valueOrNull ?? [];
          final candidates = _attendingCandidates(
            sourcePollId: sourcePollId,
            votes: votes,
            members: members,
          );
          final mySeat = assignments
              .where((a) => a['userId'] == profile?.id)
              .firstOrNull;
          if (_focusMySeatOnOpen && mySeat != null && !_editing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_focusMySeatOnOpen) return;
              setState(() {
                _visiblePart = mySeat['part']?.toString();
                _focusMySeatOnOpen = false;
              });
            });
          }
          final assignmentCounts = {
            for (final part in _seatingPartOrder)
              part: assignments.where((a) => a['part'] == part).length,
          };

          final panelPart = _editing ? _visiblePart : null;
          final panelCanEdit =
              panelPart != null &&
              (isAdmin || profile?.canActOnPart(panelPart) == true);
          final seatedIds = assignments
              .map((assignment) => assignment['userId'])
              .toSet();
          final panelCandidates = panelPart == null
              ? const <Map<String, dynamic>>[]
              : candidates
                    .where(
                      (member) =>
                          member['part'] == panelPart &&
                          !seatedIds.contains(member['id']),
                    )
                    .toList();

          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  panelCanEdit ? 188 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChartSummaryHeader(chart: chart),
                    const SizedBox(height: 12),
                    if (mySeat != null && !_editing)
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.secondarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_pin_circle_rounded,
                              color: AppColors.secondary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '내 자리: ${User.partLabels[mySeat['part']] ?? ''} ${(mySeat['row'] as int) + 1}열 ${(mySeat['col'] as int) + 1}번',
                              style: AppText.body(
                                14,
                                weight: FontWeight.w800,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (canEdit)
                      _PresetActionBar(
                        onSave: () => _savePreset(assignments),
                        onLoad: () => _showPresetPicker(candidates),
                      ),
                    if (canEdit) const SizedBox(height: 12),
                    _PartViewSelector(
                      selectedPart: _visiblePart,
                      counts: assignmentCounts,
                      onSelected: (part) => setState(() {
                        _visiblePart = part;
                        _selectedCandidate = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _visiblePart == null
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _seatingPartOrder.map((part) {
                                final partAssignments = assignments
                                    .where((a) => a['part'] == part)
                                    .toList();
                                final canEditPart =
                                    _editing &&
                                    (isAdmin ||
                                        profile?.canActOnPart(part) == true);
                                return _partColumn(
                                  context,
                                  part,
                                  partAssignments,
                                  profile,
                                  canEditPart,
                                  candidates,
                                  assignments,
                                  sourcePollId != null,
                                  spotlightMySeat: !_editing,
                                );
                              }).toList(),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final part = _visiblePart!;
                              final partAssignments = assignments
                                  .where((a) => a['part'] == part)
                                  .toList();
                              final canEditPart =
                                  _editing &&
                                  (isAdmin ||
                                      profile?.canActOnPart(part) == true);
                              return _partColumn(
                                context,
                                part,
                                partAssignments,
                                profile,
                                canEditPart,
                                candidates,
                                assignments,
                                sourcePollId != null,
                                columnWidth: constraints.maxWidth,
                                cellHeight: 54,
                                addRightPadding: false,
                                spotlightMySeat: !_editing,
                              );
                            },
                          ),
                    if (_editing)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          isAdmin
                              ? '파트를 누른 뒤 참석자를 선택하거나 좌석으로 드래그하세요'
                              : '${User.partLabels[profile?.partLeaderFor] ?? ""} 파트 참석자를 선택하거나 좌석으로 드래그하세요',
                          style: AppText.body(12, color: AppColors.muted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              if (panelCanEdit)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PartAttendeePanel(
                    part: panelPart,
                    candidates: panelCandidates,
                    selectedUserId: _selectedCandidate?['id']?.toString(),
                    usesAttendancePoll: sourcePollId != null,
                    onSelected: (member) =>
                        setState(() => _selectedCandidate = member),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _partColumn(
    BuildContext context,
    String part,
    List<Map<String, dynamic>> assignments,
    User? profile,
    bool canEdit,
    List<Map<String, dynamic>> candidates,
    List<Map<String, dynamic>> allAssignments,
    bool usesAttendancePoll, {
    double? columnWidth,
    double cellHeight = 42,
    bool addRightPadding = true,
    bool spotlightMySeat = false,
  }) {
    final count = assignments.length;
    const gap = 6.0;
    const boardPadding = 8.0;
    final effectiveWidth = columnWidth ?? _seatingCols * 76.0 + 18;
    final cellWidth =
        (effectiveWidth - boardPadding * 2 - gap * (_seatingCols - 1)) /
        _seatingCols;
    return Padding(
      padding: EdgeInsets.only(right: addRightPadding ? 12 : 0),
      child: Column(
        children: [
          Container(
            width: effectiveWidth,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  User.partLabels[part] ?? part,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '$count명',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: effectiveWidth,
            padding: const EdgeInsets.all(boardPadding),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: List.generate(_seatingRows, (r) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: r < _seatingRows - 1 ? 6 : 0,
                  ),
                  child: Row(
                    children: List.generate(_seatingCols, (c) {
                      final a = assignments
                          .where((a) => a['row'] == r && a['col'] == c)
                          .firstOrNull;
                      final isSelf = a != null && a['userId'] == profile?.id;
                      return Padding(
                        padding: EdgeInsets.only(
                          right: c < _seatingCols - 1 ? gap : 0,
                        ),
                        child: DragTarget<Map<String, dynamic>>(
                          onWillAcceptWithDetails: (details) {
                            final memberPart = details.data['part'];
                            return canEdit && memberPart == part;
                          },
                          onAcceptWithDetails: (details) =>
                              _assignCandidateToSeat(
                                part: part,
                                row: r,
                                col: c,
                                member: details.data,
                              ),
                          builder: (context, incoming, rejected) {
                            final hovering = incoming.isNotEmpty;
                            return GestureDetector(
                              onTap: canEdit
                                  ? () => _handleSeatTap(
                                      context,
                                      part,
                                      r,
                                      c,
                                      a,
                                      candidates,
                                      allAssignments,
                                      usesAttendancePoll,
                                    )
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                width: cellWidth,
                                height: cellHeight,
                                decoration: BoxDecoration(
                                  color: hovering
                                      ? AppColors.secondarySoft
                                      : isSelf
                                      ? AppColors.secondary
                                      : a != null
                                      ? AppColors.primaryContainer.withValues(
                                          alpha: 0.1,
                                        )
                                      : AppColors.card,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: hovering
                                        ? AppColors.secondary
                                        : isSelf
                                        ? AppColors.secondary
                                        : a != null
                                        ? AppColors.primaryContainer.withValues(
                                            alpha: 0.3,
                                          )
                                        : AppColors.border.withValues(
                                            alpha: 0.3,
                                          ),
                                    width: hovering || isSelf ? 2 : 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: a != null
                                    ? isSelf && spotlightMySeat
                                          ? _ShakingSeatName(
                                              text: a['userName'] ?? '-',
                                              fontSize: 11,
                                            )
                                          : Text(
                                              a['userName'] ?? '-',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: isSelf
                                                    ? Colors.white
                                                    : AppColors.primary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            )
                                    : Text(
                                        _selectedCandidate?['part'] == part
                                            ? '탭'
                                            : '-',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              _selectedCandidate?['part'] ==
                                                  part
                                              ? FontWeight.w800
                                              : FontWeight.w400,
                                          color:
                                              _selectedCandidate?['part'] ==
                                                  part
                                              ? AppColors.secondary
                                              : AppColors.muted,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _attendingCandidates({
    required String? sourcePollId,
    required List<Map<String, dynamic>> votes,
    required List<Map<String, dynamic>> members,
  }) {
    if (sourcePollId == null) return _sortCandidates(members);

    final memberById = {
      for (final member in members)
        if (member['id'] != null) member['id'].toString(): member,
    };
    final seen = <String>{};
    final candidates = <Map<String, dynamic>>[];

    for (final vote in votes) {
      if (vote['choice'] != 'attend') continue;
      final userId = vote['userId']?.toString();
      if (userId == null || userId.isEmpty || !seen.add(userId)) continue;
      final member = memberById[userId];
      candidates.add({
        ...?member,
        'id': userId,
        'name': member?['name'] ?? vote['userName'] ?? '',
        'part': member?['part'] ?? vote['userPart'] ?? '',
        'generation': member?['generation'] ?? '',
      });
    }

    return _sortCandidates(candidates);
  }

  List<Map<String, dynamic>> _sortCandidates(
    List<Map<String, dynamic>> candidates,
  ) {
    final sorted = [...candidates];
    sorted.sort((a, b) {
      final partA = _seatingPartOrder.indexOf(a['part']?.toString() ?? '');
      final partB = _seatingPartOrder.indexOf(b['part']?.toString() ?? '');
      final normalizedA = partA == -1 ? 99 : partA;
      final normalizedB = partB == -1 ? 99 : partB;
      final partCompare = normalizedA.compareTo(normalizedB);
      if (partCompare != 0) return partCompare;
      return (a['name']?.toString() ?? '').compareTo(
        b['name']?.toString() ?? '',
      );
    });
    return sorted;
  }

  void _handleSeatTap(
    BuildContext context,
    String part,
    int row,
    int col,
    Map<String, dynamic>? current,
    List<Map<String, dynamic>> candidates,
    List<Map<String, dynamic>> allAssignments,
    bool usesAttendancePoll,
  ) {
    final selected = _selectedCandidate;
    if (current == null && selected != null && selected['part'] == part) {
      _assignCandidateToSeat(part: part, row: row, col: col, member: selected);
      return;
    }

    final seatedIds = allAssignments.map((a) => a['userId']).toSet();
    final availableCandidates = candidates
        .where((m) => m['part'] == part && !seatedIds.contains(m['id']))
        .toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${User.partLabels[part] ?? part} ${row + 1}열 ${col + 1}번',
              style: AppText.headline(18),
            ),
            const SizedBox(height: 12),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.person, color: AppColors.primary),
                title: Text(
                  current['userName'] ?? '',
                  style: AppText.body(15, weight: FontWeight.w700),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    if (ref.read(localPreviewModeProvider)) {
                      _clearPreviewSeat(
                        chartId: _selectedChartId!,
                        part: part,
                        row: row,
                        col: col,
                      );
                      Navigator.pop(ctx);
                      return;
                    }
                    await FirebaseService.clearSeat(
                      chartId: _selectedChartId!,
                      part: part,
                      row: row,
                      col: col,
                    );
                    ref.invalidate(seatAssignmentsProvider(_selectedChartId!));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('해제', style: TextStyle(color: Colors.red)),
                ),
              ),
            const Divider(),
            Text(
              '배정 가능',
              style: AppText.body(
                12,
                weight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            Expanded(
              child: availableCandidates.isEmpty
                  ? Center(
                      child: Text(
                        usesAttendancePoll
                            ? '참석 투표에서 참석한 미배치 단원이 없습니다'
                            : '배정 가능한 단원이 없습니다',
                        style: AppText.body(13, color: AppColors.muted),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: availableCandidates.length,
                      itemBuilder: (_, i) {
                        final m = availableCandidates[i];
                        return ListTile(
                          title: Text(
                            m['name'] ?? '',
                            style: AppText.body(14, weight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${m['generation'] ?? ''}',
                            style: AppText.body(11, color: AppColors.muted),
                          ),
                          onTap: () async {
                            await _assignCandidateToSeat(
                              part: part,
                              row: row,
                              col: col,
                              member: m,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignCandidateToSeat({
    required String part,
    required int row,
    required int col,
    required Map<String, dynamic> member,
  }) async {
    if (ref.read(localPreviewModeProvider)) {
      _assignPreviewSeat(
        chartId: _selectedChartId!,
        part: part,
        row: row,
        col: col,
        member: member,
      );
    } else {
      await FirebaseService.assignSeat(
        chartId: _selectedChartId!,
        part: part,
        row: row,
        col: col,
        userId: member['id'].toString(),
      );
      ref.invalidate(seatAssignmentsProvider(_selectedChartId!));
    }
    if (mounted) {
      setState(() => _selectedCandidate = null);
    }
  }

  void _assignPreviewSeat({
    required String chartId,
    required String part,
    required int row,
    required int col,
    required Map<String, dynamic> member,
  }) {
    final current = ref.read(previewSeatAssignmentsProvider);
    final userId = member['id']?.toString() ?? '';
    ref.read(previewSeatAssignmentsProvider.notifier).state = [
      for (final seat in current)
        if (!(seat['chartId'] == chartId && seat['userId'] == userId) &&
            !(seat['chartId'] == chartId &&
                seat['part'] == part &&
                seat['row'] == row &&
                seat['col'] == col))
          seat,
      {
        'id': 'preview-seat-${DateTime.now().microsecondsSinceEpoch}',
        'chartId': chartId,
        'part': part,
        'row': row,
        'col': col,
        'userId': userId,
        'userName': member['name'] ?? '',
        'userGeneration': member['generation'] ?? '',
      },
    ];
  }

  void _clearPreviewSeat({
    required String chartId,
    required String part,
    required int row,
    required int col,
  }) {
    ref.read(previewSeatAssignmentsProvider.notifier).state = [
      for (final seat in ref.read(previewSeatAssignmentsProvider))
        if (!(seat['chartId'] == chartId &&
            seat['part'] == part &&
            seat['row'] == row &&
            seat['col'] == col))
          seat,
    ];
  }

  Future<void> _savePreset(List<Map<String, dynamic>> assignments) async {
    final labelCtrl = TextEditingController(
      text: '${_selectedChart?['label'] ?? '배치'} 프리셋',
    );
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('프리셋 저장'),
        content: TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(
            labelText: '프리셋 이름',
            hintText: '예: 주일 1부 기본 배치',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    labelCtrl.dispose();
    if (label == null || label.isEmpty) return;

    if (ref.read(localPreviewModeProvider)) {
      final preset = {
        'id': 'preview-preset-${DateTime.now().microsecondsSinceEpoch}',
        'label': label,
        'assignments': assignments
            .map(
              (seat) => {
                'part': seat['part'],
                'row': seat['row'],
                'col': seat['col'],
                'userId': seat['userId'],
              },
            )
            .toList(),
      };
      ref.read(previewSeatingPresetsProvider.notifier).state = [
        preset,
        ...ref.read(previewSeatingPresetsProvider),
      ];
    } else {
      await FirebaseService.saveSeatingPreset(
        label: label,
        assignments: assignments,
      );
      ref.invalidate(seatingPresetsProvider);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('프리셋을 저장했습니다')));
  }

  void _showPresetPicker(List<Map<String, dynamic>> candidates) {
    final presets = ref.read(seatingPresetsProvider).valueOrNull ?? [];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('프리셋 불러오기', style: AppText.headline(18)),
              const SizedBox(height: 6),
              Text(
                '현재 참석한 단원만 같은 자리에 복원되고, 불참자는 빈칸으로 둡니다.',
                style: AppText.body(12, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              if (presets.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '아직 저장된 프리셋이 없습니다',
                    style: AppText.body(13, color: AppColors.muted),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: presets.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final preset = presets[i];
                      final assignments =
                          (preset['assignments'] as List<dynamic>? ?? []);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.bookmark_added_rounded,
                          color: AppColors.secondary,
                        ),
                        title: Text(
                          preset['label']?.toString() ?? '이름 없는 프리셋',
                          style: AppText.body(14, weight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${assignments.length}명 배치 저장됨',
                          style: AppText.body(11, color: AppColors.muted),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _applyPreset(preset, candidates);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyPreset(
    Map<String, dynamic> preset,
    List<Map<String, dynamic>> candidates,
  ) async {
    final attendingIds = candidates
        .map((member) => member['id']?.toString())
        .whereType<String>()
        .toSet();

    if (ref.read(localPreviewModeProvider)) {
      final memberById = {
        for (final member in candidates)
          if (member['id'] != null) member['id'].toString(): member,
      };
      final presetAssignments = (preset['assignments'] as List<dynamic>? ?? [])
          .whereType<Map>();
      final restored = <Map<String, dynamic>>[];
      for (final seat in presetAssignments) {
        final userId = seat['userId']?.toString();
        if (userId == null || !attendingIds.contains(userId)) continue;
        final member = memberById[userId];
        restored.add({
          'id':
              'preview-seat-${DateTime.now().microsecondsSinceEpoch}-${restored.length}',
          'chartId': _selectedChartId!,
          'part': seat['part'],
          'row': seat['row'],
          'col': seat['col'],
          'userId': userId,
          'userName': member?['name'] ?? '',
          'userGeneration': member?['generation'] ?? '',
        });
      }
      ref.read(previewSeatAssignmentsProvider.notifier).state = [
        for (final seat in ref.read(previewSeatAssignmentsProvider))
          if (seat['chartId'] != _selectedChartId) seat,
        ...restored,
      ];
    } else {
      await FirebaseService.applySeatingPreset(
        chartId: _selectedChartId!,
        presetId: preset['id'].toString(),
        attendingUserIds: attendingIds,
      );
      ref.invalidate(seatAssignmentsProvider(_selectedChartId!));
    }

    if (!mounted) return;
    setState(() => _selectedCandidate = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('프리셋을 불러왔습니다')));
  }

  void _handleChartAction(String action, Map<String, dynamic> chart) async {
    if (ref.read(localPreviewModeProvider)) {
      await _handlePreviewChartAction(action, chart);
      return;
    }
    if (action == 'toggle') {
      await FirebaseService.publishSeatingChart(
        chart['id'],
        !(chart['isPublished'] == true),
      );
      ref.invalidate(seatingChartsProvider);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('배치판 삭제'),
          content: Text('"${chart['label']}"을(를) 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await FirebaseService.deleteSeatingChart(chart['id']);
        ref.invalidate(seatingChartsProvider);
      }
    }
  }

  Future<void> _handlePreviewChartAction(
    String action,
    Map<String, dynamic> chart,
  ) async {
    final chartId = chart['id']?.toString();
    if (chartId == null) return;
    if (action == 'toggle') {
      ref.read(previewSeatingChartsProvider.notifier).state = [
        for (final item in ref.read(previewSeatingChartsProvider))
          if (item['id'] == chartId)
            {...item, 'isPublished': !(item['isPublished'] == true)}
          else
            item,
      ];
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('배치판 삭제'),
          content: Text('"${chart['label']}"을(를) 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        ref.read(previewSeatingChartsProvider.notifier).state = [
          for (final item in ref.read(previewSeatingChartsProvider))
            if (item['id'] != chartId) item,
        ];
        ref.read(previewSeatAssignmentsProvider.notifier).state = [
          for (final seat in ref.read(previewSeatAssignmentsProvider))
            if (seat['chartId'] != chartId) seat,
        ];
      }
    }
  }

  void _showCreateDialog(BuildContext context) {
    final labelCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().split('T')[0],
    );
    final polls = ref.read(pollsProvider).valueOrNull ?? [];
    String? selectedPollId = _defaultPollId(polls);
    void syncSelectedPoll() {
      final poll = _pollById(polls, selectedPollId);
      if (poll == null) return;
      labelCtrl.text = poll['title']?.toString() ?? labelCtrl.text;
      dateCtrl.text = poll['targetDate']?.toString() ?? dateCtrl.text;
    }

    syncSelectedPoll();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('새 배치판'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  key: ValueKey(selectedPollId ?? 'none'),
                  initialValue: selectedPollId,
                  decoration: const InputDecoration(
                    labelText: '참석 투표 연결',
                    helperText: '참석으로 투표한 단원만 배치 후보에 표시됩니다',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('투표 연결 없이 만들기'),
                    ),
                    ...polls.map(
                      (poll) => DropdownMenuItem<String?>(
                        value: poll['id']?.toString(),
                        child: Text(poll['title']?.toString() ?? '제목 없음'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedPollId = value;
                      syncSelectedPoll();
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '예: 주일예배',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: '날짜 (YYYY-MM-DD)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                if (labelCtrl.text.trim().isEmpty) return;
                final selectedPoll = _pollById(polls, selectedPollId);
                if (ref.read(localPreviewModeProvider)) {
                  final chartId =
                      'preview-chart-${DateTime.now().microsecondsSinceEpoch}';
                  ref.read(previewSeatingChartsProvider.notifier).state = [
                    ...ref.read(previewSeatingChartsProvider),
                    {
                      'id': chartId,
                      'label': labelCtrl.text.trim(),
                      'eventDate': dateCtrl.text.trim(),
                      'sourcePollId': selectedPollId,
                      'sourcePollTitle': selectedPoll?['title']?.toString(),
                      'isPublished': false,
                    },
                  ];
                  Navigator.pop(ctx);
                  return;
                }
                await FirebaseService.createSeatingChart(
                  label: labelCtrl.text.trim(),
                  eventDate: dateCtrl.text.trim(),
                  sourcePollId: selectedPollId,
                  sourcePollTitle: selectedPoll?['title']?.toString(),
                );
                ref.invalidate(seatingChartsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('생성'),
            ),
          ],
        ),
      ),
    );
  }

  String? _defaultPollId(List<Map<String, dynamic>> polls) {
    if (polls.isEmpty) return null;
    final openPolls = polls.where((poll) => poll['isOpen'] == true);
    return (openPolls.isEmpty ? polls.first : openPolls.first)['id']
        ?.toString();
  }

  Map<String, dynamic>? _pollById(
    List<Map<String, dynamic>> polls,
    String? pollId,
  ) {
    if (pollId == null) return null;
    for (final poll in polls) {
      if (poll['id']?.toString() == pollId) return poll;
    }
    return null;
  }
}

String _chartDateLabel(Map<String, dynamic> chart) {
  final raw = chart['eventDate']?.toString().trim() ?? '';
  if (raw.isEmpty) return '날짜 미정';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
}

String _chartTitle(Map<String, dynamic> chart) {
  final sourceTitle = chart['sourcePollTitle']?.toString().trim() ?? '';
  final label = chart['label']?.toString().trim() ?? '';
  return sourceTitle.isNotEmpty ? sourceTitle : label;
}

String _chartBoardLabel(Map<String, dynamic> chart) {
  final label = chart['label']?.toString().trim() ?? '';
  return label.isEmpty ? '자리배치판' : label;
}

class _SeatingChartCard extends StatelessWidget {
  final Map<String, dynamic> chart;
  final bool published;
  final bool isAdmin;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  const _SeatingChartCard({
    required this.chart,
    required this.published,
    required this.isAdmin,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = _chartDateLabel(chart);
    final title = _chartTitle(chart);
    final boardLabel = _chartBoardLabel(chart);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.22)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.event_seat_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: AppText.body(
                        17,
                        weight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title.isEmpty ? boardLabel : title,
                      style: AppText.body(15, weight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      boardLabel,
                      style: AppText.body(12, color: AppColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (published ? AppColors.success : AppColors.muted)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      published ? '공개' : '비공개',
                      style: AppText.body(
                        11,
                        weight: FontWeight.w900,
                        color: published ? AppColors.success : AppColors.muted,
                      ),
                    ),
                  ),
                  if (isAdmin)
                    PopupMenuButton<String>(
                      onSelected: onAction,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(published ? '비공개로 전환' : '공개하기'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            '삭제',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 10, right: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartSummaryHeader extends StatelessWidget {
  final Map<String, dynamic> chart;
  const _ChartSummaryHeader({required this.chart});

  @override
  Widget build(BuildContext context) {
    final dateLabel = _chartDateLabel(chart);
    final title = _chartTitle(chart);
    final boardLabel = _chartBoardLabel(chart);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.grid_view_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: AppText.body(
                    18,
                    weight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title.isEmpty ? boardLabel : title,
                  style: AppText.body(14, weight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  boardLabel,
                  style: AppText.body(12, color: AppColors.muted),
                  maxLines: 1,
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

class _ShakingSeatName extends StatefulWidget {
  final String text;
  final double fontSize;

  const _ShakingSeatName({required this.text, required this.fontSize});

  @override
  State<_ShakingSeatName> createState() => _ShakingSeatNameState();
}

class _ShakingSeatNameState extends State<_ShakingSeatName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
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
      builder: (context, child) {
        final fadeOut = _controller.value < 0.82
            ? 1.0
            : (1 - ((_controller.value - 0.82) / 0.18)).clamp(0.0, 1.0);
        final dx = math.sin(_controller.value * math.pi * 36) * 3.5 * fadeOut;
        final scale = 1 + 0.05 * fadeOut;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Text(
        widget.text,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _PresetActionBar extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onLoad;
  const _PresetActionBar({required this.onSave, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_add_rounded, size: 18),
              label: const Text('프리셋 저장'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('불러오기'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartAttendeePanel extends StatelessWidget {
  final String part;
  final List<Map<String, dynamic>> candidates;
  final String? selectedUserId;
  final bool usesAttendancePoll;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _PartAttendeePanel({
    required this.part,
    required this.candidates,
    required this.selectedUserId,
    required this.usesAttendancePoll,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, -8),
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
                decoration: BoxDecoration(
                  color: AppColors.subtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${User.partLabels[part] ?? part} 참석자',
                    style: AppText.body(15, weight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '미배치 ${candidates.length}명',
                    style: AppText.body(
                      11,
                      weight: FontWeight.w900,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              usesAttendancePoll
                  ? '참석 투표한 단원만 보여요. 탭해서 선택하거나 좌석으로 드래그하세요.'
                  : '탭해서 선택하거나 좌석으로 드래그하세요.',
              style: AppText.body(11, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: candidates.isEmpty
                  ? Center(
                      child: Text(
                        usesAttendancePoll
                            ? '이 파트의 미배치 참석자가 없습니다'
                            : '배치할 단원이 없습니다',
                        style: AppText.body(13, color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: candidates.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final member = candidates[i];
                        final selected =
                            selectedUserId == member['id']?.toString();
                        return Draggable<Map<String, dynamic>>(
                          data: member,
                          feedback: Material(
                            color: Colors.transparent,
                            child: _AttendeePill(
                              member: member,
                              selected: true,
                              compact: false,
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: _AttendeePill(
                              member: member,
                              selected: selected,
                              compact: false,
                            ),
                          ),
                          child: GestureDetector(
                            onTap: () => onSelected(member),
                            child: _AttendeePill(
                              member: member,
                              selected: selected,
                              compact: false,
                            ),
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

class _AttendeePill extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool selected;
  final bool compact;
  const _AttendeePill({
    required this.member,
    required this.selected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: compact ? 112 : 126,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryContainer : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? AppColors.secondaryContainer
              : AppColors.border.withValues(alpha: 0.35),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            member['name']?.toString() ?? '',
            style: AppText.body(
              13,
              weight: FontWeight.w900,
              color: selected ? Colors.white : AppColors.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            member['generation']?.toString() ?? '',
            style: AppText.body(
              10,
              color: selected
                  ? Colors.white.withValues(alpha: 0.68)
                  : AppColors.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PartViewSelector extends StatelessWidget {
  final String? selectedPart;
  final Map<String, int> counts;
  final ValueChanged<String?> onSelected;

  const _PartViewSelector({
    required this.selectedPart,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        label: '전체',
        count: counts.values.fold<int>(0, (total, count) => total + count),
        part: null,
      ),
      for (final part in _seatingPartOrder)
        (
          label: User.partLabels[part] ?? part,
          count: counts[part] ?? 0,
          part: part,
        ),
    ];

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(
                child: _PartFilterChip(
                  label: items[i].label,
                  count: items[i].count,
                  active: selectedPart == items[i].part,
                  onTap: () => onSelected(items[i].part),
                ),
              ),
              if (i < 2) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 3; i < items.length; i++) ...[
              Expanded(
                child: _PartFilterChip(
                  label: items[i].label,
                  count: items[i].count,
                  active: selectedPart == items[i].part,
                  onTap: () => onSelected(items[i].part),
                ),
              ),
              if (i < items.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _PartFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _PartFilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryContainer : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? AppColors.primaryContainer
                : AppColors.border.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.body(
                  13,
                  weight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: AppText.body(
                  11,
                  weight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
