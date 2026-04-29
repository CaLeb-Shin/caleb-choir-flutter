import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../services/firebase_service.dart';
import '../models/user.dart';
import '../models/church.dart';

const _previewUserId = 'sinbun001-preview';

final _previewChurch = Church(
  id: 'preview-church',
  name: '갈렙교회',
  nameLower: '갈렙교회',
  status: 'approved',
  requestedBy: _previewUserId,
  adminUids: const [_previewUserId],
);

const List<Map<String, dynamic>> _previewMembers = [
  {
    'id': _previewUserId,
    'name': 'sinbun001',
    'nickname': '플랫폼 관리자',
    'role': 'admin',
    'part': 'soprano',
    'generation': '1기',
  },
  {
    'id': 'preview-bass-1',
    'name': '김베이스',
    'role': 'part_leader',
    'part': 'bass',
    'partLeaderFor': 'bass',
    'generation': '3기',
  },
  {
    'id': 'preview-bass-2',
    'name': '박저음',
    'role': 'member',
    'part': 'bass',
    'generation': '4기',
  },
  {
    'id': 'preview-bass-3',
    'name': '이든든',
    'role': 'member',
    'part': 'bass',
    'generation': '5기',
  },
  {
    'id': 'preview-alto-1',
    'name': '최알토',
    'role': 'part_leader',
    'part': 'alto',
    'partLeaderFor': 'alto',
    'generation': '2기',
  },
  {
    'id': 'preview-alto-2',
    'name': '정화음',
    'role': 'member',
    'part': 'alto',
    'generation': '6기',
  },
  {
    'id': 'preview-alto-3',
    'name': '한중음',
    'role': 'member',
    'part': 'alto',
    'generation': '5기',
  },
  {
    'id': 'preview-soprano-1',
    'name': '윤소프',
    'role': 'part_leader',
    'part': 'soprano',
    'partLeaderFor': 'soprano',
    'generation': '2기',
  },
  {
    'id': 'preview-soprano-2',
    'name': '오높음',
    'role': 'member',
    'part': 'soprano',
    'generation': '7기',
  },
  {
    'id': 'preview-tenor-1',
    'name': '강테너',
    'role': 'part_leader',
    'part': 'tenor',
    'partLeaderFor': 'tenor',
    'generation': '3기',
  },
  {
    'id': 'preview-tenor-2',
    'name': '서맑음',
    'role': 'member',
    'part': 'tenor',
    'generation': '5기',
  },
  {
    'id': 'preview-tenor-3',
    'name': '남울림',
    'role': 'member',
    'part': 'tenor',
    'generation': '6기',
  },
];

const _previewPollId = 'preview-poll-sunday';

const _previewSheetMusic = [
  {
    'id': 'preview-sheet-1',
    'title': '주만 바라볼지라',
    'composer': '미리보기 악보',
    'createdAt': '2026-04-28T09:00:00',
  },
];

const _previewVideos = [
  {
    'id': 'preview-video-1',
    'title': '유튜브 링크 샘플 영상',
    'description': '유튜브 링크를 올리면 이렇게 영상 카드로 표시됩니다.',
    'youtubeUrl': 'https://www.youtube.com/watch?v=3IbpADYMC2Q',
    'createdAt': '2026-04-28T09:10:00',
  },
];

const _previewAnnouncements = [
  {
    'id': 'preview-announcement-1',
    'title': '미리보기 공지',
    'content': '인앱 브라우저 작업용 샘플 공지입니다.',
    'isRead': false,
    'createdAt': '2026-04-28T09:20:00',
  },
];

const _previewPosts = [
  {
    'id': 'preview-post-video-1',
    'title': '12초 영상 업로드 샘플',
    'content': '서버에서 압축된 짧은 영상은 이렇게 카드로 표시됩니다.',
    'userId': 'preview-alto-2',
    'userName': '이알토',
    'userPart': 'alto',
    'mediaType': 'video',
    'videoStatus': 'ready',
    'videoUrl':
        'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    'videoDurationSeconds': 12,
    'createdAt': '2026-04-28T09:45:00',
    'reactions': {
      'like': [_previewUserId, 'preview-bass-1', 'preview-soprano-1'],
      'pray': [],
    },
    'commentCount': 1,
  },
  {
    'id': 'preview-post-1',
    'title': '연습 끝나고 한 컷',
    'content': '오늘 화음이 딱 맞아서 다 같이 기분 좋았던 순간',
    'userId': _previewUserId,
    'userName': 'sinbun001',
    'userPart': 'soprano',
    'imageUrl':
        'https://images.unsplash.com/photo-1516280440614-37939bbacd81?auto=format&fit=crop&w=900&q=80',
    'createdAt': '2026-04-28T09:30:00',
    'reactions': {
      'like': [
        'preview-bass-1',
        'preview-alto-1',
        'preview-soprano-1',
        'preview-tenor-1',
        'preview-tenor-2',
      ],
      'pray': ['preview-soprano-2'],
    },
    'commentCount': 4,
  },
  {
    'id': 'preview-post-2',
    'title': '지휘자님 몰래 리듬 맞추기',
    'content': '쉬는 시간에도 몸이 먼저 반응하는 갈렙',
    'userId': 'preview-bass-1',
    'userName': '김베이스',
    'userPart': 'bass',
    'imageUrl':
        'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=900&q=80',
    'createdAt': '2026-04-28T08:10:00',
    'reactions': {
      'like': [
        _previewUserId,
        'preview-alto-1',
        'preview-alto-2',
        'preview-tenor-1',
      ],
      'pray': ['preview-soprano-1'],
    },
    'commentCount': 3,
  },
  {
    'id': 'preview-post-3',
    'title': '소프라노 음정 점검 중',
    'content': '높은 음도 웃으면서 다시 한 번',
    'userId': 'preview-soprano-1',
    'userName': '윤소프',
    'userPart': 'soprano',
    'imageUrl':
        'https://images.unsplash.com/photo-1524368535928-5b5e00ddc76b?auto=format&fit=crop&w=900&q=80',
    'createdAt': '2026-04-27T20:05:00',
    'reactions': {
      'like': [_previewUserId, 'preview-bass-2', 'preview-alto-3'],
      'pray': ['preview-tenor-3'],
    },
    'commentCount': 2,
  },
  {
    'id': 'preview-post-4',
    'title': '알토 파트 단체 인증',
    'content': '중간 소리가 든든하면 전체가 편해져요',
    'userId': 'preview-alto-1',
    'userName': '최알토',
    'userPart': 'alto',
    'imageUrl':
        'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?auto=format&fit=crop&w=900&q=80',
    'createdAt': '2026-04-27T18:35:00',
    'reactions': {
      'like': [_previewUserId, 'preview-bass-3', 'preview-tenor-2'],
      'sad': [],
      'pray': [],
    },
    'commentCount': 1,
  },
  {
    'id': 'preview-post-5',
    'title': '테너의 자신감',
    'content': '오늘은 입장부터 이미 준비 완료',
    'userId': 'preview-tenor-1',
    'userName': '강테너',
    'userPart': 'tenor',
    'imageUrl':
        'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&w=900&q=80',
    'createdAt': '2026-04-26T21:10:00',
    'reactions': {
      'like': ['preview-soprano-2', 'preview-alto-2'],
      'pray': [_previewUserId],
    },
    'commentCount': 2,
  },
  {
    'id': 'preview-post-6',
    'title': '베이스 자리에서 보는 풍경',
    'content': '맨왼쪽에서 전체 소리를 받쳐주는 자리',
    'userId': 'preview-bass-2',
    'userName': '박저음',
    'userPart': 'bass',
    'imageUrl':
        'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=900&q=80',
    'createdAt': '2026-04-26T12:40:00',
    'reactions': {
      'like': ['preview-alto-1'],
      'pray': ['preview-tenor-1'],
    },
    'commentCount': 0,
  },
];

const _previewComments = [
  {
    'id': 'preview-comment-1',
    'postId': 'preview-post-1',
    'userId': 'preview-bass-1',
    'userName': '김베이스',
    'userPart': 'bass',
    'content': '베이스 파트 확인했습니다.',
    'createdAt': '2026-04-28T09:40:00',
  },
];

const _previewEvents = [
  {
    'id': 'preview-event-1',
    'title': '수요 예배 리허설',
    'description': '주일 찬양 전 파트별 밸런스를 맞추는 리허설입니다.',
    'date': '2026-04-30',
    'eventDate': '2026-04-30',
    'time': '오후 8:00',
    'location': '찬양대실',
    'type': 'dressrehearsal',
  },
  {
    'id': 'preview-event-2',
    'title': '주일 찬양',
    'description': '5월 첫 주 예배 찬양입니다.',
    'date': '2026-05-05',
    'eventDate': '2026-05-05',
    'time': '오전 10:00',
    'location': '본당',
    'type': 'rehearsal',
  },
];

enum PreviewPersona {
  admin,
  bassLeader,
  altoLeader,
  sopranoLeader,
  tenorLeader,
  sopranoMember,
}

const previewPersonaLabels = {
  PreviewPersona.admin: '관리자',
  PreviewPersona.bassLeader: '베이스장',
  PreviewPersona.altoLeader: '알토장',
  PreviewPersona.sopranoLeader: '소프라노장',
  PreviewPersona.tenorLeader: '테너장',
  PreviewPersona.sopranoMember: '일반 단원',
};

const _previewPersonaUserIds = {
  PreviewPersona.admin: _previewUserId,
  PreviewPersona.bassLeader: 'preview-bass-1',
  PreviewPersona.altoLeader: 'preview-alto-1',
  PreviewPersona.sopranoLeader: 'preview-soprano-1',
  PreviewPersona.tenorLeader: 'preview-tenor-1',
  PreviewPersona.sopranoMember: 'preview-soprano-2',
};

User _previewUserForPersona(PreviewPersona persona) {
  final userId = _previewPersonaUserIds[persona] ?? _previewUserId;
  final member = _previewMembers.firstWhere(
    (member) => member['id'] == userId,
    orElse: () => _previewMembers.first,
  );
  return User.fromMap({
    ...member,
    'email': persona == PreviewPersona.admin
        ? 'sinbun001@gmail.com'
        : '${member['id']}@preview.local',
    'profileCompleted': true,
    'approvalStatus': 'approved',
    'churchId': _previewChurch.id,
    'isPlatformAdmin': persona == PreviewPersona.admin,
  });
}

// ─── Navigation ───
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ─── Local Preview ───
final localPreviewModeProvider = StateProvider<bool>((ref) {
  return Uri.base.queryParameters['preview'] == '1';
});

final loginPreviewModeProvider = StateProvider<bool>((ref) {
  return Uri.base.queryParameters['login'] == '1';
});

final onboardingPreviewDismissedProvider = StateProvider<bool>((ref) => false);

final previewPersonaProvider = StateProvider<PreviewPersona>(
  (ref) => PreviewPersona.admin,
);

final previewSeatingChartsProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => const [
    {
      'id': 'preview-chart-sunday',
      'label': '주일 찬양 자리배치',
      'eventDate': '2026-05-05',
      'sourcePollId': _previewPollId,
      'sourcePollTitle': '5월 5일 주일 찬양 참석',
      'isPublished': false,
    },
  ],
);

final previewSeatAssignmentsProvider =
    StateProvider<List<Map<String, dynamic>>>(
      (ref) => const [
        {
          'id': 'preview-seat-1',
          'chartId': 'preview-chart-sunday',
          'part': 'bass',
          'row': 0,
          'col': 0,
          'userId': 'preview-bass-1',
          'userName': '김베이스',
          'userGeneration': '3기',
        },
        {
          'id': 'preview-seat-2',
          'chartId': 'preview-chart-sunday',
          'part': 'alto',
          'row': 0,
          'col': 0,
          'userId': 'preview-alto-1',
          'userName': '최알토',
          'userGeneration': '2기',
        },
        {
          'id': 'preview-seat-3',
          'chartId': 'preview-chart-sunday',
          'part': 'soprano',
          'row': 0,
          'col': 0,
          'userId': _previewUserId,
          'userName': 'sinbun001',
          'userGeneration': '1기',
        },
        {
          'id': 'preview-seat-4',
          'chartId': 'preview-chart-sunday',
          'part': 'tenor',
          'row': 0,
          'col': 0,
          'userId': 'preview-tenor-1',
          'userName': '강테너',
          'userGeneration': '3기',
        },
      ],
    );

final previewSeatingPresetsProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => const [],
);

// ─── Logged-out flag (로그아웃 안내 메시지 1회 표시용) ───
final loggedOutProvider = StateProvider<bool>((ref) => false);

// ─── View-as-Member (관리자가 일반 단원 시점으로 시스템을 살피기 위한 로컬 토글) ───
// Firestore 의 실제 role 은 건드리지 않고 UI 렌더에만 영향을 줌.
final viewAsMemberProvider = StateProvider<bool>((ref) => false);

/// 현재 세션에서 "관리자 UI" 를 보여줄지 여부. 실제 admin 이면서
/// viewAsMember 토글이 꺼져있을 때만 true.
final effectiveIsAdminProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final viewAsMember = ref.watch(viewAsMemberProvider);
  return (profile?.isAdmin ?? false) && !viewAsMember;
});

/// 관리자 + 임원(officer) 모두 포함한 관리 권한. viewAsMember 토글 반영.
final effectiveHasManagePermissionProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final viewAsMember = ref.watch(viewAsMemberProvider);
  return (profile?.hasManagePermission ?? false) && !viewAsMember;
});

// ─── Auth ───
final authStateProvider = StreamProvider<fb.User?>((ref) {
  return FirebaseService.authStateChanges;
});

// ─── User Profile ───
final profileProvider = FutureProvider<User?>((ref) async {
  if (ref.watch(localPreviewModeProvider)) {
    return _previewUserForPersona(ref.watch(previewPersonaProvider));
  }
  final authState = ref.watch(authStateProvider);
  final fbUser = authState.valueOrNull;
  if (fbUser == null) return null;
  // 관리자 이메일이면 자동 admin 권한 부여
  await FirebaseService.ensurePlatformAdminRole();
  final data = await FirebaseService.getProfile();
  if (data == null) return null;
  return User.fromMap(data);
});

/// 실시간 프로필 스트림 (관리자 승인 시 UI 자동 전환용)
/// 추가로 FirebaseService.currentChurchId 캐시도 동기화 — 도메인 메서드가 동기 접근하기 위함.
final myProfileStreamProvider = StreamProvider<User?>((ref) {
  if (ref.watch(localPreviewModeProvider)) {
    FirebaseService.setCurrentChurchId(_previewChurch.id);
    return Stream.value(
      _previewUserForPersona(ref.watch(previewPersonaProvider)),
    );
  }
  final authState = ref.watch(authStateProvider);
  final fbUser = authState.valueOrNull;
  if (fbUser == null) {
    FirebaseService.setCurrentChurchId(null);
    return Stream.value(null);
  }
  // 로그인 시 한 번 platform admin 자동 부트스트랩 실행
  FirebaseService.ensurePlatformAdminRole();
  return FirebaseService.watchMyProfile().map((data) {
    if (data == null) {
      FirebaseService.setCurrentChurchId(null);
      return null;
    }
    FirebaseService.setCurrentChurchId(data['churchId'] as String?);
    return User.fromMap(data);
  });
});

// ─── Multi-tenant (Church) ───
/// 현재 로그인 유저의 churchId. 미소속/신청 전이면 null.
final currentChurchIdProvider = Provider<String?>((ref) {
  return ref.watch(myProfileStreamProvider).valueOrNull?.churchId;
});

/// 현재 유저가 속한 교회 정보. churchId가 null이면 null.
final currentChurchProvider = FutureProvider<Church?>((ref) async {
  if (ref.watch(localPreviewModeProvider)) return _previewChurch;
  final id = ref.watch(currentChurchIdProvider);
  if (id == null) return null;
  final data = await FirebaseService.getChurch(id);
  return data == null ? null : Church.fromMap(data);
});

/// 승인된 교회 검색 (ChurchSearchScreen용). query 변경 시 자동 재조회.
final churchSearchProvider = FutureProvider.family<List<Church>, String>((
  ref,
  query,
) async {
  if (ref.watch(localPreviewModeProvider)) return [_previewChurch];
  final list = await FirebaseService.searchApprovedChurches(query);
  return list.map((m) => Church.fromMap(m)).toList();
});

// ─── Admin: Pending Approvals ───
final pendingUsersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) return const [];
  return FirebaseService.getPendingUsers();
});

final rejectedUsersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) return const [];
  return FirebaseService.getRejectedUsers();
});

// ─── Attendance ───
final activeSessionProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) {
    return const {
      'id': 'preview-session-1',
      'title': '주일 찬양 연습',
      'openedAt': '2026-04-28T10:00:00',
      'location': '본당',
    };
  }
  return FirebaseService.getActiveSession();
});

final myHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) {
    return [
      {
        'sessionTitle': '주일 찬양 연습',
        'checkedInAt': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      },
      {
        'sessionTitle': '수요 예배 리허설',
        'checkedInAt': DateTime.now()
            .subtract(const Duration(days: 5))
            .toIso8601String(),
      },
    ];
  }
  return FirebaseService.getMyHistory();
});

final recentSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) {
    return const [
      {
        'id': 'preview-session-1',
        'title': '주일 찬양 연습',
        'openedAt': '2026-04-28T10:00:00',
        'location': '본당',
        'count': 4,
      },
    ];
  }
  return FirebaseService.getRecentSessions(limit: 5);
});

// ─── Content ───
final videosProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(localPreviewModeProvider)) return _previewVideos;
  return FirebaseService.getVideos();
});

final postsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(localPreviewModeProvider)) return _previewPosts;
  return FirebaseService.getPosts();
});

final postProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  postId,
) async {
  if (ref.watch(localPreviewModeProvider)) {
    try {
      return _previewPosts.firstWhere((post) => post['id'] == postId);
    } catch (_) {
      return null;
    }
  }
  return FirebaseService.getPost(postId);
});

final commentsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      postId,
    ) async {
      if (ref.watch(localPreviewModeProvider)) {
        return _previewComments
            .where((comment) => comment['postId'] == postId)
            .toList();
      }
      return FirebaseService.getComments(postId);
    });

final announcementsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) return _previewAnnouncements;
  return FirebaseService.getAnnouncements();
});

final sheetMusicProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) return _previewSheetMusic;
  return FirebaseService.getSheetMusic();
});

final eventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(localPreviewModeProvider)) return _previewEvents;
  return FirebaseService.getEvents();
});

final membersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(localPreviewModeProvider)) {
    return _previewMembers;
  }
  return FirebaseService.getAllMembers();
});

// ─── Part Leader ───
final effectiveIsPartLeaderProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final viewAsMember = ref.watch(viewAsMemberProvider);
  return (profile?.isPartLeader ?? false) && !viewAsMember;
});

// ─── Polls ───
final pollsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(localPreviewModeProvider)) {
    return const [
      {
        'id': _previewPollId,
        'title': '5월 5일 주일 찬양 참석',
        'targetDate': '2026-05-05',
        'isOpen': true,
      },
    ];
  }
  return FirebaseService.getPolls();
});

final pollVotesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      pollId,
    ) async {
      if (ref.watch(localPreviewModeProvider)) {
        if (pollId != _previewPollId) return const [];
        return _previewMembers
            .map(
              (member) => {
                'id': 'vote-${member['id']}',
                'pollId': _previewPollId,
                'userId': member['id'],
                'choice': member['id'] == 'preview-alto-3'
                    ? 'absent'
                    : 'attend',
                'userName': member['name'],
                'userPart': member['part'],
              },
            )
            .toList();
      }
      return FirebaseService.getPollVotes(pollId);
    });

// ─── Seating ───
final seatingChartsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) {
    return ref.watch(previewSeatingChartsProvider);
  }
  final profile = ref.watch(profileProvider).valueOrNull;
  final publishedOnly = profile?.role == 'member';
  return FirebaseService.getSeatingCharts(publishedOnly: publishedOnly);
});

final seatAssignmentsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      chartId,
    ) async {
      if (ref.watch(localPreviewModeProvider)) {
        return ref
            .watch(previewSeatAssignmentsProvider)
            .where((seat) => seat['chartId'] == chartId)
            .toList();
      }
      return FirebaseService.getSeatAssignments(chartId);
    });

final seatingPresetsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) {
    return ref.watch(previewSeatingPresetsProvider);
  }
  return FirebaseService.getSeatingPresets();
});

// ─── This Week's Uploads ───
final recentSheetMusicProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) return _previewSheetMusic;
  final all = await FirebaseService.getSheetMusic();
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  return all.where((s) {
    final created = s['createdAt'];
    if (created == null) return false;
    try {
      final d = created is Timestamp
          ? created.toDate()
          : DateTime.parse(created.toString());
      return d.isAfter(weekAgo);
    } catch (_) {
      return false;
    }
  }).toList();
});

final recentVideosProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (ref.watch(localPreviewModeProvider)) return _previewVideos;
  final all = await FirebaseService.getVideos();
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  return all.where((v) {
    final created = v['createdAt'];
    if (created == null) return false;
    try {
      final d = created is Timestamp
          ? created.toDate()
          : DateTime.parse(created.toString());
      return d.isAfter(weekAgo);
    } catch (_) {
      return false;
    }
  }).toList();
});
