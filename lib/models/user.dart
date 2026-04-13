class User {
  final String id;
  final String? name;
  final String? nickname;
  final String? email;
  final String? role;
  final String? generation;
  final String? part;
  final String? phone;
  final String? profileImageUrl;
  final bool profileCompleted;

  User({
    required this.id,
    this.name,
    this.nickname,
    this.email,
    this.role,
    this.generation,
    this.part,
    this.phone,
    this.profileImageUrl,
    this.profileCompleted = false,
  });

  bool get isAdmin => role == 'admin';
  bool get isOfficer => role == 'officer';
  /// 관리자/임원 권한 (콘텐츠 작성, 출석 관리 등)
  bool get hasManagePermission => isAdmin || isOfficer;

  static const roleLabels = {
    'admin': '관리자',
    'officer': '임원',
    'member': '단원',
  };

  String get roleLabel => roleLabels[role] ?? '단원';

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
      part: map['part'] as String?,
      phone: map['phone'] as String?,
      profileImageUrl: map['profileImageUrl'] as String?,
      profileCompleted: map['profileCompleted'] as bool? ?? false,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);

  static const partLabels = {
    'soprano': '소프라노',
    'alto': '알토',
    'tenor': '테너',
    'bass': '베이스',
    'guitar': '기타',
    'bass_guitar': '베이스기타',
    'drum': '드럼',
    'keyboard': '건반',
    'etc': '기타(악기)',
  };

  String get partLabel => partLabels[part] ?? part ?? '';
  String get partInitial => partLabel.isNotEmpty ? partLabel[0] : '?';
}
