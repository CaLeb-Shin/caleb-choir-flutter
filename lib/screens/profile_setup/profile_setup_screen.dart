import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../services/firebase_service.dart';
import '../../providers/app_providers.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  /// 거절 후 재신청 모드
  final bool isReapply;
  const ProfileSetupScreen({super.key, this.isReapply = false});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _genCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _part = 'soprano';
  // 가입 희망 역할
  String _requestedRole = 'member';
  // 파트장 신청 시 담당 파트 (part와 동일하게 시작)
  String _leaderPart = 'soprano';
  Uint8List? _imageBytes;
  String? _uploadedImageUrl;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Firebase Auth의 displayName 자동 채움
    final fbUser = FirebaseService.currentUser;
    if (fbUser?.displayName != null) {
      _nameCtrl.text = fbUser!.displayName!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    _genCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() { _imageBytes = bytes; _uploading = true; });
      final url = await FirebaseService.uploadProfileImage(bytes);
      setState(() { _uploadedImageUrl = url; _uploading = false; });
    } catch (e) {
      setState(() { _uploading = false; _error = '사진 업로드 실패: $e'; });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = '이름을 입력해주세요');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'nickname': _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
        'generation': _genCtrl.text.trim(),
        'part': _part,
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'profileImageUrl': _uploadedImageUrl,
        'requestedRole': _requestedRole,
        'requestedPart': _requestedRole == 'part_leader' ? _leaderPart : null,
      };
      if (widget.isReapply) {
        await FirebaseService.reapplyApproval(data);
      } else {
        await FirebaseService.createProfile(data);
      }
      ref.invalidate(profileProvider);
    } catch (e) {
      setState(() { _saving = false; _error = '저장 실패: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.isReapply ? '다시 신청' : '환영합니다', style: AppText.label()),
              const SizedBox(height: 6),
              Text(widget.isReapply ? '프로필을 수정하여 다시 신청해주세요' : '프로필을 완성해주세요', style: AppText.headline(26)),
              const SizedBox(height: 8),
              Text('함께 찬양할 멤버 정보를 알려주세요',
                style: AppText.body(14, color: AppColors.muted)),
              const SizedBox(height: 32),

              // ── Profile Image
              Center(
                child: GestureDetector(
                  onTap: _uploading ? null : _pickImage,
                  child: Stack(children: [
                    Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primarySoft,
                        image: _imageBytes != null
                            ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _imageBytes == null
                          ? Icon(Icons.person_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.4))
                          : null,
                    ),
                    if (_uploading)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
                          child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        ),
                      ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 3),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text('사진 추가 (선택)', style: AppText.body(12, color: AppColors.muted))),
              const SizedBox(height: 28),

              // ── Role selection
              _Label(text: '가입 유형 *'),
              const SizedBox(height: 6),
              Column(children: [
                _RoleOption(
                  value: 'member',
                  groupValue: _requestedRole,
                  label: '찬양대원',
                  desc: '일반 단원으로 가입합니다',
                  icon: Icons.person_rounded,
                  onChanged: (v) => setState(() => _requestedRole = v),
                ),
                const SizedBox(height: 8),
                _RoleOption(
                  value: 'part_leader',
                  groupValue: _requestedRole,
                  label: '파트장',
                  desc: '파트를 이끄는 역할입니다',
                  icon: Icons.star_rounded,
                  onChanged: (v) => setState(() => _requestedRole = v),
                ),
                if (_requestedRole == 'part_leader') ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 12),
                    child: DropdownButtonFormField<String>(
                      value: _leaderPart,
                      decoration: const InputDecoration(labelText: '담당 파트'),
                      items: User.partLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setState(() => _leaderPart = v ?? _leaderPart),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _RoleOption(
                  value: 'admin',
                  groupValue: _requestedRole,
                  label: '관리자',
                  desc: '앱 전체를 관리합니다 (승인 필요)',
                  icon: Icons.shield_rounded,
                  onChanged: (v) => setState(() => _requestedRole = v),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '가입 신청 후 관리자의 승인이 필요합니다',
                    style: AppText.body(12, weight: FontWeight.w600, color: AppColors.secondary),
                  )),
                ]),
              ),
              const SizedBox(height: 24),

              // ── Form fields
              _Label(text: '이름 *'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: '실명을 입력하세요'),
              ),
              const SizedBox(height: 16),

              _Label(text: '별칭 (선택)'),
              const SizedBox(height: 6),
              TextField(
                controller: _nicknameCtrl,
                decoration: const InputDecoration(hintText: '예: 길동이 → "홍길동 (길동이)"로 표시됩니다'),
              ),
              const SizedBox(height: 16),

              _Label(text: '기수'),
              const SizedBox(height: 6),
              TextField(
                controller: _genCtrl,
                decoration: const InputDecoration(hintText: '예: 91기, 23기'),
              ),
              const SizedBox(height: 16),

              _Label(text: '파트'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _part,
                items: User.partLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _part = v ?? _part;
                  _leaderPart = _part;
                }),
              ),
              const SizedBox(height: 16),

              _Label(text: '전화번호 (선택)'),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '010-0000-0000'),
              ),
              const SizedBox(height: 24),

              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!, style: AppText.body(13, color: AppColors.error)),
                ),

              // ── Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.isReapply ? '다시 신청' : '가입 신청'),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: TextButton(
                onPressed: () async {
                  await FirebaseService.signOut();
                },
                child: Text('다른 계정으로 로그인', style: AppText.body(13, color: AppColors.muted)),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.body(12, weight: FontWeight.w700, color: AppColors.onSurfaceVariant));
  }
}

class _RoleOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final String desc;
  final IconData icon;
  final ValueChanged<String> onChanged;
  const _RoleOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.desc,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: selected ? Colors.white : AppColors.muted, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.body(15, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(desc, style: AppText.body(12, color: AppColors.muted)),
              ],
            ),
          ),
          Radio<String>(
            value: value,
            groupValue: groupValue,
            onChanged: (v) => onChanged(v ?? value),
          ),
        ]),
      ),
    );
  }
}
