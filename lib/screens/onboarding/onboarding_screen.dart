import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../models/church.dart';
import '../../models/user.dart';
import '../../providers/app_providers.dart';
import '../../services/address_search/address_search.dart';
import '../../services/firebase_service.dart';

/// 로그인 직후 통합 온보딩 화면 — 가입 유형 선택과 프로필 입력을 한 페이지에서 처리.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _RoleChoice { member, partLeader, churchAdmin }

enum _ValidationTarget {
  churchPicker,
  churchAddress,
  churchName,
  choirName,
  churchContactPhone,
  churchContactEmail,
  name,
}

class _ValidationIssue {
  final String message;
  final _ValidationTarget target;

  const _ValidationIssue(this.message, this.target);
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _RoleChoice _role = _RoleChoice.member;

  final _scrollCtrl = ScrollController();

  // ── 공통 프로필 컨트롤러
  final _nameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _genCtrl = TextEditingController();
  final _choirNameCtrl = TextEditingController();
  final _churchPositionCtrl = TextEditingController();
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

  final _churchPickerKey = GlobalKey();
  final _churchAddressKey = GlobalKey();
  final _churchNameKey = GlobalKey();
  final _choirNameKey = GlobalKey();
  final _churchContactPhoneKey = GlobalKey();
  final _churchContactEmailKey = GlobalKey();
  final _nameKey = GlobalKey();

  final _churchSearchFocus = FocusNode();
  final _churchNameFocus = FocusNode();
  final _choirNameFocus = FocusNode();
  final _churchContactPhoneFocus = FocusNode();
  final _churchContactEmailFocus = FocusNode();
  final _nameFocus = FocusNode();

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
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    _genCtrl.dispose();
    _choirNameCtrl.dispose();
    _churchPositionCtrl.dispose();
    _phoneCtrl.dispose();
    _churchSearchCtrl.dispose();
    _churchNameCtrl.dispose();
    _churchAddressCtrl.dispose();
    _churchContactPhoneCtrl.dispose();
    _churchContactEmailCtrl.dispose();
    _churchSearchFocus.dispose();
    _churchNameFocus.dispose();
    _choirNameFocus.dispose();
    _churchContactPhoneFocus.dispose();
    _churchContactEmailFocus.dispose();
    _nameFocus.dispose();
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

  void _switchToChurchRegister({String? seedName}) {
    setState(() {
      _role = _RoleChoice.churchAdmin;
      if (seedName != null && seedName.trim().isNotEmpty) {
        _churchNameCtrl.text = seedName.trim();
      }
      _selectedChurch = null;
      _churchSearchCtrl.clear();
      _churchQuery = '';
    });
  }

  Future<void> _openAddressSearchDialog() async {
    final officialAddress = await openOfficialAddressSearch();
    if (officialAddress != null &&
        officialAddress.trim().isNotEmpty &&
        mounted) {
      setState(() => _churchAddressCtrl.text = officialAddress.trim());
      return;
    }

    if (officialAddress != null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('카카오/다음 주소검색을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.')),
    );
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

  Future<void> _signOutAndReturnToLogin() async {
    ref.read(loggedOutProvider.notifier).state = true;
    ref.read(onboardingPreviewDismissedProvider.notifier).state = true;
    ref.read(localPreviewModeProvider.notifier).state = false;
    ref.read(loginPreviewModeProvider.notifier).state = true;
    try {
      await FirebaseService.signOut();
    } catch (e) {
      debugPrint('Sign out skipped: $e');
    }
  }

  _ValidationIssue? _validate() {
    if (_isChurchAdmin) {
      if (_churchAddressCtrl.text.trim().isEmpty) {
        return const _ValidationIssue(
          '공식 주소검색으로 교회 주소를 입력해주세요',
          _ValidationTarget.churchAddress,
        );
      }
      if (_churchNameCtrl.text.trim().isEmpty) {
        return const _ValidationIssue(
          '교회명을 입력해주세요',
          _ValidationTarget.churchName,
        );
      }
      if (_choirNameCtrl.text.trim().isEmpty) {
        return const _ValidationIssue(
          '찬양대 이름을 입력해주세요',
          _ValidationTarget.choirName,
        );
      }
      if (_churchContactPhoneCtrl.text.trim().isEmpty) {
        return const _ValidationIssue(
          '대표 연락처를 입력해주세요',
          _ValidationTarget.churchContactPhone,
        );
      }
      if (_churchContactEmailCtrl.text.trim().isEmpty) {
        return const _ValidationIssue(
          '대표 이메일을 입력해주세요',
          _ValidationTarget.churchContactEmail,
        );
      }
    } else if (_selectedChurch == null) {
      return const _ValidationIssue(
        '가입할 교회를 선택해주세요',
        _ValidationTarget.churchPicker,
      );
    }

    if (_nameCtrl.text.trim().isEmpty) {
      return const _ValidationIssue('이름을 입력해주세요', _ValidationTarget.name);
    }
    return null;
  }

  GlobalKey _keyForTarget(_ValidationTarget target) => switch (target) {
    _ValidationTarget.churchPicker => _churchPickerKey,
    _ValidationTarget.churchAddress => _churchAddressKey,
    _ValidationTarget.churchName => _churchNameKey,
    _ValidationTarget.choirName => _choirNameKey,
    _ValidationTarget.churchContactPhone => _churchContactPhoneKey,
    _ValidationTarget.churchContactEmail => _churchContactEmailKey,
    _ValidationTarget.name => _nameKey,
  };

  FocusNode? _focusForTarget(_ValidationTarget target) => switch (target) {
    _ValidationTarget.churchPicker => _churchSearchFocus,
    _ValidationTarget.churchAddress => null,
    _ValidationTarget.churchName => _churchNameFocus,
    _ValidationTarget.choirName => _choirNameFocus,
    _ValidationTarget.churchContactPhone => _churchContactPhoneFocus,
    _ValidationTarget.churchContactEmail => _churchContactEmailFocus,
    _ValidationTarget.name => _nameFocus,
  };

  Future<void> _guideToValidationIssue(_ValidationIssue issue) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final targetContext = _keyForTarget(issue.target).currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }
    if (!mounted) return;
    _focusForTarget(issue.target)?.requestFocus();
  }

  Future<void> _submit() async {
    final issue = _validate();
    if (issue != null) {
      setState(() => _error = issue.message);
      await _guideToValidationIssue(issue);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profileData = <String, dynamic>{
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
        'requestedRole': _requestedRole,
        'requestedPart': _isPartLeader ? _leaderPart : null,
      };

      if (_isChurchAdmin) {
        await FirebaseService.requestChurchRegistration(
          name: _churchNameCtrl.text.trim(),
          address: _churchAddressCtrl.text.trim(),
          contactPhone: _churchContactPhoneCtrl.text.trim(),
          contactEmail: _churchContactEmailCtrl.text.trim(),
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
      ref.read(onboardingPreviewDismissedProvider.notifier).state = true;
      ref.invalidate(profileProvider);
      ref.invalidate(myProfileStreamProvider);
      // main.dart의 myProfileStreamProvider가 승인 대기 화면으로 자동 전환
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '저장 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.primary,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF041D3D), AppColors.primary, Color(0xFF031225)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18, 20, 18, keyboardBottom + 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _OnboardingHero(),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFAF6),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StepHeader(
                        step: '01',
                        title: '가입 방식',
                        subtitle: '가입 유형을 먼저 선택해주세요.',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _RoleOptionCard(
                              icon: Icons.person_rounded,
                              title: '단원',
                              subtitle: '승인된 교회',
                              compact: true,
                              selected: _role == _RoleChoice.member,
                              onTap: () =>
                                  setState(() => _role = _RoleChoice.member),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _RoleOptionCard(
                              icon: Icons.stars_rounded,
                              title: '파트장',
                              subtitle: '담당 파트',
                              compact: true,
                              selected: _role == _RoleChoice.partLeader,
                              onTap: () => setState(() {
                                _role = _RoleChoice.partLeader;
                                _leaderPart = _part;
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _RoleOptionCard(
                        icon: Icons.add_business_rounded,
                        title: '등록된 교회가 없어요',
                        subtitle: '주소 확인 후 교회 등록 신청',
                        selected: _role == _RoleChoice.churchAdmin,
                        onTap: () => _switchToChurchRegister(),
                      ),
                      const SizedBox(height: 12),
                      _InfoCallout(
                        icon: Icons.verified_user_rounded,
                        text: _isChurchAdmin
                            ? '교회 등록 신청은 플랫폼 관리자 승인 후 최종 등록됩니다.'
                            : '교회 관리자가 승인하면 가입이 완료됩니다.',
                      ),
                      const SizedBox(height: 22),

                      _StepHeader(
                        step: '02',
                        title: _isJoinFlow ? '교회 선택' : '교회 등록 신청',
                        subtitle: _isJoinFlow
                            ? '등록된 교회를 검색해 선택하세요.'
                            : '공식 주소 확인 후 승인 대기로 접수됩니다.',
                      ),
                      const SizedBox(height: 12),
                      if (_isJoinFlow)
                        KeyedSubtree(
                          key: _churchPickerKey,
                          child: _buildChurchPickerSection(),
                        )
                      else
                        _buildChurchRegisterSection(),

                      const SizedBox(height: 22),
                      _StepHeader(
                        step: '03',
                        title: '내 정보',
                        subtitle: '실명과 파트를 정확히 적어주세요.',
                      ),
                      const SizedBox(height: 16),

                      Center(
                        child: _ProfileImagePicker(
                          imageBytes: _imageBytes,
                          uploading: _uploading,
                          onTap: _uploading ? null : _pickImage,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          '프로필 사진 추가 (선택)',
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const _Label(text: '이름 *'),
                      const SizedBox(height: 6),
                      KeyedSubtree(
                        key: _nameKey,
                        child: TextField(
                          controller: _nameCtrl,
                          focusNode: _nameFocus,
                          decoration: const InputDecoration(
                            hintText: '실명을 입력하세요',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      const _Label(text: '별칭 (선택)'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nicknameCtrl,
                        decoration: const InputDecoration(
                          hintText: '별칭을 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 16),

                      const _Label(text: '기수'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _genCtrl,
                        decoration: const InputDecoration(
                          hintText: '기수를 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (!_isChurchAdmin) ...[
                        const _Label(text: '찬양대 이름 (선택)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _choirNameCtrl,
                          decoration: const InputDecoration(
                            hintText: '찬양대 이름을 입력하세요',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      const _Label(text: '교회 내 직분 (선택)'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _churchPositionCtrl,
                        decoration: const InputDecoration(
                          hintText: '직분을 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 16),

                      const _Label(text: '소속 파트 *'),
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
                      if (_isPartLeader) ...[
                        const SizedBox(height: 16),
                        const _Label(text: '담당 파트 *'),
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
                      const SizedBox(height: 16),

                      const _Label(text: '전화번호 (선택)'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '전화번호를 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: AppText.body(13, color: AppColors.error),
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _submit,
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
                              : Text(_isChurchAdmin ? '교회 등록 승인 요청' : '가입 신청'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _saving ? null : _signOutAndReturnToLogin,
                          child: Text(
                            '다른 계정으로 로그인',
                            style: AppText.body(13, color: AppColors.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChurchPickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedChurch != null)
          _SelectedChurchTile(
            church: _selectedChurch!,
            onClear: () => setState(() => _selectedChurch = null),
          )
        else ...[
          TextField(
            controller: _churchSearchCtrl,
            focusNode: _churchSearchFocus,
            onChanged: _onChurchSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '교회명으로 검색',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _churchSearchCtrl.text.isEmpty
                  ? null
                  : IconButton(
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
            fallbackName: _churchSearchCtrl.text,
            onSelect: (c) => setState(() {
              _selectedChurch = c;
              _churchSearchCtrl.clear();
              _churchQuery = '';
            }),
            onRegisterNew: _switchToChurchRegister,
          ),
        ],
      ],
    );
  }

  Widget _buildChurchRegisterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoCallout(
          icon: Icons.manage_search_rounded,
          text: '먼저 공식 주소를 검색해 교회 위치를 확인해주세요.',
        ),
        const SizedBox(height: 12),
        const _Label(text: '공식 주소 *'),
        const SizedBox(height: 6),
        KeyedSubtree(
          key: _churchAddressKey,
          child: _AddressSearchField(
            controller: _churchAddressCtrl,
            onSearch: _openAddressSearchDialog,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '주소는 교회 중복 확인과 승인 검토에 사용됩니다. 승인 전에는 앱에 등록되지 않습니다.',
          style: AppText.body(11, color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        const _Label(text: '교회명 *'),
        const SizedBox(height: 6),
        KeyedSubtree(
          key: _churchNameKey,
          child: TextField(
            controller: _churchNameCtrl,
            focusNode: _churchNameFocus,
            decoration: const InputDecoration(hintText: '교회명을 입력하세요'),
          ),
        ),
        const SizedBox(height: 12),
        const _Label(text: '찬양대 이름 *'),
        const SizedBox(height: 6),
        KeyedSubtree(
          key: _choirNameKey,
          child: TextField(
            controller: _choirNameCtrl,
            focusNode: _choirNameFocus,
            decoration: const InputDecoration(hintText: '찬양대 이름을 입력하세요'),
          ),
        ),
        const SizedBox(height: 12),
        const _Label(text: '대표 연락처 *'),
        const SizedBox(height: 6),
        KeyedSubtree(
          key: _churchContactPhoneKey,
          child: TextField(
            controller: _churchContactPhoneCtrl,
            focusNode: _churchContactPhoneFocus,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '대표 연락처를 입력하세요'),
          ),
        ),
        const SizedBox(height: 12),
        const _Label(text: '대표 이메일 *'),
        const SizedBox(height: 6),
        KeyedSubtree(
          key: _churchContactEmailKey,
          child: TextField(
            controller: _churchContactEmailCtrl,
            focusNode: _churchContactEmailFocus,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: '대표 이메일을 입력하세요'),
          ),
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

class _AddressSearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;

  const _AddressSearchField({required this.controller, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasAddress = value.text.trim().isNotEmpty;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onSearch,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasAddress
                      ? AppColors.primaryContainer.withValues(alpha: 0.55)
                      : AppColors.border.withValues(alpha: 0.8),
                  width: hasAddress ? 1.35 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasAddress
                        ? Icons.location_on_rounded
                        : Icons.manage_search_rounded,
                    size: 22,
                    color: hasAddress
                        ? AppColors.primaryContainer
                        : AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasAddress ? value.text.trim() : '공식 주소를 먼저 검색하세요',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        14,
                        weight: hasAddress ? FontWeight.w700 : FontWeight.w500,
                        color: hasAddress ? AppColors.ink : AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      hasAddress ? '변경' : '검색',
                      style: AppText.body(
                        12,
                        weight: FontWeight.w800,
                        color: AppColors.primaryContainer,
                      ),
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
}

class _AddressSearchDialog extends StatefulWidget {
  final String initialQuery;

  const _AddressSearchDialog({required this.initialQuery});

  @override
  State<_AddressSearchDialog> createState() => _AddressSearchDialogState();
}

class _AddressSearchDialogState extends State<_AddressSearchDialog> {
  late final TextEditingController _queryCtrl;
  Timer? _searchDebouncer;
  List<_AddressOption> _apiAddresses = const [];
  bool _isSearching = false;
  String? _searchError;

  static const _jusoApiKey = String.fromEnvironment('JUSO_API_KEY');
  static const _jusoEndpoint =
      'https://business.juso.go.kr/addrlink/addrLinkApi.do';

  static const _sampleAddresses = [
    _AddressOption(
      title: '갈렙교회',
      road: '서울특별시 서초구 반포대로 58',
      jibun: '서울특별시 서초구 서초동 1538-1',
    ),
    _AddressOption(
      title: '예원교회',
      road: '서울특별시 강남구 테헤란로 152',
      jibun: '서울특별시 강남구 역삼동 737',
    ),
    _AddressOption(
      title: '부산시민회관',
      road: '부산광역시 동구 자성로133번길 16',
      jibun: '부산광역시 동구 범일동 830-31',
    ),
    _AddressOption(
      title: '세종문화회관',
      road: '서울특별시 종로구 세종대로 175',
      jibun: '서울특별시 종로구 세종로 81-3',
    ),
    _AddressOption(
      title: '예술의전당',
      road: '서울특별시 서초구 남부순환로 2406',
      jibun: '서울특별시 서초구 서초동 700',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    if (_usesOfficialApi && widget.initialQuery.trim().isNotEmpty) {
      _searchOfficialAddress(widget.initialQuery.trim());
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  bool get _usesOfficialApi => _jusoApiKey.trim().isNotEmpty;

  List<_AddressOption> get _filteredAddresses {
    final query = _queryCtrl.text.trim().toLowerCase();
    if (_usesOfficialApi) return _apiAddresses;
    if (query.isEmpty) return _sampleAddresses;
    return _sampleAddresses.where((address) {
      return address.title.toLowerCase().contains(query) ||
          address.road.toLowerCase().contains(query) ||
          address.jibun.toLowerCase().contains(query);
    }).toList();
  }

  void _onQueryChanged(String value) {
    setState(() {
      if (!_usesOfficialApi) return;
      _searchError = null;
      if (value.trim().isEmpty) _apiAddresses = const [];
    });

    if (!_usesOfficialApi) return;
    _searchDebouncer?.cancel();
    final keyword = value.trim();
    if (keyword.length < 2) {
      setState(() => _isSearching = false);
      return;
    }
    _searchDebouncer = Timer(
      const Duration(milliseconds: 350),
      () => _searchOfficialAddress(keyword),
    );
  }

  Future<void> _searchOfficialAddress(String keyword) async {
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final uri = Uri.parse(_jusoEndpoint).replace(
        queryParameters: {
          'confmKey': _jusoApiKey,
          'currentPage': '1',
          'countPerPage': '10',
          'keyword': keyword,
          'resultType': 'json',
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('주소검색 서버 응답이 원활하지 않습니다.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final results = decoded['results'] as Map<String, dynamic>?;
      final common = results?['common'] as Map<String, dynamic>?;
      final errorCode = common?['errorCode']?.toString();
      final errorMessage = common?['errorMessage']?.toString();
      if (errorCode != '0') {
        throw Exception(errorMessage ?? '주소검색에 실패했습니다.');
      }

      final rawJuso = results?['juso'];
      final jusoList = rawJuso is List ? rawJuso : const [];
      final addresses = jusoList
          .whereType<Map<String, dynamic>>()
          .map(_AddressOption.fromJuso)
          .where((address) => address.road.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _apiAddresses = addresses;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _apiAddresses = const [];
        _isSearching = false;
        _searchError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _selectAddress(String address) {
    Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) {
    final addresses = _filteredAddresses;
    final manualAddress = _queryCtrl.text.trim();
    final showManualAddressButton =
        manualAddress.isNotEmpty && !_usesOfficialApi;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFAF6),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.manage_search_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '공식 주소 검색',
                          style: AppText.body(18, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '도로명, 건물명, 지번으로 검색하세요.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            12,
                            color: AppColors.muted,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _queryCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                decoration: const InputDecoration(
                  hintText: '예: 예원교회, 세종대로 175',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_isSearching)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_searchError != null)
                        _InlineNotice(
                          icon: Icons.info_outline_rounded,
                          text: _searchError!,
                          tone: _NoticeTone.error,
                        )
                      else if (addresses.isEmpty)
                        _ManualAddressCard(
                          address: manualAddress,
                          officialMode: _usesOfficialApi,
                          onUse: manualAddress.isEmpty || _usesOfficialApi
                              ? null
                              : () => _selectAddress(manualAddress),
                        )
                      else
                        ...addresses.map(
                          (address) => _AddressResultTile(
                            option: address,
                            onTap: () => _selectAddress(address.road),
                          ),
                        ),
                      if (showManualAddressButton) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _selectAddress(manualAddress),
                            icon: const Icon(
                              Icons.edit_location_alt_rounded,
                              size: 17,
                            ),
                            label: const Text('입력한 주소 사용'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _usesOfficialApi
                    ? '행정안전부 도로명주소 검색 API 결과를 사용합니다.'
                    : 'API 승인키가 없어서 테스트 주소를 표시하고 있습니다. 운영 키를 연결하면 실제 공식 검색 결과로 바뀝니다.',
                style: AppText.body(11, color: AppColors.muted, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressOption {
  final String title;
  final String road;
  final String jibun;

  const _AddressOption({
    required this.title,
    required this.road,
    required this.jibun,
  });

  factory _AddressOption.fromJuso(Map<String, dynamic> json) {
    final buildingName = json['bdNm']?.toString().trim() ?? '';
    final roadAddress =
        json['roadAddr']?.toString().trim() ??
        json['roadAddrPart1']?.toString().trim() ??
        '';
    final jibunAddress = json['jibunAddr']?.toString().trim() ?? '';
    return _AddressOption(
      title: buildingName.isNotEmpty ? buildingName : roadAddress,
      road: roadAddress,
      jibun: jibunAddress,
    );
  }
}

class _AddressResultTile extends StatelessWidget {
  final _AddressOption option;
  final VoidCallback onTap;

  const _AddressResultTile({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.34),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(13, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        option.road,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          12,
                          weight: FontWeight.w600,
                          color: AppColors.ink,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        option.jibun,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          11,
                          color: AppColors.muted,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualAddressCard extends StatelessWidget {
  final String address;
  final bool officialMode;
  final VoidCallback? onUse;

  const _ManualAddressCard({
    required this.address,
    required this.officialMode,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('검색 결과가 없어요', style: AppText.body(13, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            officialMode
                ? '검색어를 더 구체적으로 입력해주세요.'
                : '주소를 정확히 입력했다면 직접 사용할 수 있습니다.',
            style: AppText.body(12, color: AppColors.muted, height: 1.35),
          ),
          if (!officialMode) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onUse,
                child: Text(address.isEmpty ? '주소를 입력해주세요' : '입력한 주소 사용'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingHero extends StatelessWidget {
  const _OnboardingHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'C.C Note 가입',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.headline(
                    27,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '교회 승인 후 함께 참여해요.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    13,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.25,
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

class _StepHeader extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;

  const _StepHeader({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            step,
            style: AppText.body(
              11,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(18, weight: FontWeight.w800, height: 1.18),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  12,
                  weight: FontWeight.w500,
                  color: AppColors.muted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCallout extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoCallout({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.secondaryContainer.withValues(alpha: 0.64),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.body(
                12,
                weight: FontWeight.w700,
                color: AppColors.secondary,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _NoticeTone { error, muted }

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final _NoticeTone tone;

  const _InlineNotice({
    required this.icon,
    required this.text,
    this.tone = _NoticeTone.muted,
  });

  @override
  Widget build(BuildContext context) {
    final isError = tone == _NoticeTone.error;
    final color = isError ? AppColors.error : AppColors.muted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.error.withValues(alpha: 0.06)
            : AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isError ? 0.14 : 0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.84)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                12,
                weight: FontWeight.w600,
                color: color,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE7EEF7),
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
              image: imageBytes != null
                  ? DecorationImage(
                      image: MemoryImage(imageBytes!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageBytes == null
                ? Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: AppColors.primary.withValues(alpha: 0.4),
                  )
                : null,
          ),
          if (uploading)
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
                border: Border.all(color: const Color(0xFFFBFAF6), width: 3),
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
    );
  }
}

class _RoleOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  const _RoleOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryContainer : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.primaryContainer
                  : AppColors.border.withValues(alpha: 0.34),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 9),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 36 : 40,
                height: compact ? 36 : 40,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.14)
                      : const Color(0xFFEAF1F8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : AppColors.primary,
                  size: compact ? 18 : 20,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        compact ? 14 : 15,
                        weight: FontWeight.w800,
                        color: selected ? Colors.white : AppColors.ink,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 3),
                    Text(
                      subtitle,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        compact ? 11 : 12,
                        weight: FontWeight.w500,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppColors.muted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected
                    ? AppColors.secondaryContainer
                    : AppColors.muted.withValues(alpha: 0.78),
                size: compact ? 18 : 20,
              ),
            ],
          ),
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
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryContainer, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.church_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  church.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(15, weight: FontWeight.w700),
                ),
                if (church.address != null && church.address!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    church.address!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onClear,
            tooltip: '다시 선택',
          ),
        ],
      ),
    );
  }
}

class _ChurchSearchResults extends ConsumerWidget {
  final String query;
  final String fallbackName;
  final void Function(Church) onSelect;
  final void Function({String? seedName}) onRegisterNew;

  const _ChurchSearchResults({
    required this.query,
    required this.fallbackName,
    required this.onSelect,
    required this.onRegisterNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(churchSearchProvider(query));
    return result.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) {
        debugPrint('Church search failed: $e');
        if (query.trim().isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _InlineNotice(
            icon: Icons.info_outline_rounded,
            text: '교회 검색을 잠시 불러오지 못했어요. 다시 검색하거나 새 교회 등록 신청을 이용해주세요.',
            tone: _NoticeTone.muted,
          ),
        );
      },
      data: (churches) {
        if (churches.isEmpty && query.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 18,
                        color: AppColors.muted.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '등록된 교회를 찾지 못했어요',
                          style: AppText.body(13, weight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '새 교회 등록 신청으로 이동해 공식 주소를 입력하면 플랫폼 관리자가 확인 후 등록합니다.',
                    style: AppText.body(
                      12,
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => onRegisterNew(seedName: fallbackName),
                      icon: const Icon(Icons.add_business_rounded, size: 17),
                      label: const Text('새 교회 등록 신청'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (churches.isEmpty) return const SizedBox.shrink();
        return Column(
          children: churches
              .take(6)
              .map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => onSelect(c),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.church_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body(
                                      14,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  if (c.address != null &&
                                      c.address!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      c.address!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.body(
                                        11,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
