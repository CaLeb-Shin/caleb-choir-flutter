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
  choirName: '갈렙찬양대',
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
    'id': 'preview-soprano-3',
    'name': '정소절',
    'role': 'member',
    'part': 'soprano',
    'generation': '5기',
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
    'title': '[소프라노] 2026.05.05 / 주만 바라볼지라',
    'songTitle': '주만 바라볼지라',
    'sheetPart': 'soprano',
    'sheetDate': '2026-05-05',
    'composer': '미리보기 악보&음원',
    'conductorComment': '후렴은 한 호흡으로 넓게 열고, 가사의 방향을 먼저 생각하며 불러주세요.',
    'lyricsText': '주만 바라볼지라\n염려하지 말고 바라볼지라\n주님만 의지해\n한 걸음씩 나아가리라',
    'lyricsTimeline': [
      {'timeSec': 0.0, 'text': '주만 바라볼지라'},
      {'timeSec': 4.0, 'text': '염려하지 말고 바라볼지라'},
      {'timeSec': 8.0, 'text': '주님만 의지해'},
      {'timeSec': 12.0, 'text': '한 걸음씩 나아가리라'},
    ],
    'fileUrl':
        'https://mozilla.github.io/pdf.js/web/compressed.tracemonkey-pldi-09.pdf',
    'audioUrl': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'audioFileName': '파트연습.mp3',
    'mrAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    'mrAudioFileName': '파트MR.mp3',
    'createdAt': '2026-04-28T09:00:00',
  },
  {
    'id': 'preview-sheet-2',
    'title': '[알토] 2026.05.05 / 주만 바라볼지라',
    'songTitle': '주만 바라볼지라',
    'sheetPart': 'alto',
    'sheetDate': '2026-05-05',
    'composer': '미리보기 악보&음원',
    'fileUrl':
        'https://mozilla.github.io/pdf.js/web/compressed.tracemonkey-pldi-09.pdf',
    'createdAt': '2026-04-28T09:00:00',
  },
  {
    'id': 'preview-sheet-3',
    'title': '[테너] 2026.05.05 / 주만 바라볼지라',
    'songTitle': '주만 바라볼지라',
    'sheetPart': 'tenor',
    'sheetDate': '2026-05-05',
    'audioUrl': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    'audioFileName': '테너연습.mp3',
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

const _previewHarmonyNotes = [
  {
    'id': 'preview-harmony-1',
    'churchId': 'preview-church',
    'part': 'soprano',
    'title': '후렴 시작 호흡 맞추기',
    'prompt': '첫 박을 너무 급하게 잡지 말고, 같이 숨 들이마신 뒤 들어가요.',
    'audioUrl': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'audioFileName': 'soprano_harmony_note.mp3',
    'userId': 'preview-soprano-1',
    'userName': '윤소프',
    'userPart': 'soprano',
    'createdAt': '2026-04-28T10:20:00',
  },
  {
    'id': 'preview-harmony-2',
    'churchId': 'preview-church',
    'part': 'bass',
    'title': '베이스 진입음 확인',
    'prompt': '두 번째 줄은 말하듯 낮게 시작하면 전체가 더 안정적으로 들려요.',
    'audioUrl': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    'audioFileName': 'bass_harmony_note.mp3',
    'userId': 'preview-bass-1',
    'userName': '김베이스',
    'userPart': 'bass',
    'createdAt': '2026-04-28T09:55:00',
  },
];

const _previewHarmonyRelays = [
  {
    'id': 'preview-relay-soprano-1',
    'churchId': 'preview-church',
    'part': 'soprano',
    'title': '주만 바라볼지라 릴레이',
    'segmentLabel': '후렴 1마디',
    'guide': '첫 음을 너무 밀지 말고, 숨을 같이 들이마신 느낌으로 이어주세요.',
    'lyricsText': '주만 바라볼지라\n염려하지 말고 바라볼지라\n주님만 의지해',
    'lyricsTimeline': [
      {'timeSec': 0.0, 'text': '주만 바라볼지라'},
      {'timeSec': 4.0, 'text': '염려하지 말고 바라볼지라'},
      {'timeSec': 8.0, 'text': '주님만 의지해'},
    ],
    'lyricsLine': '주만 바라볼지라',
    'nextLyricsLine': '염려하지 말고 바라볼지라',
    'segmentStartSec': 0.0,
    'segmentEndSec': 12.0,
    'segmentDurationSec': 12.0,
    'guideAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'guideAudioFileName': 'soprano_guide.mp3',
    'mrAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    'mrAudioFileName': 'soprano_mr.mp3',
    'sourceTitle': '주만 바라볼지라',
    'missionGroupId': 'preview-song-soprano',
    'missionTotalSegments': 3,
    'segmentId': 'seg-01',
    'segmentOrder': 1,
    'status': 'open',
    'currentAssigneeId': 'preview-soprano-2',
    'currentAssigneeName': '오높음',
    'clipCount': 0,
    'createdAt': '2026-04-28T10:40:00',
    'clips': [],
  },
  {
    'id': 'preview-relay-soprano-2',
    'churchId': 'preview-church',
    'part': 'soprano',
    'title': '주만 바라볼지라 릴레이',
    'segmentLabel': '후렴 2마디',
    'guide': '첫 음을 너무 밀지 말고, 숨을 같이 들이마신 느낌으로 이어주세요.',
    'lyricsText': '주만 바라볼지라\n염려하지 말고 바라볼지라\n주님만 의지해',
    'lyricsTimeline': [
      {'timeSec': 0.0, 'text': '주만 바라볼지라'},
      {'timeSec': 4.0, 'text': '염려하지 말고 바라볼지라'},
      {'timeSec': 8.0, 'text': '주님만 의지해'},
    ],
    'lyricsLine': '염려하지 말고 바라볼지라',
    'nextLyricsLine': '주님만 의지해',
    'segmentStartSec': 4.0,
    'segmentEndSec': 8.0,
    'segmentDurationSec': 4.0,
    'guideAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'guideAudioFileName': 'soprano_guide.mp3',
    'mrAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    'mrAudioFileName': 'soprano_mr.mp3',
    'sourceTitle': '주만 바라볼지라',
    'missionGroupId': 'preview-song-soprano',
    'missionTotalSegments': 3,
    'segmentId': 'seg-02',
    'segmentOrder': 2,
    'status': 'open',
    'currentAssigneeId': '',
    'currentAssigneeName': '',
    'clipCount': 0,
    'createdAt': '2026-04-28T10:40:00',
    'clips': [],
  },
  {
    'id': 'preview-relay-soprano-3',
    'churchId': 'preview-church',
    'part': 'soprano',
    'title': '주만 바라볼지라 릴레이',
    'segmentLabel': '후렴 3마디',
    'guide': '첫 음을 너무 밀지 말고, 숨을 같이 들이마신 느낌으로 이어주세요.',
    'lyricsText': '주만 바라볼지라\n염려하지 말고 바라볼지라\n주님만 의지해',
    'lyricsTimeline': [
      {'timeSec': 0.0, 'text': '주만 바라볼지라'},
      {'timeSec': 4.0, 'text': '염려하지 말고 바라볼지라'},
      {'timeSec': 8.0, 'text': '주님만 의지해'},
    ],
    'lyricsLine': '주님만 의지해',
    'nextLyricsLine': '',
    'segmentStartSec': 8.0,
    'segmentEndSec': 12.0,
    'segmentDurationSec': 4.0,
    'guideAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'guideAudioFileName': 'soprano_guide.mp3',
    'mrAudioUrl':
        'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    'mrAudioFileName': 'soprano_mr.mp3',
    'sourceTitle': '주만 바라볼지라',
    'missionGroupId': 'preview-song-soprano',
    'missionTotalSegments': 3,
    'segmentId': 'seg-03',
    'segmentOrder': 3,
    'status': 'open',
    'currentAssigneeId': '',
    'currentAssigneeName': '',
    'clipCount': 0,
    'createdAt': '2026-04-28T10:40:00',
    'clips': [],
  },
];

List<Map<String, dynamic>> _clonePreviewHarmonyRelays() {
  return _previewHarmonyRelays.map((relay) {
    return {
      ...relay,
      'lyricsTimeline': ((relay['lyricsTimeline'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
      'clips': ((relay['clips'] as List?) ?? const [])
          .whereType<Map>()
          .map((clip) => Map<String, dynamic>.from(clip))
          .toList(),
    };
  }).toList();
}

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
    'needsAttendance': true,
    'needsSeating': false,
  },
  {
    'id': 'preview-event-2',
    'title': '주일 찬양',
    'description': '일정 등록에서 하모니챗 가사를 함께 준비한 예배 찬양입니다.',
    'date': '2026-05-17',
    'eventDate': '2026-05-17',
    'time': '오전 10:00',
    'location': '본당',
    'type': 'rehearsal',
    'needsAttendance': true,
    'needsSeating': true,
    'harmonyEnabled': true,
    'harmonyTitle': '주일 찬양 릴레이',
    'harmonyGuide': '후렴을 짧게 나눠 서로 이어 불러요.',
    'harmonyLyricsText':
        '[00:00.00] 주만 바라볼지라\n[00:04.00] 염려하지 말고 바라볼지라\n[00:08.00] 주님만 의지해',
    'harmonyLyricsTimeline': [
      {'timeSec': 0.0, 'text': '주만 바라볼지라'},
      {'timeSec': 4.0, 'text': '염려하지 말고 바라볼지라'},
      {'timeSec': 8.0, 'text': '주님만 의지해'},
    ],
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

final previewHarmonyRelaysProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => _clonePreviewHarmonyRelays(),
);

final previewHarmonyPracticeProgressProvider =
    StateProvider<Map<String, dynamic>>(
      (ref) => {
        'id': _previewUserId,
        'userId': _previewUserId,
        'part': 'soprano',
        'xp': 180,
        'level': FirebaseService.harmonyLevelForXp(180),
        'practiceCount': 6,
        'lastPracticeDate': '2026-05-26',
        'practiceDates': const ['2026-05-24', '2026-05-25', '2026-05-26'],
        'completedTutorialSteps': const {
          'mrRecording': true,
          'dailyMission': true,
        },
      },
    );

final previewHarmonyPracticeSubmissionsProvider =
    StateProvider<List<Map<String, dynamic>>>(
      (ref) => const [
        {
          'id': 'preview-practice-1',
          'churchId': 'preview-church',
          'userId': 'preview-soprano-2',
          'userName': '오높음',
          'part': 'soprano',
          'title': '주만 바라볼지라 개인연습',
          'missionTitle': '후렴 첫 호흡을 MR에 맞춰 녹음',
          'audioUrl':
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
          'audioFileName': 'preview_practice.wav',
          'mrAudioUrl':
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
          'mrAudioFileName': '파트MR.mp3',
          'durationSeconds': 12,
          'xpAwarded': 35,
          'status': 'reviewed',
          'leaderFeedback': '첫 진입이 좋아졌어요. 다음에는 마지막 음을 조금만 더 길게 잡아봐요.',
          'feedbackByName': '정소프라노 파트장',
          'createdAt': '2026-05-26T09:20:00',
          'feedbackAt': '2026-05-26T10:05:00',
        },
      ],
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
  return FirebaseService.authStateChangesWithCurrentUser();
});

// ─── User Profile ───
final profileProvider = FutureProvider<User?>((ref) async {
  if (ref.watch(localPreviewModeProvider)) {
    return _previewUserForPersona(ref.watch(previewPersonaProvider));
  }
  final authState = ref.watch(authStateProvider);
  final fbUser = authState.valueOrNull;
  if (fbUser == null) return null;
  final liveProfile = ref.watch(myProfileStreamProvider).valueOrNull;
  if (liveProfile != null) return liveProfile;
  final cachedProfile =
      FirebaseService.cachedProfileSnapshot() ??
      await FirebaseService.getCachedProfile();
  if (cachedProfile != null && cachedProfile['id']?.toString() == fbUser.uid) {
    FirebaseService.setCurrentChurchId(cachedProfile['churchId'] as String?);
    return User.fromMap(cachedProfile);
  }
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
  return FirebaseService.watchMyProfile(emitCached: true).map((data) {
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
final activeSessionProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  if (ref.watch(localPreviewModeProvider)) {
    return Stream.value(const {
      'id': 'preview-session-1',
      'title': '주일 찬양 연습',
      'openedAt': '2026-04-28T10:00:00',
      'attendanceDate': '2026-04-28',
      'location': '본당',
    });
  }
  return FirebaseService.watchActiveSession();
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

/// 열린 세션의 출석자를 실시간으로 구독(일찍 온 순 정렬). 얼리버드 순위판용.
final sessionAttendeesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, sessionId) {
      if (ref.watch(localPreviewModeProvider)) {
        final now = DateTime.now();
        Map<String, dynamic> seed(
          String userId,
          String name,
          String part,
          int minsAgo,
        ) => {
          'id': '${sessionId}_$userId',
          'userId': userId,
          'userName': name,
          'userPart': part,
          'checkedInAt': now
              .subtract(Duration(minutes: minsAgo))
              .toIso8601String(),
        };
        return Stream.value([
          seed('preview-tenor-1', '정테너', 'tenor', 47),
          seed('preview-alto-1', '최알토', 'alto', 41),
          seed('preview-bass-1', '김베이스', 'bass', 33),
          seed(_previewUserId, 'sinbun001', 'soprano', 21),
          seed('preview-bass-2', '박저음', 'bass', 12),
          seed('preview-alto-2', '한고음', 'alto', 5),
        ]);
      }
      return FirebaseService.watchSessionAttendees(sessionId);
    });

/// 내가 받은 월간 트로피 목록 — 마이 화면 동기부여용. 각 항목:
/// {month:'YYYY-MM', category:'attendance'|'earlybird', rank:1~3}
final myMonthlyTrophiesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      if (ref.watch(localPreviewModeProvider)) {
        return const [
          {'month': '2026-05', 'category': 'attendance', 'rank': 1},
          {'month': '2026-05', 'category': 'earlybird', 'rank': 2},
          {'month': '2026-04', 'category': 'earlybird', 'rank': 1},
          {'month': '2026-03', 'category': 'attendance', 'rank': 3},
        ];
      }
      return FirebaseService.getMyMonthlyTrophies();
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

final postsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  if (ref.watch(localPreviewModeProvider)) return Stream.value(_previewPosts);
  return FirebaseService.watchPosts();
});

final harmonyNotesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final part = profile?.partLeaderFor ?? profile?.part ?? '';
  if (ref.watch(localPreviewModeProvider)) {
    return Stream.value(
      _previewHarmonyNotes.where((note) => note['part'] == part).toList(),
    );
  }
  if (part.isEmpty) return Stream.value(const []);
  return FirebaseService.watchHarmonyNotes(part: part);
});

final harmonyRelaysProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final part = profile?.partLeaderFor ?? profile?.part ?? '';
  if (ref.watch(localPreviewModeProvider)) {
    final relays = ref.watch(previewHarmonyRelaysProvider);
    return Stream.value(
      relays.where((relay) => relay['part'] == part).toList(),
    );
  }
  if (part.isEmpty) return Stream.value(const []);
  return FirebaseService.watchHarmonyRelays(part: part);
});

final latestPartGuideProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final part = profile?.partLeaderFor ?? profile?.part ?? '';
  if (part.isEmpty) return Future.value(null);
  if (ref.watch(localPreviewModeProvider)) {
    final preview = _previewSheetMusic.firstWhere(
      (sheet) => sheet['sheetPart'] == part && (sheet['audioUrl'] ?? '') != '',
      orElse: () => const {},
    );
    if (preview.isEmpty) return Future.value(null);
    return Future.value({
      'sheetMusicId': preview['id'],
      'title': preview['songTitle'] ?? preview['title'],
      'songTitle': preview['songTitle'] ?? preview['title'],
      'sheetDate': preview['sheetDate'],
      'part': part,
      'guideAudioUrl': preview['audioUrl'],
      'guideAudioFileName': preview['audioFileName'],
      'mrAudioUrl': preview['mrAudioUrl'],
      'mrAudioFileName': preview['mrAudioFileName'],
      'guide': preview['conductorComment'] ?? '',
      'lyricsText': preview['lyricsText'] ?? '',
      'lyricsTimeline': preview['lyricsTimeline'] ?? const [],
      'lyricLines': (preview['lyricsText']?.toString() ?? '')
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
      'composer': preview['composer'] ?? '',
      'sheetUrl': preview['fileUrl'] ?? '',
    });
  }
  return FirebaseService.getLatestPartGuideForRelay(part: part);
});

final activeHarmonyPracticeMissionProvider =
    StreamProvider<Map<String, dynamic>?>((ref) {
      final profile = ref.watch(profileProvider).valueOrNull;
      final part = profile?.partLeaderFor ?? profile?.part ?? '';
      if (part.isEmpty) return Stream.value(null);
      if (ref.watch(localPreviewModeProvider)) {
        return Stream.value({
          'id': 'preview-practice-mission',
          'churchId': 'preview-church',
          'part': part,
          'title': '후렴 첫 호흡을 MR에 맞춰 녹음',
          'prompt': 'MR을 들으며 1번 이상 녹음하고, 마음에 드는 테이크를 파트장에게 보내보세요.',
          'xpReward': 35,
          'targetPractices': 1,
          'tutorialSteps': const [
            'MR 재생과 녹음 시작하기',
            '오늘 1회 연습 완료 확인하기',
            '파트장에게 피드백 요청하기',
          ],
          'active': true,
        });
      }
      return FirebaseService.watchActiveHarmonyPracticeMission(part: part);
    });

final harmonyPracticeProgressProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) {
  if (ref.watch(localPreviewModeProvider)) {
    return Stream.value(ref.watch(previewHarmonyPracticeProgressProvider));
  }
  return FirebaseService.watchHarmonyPracticeProgress();
});

final myHarmonyPracticeSubmissionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
      final profile = ref.watch(profileProvider).valueOrNull;
      final part = profile?.partLeaderFor ?? profile?.part ?? '';
      if (part.isEmpty) return Stream.value(const []);
      if (ref.watch(localPreviewModeProvider)) {
        final submissions = ref.watch(
          previewHarmonyPracticeSubmissionsProvider,
        );
        return Stream.value(
          submissions.where((item) => item['part'] == part).toList(),
        );
      }
      return FirebaseService.watchMyHarmonyPracticeSubmissions(part: part);
    });

// Part leader's review queue: every practice take submitted by their part.
// Empty for everyone who isn't a part leader.
final partPracticeReviewProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
      final profile = ref.watch(profileProvider).valueOrNull;
      final isLeader = profile?.isPartLeader ?? false;
      final part = profile?.partLeaderFor ?? profile?.part ?? '';
      if (!isLeader || part.isEmpty) return Stream.value(const []);
      if (ref.watch(localPreviewModeProvider)) {
        final submissions = ref.watch(
          previewHarmonyPracticeSubmissionsProvider,
        );
        return Stream.value(
          submissions.where((item) => item['part'] == part).toList(),
        );
      }
      return FirebaseService.watchPartPracticeSubmissions(part: part);
    });

final postProvider = StreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  postId,
) {
  if (ref.watch(localPreviewModeProvider)) {
    try {
      return Stream.value(
        _previewPosts.firstWhere((post) => post['id'] == postId),
      );
    } catch (_) {
      return Stream.value(null);
    }
  }
  return FirebaseService.watchPost(postId);
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

final eventsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  if (ref.watch(localPreviewModeProvider)) return Stream.value(_previewEvents);
  return FirebaseService.watchEvents();
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
final pollsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  if (ref.watch(localPreviewModeProvider)) {
    return Stream.value(const [
      {
        'id': _previewPollId,
        'title': '5월 5일 주일 찬양 참석',
        'targetDate': '2026-05-05',
        'isOpen': true,
      },
    ]);
  }
  return FirebaseService.watchPolls().map(_dedupePolls);
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

List<Map<String, dynamic>> _dedupePolls(List<Map<String, dynamic>> polls) {
  final deduped = <String, Map<String, dynamic>>{};
  for (final poll in polls) {
    final key = _pollDedupeKey(poll);
    final existing = deduped[key];
    if (existing == null || _pollPriority(poll) > _pollPriority(existing)) {
      deduped[key] = poll;
    }
  }
  return deduped.values.toList();
}

String _pollDedupeKey(Map<String, dynamic> poll) {
  final scope = poll['scopePart']?.toString() ?? 'all';
  final sourceEventId =
      poll['sourceEventId']?.toString() ?? poll['sourceScheduleId']?.toString();
  if (sourceEventId != null && sourceEventId.isNotEmpty) {
    return 'event:$sourceEventId:$scope';
  }

  final targetDate = _dateKey(poll['targetDate']);
  final title = poll['title']?.toString().trim();
  if (targetDate != null && title != null && title.isNotEmpty) {
    return 'date:$targetDate:title:$title:scope:$scope';
  }

  return 'id:${poll['id']}';
}

int _pollPriority(Map<String, dynamic> poll) {
  var score = 0;
  if (poll['sourceEventId'] != null || poll['sourceScheduleId'] != null) {
    score += 100;
  }
  if (poll['sourceSessionId'] != null ||
      poll['sourceAttendanceSessionId'] != null) {
    score += 40;
  }
  if (poll['source'] == 'schedule') score += 20;
  if (poll['isOpen'] == true) score += 10;
  return score;
}

String? _dateKey(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  if (raw.length >= 10) return raw.substring(0, 10).replaceAll('.', '-');
  return raw.replaceAll('.', '-');
}

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
  // Home only needs the last 7 days; cap the fetch so it never downloads the
  // entire sheet_music history just to filter it client-side.
  final all = await FirebaseService.getSheetMusic(limit: 50);
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
  // Home only needs the last 7 days; cap the fetch (see recentSheetMusicProvider).
  final all = await FirebaseService.getVideos(limit: 50);
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
