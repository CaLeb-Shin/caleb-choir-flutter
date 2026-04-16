import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../models/user.dart' show User;

const _seatingPartOrder = ['bass', 'alto', 'soprano', 'tenor'];
const _seatingRows = 10;
const _seatingCols = 4;

class SeatingScreen extends ConsumerStatefulWidget {
  const SeatingScreen({super.key});
  @override
  ConsumerState<SeatingScreen> createState() => _SeatingScreenState();
}

class _SeatingScreenState extends ConsumerState<SeatingScreen> {
  String? _selectedChartId;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final chartsAsync = ref.watch(seatingChartsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final isAdmin = ref.watch(effectiveIsAdminProvider);

    if (_selectedChartId != null) {
      return _chartDetail(context, profile, isAdmin);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('배치판', style: AppText.headline(20)),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _showCreateDialog(context),
            ),
        ],
      ),
      body: chartsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (charts) {
          if (charts.isEmpty) {
            return Center(child: Text('아직 배치판이 없습니다', style: AppText.body(14, color: AppColors.muted)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: charts.length,
            itemBuilder: (_, i) {
              final c = charts[i];
              final published = c['isPublished'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  onTap: () => setState(() => _selectedChartId = c['id']),
                  leading: Icon(Icons.grid_view_rounded,
                      color: published ? AppColors.success : AppColors.muted),
                  title: Text(c['label'] ?? '', style: AppText.body(16, weight: FontWeight.w800)),
                  subtitle: Text(c['eventDate'] ?? '', style: AppText.body(12, color: AppColors.muted)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (published ? AppColors.success : AppColors.muted).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(published ? '공개' : '비공개',
                          style: AppText.body(11, weight: FontWeight.w800,
                              color: published ? AppColors.success : AppColors.muted)),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (v) => _handleChartAction(v, c),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'toggle', child: Text(published ? '비공개로 전환' : '공개하기')),
                          const PopupMenuItem(value: 'delete', child: Text('삭제', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _chartDetail(BuildContext context, User? profile, bool isAdmin) {
    final assignmentsAsync = ref.watch(seatAssignmentsProvider(_selectedChartId!));
    final membersAsync = ref.watch(membersProvider);
    final canEdit = isAdmin || (profile?.isPartLeader ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() { _selectedChartId = null; _editing = false; }),
        ),
        title: Text('배치판', style: AppText.headline(18)),
        actions: [
          if (canEdit)
            TextButton(
              onPressed: () => setState(() => _editing = !_editing),
              child: Text(_editing ? '완료' : '편집',
                  style: TextStyle(color: _editing ? AppColors.secondary : AppColors.primary, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
      body: assignmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (assignments) {
          final mySeat = assignments.where((a) => a['userId'] == profile?.id).firstOrNull;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (mySeat != null && !_editing)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_pin_circle_rounded, color: AppColors.secondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '내 자리: ${User.partLabels[mySeat['part']] ?? ''} ${(mySeat['row'] as int) + 1}열 ${(mySeat['col'] as int) + 1}번',
                      style: AppText.body(14, weight: FontWeight.w800, color: AppColors.secondary),
                    ),
                  ]),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _seatingPartOrder.map((part) {
                    final partAssignments = assignments.where((a) => a['part'] == part).toList();
                    final canEditPart = _editing && (isAdmin || profile?.canActOnPart(part) == true);
                    return _partColumn(context, part, partAssignments, profile, canEditPart, membersAsync.valueOrNull ?? [], assignments);
                  }).toList(),
                ),
              ),
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    isAdmin ? '빈 자리를 탭하여 배치하세요' :
                        '${User.partLabels[profile?.partLeaderFor] ?? ""} 파트의 빈 자리를 탭하세요',
                    style: AppText.body(12, color: AppColors.muted),
                    textAlign: TextAlign.center,
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  Widget _partColumn(BuildContext context, String part,
      List<Map<String, dynamic>> assignments, User? profile,
      bool canEdit, List<Map<String, dynamic>> allMembers,
      List<Map<String, dynamic>> allAssignments) {
    final count = assignments.length;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(children: [
        Container(
          width: _seatingCols * 76.0 + 18,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(User.partLabels[part] ?? part, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            Text('$count명', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: List.generate(_seatingRows, (r) {
            return Padding(
              padding: EdgeInsets.only(bottom: r < _seatingRows - 1 ? 6 : 0),
              child: Row(children: List.generate(_seatingCols, (c) {
                final a = assignments.where((a) => a['row'] == r && a['col'] == c).firstOrNull;
                final isSelf = a != null && a['userId'] == profile?.id;
                return Padding(
                  padding: EdgeInsets.only(right: c < _seatingCols - 1 ? 6 : 0),
                  child: GestureDetector(
                    onTap: canEdit ? () => _handleSeatTap(context, part, r, c, a, allMembers, allAssignments) : null,
                    child: Container(
                      width: 70, height: 42,
                      decoration: BoxDecoration(
                        color: isSelf ? AppColors.secondary :
                            a != null ? AppColors.primaryContainer.withValues(alpha: 0.1) : AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelf ? AppColors.secondary :
                              a != null ? AppColors.primaryContainer.withValues(alpha: 0.3) :
                              AppColors.border.withValues(alpha: 0.3),
                          width: isSelf ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: a != null
                          ? Text(a['userName'] ?? '-',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: isSelf ? Colors.white : AppColors.primary),
                              overflow: TextOverflow.ellipsis)
                          : Text('-', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ),
                  ),
                );
              })),
            );
          })),
        ),
      ]),
    );
  }

  void _handleSeatTap(BuildContext context, String part, int row, int col,
      Map<String, dynamic>? current, List<Map<String, dynamic>> allMembers,
      List<Map<String, dynamic>> allAssignments) {
    final seatedIds = allAssignments.map((a) => a['userId']).toSet();
    final candidates = allMembers.where((m) => m['part'] == part && !seatedIds.contains(m['id'])).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${User.partLabels[part] ?? part} ${row + 1}열 ${col + 1}번', style: AppText.headline(18)),
          const SizedBox(height: 12),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.person, color: AppColors.primary),
              title: Text(current['userName'] ?? '', style: AppText.body(15, weight: FontWeight.w700)),
              trailing: TextButton(
                onPressed: () async {
                  await FirebaseService.clearSeat(chartId: _selectedChartId!, part: part, row: row, col: col);
                  ref.invalidate(seatAssignmentsProvider(_selectedChartId!));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('해제', style: TextStyle(color: Colors.red)),
              ),
            ),
          const Divider(),
          Text('배정 가능', style: AppText.body(12, weight: FontWeight.w700, color: AppColors.muted)),
          Expanded(
            child: candidates.isEmpty
                ? Center(child: Text('배정 가능한 단원이 없습니다', style: AppText.body(13, color: AppColors.muted)))
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final m = candidates[i];
                      return ListTile(
                        title: Text(m['name'] ?? '', style: AppText.body(14, weight: FontWeight.w600)),
                        subtitle: Text('${m['generation'] ?? ''}', style: AppText.body(11, color: AppColors.muted)),
                        onTap: () async {
                          await FirebaseService.assignSeat(
                            chartId: _selectedChartId!, part: part, row: row, col: col, userId: m['id'],
                          );
                          ref.invalidate(seatAssignmentsProvider(_selectedChartId!));
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  void _handleChartAction(String action, Map<String, dynamic> chart) async {
    if (action == 'toggle') {
      await FirebaseService.publishSeatingChart(chart['id'], !(chart['isPublished'] == true));
      ref.invalidate(seatingChartsProvider);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('배치판 삭제'),
          content: Text('"${chart['label']}"을(를) 삭제할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed == true) {
        await FirebaseService.deleteSeatingChart(chart['id']);
        ref.invalidate(seatingChartsProvider);
      }
    }
  }

  void _showCreateDialog(BuildContext context) {
    final labelCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 배치판'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: '제목', hintText: '예: 주일예배')),
          const SizedBox(height: 12),
          TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: '날짜 (YYYY-MM-DD)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              if (labelCtrl.text.trim().isEmpty) return;
              await FirebaseService.createSeatingChart(label: labelCtrl.text.trim(), eventDate: dateCtrl.text.trim());
              ref.invalidate(seatingChartsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('생성'),
          ),
        ],
      ),
    );
  }
}
