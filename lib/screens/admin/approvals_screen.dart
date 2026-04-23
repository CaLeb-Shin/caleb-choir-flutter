import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart' show User;
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  int _tab = 0; // 0: 대기중, 1: 거절됨

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(effectiveIsAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('승인 관리')),
        body: Center(child: Text('관리자만 접근할 수 있습니다', style: AppText.body(14, color: AppColors.muted))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('가입 승인', style: AppText.headline(20))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            _TabChip(label: '대기 중', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
            const SizedBox(width: 8),
            _TabChip(label: '거절됨', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
          ]),
        ),
        Expanded(child: _tab == 0 ? const _PendingList() : const _RejectedList()),
      ]),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: AppText.body(14,
            weight: FontWeight.w700,
            color: active ? Colors.white : AppColors.muted)),
      ),
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingUsersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (users) {
        if (users.isEmpty) {
          return Center(child: Text('대기 중인 신청이 없습니다', style: AppText.body(14, color: AppColors.muted)));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pendingUsersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _UserCard(
              user: User.fromMap(users[i]),
              onApprove: () => _showApproveDialog(context, ref, User.fromMap(users[i])),
              onReject: () => _showRejectDialog(context, ref, User.fromMap(users[i])),
            ),
          ),
        );
      },
    );
  }

  void _showApproveDialog(BuildContext context, WidgetRef ref, User user) {
    // 기본값은 항상 'member' (무분별한 관리자 승격 방지)
    String role = 'member';
    String part = user.requestedPart ?? user.part ?? 'soprano';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text('${user.displayName} 승인'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.secondary),
                const SizedBox(width: 6),
                Expanded(child: Text('신청: ${user.requestedRoleLabel}',
                    style: AppText.body(12, weight: FontWeight.w700, color: AppColors.secondary))),
              ]),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: '확정 역할'),
              items: const [
                DropdownMenuItem(value: 'member', child: Text('찬양대원')),
                DropdownMenuItem(value: 'part_leader', child: Text('파트장')),
                DropdownMenuItem(value: 'admin', child: Text('관리자')),
              ],
              onChanged: (v) => setDialogState(() => role = v ?? role),
            ),
            if (role == 'part_leader') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: part,
                decoration: const InputDecoration(labelText: '담당 파트'),
                items: User.partLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setDialogState(() => part = v ?? part),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                await FirebaseService.approveUser(
                  user.id,
                  role: role,
                  partLeaderFor: role == 'part_leader' ? part : null,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                ref.invalidate(pendingUsersProvider);
                ref.invalidate(membersProvider);
              },
              child: const Text('승인'),
            ),
          ],
        );
      }),
    );
  }

  void _showRejectDialog(BuildContext context, WidgetRef ref, User user) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${user.displayName} 거절'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '거절 사유',
            hintText: '예: 찬양대 단원이 아닙니다',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final reason = ctrl.text.trim().isEmpty ? '승인되지 않았습니다' : ctrl.text.trim();
              await FirebaseService.rejectUser(user.id, reason);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(pendingUsersProvider);
              ref.invalidate(rejectedUsersProvider);
            },
            child: const Text('거절', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _RejectedList extends ConsumerWidget {
  const _RejectedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rejectedUsersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (users) {
        if (users.isEmpty) {
          return Center(child: Text('거절된 신청이 없습니다', style: AppText.body(14, color: AppColors.muted)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final u = User.fromMap(users[i]);
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      backgroundColor: AppColors.error.withValues(alpha: 0.1),
                      child: Text(u.partInitial,
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.displayName, style: AppText.body(15, weight: FontWeight.w700)),
                      Text('신청: ${u.requestedRoleLabel}', style: AppText.body(11, color: AppColors.muted)),
                    ])),
                  ]),
                  if (u.rejectionReason != null && u.rejectionReason!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(u.rejectionReason!, style: AppText.body(12, color: AppColors.ink)),
                    ),
                  ],
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  final User user;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _UserCard({required this.user, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.primarySoft,
              child: Text(user.partInitial,
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.displayName, style: AppText.body(15, weight: FontWeight.w700)),
                Text(user.partLabel, style: AppText.body(11, color: AppColors.muted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(user.requestedRoleLabel,
                  style: AppText.body(11, weight: FontWeight.w700, color: AppColors.secondary)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            if (user.generation != null && user.generation!.isNotEmpty)
              Text('기수 ${user.generation}', style: AppText.body(12, color: AppColors.muted)),
            if (user.phone != null && user.phone!.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(user.phone!, style: AppText.body(12, color: AppColors.muted)),
            ],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: onReject,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('거절'),
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(
              onPressed: onApprove,
              child: const Text('승인'),
            )),
          ]),
        ]),
      ),
    );
  }
}
