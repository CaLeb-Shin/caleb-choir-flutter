import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../models/user.dart';
import '../../widgets/interactive.dart';
import '../admin/members_screen.dart';
import 'my_qr_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final historyAsync = ref.watch(myHistoryProvider);
    final viewAsMember = ref.watch(viewAsMemberProvider);
    final effectiveIsAdmin = ref.watch(effectiveIsAdminProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('프로필을 불러올 수 없습니다')),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final history = historyAsync.valueOrNull ?? [];
        final total = history.length;

        // 최근 4주 출석 계산
        final now = DateTime.now();
        final weekCounts = List.generate(4, (w) {
          final start = now.subtract(Duration(days: (w + 1) * 7));
          final end = now.subtract(Duration(days: w * 7));
          return history.where((r) {
            try {
              final d = DateTime.parse(r['checkedInAt'].toString());
              return d.isAfter(start) && d.isBefore(end);
            } catch (_) {
              return false;
            }
          }).length;
        }).reversed.toList();
        final maxWeek = weekCounts.fold<int>(1, (a, b) => a > b ? a : b);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('마이페이지', style: AppText.label()),
              const SizedBox(height: 6),
              Text(
                profile.displayName.isEmpty ? '멤버' : profile.displayName,
                style: AppText.headline(28),
              ),
              if (ref.watch(localPreviewModeProvider)) ...[
                const SizedBox(height: 14),
                const _PreviewPersonaSwitcher(),
              ],
              if (profile.isAdmin && viewAsMember) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '단원 시점으로 보고 있습니다',
                          style: AppText.body(
                            12,
                            weight: FontWeight.w600,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(viewAsMemberProvider.notifier).state =
                                false,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '나가기',
                          style: AppText.body(
                            12,
                            weight: FontWeight.w700,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Profile Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF000E24), Color(0xFF00234B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    // 프로필 이미지 또는 파트 이니셜
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.secondaryContainer,
                        image: profile.profileImageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(profile.profileImageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: profile.profileImageUrl == null
                          ? Center(
                              child: Text(
                                profile.partInitial,
                                style: AppText.headline(
                                  32,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile.displayName.isEmpty
                          ? '이름 없음'
                          : profile.displayName,
                      style: AppText.headline(22, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if ((profile.generation ?? '').isNotEmpty)
                          profile.generation!,
                        if ((profile.choirName ?? '').isNotEmpty)
                          profile.choirName!,
                        if ((profile.churchPosition ?? '').isNotEmpty)
                          profile.churchPosition!,
                        profile.partLabel,
                      ].join(' · '),
                      style: AppText.body(14, color: Colors.white60),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Chip(
                          label: profile.roleLabel,
                          bg: Colors.white.withValues(alpha: 0.12),
                          fg: Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        _Chip(
                          label: '출석 $total회',
                          bg: AppColors.secondaryContainer.withValues(
                            alpha: 0.3,
                          ),
                          fg: AppColors.secondaryContainer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Attendance Stats
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('출석 현황', style: AppText.label()),
                    const SizedBox(height: 4),
                    Text('총 $total회 출석', style: AppText.headline(20)),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(4, (i) {
                        final h = maxWeek > 0
                            ? (weekCounts[i] / maxWeek * 48).clamp(4.0, 48.0)
                            : 4.0;
                        final isThisWeek = i == 3;
                        return Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${weekCounts[i]}',
                                style: AppText.body(
                                  12,
                                  weight: FontWeight.w700,
                                  color: isThisWeek
                                      ? AppColors.secondary
                                      : AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: h,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isThisWeek
                                      ? AppColors.secondaryContainer
                                      : AppColors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${4 - i}주전',
                                style: AppText.body(10, color: AppColors.muted),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Contact Info
              if (profile.email != null)
                _InfoTile(
                  icon: Icons.mail_outline_rounded,
                  label: '이메일',
                  value: profile.email!,
                ),
              if (profile.phone != null && profile.phone!.isNotEmpty)
                _InfoTile(
                  icon: Icons.phone_outlined,
                  label: '연락처',
                  value: profile.phone!,
                ),
              const SizedBox(height: 8),

              // ── Menu
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    _MenuItem(
                      icon: Icons.person_outline_rounded,
                      label: '프로필 수정',
                      onTap: () => _showEditSheet(context, ref, profile),
                    ),
                    Divider(
                      height: 0.5,
                      indent: 56,
                      color: AppColors.border.withValues(alpha: 0.2),
                    ),
                    _MenuItem(
                      icon: Icons.qr_code_rounded,
                      label: '내 출석 QR',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyQrScreen()),
                      ),
                    ),
                    Divider(
                      height: 0.5,
                      indent: 56,
                      color: AppColors.border.withValues(alpha: 0.2),
                    ),
                    _MenuItem(
                      icon: Icons.calendar_today_rounded,
                      label: '출석 기록',
                      onTap: () =>
                          ref.read(tabIndexProvider.notifier).state = 3,
                    ),
                    if (effectiveIsAdmin) ...[
                      Divider(
                        height: 0.5,
                        indent: 56,
                        color: AppColors.border.withValues(alpha: 0.2),
                      ),
                      _MenuItem(
                        icon: Icons.admin_panel_settings_rounded,
                        label: '단원 관리',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MembersScreen(),
                          ),
                        ),
                      ),
                    ],
                    if (profile.isAdmin) ...[
                      Divider(
                        height: 0.5,
                        indent: 56,
                        color: AppColors.border.withValues(alpha: 0.2),
                      ),
                      _MenuItem(
                        icon: viewAsMember
                            ? Icons.admin_panel_settings_outlined
                            : Icons.visibility_outlined,
                        label: viewAsMember ? '관리자 모드로 복귀' : '단원 뷰로 전환',
                        onTap: () {
                          ref.read(viewAsMemberProvider.notifier).state =
                              !viewAsMember;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                !viewAsMember
                                    ? '단원 시점으로 보고 있습니다'
                                    : '관리자 모드로 돌아왔습니다',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                    Divider(
                      height: 0.5,
                      indent: 56,
                      color: AppColors.border.withValues(alpha: 0.2),
                    ),
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: '로그아웃',
                      isDestructive: true,
                      onTap: () => _confirmLogout(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'C.C Note v1.0.0',
                  style: AppText.body(12, color: AppColors.subtle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, User profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ProfileEditSheet(profile: profile, ref: ref),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              ref.read(loggedOutProvider.notifier).state = true;
              await FirebaseService.signOut();
            },
            child: const Text('로그아웃', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ── Profile Edit Sheet (with image upload, nickname, free-text generation)
class _ProfileEditSheet extends StatefulWidget {
  final User profile;
  final WidgetRef ref;
  const _ProfileEditSheet({required this.profile, required this.ref});

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _genCtrl;
  late final TextEditingController _choirNameCtrl;
  late final TextEditingController _churchPositionCtrl;
  late String _part;
  Uint8List? _newImageBytes;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name ?? '');
    _nicknameCtrl = TextEditingController(text: widget.profile.nickname ?? '');
    _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
    _genCtrl = TextEditingController(text: widget.profile.generation ?? '');
    _choirNameCtrl = TextEditingController(
      text: widget.profile.choirName ?? '',
    );
    _churchPositionCtrl = TextEditingController(
      text: widget.profile.churchPosition ?? '',
    );
    final initialPart = widget.profile.part ?? 'soprano';
    _part = User.selectableParts.contains(initialPart) ? initialPart : 'band';
    _imageUrl = widget.profile.profileImageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    _phoneCtrl.dispose();
    _genCtrl.dispose();
    _choirNameCtrl.dispose();
    _churchPositionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        imageQuality: 68,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('프로필 사진은 5MB 이하로 선택해주세요')));
        return;
      }
      setState(() {
        _newImageBytes = bytes;
        _uploading = true;
      });
      final url = await FirebaseService.uploadProfileImage(bytes);
      setState(() {
        _imageUrl = url;
        _uploading = false;
      });
    } catch (e) {
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'nickname': _nicknameCtrl.text.trim().isEmpty
            ? null
            : _nicknameCtrl.text.trim(),
        'generation': _genCtrl.text.trim(),
        'choirName': _choirNameCtrl.text.trim().isEmpty
            ? null
            : _choirNameCtrl.text.trim(),
        'churchPosition': _churchPositionCtrl.text.trim().isEmpty
            ? null
            : _churchPositionCtrl.text.trim(),
        'part': _part,
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      };
      if (_imageUrl != null) data['profileImageUrl'] = _imageUrl;
      await FirebaseService.updateProfile(data);
      widget.ref.invalidate(profileProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.subtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('프로필 수정', style: AppText.headline(20)),
            const SizedBox(height: 20),

            // ── Profile image
            Center(
              child: GestureDetector(
                onTap: _uploading ? null : _pickImage,
                child: Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primarySoft,
                        image: _newImageBytes != null
                            ? DecorationImage(
                                image: MemoryImage(_newImageBytes!),
                                fit: BoxFit.cover,
                              )
                            : (_imageUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(_imageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null),
                      ),
                      child: (_newImageBytes == null && _imageUrl == null)
                          ? Icon(
                              Icons.person_rounded,
                              size: 40,
                              color: AppColors.primary.withValues(alpha: 0.4),
                            )
                          : null,
                    ),
                    if (_uploading)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '이름 (실명)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameCtrl,
              decoration: const InputDecoration(
                labelText: '별칭 (선택)',
                hintText: '별칭을 입력하세요',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _genCtrl,
              decoration: const InputDecoration(
                labelText: '기수',
                hintText: '기수를 입력하세요',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _choirNameCtrl,
              decoration: const InputDecoration(
                labelText: '찬양대 이름 (선택)',
                hintText: '찬양대 이름을 입력하세요',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _churchPositionCtrl,
              decoration: const InputDecoration(
                labelText: '교회 내 직분 (선택)',
                hintText: '직분을 입력하세요',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _part,
              decoration: const InputDecoration(labelText: '파트'),
              items: User.selectableParts
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(User.partLabels[k] ?? k),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _part = v ?? _part),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: '전화번호 (선택)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppText.body(12, weight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _PreviewPersonaSwitcher extends ConsumerWidget {
  const _PreviewPersonaSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(previewPersonaProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.science_rounded,
              color: AppColors.secondaryContainer,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<PreviewPersona>(
              initialValue: persona,
              decoration: InputDecoration(
                labelText: '테스트 계정',
                helperText: '미리보기에서만 계정을 바꿔볼 수 있어요',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.secondary.withValues(alpha: 0.16),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.secondary.withValues(alpha: 0.16),
                  ),
                ),
              ),
              items: PreviewPersona.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(previewPersonaLabels[value] ?? value.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                ref.read(previewPersonaProvider.notifier).state = value;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${previewPersonaLabels[value] ?? value.name} 계정으로 전환했습니다',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.body(11, color: AppColors.muted)),
              Text(value, style: AppText.body(14, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;
  const _MenuItem({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.ink;
    return HoverButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDestructive ? AppColors.error : AppColors.muted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppText.body(15, weight: FontWeight.w500, color: color),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.subtle,
            ),
          ],
        ),
      ),
    );
  }
}
