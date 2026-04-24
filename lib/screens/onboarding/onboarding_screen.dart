import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../models/church.dart';
import '../../models/user.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

/// 로그인 직후 통합 온보딩 화면 — 가입 유형 선택과 프로필 입력을 한 페이지에서 처리.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _RoleChoice { member, partLeader, churchAdmin }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _RoleChoice _role = _RoleChoice.member;

  // ── 공통 프로필 컨트롤러
  final _nameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _genCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _part = 'soprano';
  String _leaderPart = 'soprano';

  // ── 교회 선택/검색 (찬양대원/파트장용)
  final _churchSearchCtrl = TextEditingController();
  String _churchQuery = '';
  Timer? _searchDebouncer;
  Church? _selectedChurch;

  // ── 새 교회 등록 (관리자용)
  final _churchNameCtrl = TextEditingController();
  final _churchAddressCtrl = TextEditingController();
  final _churchContactPhoneCtrl = TextEditingController();
  final _churchContactEmailCtrl = TextEditingController();

  // ── 이미지
  Uint8List? _imageBytes;
  String? _uploadedImageUrl;
  bool _uploading = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final fbUser = FirebaseService.currentUser;
    if (fbUser?.displayName != null) _nameCtrl.text = fbUser!.displayName!;
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    _genCtrl.dispose();
    _phoneCtrl.dispose();
    _churchSearchCtrl.dispose();
    _churchNameCtrl.dispose();
    _churchAddressCtrl.dispose();
    _churchContactPhoneCtrl.dispose();
    _churchContactEmailCtrl.dispose();
    super.dispose();
  }

  bool get _isPartLeader => _role == _RoleChoice.partLeader;
  bool get _isChurchAdmin => _role == _RoleChoice.churchAdmin;
  bool get _isJoinFlow => !_isChurchAdmin;

  String get _requestedRole => switch (_role) {
        _RoleChoice.member => 'member',
        _RoleChoice.partLeader => 'part_leader',
        _RoleChoice.churchAdmin => 'church_admin',
      };

  void _onChurchSearchChanged(String v) {
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _churchQuery = v);
    });
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

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return '이름을 입력해주세요';
    if (_isJoinFlow && _selectedChurch == null) return '가입할 교회를 선택해주세요';
    if (_isChurchAdmin) {
      if (_churchNameCtrl.text.trim().isEmpty) return '교회명을 입력해주세요';
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final profileData = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'nickname': _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
        'generation': _genCtrl.text.trim(),
        'part': _part,
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'profileImageUrl': _uploadedImageUrl,
        'requestedRole': _requestedRole,
        'requestedPart': _isPartLeader ? _leaderPart : null,
      };

      if (_isChurchAdmin) {
        await FirebaseService.requestChurchRegistration(
          name: _churchNameCtrl.text.trim(),
          address: _churchAddressCtrl.text.trim().isEmpty ? null : _churchAddressCtrl.text.trim(),
          contactPhone: _churchContactPhoneCtrl.text.trim().isEmpty ? null : _churchContactPhoneCtrl.text.trim(),
          contactEmail: _churchContactEmailCtrl.text.trim().isEmpty ? null : _churchContactEmailCtrl.text.trim(),
          profileData: profileData,
        );
      } else {
        await FirebaseService.requestChurchJoin(
          churchId: _selectedChurch!.id,
          requestedRole: _requestedRole,
          requestedPart: _isPartLeader ? _leaderPart : null,
          profileData: profileData,
        );
      }
      ref.invalidate(profileProvider);
      // main.dart의 myProfileStreamProvider가 승인 대기 화면으로 자동 전환
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
              Text('환영합니다', style: AppText.label()),
              const SizedBox(height: 6),
              Text('프로필을 완성해주세요', style: AppText.headline(26)),
              const SizedBox(height: 8),
              Text('함께 찬양할 멤버 정보를 알려주세요',
                  style: AppText.body(14, color: AppColors.muted)),
              const SizedBox(height: 28),

              // 프로필 사진
              Center(child: _ProfileImagePicker(
                imageBytes: _imageBytes,
                uploading: _uploading,
                onTap: _uploading ? null : _pickImage,
              )),
              const SizedBox(height: 8),
              Center(child: Text('사진 추가 (선택)', style: AppText.body(12, color: AppColors.muted))),
              const SizedBox(height: 28),

              // ── 가입 유형 라디오
              const _Label(text: '가입 유형 *'),
              const SizedBox(height: 8),
              _RoleOptionCard(
                icon: Icons.person_rounded,
                title: '찬양대원',
                subtitle: '일반 단원으로 가입합니다',
                selected: _role == _RoleChoice.member,
                onTap: () => setState(() => _role = _RoleChoice.member),
              ),
              const SizedBox(height: 8),
              _RoleOptionCard(
                icon: Icons.star_rounded,
                title: '파트장',
                subtitle: '파트를 이끄는 역할입니다',
                selected: _role == _RoleChoice.partLeader,
                onTap: () => setState(() => _role = _RoleChoice.partLeader),
              ),
              const SizedBox(height: 8),
              _RoleOptionCard(
                icon: Icons.admin_panel_settings_rounded,
                title: '새 교회 등록 (관리자)',
                subtitle: '우리 교회를 직접 등록하고 관리합니다',
                selected: _role == _RoleChoice.churchAdmin,
                onTap: () => setState(() => _role = _RoleChoice.churchAdmin),
              ),
              const SizedBox(height: 12),
              Container(
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

              // ── 섹션: 교회 선택 또는 교회 등록
              if (_isJoinFlow) _buildChurchPickerSection() else _buildChurchRegisterSection(),

              const SizedBox(height: 24),

              // ── 기본 프로필 필드
              const _Label(text: '이름 *'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: '실명을 입력하세요'),
              ),
              const SizedBox(height: 16),

              const _Label(text: '별칭 (선택)'),
              const SizedBox(height: 6),
              TextField(
                controller: _nicknameCtrl,
                decoration: const InputDecoration(hintText: '예: 길동이 → "홍길동 (길동이)"로 표시됩니다'),
              ),
              const SizedBox(height: 16),

              const _Label(text: '기수'),
              const SizedBox(height: 6),
              TextField(
                controller: _genCtrl,
                decoration: const InputDecoration(hintText: '예: 91기, 23기'),
              ),
              const SizedBox(height: 16),

              const _Label(text: '소속 파트 *'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _part,
                items: User.selectableParts
                    .map((k) => DropdownMenuItem(value: k, child: Text(User.partLabels[k] ?? k)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _part = v ?? _part;
                  if (_isPartLeader) _leaderPart = _part;
                }),
              ),
              if (_isPartLeader) ...[
                const SizedBox(height: 16),
                const _Label(text: '담당 파트 * (파트장으로 이끌 파트)'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _leaderPart,
                  items: User.selectableParts
                      .map((k) => DropdownMenuItem(value: k, child: Text(User.partLabels[k] ?? k)))
                      .toList(),
                  onChanged: (v) => setState(() => _leaderPart = v ?? _leaderPart),
                ),
              ],
              const SizedBox(height: 16),

              const _Label(text: '전화번호 (선택)'),
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

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('가입 신청'),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: TextButton(
                onPressed: _saving ? null : () async { await FirebaseService.signOut(); },
                child: Text('다른 계정으로 로그인', style: AppText.body(13, color: AppColors.muted)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChurchPickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label(text: '가입할 교회 *'),
        const SizedBox(height: 6),
        if (_selectedChurch != null)
          _SelectedChurchTile(
            church: _selectedChurch!,
            onClear: () => setState(() => _selectedChurch = null),
          )
        else ...[
          TextField(
            controller: _churchSearchCtrl,
            onChanged: _onChurchSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '교회명으로 검색 (예: 갈렙)',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _churchSearchCtrl.text.isEmpty ? null : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _churchSearchCtrl.clear();
                  _onChurchSearchChanged('');
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ChurchSearchResults(
            query: _churchQuery,
            onSelect: (c) => setState(() {
              _selectedChurch = c;
              _churchSearchCtrl.clear();
              _churchQuery = '';
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildChurchRegisterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label(text: '새 교회 정보'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.add_business_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '신청자는 등록 승인 시 교회 관리자로 지정됩니다',
              style: AppText.body(12, weight: FontWeight.w600, color: AppColors.primary),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        const _Label(text: '교회명 *'),
        const SizedBox(height: 6),
        TextField(
          controller: _churchNameCtrl,
          decoration: const InputDecoration(hintText: '예: 갈렙찬양대'),
        ),
        const SizedBox(height: 12),
        const _Label(text: '주소 (선택)'),
        const SizedBox(height: 6),
        TextField(
          controller: _churchAddressCtrl,
          decoration: const InputDecoration(hintText: '예: 서울시 강남구 ...'),
        ),
        const SizedBox(height: 12),
        const _Label(text: '대표 연락처 (선택)'),
        const SizedBox(height: 6),
        TextField(
          controller: _churchContactPhoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '010-0000-0000'),
        ),
        const SizedBox(height: 12),
        const _Label(text: '대표 이메일 (선택)'),
        const SizedBox(height: 6),
        TextField(
          controller: _churchContactEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'church@example.com'),
        ),
      ],
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

class _ProfileImagePicker extends StatelessWidget {
  final Uint8List? imageBytes;
  final bool uploading;
  final VoidCallback? onTap;
  const _ProfileImagePicker({
    required this.imageBytes,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        Container(
          width: 110, height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primarySoft,
            image: imageBytes != null
                ? DecorationImage(image: MemoryImage(imageBytes!), fit: BoxFit.cover)
                : null,
          ),
          child: imageBytes == null
              ? Icon(Icons.person_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.4))
              : null,
        ),
        if (uploading)
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
    );
  }
}

class _RoleOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                color: selected ? Colors.white : AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(15, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: AppText.body(12, color: AppColors.muted)),
              ],
            )),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.muted,
            ),
          ]),
        ),
      ),
    );
  }
}

class _SelectedChurchTile extends StatelessWidget {
  final Church church;
  final VoidCallback onClear;
  const _SelectedChurchTile({required this.church, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.church_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(church.name, style: AppText.body(15, weight: FontWeight.w700)),
            if (church.address != null && church.address!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(church.address!, style: AppText.body(12, color: AppColors.muted)),
            ],
          ],
        )),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: onClear,
          tooltip: '다시 선택',
        ),
      ]),
    );
  }
}

class _ChurchSearchResults extends ConsumerWidget {
  final String query;
  final void Function(Church) onSelect;
  const _ChurchSearchResults({required this.query, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(churchSearchProvider(query));
    return result.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('검색 실패: $e', style: AppText.body(12, color: AppColors.error)),
      ),
      data: (churches) {
        if (churches.isEmpty && query.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Icon(Icons.search_off_rounded, size: 18, color: AppColors.muted.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '찾으시는 교회가 없어요. 상단에서 "새 교회 등록"을 선택해 직접 등록할 수 있습니다',
                style: AppText.body(12, color: AppColors.muted),
              )),
            ]),
          );
        }
        if (churches.isEmpty) return const SizedBox.shrink();
        return Column(
          children: churches.take(6).map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => onSelect(c),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.church_rounded, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: AppText.body(14, weight: FontWeight.w700)),
                        if (c.address != null && c.address!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(c.address!, style: AppText.body(11, color: AppColors.muted)),
                        ],
                      ],
                    )),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
              ),
            ),
          )).toList(),
        );
      },
    );
  }
}
