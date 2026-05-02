import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../models/user.dart' show User;
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';

class PollsScreen extends ConsumerStatefulWidget {
  final String? initialPollId;
  final String? initialTargetDate;
  final String? initialTitle;

  const PollsScreen({
    super.key,
    this.initialPollId,
    this.initialTargetDate,
    this.initialTitle,
  });

  @override
  ConsumerState<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends ConsumerState<PollsScreen> {
  bool _showOpen = true;
  String? _selectedPollId;
  bool _initialSelectionApplied = false;

  @override
  void initState() {
    super.initState();
    _selectedPollId = widget.initialPollId;
  }

  @override
  Widget build(BuildContext context) {
    final pollsAsync = ref.watch(pollsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final canCreate =
        ref.watch(effectiveHasManagePermissionProvider) ||
        ref.watch(effectiveIsPartLeaderProvider);

    return Scaffold(
      appBar: AppBar(
        title: AppLogoTitle(title: '참석 투표', textStyle: AppText.headline(20)),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _showCreateDialog(context, profile),
            ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(),
      body: pollsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (polls) {
          final userPart = profile?.part;
          final isAdmin = profile?.isAdmin ?? false;
          final filtered = polls
              .where((p) {
                if (isAdmin) return true;
                final scope = p['scopePart'];
                return scope == null || scope == userPart;
              })
              .where(
                (p) => _showOpen ? p['isOpen'] == true : p['isOpen'] != true,
              )
              .toList();
          if (!_initialSelectionApplied && filtered.isNotEmpty) {
            _selectedPollId ??= _initialMatchingPollId(filtered);
            _initialSelectionApplied = true;
          }
          final selectedPollId = _selectedPollId;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _tabChip(
                      '진행 중',
                      _showOpen,
                      () => setState(() => _showOpen = true),
                    ),
                    const SizedBox(width: 8),
                    _tabChip(
                      '마감됨',
                      !_showOpen,
                      () => setState(() => _showOpen = false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _showOpen ? '진행 중인 투표가 없습니다' : '마감된 투표가 없습니다',
                          style: AppText.body(14, color: AppColors.muted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _PollCard(
                          poll: filtered[i],
                          profile: profile,
                          isSelected: selectedPollId == filtered[i]['id'],
                          onTap: () => setState(() {
                            _selectedPollId =
                                selectedPollId == filtered[i]['id']
                                ? null
                                : filtered[i]['id'];
                          }),
                          onVote: (choice) =>
                              _handleVote(filtered[i]['id'], choice),
                          onClose: () => _handleClose(filtered[i]['id']),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _initialMatchingPollId(List<Map<String, dynamic>> polls) {
    final targetDate = widget.initialTargetDate?.trim();
    if (targetDate != null && targetDate.isNotEmpty) {
      for (final poll in polls) {
        if (poll['targetDate']?.toString().trim() == targetDate) {
          return poll['id']?.toString();
        }
      }
    }

    final title = widget.initialTitle?.trim();
    if (title != null && title.isNotEmpty) {
      for (final poll in polls) {
        final pollTitle = poll['title']?.toString().trim() ?? '';
        if (pollTitle.isEmpty) continue;
        if (pollTitle.contains(title) || title.contains(pollTitle)) {
          return poll['id']?.toString();
        }
      }
    }
    return null;
  }

  Widget _tabChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryContainer : AppColors.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: AppText.body(
            14,
            weight: FontWeight.w700,
            color: active ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }

  Future<void> _handleVote(String pollId, String choice) async {
    try {
      await FirebaseService.vote(pollId, choice);
      ref.invalidate(pollsProvider);
      ref.invalidate(pollVotesProvider(pollId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(choice == 'attend' ? '참석으로 투표했습니다' : '불참으로 투표했습니다'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
  }

  Future<void> _handleClose(String pollId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('투표 마감'),
        content: const Text('이 투표를 마감할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('마감', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseService.closePoll(pollId);
      ref.invalidate(pollsProvider);
    }
  }

  void _showCreateDialog(BuildContext context, User? profile) {
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().split('T')[0],
    );
    final isPartLeader = profile?.isPartLeader ?? false;
    String? scopePart = isPartLeader ? profile?.partLeaderFor : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('새 투표'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '예: 4/21 주일 참석 여부',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: '날짜 (YYYY-MM-DD)',
                  ),
                ),
                if (!isPartLeader && (profile?.isAdmin ?? false)) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: scopePart,
                    decoration: const InputDecoration(labelText: '대상 범위'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('전체')),
                      ...User.selectableParts.map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(User.partLabels[k] ?? k),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => scopePart = v),
                  ),
                ],
                if (isPartLeader)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${User.partLabels[profile?.partLeaderFor] ?? ""} 파트 대상 투표',
                      style: AppText.body(12, color: AppColors.secondary),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  await FirebaseService.createPoll(
                    title: titleCtrl.text.trim(),
                    targetDate: dateCtrl.text.trim(),
                    scopePart: scopePart,
                  );
                  ref.invalidate(pollsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('생성'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PollCard extends ConsumerWidget {
  final Map<String, dynamic> poll;
  final User? profile;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(String) onVote;
  final VoidCallback onClose;

  const _PollCard({
    required this.poll,
    required this.profile,
    required this.isSelected,
    required this.onTap,
    required this.onVote,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = poll['isOpen'] == true;
    final scopePart = poll['scopePart'] as String?;
    final scopeLabel = scopePart != null
        ? '${User.partLabels[scopePart] ?? scopePart} 파트'
        : '전체';
    final votesAsync = ref.watch(pollVotesProvider(poll['id']));
    final votes = votesAsync.valueOrNull ?? [];
    final attend = votes.where((v) => v['choice'] == 'attend').length;
    final absent = votes.where((v) => v['choice'] == 'absent').length;
    final myVote = votes.where((v) => v['userId'] == profile?.id).firstOrNull;
    final myChoice = myVote?['choice'] as String?;

    final canClose =
        isOpen &&
        (profile?.isAdmin == true ||
            (profile?.isPartLeader == true &&
                poll['createdBy'] == profile?.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOpen ? AppColors.success : AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOpen ? '진행 중' : '마감됨',
                    style: AppText.body(
                      12,
                      weight: FontWeight.w700,
                      color: isOpen ? AppColors.success : AppColors.muted,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      scopeLabel,
                      style: AppText.body(
                        11,
                        weight: FontWeight.w700,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(poll['title'] ?? '', style: AppText.headline(17)),
              const SizedBox(height: 4),
              Text(
                poll['targetDate'] ?? '',
                style: AppText.body(13, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _countChip('참석', attend, AppColors.success),
                  const SizedBox(width: 12),
                  _countChip('불참', absent, AppColors.error),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: myChoice == 'attend'
                            ? AppColors.success
                            : myChoice == 'absent'
                            ? AppColors.error
                            : AppColors.muted,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '내 투표: ${myChoice == 'attend'
                          ? '참석'
                          : myChoice == 'absent'
                          ? '불참'
                          : '미투표'}',
                      style: AppText.body(
                        11,
                        weight: FontWeight.w700,
                        color: myChoice == 'attend'
                            ? AppColors.success
                            : myChoice == 'absent'
                            ? AppColors.error
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              if (isSelected) ...[
                const SizedBox(height: 16),
                if (isOpen)
                  Row(
                    children: [
                      Expanded(child: _voteButton('참석', 'attend', myChoice)),
                      const SizedBox(width: 10),
                      Expanded(child: _voteButton('불참', 'absent', myChoice)),
                    ],
                  ),
                if (isOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '마감 전까지 변경 가능',
                      textAlign: TextAlign.center,
                      style: AppText.body(11, color: AppColors.muted),
                    ),
                  ),
                if ((profile?.isAdmin ?? false) ||
                    (profile?.isPartLeader ?? false))
                  _voterList(votes),
                if (canClose)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton(
                      onPressed: onClose,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('투표 마감'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppText.body(
            10,
            weight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _voteButton(String label, String choice, String? currentChoice) {
    final isSelected = currentChoice == choice;
    final color = choice == 'attend' ? AppColors.success : AppColors.error;
    return ElevatedButton(
      onPressed: () => onVote(choice),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : AppColors.card,
        foregroundColor: isSelected ? Colors.white : color,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 2),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _voterList(List<Map<String, dynamic>> votes) {
    final filtered = profile?.isPartLeader == true && profile?.isAdmin != true
        ? votes.where((v) => v['userPart'] == profile?.partLeaderFor).toList()
        : votes;
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          '투표자 상세',
          style: AppText.body(
            12,
            weight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        ...filtered.map(
          (v) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  v['userName'] ?? '',
                  style: AppText.body(14, weight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  User.partLabels[v['userPart']] ?? '',
                  style: AppText.body(11, color: AppColors.muted),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (v['choice'] == 'attend'
                                ? AppColors.success
                                : AppColors.error)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    v['choice'] == 'attend' ? '참석' : '불참',
                    style: AppText.body(
                      11,
                      weight: FontWeight.w700,
                      color: v['choice'] == 'attend'
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
