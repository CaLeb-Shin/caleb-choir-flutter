class User {
  final int id;
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

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String?,
      generation: json['generation'] as String?,
      part: json['part'] as String?,
      phone: json['phone'] as String?,
      profileCompleted: json['profileCompleted'] as bool? ?? false,
    );
  }

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
