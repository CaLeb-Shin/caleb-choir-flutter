class Church {
  final String id;
  final String name;
  final String nameLower;
  final String? address;
  final String? choirName;
  final String? logoUrl;
  final String? contactPhone;
  final String? contactEmail;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String requestedBy; // uid
  final List<String> adminUids;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? approvedAt;

  // ── Subscription (member-count based, org-level). See billing plan.
  final String plan; // 'free' | 'paid' | 'sponsored'
  final int paidBlocks; // blocks of [blockSize] members purchased
  final int activeMemberCount; // maintained server-side
  final int? sponsoredLimit; // 미자립 grant: overrides the derived limit
  final String
  subscriptionStatus; // 'none' | 'active' | 'past_due' | 'canceled'

  /// Free tier ceiling and paid block size. Server `config/billing` may tune
  /// these later; these are the defaults the app reasons with.
  /// 100 members free; beyond that, subscribe per additional 10.
  static const int freeLimit = 100;
  static const int blockSize = 10;

  Church({
    required this.id,
    required this.name,
    required this.nameLower,
    required this.status,
    required this.requestedBy,
    this.adminUids = const [],
    this.address,
    this.choirName,
    this.logoUrl,
    this.contactPhone,
    this.contactEmail,
    this.rejectionReason,
    this.createdAt,
    this.approvedAt,
    this.plan = 'free',
    this.paidBlocks = 0,
    this.activeMemberCount = 0,
    this.sponsoredLimit,
    this.subscriptionStatus = 'none',
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  /// Max approved members allowed: a sponsor grant wins, otherwise free 50 plus
  /// [blockSize] per purchased block.
  int get effectiveMemberLimit =>
      sponsoredLimit ?? (freeLimit + paidBlocks * blockSize);

  /// True once the church is at/over its member allowance (blocks new approvals).
  bool get isOverMemberLimit => activeMemberCount >= effectiveMemberLimit;

  int get remainingMemberSlots {
    final left = effectiveMemberLimit - activeMemberCount;
    return left < 0 ? 0 : left;
  }

  bool get isSponsored => plan == 'sponsored' || sponsoredLimit != null;
  bool get isPaidPlan => plan == 'paid' && paidBlocks > 0;

  String get planLabel {
    if (isSponsored) return '후원';
    if (isPaidPlan) return '구독';
    return '무료';
  }

  String get displayName {
    final choir = _effectiveChoirName;
    if (choir == null || choir.isEmpty || choir == name) return name;
    return '$name-$choir';
  }

  String? get _effectiveChoirName {
    final choir = choirName?.trim();
    if (choir != null && choir.isNotEmpty) return choir;
    if (name.trim() == '예원교회') return '갈렙찬양대';
    return null;
  }

  factory Church.fromMap(Map<String, dynamic> map) {
    return Church(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      nameLower: (map['nameLower'] ?? '').toString(),
      address: map['address'] as String?,
      choirName: map['choirName'] as String?,
      logoUrl: map['logoUrl'] as String?,
      contactPhone: map['contactPhone'] as String?,
      contactEmail: map['contactEmail'] as String?,
      status: (map['status'] ?? 'pending').toString(),
      requestedBy: (map['requestedBy'] ?? '').toString(),
      adminUids: (map['adminUids'] as List?)?.cast<String>() ?? const [],
      rejectionReason: map['rejectionReason'] as String?,
      createdAt: _parseDate(map['createdAt']),
      approvedAt: _parseDate(map['approvedAt']),
      plan: (map['plan'] ?? 'free').toString(),
      paidBlocks: (map['paidBlocks'] as num?)?.toInt() ?? 0,
      activeMemberCount: (map['activeMemberCount'] as num?)?.toInt() ?? 0,
      sponsoredLimit: (map['sponsoredLimit'] as num?)?.toInt(),
      subscriptionStatus: (map['subscriptionStatus'] ?? 'none').toString(),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    try {
      return (v as dynamic).toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
