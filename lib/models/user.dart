class User {
  final String id;
  final String? name;
  final String? email;
  final String? role;
  final String? generation;
  final String? part;
  final String? phone;
  final bool profileCompleted;

  User({
    required this.id,
    this.name,
    this.email,
    this.role,
    this.generation,
    this.part,
    this.phone,
    this.profileCompleted = false,
  });

  bool get isAdmin => role == 'admin';

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: (map['id'] ?? '').toString(),
      name: map['name'] as String?,
      email: map['email'] as String?,
      role: map['role'] as String?,
      generation: map['generation'] as String?,
      part: map['part'] as String?,
      phone: map['phone'] as String?,
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
