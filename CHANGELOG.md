# Changelog
모든 주요 변경 사항을 이 파일에 기록합니다.
[Keep a Changelog 1.1.0](https://keepachangelog.com/ko/1.1.0/) 형식을 따릅니다.

## [Unreleased]

## [2026-04-24] Phase 8: E2E 검증 준비
### Added
- `E2E_CHECKLIST.md` — 멀티 교회 플로우 8개 시나리오 체크리스트
  1. Platform Admin 부트스트랩
  2. 새 교회 등록 (Flutter)
  3. Platform Admin이 교회 승인
  4. Church Admin 어드민 웹 접속
  5. 다른 계정 단원 가입
  6. 데이터 격리 (교차 교회 접근 차단)
  7. 중복 교회명 차단
  8. 거부 후 재신청 (church scope + platform scope)

### Verified
- `flutter analyze` — 내 변경분 0 에러 (pre-existing info 40만 유지)
- `next build` — 13 라우트 정적 생성 성공

## [2026-04-24] Phase 7: Edge Cases
### Changed
- `lib/screens/approval/rejected_screen.dart` — `approvalScope`에 따라 2가지 경로 분기
  - **church scope** (기존 교회 가입이 거부됨): "같은 정보로 다시 신청" (primary) + "다른 교회에 가입" (secondary)
  - **platform scope** (새 교회 등록이 거부됨): "다른 교회에 가입 또는 재등록" (primary only, 같은 정보 재신청은 의미 없음 — 교회 이름부터 새로 입력 필요)
  - 로그아웃 버튼은 최하단 텍스트 링크로 이동
- `requestChurchJoin` / `requestChurchRegistration` — 유저 문서 저장 시 `rejectionReason: FieldValue.delete()` 포함
  - 거부 후 다른 경로 선택 시 이전 거절 사유 자동 정리
  - Firestore rules의 "재신청(rejected→pending)" 허용 범주 안에서 작동

### Verified (기존 Phase 작업으로 이미 커버)
- 중복 교회명 차단 (`isChurchNameTaken` — Phase 4/5)
- 이미 승인된 유저의 다른 교회 가입 차단 (main.dart 라우팅)
- 앱 재시작 시 상태 복원 (`myProfileStreamProvider`)
- Platform Admin이 Flutter 앱으로 로그인 → `PlatformAdminNoticeScreen` (Phase 5)

### Deferred
- 교회 soft-delete (status=rejected + 소속 멤버 일괄 처리) — 이번 스콥 외, 추후 Platform Admin UI에서 추가 예정

## [2026-04-24] Phase 6: churchId 격리 적용
### Added
- `FirebaseService._currentChurchIdCache` (정적 필드) + `setCurrentChurchId/currentChurchId/_requireChurchId` 유틸 — 도메인 메서드가 churchId를 동기 접근
- `myProfileStreamProvider`가 emit할 때마다 `setCurrentChurchId` 자동 호출 → 캐시 상시 동기화
- firestore.rules: `match /posts/{postId}/comments/{commentId}` 서브컬렉션 규칙 + collectionGroup 쿼리용 `match /{path=**}/comments/{commentId}`
- firestore.indexes.json: comments collectionGroup, attendance (churchId+userId+checkedInAt, churchId+checkedInAt), poll_votes, seat_assignments, seating_charts, users+profileCompleted 인덱스

### Changed
- **FirebaseService**: 모든 도메인 read/write 메서드에 `churchId` 필터/삽입
  - Read: `getAllMembers`, `getActiveSession`, `getRecentSessions`, `getMyHistory`, `getSessionAttendees`, `getPostsSince`, `getAttendanceSince`, `getSessionsSince`, `getCommentsSince`, `getPosts`, `getAnnouncements`, `getSheetMusic`, `getEvents`, `getVideos`, `getPolls`, `getPollVotes`, `getSeatingCharts`, `getSeatAssignments`, `getPendingUsers`, `getRejectedUsers`
  - Write: `openSession`, `checkIn`, `adminCheckIn`, `createPost`, `addComment`, `createAnnouncement`, `addVideo`, `addSheetMusic`, `createPoll`, `vote`, `createSeatingChart`, `assignSeat`, `clearSeat`, `deleteSeatingChart`
- `signOut()`이 churchId 캐시를 null로 리셋

### Security
- 모든 도메인 메서드가 churchId를 강제 사용 → 클라이언트 레벨 격리
- rules 레벨 격리와 2중 방어
- 댓글 서브컬렉션도 churchId 필드 포함 및 rule로 격리

## [2026-04-24] Phase 5: 가입 플로우 화면
### Added
- `lib/screens/church/church_selection_screen.dart` — 로그인 직후 3갈래 카드 UI (찬양대원/파트장/새 교회 등록) + "다른 계정" 링크
- `lib/screens/church/church_search_screen.dart` — 300ms debounce 검색, 빈 결과 시 "새 교회 등록" 전환 유도
- `lib/screens/church/church_register_screen.dart` — 교회 정보 폼, `isChurchNameTaken` 중복 체크 후 ProfileSetup으로 이동
- `lib/screens/platform_admin_notice_screen.dart` — 플랫폼 관리자(sinbun001)가 Flutter 로그인 시 웹 어드민 사용 안내

### Changed
- `lib/screens/profile_setup/profile_setup_screen.dart` — **전면 리팩터**
  - `ProfileSetupMode` enum 도입 (`joinChurch` / `registerChurch` / `reapply`)
  - 시그니처에 `mode`, `requestedRole`, `churchId`, `churchName`, `pendingChurchData` 추가
  - 제출 분기: `requestChurchJoin` / `requestChurchRegistration` / `reapplyApproval`
  - 역할 선택 UI 제거 → 이전 화면에서 결정된 역할을 읽기 전용으로 표시
  - 파트장일 때만 "담당 파트" 드롭다운 노출
- `lib/screens/approval/pending_approval_screen.dart` — `approvalScope`에 따라 문구/아이콘 분기
  - `platform`: "새 교회 등록 심사 중" + `requestedChurchId`에서 이름 로드
  - `church`: "OO교회 관리자가 검토 중" + `churchId`에서 이름 로드
  - 신청 정보 카드에 "교회" 행 추가
- `lib/screens/approval/rejected_screen.dart` — ProfileSetup 호출 시 `mode: reapply` + 원본 `requestedRole` 전달
- `lib/main.dart` — 라우팅 분기 확장
  ```
  profile null              → ChurchSelection
  isPlatformAdmin           → PlatformAdminNotice
  needsChurchSelection      → ChurchSelection
  !profileCompleted         → ChurchSelection (fallback)
  isRejected                → Rejected
  isPending                 → PendingApproval
  else                      → MainShell
  ```
- `firestore.rules` — self-update 룰을 2개로 분리
  - 일반 update: 민감 필드(role/partLeaderFor/rejectionReason/isPlatformAdmin/approvalStatus) 전부 불변
  - 재신청 update: rejected → pending 전환 시 `rejectionReason` 리셋만 추가로 허용

### Removed
- `ProfileSetupScreen` 내부의 Role 선택 UI (이전엔 ProfileSetup에서 member/part_leader/admin 선택했으나, 이제는 ChurchSelection/Search/Register에서 결정)

## [2026-04-24] Phase 4: Church 서비스 & Provider
### Added
- `FirebaseService`에 교회 메서드 5종:
  - `searchApprovedChurches(query)` — nameLower prefix 검색 (최대 20건)
  - `getChurch(id)` — 교회 단건 조회
  - `isChurchNameTaken(name)` — pending/approved 상태 중 동일 이름 존재 확인
  - `requestChurchRegistration({name, address, contactPhone, contactEmail, profileData})` — batch로 churches 생성 + 유저 프로필 approvalScope='platform' 설정
  - `requestChurchJoin({churchId, requestedRole, requestedPart, profileData})` — 기존 교회 가입 신청
- `app_providers.dart`에 `currentChurchIdProvider`, `currentChurchProvider`, `churchSearchProvider` (family with query string)

### Changed
- `ensureAdminRole()` → `ensurePlatformAdminRole()`로 개명 + 동작 변경
  - 이전: role='admin', approvalStatus='approved' 자동 설정
  - 신규: users 문서가 없을 때만 `isPlatformAdmin: true`로 생성. role/churchId는 건드리지 않음 (교회 소속은 별도 플로우)
- `myProfileStreamProvider`/`profileProvider` 내부 호출을 신규 이름으로 치환

## [2026-04-24] Phase 2: Firestore Rules & Indexes
### Changed
- `firestore.rules` 전면 재작성 — 멀티테넌트 격리
  - 헬퍼: `isSignedIn`, `hasProfile`, `myData`, `isPlatformAdmin`, `myRole`, `hasChurch`, `sameChurch`, `isChurchAdminOf`, `isBootstrapAdminEmail`
  - `churches` 신규 규칙 (approved는 공개 검색, pending/rejected는 본인/플랫폼 admin만)
  - 모든 도메인 컬렉션(announcements/attendance/attendance_sessions/posts/comments/sheet_music/events/videos/polls/poll_votes/seating_charts/seat_assignments/notifications)에 `sameChurch(churchId)` 강제
- `firebase.json` — `firestore.indexes` 필드 추가

### Added
- `firestore.indexes.json` — churchId 기반 복합 인덱스 12종
  (churches/announcements/videos/sheet_music/events/posts/attendance_sessions/attendance/polls/users)

### Security
- 다른 교회 데이터 교차 read/write 완전 차단
- `isPlatformAdmin=true` 셀프 설정 차단 (부트스트랩 이메일만 허용)
- 본인 역할(role/partLeaderFor) 셀프 상승 차단

## [2026-04-24] Phase 1: 멀티 교회 데이터 모델
### Added
- `lib/models/church.dart` — Church 엔티티 (id/name/nameLower/status/requestedBy/adminUids 등)
- `User` 모델에 `churchId`, `approvalScope`, `requestedChurchId`, `isPlatformAdmin` 필드
- `User.isChurchAdmin`, `User.needsChurchSelection` getter

### Changed
- `User.roleLabels`에 `church_admin` 추가 (기존 `admin`은 별칭으로 유지)
- `User.isAdmin`이 `role == 'admin'` 또는 `'church_admin'`을 모두 수용
- `requestedRole` 설명: `'member' | 'part_leader' | 'church_admin'` (기존 `admin` → `church_admin`)
