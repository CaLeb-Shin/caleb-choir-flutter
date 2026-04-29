import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../services/firebase_service.dart';
import '../../providers/app_providers.dart';
import '../../widgets/app_logo_title.dart';

/// ProfileSetupScreen의 3가지 진입 모드.
enum ProfileSetupMode {
  /// 승인된 교회에 가입 신청 (찬양대원/파트장)
  joinChurch,

  /// 새 교회 등록 신청 (신청자는 해당 교회 admin이 될 예정)
  registerChurch,

  /// 거부 후 재신청
  reapply,
}

class ProfileSetupScreen extends ConsumerStatefulWidget {
  final ProfileSetupMode mode;
  final String requestedRole; // 'member' | 'part_leader' | 'church_admin'
  final String? churchId; // mode == joinChurch에서 필수
  final String? churchName; // 화면 상단 컨텍스트 표시용
  final Map<String, dynamic>? pendingChurchData; // mode == registerChurch에서 필수

  const ProfileSetupScreen({
    super.key,
    required this.mode,
    required this.requestedRole,
    this.churchId,
    this.churchName,
    this.pendingChurchData,
  });

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _genCtrl = TextEditingController();
  final _choirNameCtrl = TextEditingController();
  final _churchPositionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _part = 'soprano';
  String _leaderPart = 'soprano';
  Uint8List? _imageBytes;
  String? _uploadedImageUrl;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  bool get _isPartLeader => widget.requestedRole == 'part_leader';
  bool get _isChurchAdminFlow => widget.requestedRole == 'church_admin';
  bool get _isReapply => widget.mode == ProfileSetupMode.reapply;

  @override
  void initState() {
    super.initState();
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
    _choirNameCtrl.dispose();
    _churchPositionCtrl.dispose();
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
      setState(() {
        _imageBytes = bytes;
        _uploading = true;
      });
      final url = await FirebaseService.uploadProfileImage(bytes);
      setState(() {
        _uploadedImageUrl = url;
        _uploading = false;
      });
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = '사진 업로드 실패: $e';
      });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = '이름을 입력해주세요');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
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
        'profileImageUrl': _uploadedImageUrl,
        'requestedRole': widget.requestedRole,
        'requestedPart': _isPartLeader ? _leaderPart : null,
      };
      switch (widget.mode) {
        case ProfileSetupMode.joinChurch:
          await FirebaseService.requestChurchJoin(
            churchId: widget.churchId!,
            requestedRole: widget.requestedRole,
            requestedPart: _isPartLeader ? _leaderPart : null,
            profileData: data,
          );
          break;
        case ProfileSetupMode.registerChurch:
          final d = widget.pendingChurchData!;
          await FirebaseService.requestChurchRegistration(
            name: d['name'] as String,
            address: d['address'] as String?,
            contactPhone: d['contactPhone'] as String?,
            contactEmail: d['contactEmail'] as String?,
            profileData: data,
          );
          break;
        case ProfileSetupMode.reapply:
          await FirebaseService.reapplyApproval(data);
          break;
      }
      ref.invalidate(profileProvider);
      // main.dart의 myProfileStreamProvider가 자동으로 다음 화면으로 전환시킴
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '저장 실패: $e';
      });
    }
  }

  String get _submitLabel {
    if (_isReapply) return '다시 신청';
    return '가입 신청';
  }

  String get _contextBanner {
    switch (widget.mode) {
      case ProfileSetupMode.registerChurch:
        return '"${widget.churchName}" 등록 신청';
      case ProfileSetupMode.joinChurch:
        return '"${widget.churchName}" ${_isPartLeader ? "파트장" : "찬양대원"} 신청';
      case ProfileSetupMode.reapply:
        return '재신청 (거부 후)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _isReapply
          ? null
          : AppBar(
              backgroundColor: AppColors.bg,
              elevation: 0,
              iconTheme: const IconThemeData(color: AppColors.ink),
              title: AppLogoTitle(
                title: '프로필 작성',
                textStyle: AppText.body(15, weight: FontWeight.w700),
              ),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, _isReapply ? 32 : 12, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isReapply) ...[
                Text('다시 신청', style: AppText.label()),
                const SizedBox(height: 6),
                Text('프로필을 수정하여 다시 신청해주세요', style: AppText.headline(26)),
                const SizedBox(height: 24),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.mode == ProfileSetupMode.registerChurch
                            ? Icons.add_business_rounded
                            : (_isPartLeader
                                  ? Icons.star_rounded
                                  : Icons.music_note_rounded),
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _contextBanner,
                          style: AppText.body(
                            13,
                            weight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('프로필 작성', style: AppText.headline(26)),
                const SizedBox(height: 8),
                Text(
                  '함께 찬양할 멤버 정보를 알려주세요',
                  style: AppText.body(14, color: AppColors.muted),
                ),
                const SizedBox(height: 24),
              ],

              // ── Profile Image
              Center(
                child: GestureDetector(
                  onTap: _uploading ? null : _pickImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primarySoft,
                          image: _imageBytes != null
                              ? DecorationImage(
                                  image: MemoryImage(_imageBytes!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _imageBytes == null
                            ? Icon(
                                Icons.person_rounded,
                                size: 48,
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
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.bg, width: 3),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '사진 추가 (선택)',
                  style: AppText.body(12, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 28),

              // ── Role info (now fixed — comes from previous screen)
              _Label(text: '신청 유형'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isChurchAdminFlow
                          ? Icons.admin_panel_settings_rounded
                          : (_isPartLeader
                                ? Icons.star_rounded
                                : Icons.music_note_rounded),
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        User.roleLabels[widget.requestedRole] ??
                            widget.requestedRole,
                        style: AppText.body(14, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isPartLeader) ...[
                const SizedBox(height: 12),
                _Label(text: '담당 파트 *'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _leaderPart,
                  items: User.selectableParts
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(User.partLabels[k] ?? k),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _leaderPart = v ?? _leaderPart),
                ),
              ],
              const SizedBox(height: 20),

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
                decoration: const InputDecoration(hintText: '별칭을 입력하세요'),
              ),
              const SizedBox(height: 16),

              _Label(text: '기수'),
              const SizedBox(height: 6),
              TextField(
                controller: _genCtrl,
                decoration: const InputDecoration(hintText: '기수를 입력하세요'),
              ),
              const SizedBox(height: 16),

              _Label(text: '찬양대 이름 (선택)'),
              const SizedBox(height: 6),
              TextField(
                controller: _choirNameCtrl,
                decoration: const InputDecoration(hintText: '찬양대 이름을 입력하세요'),
              ),
              const SizedBox(height: 16),

              _Label(text: '교회 내 직분 (선택)'),
              const SizedBox(height: 6),
              TextField(
                controller: _churchPositionCtrl,
                decoration: const InputDecoration(hintText: '직분을 입력하세요'),
              ),
              const SizedBox(height: 16),

              _Label(text: '파트'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _part,
                items: User.selectableParts
                    .map(
                      (k) => DropdownMenuItem(
                        value: k,
                        child: Text(User.partLabels[k] ?? k),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _part = v ?? _part;
                  if (_isPartLeader) _leaderPart = _part;
                }),
              ),
              const SizedBox(height: 16),

              _Label(text: '전화번호 (선택)'),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '전화번호를 입력하세요'),
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
                  child: Text(
                    _error!,
                    style: AppText.body(13, color: AppColors.error),
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_submitLabel),
                ),
              ),
              if (_isReapply) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await FirebaseService.signOut();
                    },
                    child: Text(
                      '다른 계정으로 로그인',
                      style: AppText.body(13, color: AppColors.muted),
                    ),
                  ),
                ),
              ],
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
    return Text(
      text,
      style: AppText.body(
        12,
        weight: FontWeight.w700,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
