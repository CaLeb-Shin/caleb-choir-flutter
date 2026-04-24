class Church {
  final String id;
  final String name;
  final String nameLower;
  final String? address;
  final String? contactPhone;
  final String? contactEmail;
  final String status;             // 'pending' | 'approved' | 'rejected'
  final String requestedBy;        // uid
  final List<String> adminUids;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? approvedAt;

  Church({
    required this.id,
    required this.name,
    required this.nameLower,
    required this.status,
    required this.requestedBy,
    this.adminUids = const [],
    this.address,
    this.contactPhone,
    this.contactEmail,
    this.rejectionReason,
    this.createdAt,
    this.approvedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory Church.fromMap(Map<String, dynamic> map) {
    return Church(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      nameLower: (map['nameLower'] ?? '').toString(),
      address: map['address'] as String?,
      contactPhone: map['contactPhone'] as String?,
      contactEmail: map['contactEmail'] as String?,
      status: (map['status'] ?? 'pending').toString(),
      requestedBy: (map['requestedBy'] ?? '').toString(),
      adminUids: (map['adminUids'] as List?)?.cast<String>() ?? const [],
      rejectionReason: map['rejectionReason'] as String?,
      createdAt: _parseDate(map['createdAt']),
      approvedAt: _parseDate(map['approvedAt']),
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
