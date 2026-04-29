class User {
  final String id;
  final String? name;
  final String? nickname;
  final String? email;
  final String? role;
  final String? generation;
  final String? choirName;
  final String? churchPosition;
  final String? part;
  final String? phone;
  final String? profileImageUrl;
  final String? partLeaderFor;
  final bool profileCompleted;
  // ── Approval workflow ──
  final String? requestedRole; // 'member' | 'part_leader' | 'church_admin'
  final String? requestedPart;
  final String? approvalStatus; // 'pending' | 'approved' | 'rejected'
  final String? rejectionReason;
  // ── Multi-tenant ──
  final String? churchId; // 승인 전엔 null
  final String? approvalScope; // 'church' | 'platform' | null
  final String? requestedChurchId; // platform scope일 때 churches doc 참조
  final bool isPlatformAdmin;

  User({
    required this.id,
    this.name,
    this.nickname,
    this.email,
    this.role,
    this.generation,
    this.choirName,
    this.churchPosition,
    this.part,
    this.phone,
    this.profileImageUrl,
    this.partLeaderFor,
    this.profileCompleted = false,
    this.requestedRole,
    this.requestedPart,
    this.approvalStatus,
    this.rejectionReason,
    this.churchId,
    this.approvalScope,
    this.requestedChurchId,
    this.isPlatformAdmin = false,
  });

  bool get isAdmin => role == 'admin' || role == 'church_admin';
  bool get isChurchAdmin => role == 'admin' || role == 'church_admin';
  bool get isOfficer => role == 'officer';
  bool get isPartLeader => role == 'part_leader';
  bool get hasManagePermission => isAdmin || isOfficer || isPartLeader;
  bool canActOnPart(String? targetPart) =>
      isAdmin || (isPartLeader && partLeaderFor == targetPart);

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'approved';
  bool get isRejected => approvalStatus == 'rejected';
  bool get needsChurchSelection => churchId == null && approvalScope == null;

  static const roleLabels = {
    'admin': '교회 관리자',
    'church_admin': '교회 관리자',
    'officer': '임원',
    'part_leader': '파트장',
    'member': '찬양대원',
  };

  String get roleLabel {
    if (isPartLeader && partLeaderFor != null) {
      final pLabel = partLabels[partLeaderFor] ?? partLeaderFor;
      return '$pLabel 파트장';
    }
    return roleLabels[role] ?? '찬양대원';
  }

  String get requestedRoleLabel {
    if (requestedRole == 'part_leader' && requestedPart != null) {
      final pLabel = partLabels[requestedPart] ?? requestedPart;
      return '$pLabel 파트장';
    }
    return roleLabels[requestedRole] ?? '찬양대원';
  }

  /// "홍길동 (길동이)" 형식. 별칭 없으면 그냥 이름.
  String get displayName {
    final n = name ?? '';
    if (nickname != null && nickname!.isNotEmpty) {
      return '$n ($nickname)';
    }
    return n;
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: (map['id'] ?? '').toString(),
      name: map['name'] as String?,
      nickname: map['nickname'] as String?,
      email: map['email'] as String?,
      role: map['role'] as String?,
      generation: map['generation'] as String?,
      choirName: map['choirName'] as String?,
      churchPosition: map['churchPosition'] as String?,
      part: map['part'] as String?,
      phone: map['phone'] as String?,
      profileImageUrl: map['profileImageUrl'] as String?,
      partLeaderFor: map['partLeaderFor'] as String?,
      profileCompleted: map['profileCompleted'] as bool? ?? false,
      requestedRole: map['requestedRole'] as String?,
      requestedPart: map['requestedPart'] as String?,
      approvalStatus: map['approvalStatus'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
      churchId: map['churchId'] as String?,
      approvalScope: map['approvalScope'] as String?,
      requestedChurchId: map['requestedChurchId'] as String?,
      isPlatformAdmin: map['isPlatformAdmin'] as bool? ?? false,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);

  static const partLabels = {
    'soprano': '소프라노',
    'alto': '알토',
    'tenor': '테너',
    'bass': '베이스',
    'band': '밴드',
    'orchestra': '오케스트라',
    'band_master': '밴드마스터',
    'officer_part': '임원',
    // legacy — 기존 데이터 호환용. '밴드'로 통합 표시.
    'guitar': '밴드',
    'bass_guitar': '밴드',
    'drum': '밴드',
    'keyboard': '밴드',
    'etc': '밴드',
  };

  /// 가입/승인 UI 드롭다운에서 선택 가능한 파트 목록 (legacy 키 제외).
  static const selectableParts = [
    'soprano',
    'alto',
    'tenor',
    'bass',
    'band',
    'orchestra',
    'band_master',
    'officer_part',
  ];

  String get partLabel => partLabels[part] ?? part ?? '';
  String get partInitial => partLabel.isNotEmpty ? partLabel[0] : '?';
}
