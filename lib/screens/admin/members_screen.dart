import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../models/user.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';
import '../../widgets/interactive.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);
    final canEdit = ref.watch(effectiveIsAdminProvider);
    final myUid = FirebaseService.uid;

    return Scaffold(
      appBar: AppBar(title: const AppLogoTitle(title: '단원 관리')),
      bottomNavigationBar: const AppBottomNavBar(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(membersProvider),
        child: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('불러오기 실패: $e')),
        data: (members) {
          // 관리자 → 임원 → 단원 순으로 정렬
          members.sort((a, b) {
            const order = {'admin': 0, 'officer': 1, 'member': 2};
            return (order[a['role']] ?? 99).compareTo(order[b['role']] ?? 99);
          });

          if (members.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 120),
                  child: Center(
                    child: Text(
                      '등록된 단원이 없습니다',
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final m = members[i];
              final memberUser = User.fromMap(m);
              final isMe = m['id'] == myUid;

              return Tappable(
                onTap: canEdit && !isMe
                    ? () => _showMemberEditDialog(context, ref, m)
                    : null,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primarySoft,
                          image: m['profileImageUrl'] != null
                              ? DecorationImage(
                                  image: NetworkImage(m['profileImageUrl']),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: m['profileImageUrl'] == null
                            ? Center(
                                child: Text(
                                  memberUser.partInitial,
                                  style: AppText.body(
                                    16,
                                    weight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    memberUser.displayName.isEmpty
                                        ? '이름 없음'
                                        : memberUser.displayName,
                                    style: AppText.body(
                                      15,
                                      weight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '(나)',
                                    style: AppText.body(
                                      11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              '${memberUser.generation ?? ''} · ${memberUser.partLabel}',
                              style: AppText.body(12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      // Role chip
                      _RoleChip(role: m['role'] ?? 'member'),
                    ],
                  ),
                ),
              );
            },
          );
        },
        ),
      ),
    );
  }

  void _showMemberEditDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> member,
  ) {
    var selectedRole = (member['role'] ?? 'member').toString();
    var selectedPart = (member['part'] ?? User.selectableParts.first)
        .toString();
    if (!User.selectableParts.contains(selectedPart)) {
      selectedPart = User.selectableParts.first;
    }
    final generationController = TextEditingController(
      text: member['generation']?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text('${member['name'] ?? ''}님 정보 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: '등급'),
                items: User.roleLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedRole = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedPart,
                decoration: const InputDecoration(labelText: '파트'),
                items: User.selectableParts
                    .map(
                      (part) => DropdownMenuItem(
                        value: part,
                        child: Text(User.partLabels[part] ?? part),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedPart = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: generationController,
                decoration: const InputDecoration(
                  labelText: '기수',
                  hintText: '예: 1기',
                ),
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await FirebaseService.updateUserAdminFields(
                  member['id'],
                  role: selectedRole,
                  part: selectedPart,
                  generation: generationController.text,
                );
                ref.invalidate(membersProvider);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    ).whenComplete(generationController.dispose);
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (role) {
      'admin' || 'church_admin' => (AppColors.primary, Colors.white, '관리자'),
      'officer' => (AppColors.secondaryContainer, AppColors.secondary, '임원'),
      'part_leader' => (
        AppColors.secondarySoft,
        AppColors.secondary,
        '파트장',
      ),
      _ => (AppColors.surfaceMid, AppColors.muted, '단원'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppText.body(11, weight: FontWeight.w700, color: fg),
      ),
    );
  }
}
