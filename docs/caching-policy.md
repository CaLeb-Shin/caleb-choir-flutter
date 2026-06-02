# 캐싱 정책 (Caching Policy)

앱이 "저장은 됐는데 화면은 안 바뀐 것처럼" 보이지 않도록, 데이터를 **언제 캐시하고 / 언제 다시 불러오고 / 언제 버릴지**를 정리한 문서. (Flutter + Riverpod + Firestore)

## 골든 룰
> **스트림(StreamProvider)이 받쳐주는 컬렉션에 쓰면 → 무효화 불필요(자동 갱신).**
> **Future 목록(FutureProvider)에 쓰면 → 그 provider를 `ref.invalidate()`로 무효화.**
> 프로필처럼 여러 문서에 **비정규화로 복사된 값**(이름/파트/사진)은 → 현재 사용자 것은 **읽을 때 라이브로 재해석**(`_authorFields`+`_safeUserData`) + 저장 직후 `FirebaseService.invalidateUserDataCache(uid)`.

## 1. 캐시 vs 실시간 분류
- **실시간(StreamProvider, 무효화 불필요)** — 협업·민감 데이터:
  posts(`postsProvider`/`postProvider`), 이벤트(`eventsProvider`), 폴 목록(`pollsProvider`), 출석 세션(`activeSessionProvider`), 하모니(`harmonyNotes`/`harmonyRelays`/`activeHarmonyPracticeMission`/`harmonyPracticeProgress`/`myHarmonyPracticeSubmissions`/`partPracticeReview`), 내 프로필(`myProfileStreamProvider`), 인증(`authStateProvider`).
- **캐시(FutureProvider, 무효화 전까지 유지)** — 참조·목록 데이터:
  악보(`sheetMusicProvider`), 영상(`videosProvider`), 공지(`announcementsProvider`), 멤버(`membersProvider`), 좌석(`seatingCharts`/`seatAssignments`/`seatingPresets`), 시상(`awardsProvider`), 교회(`currentChurchProvider`), 내 출석이력(`myHistoryProvider`), 최근 세션(`recentSessionsProvider`), 댓글(`commentsProvider` family), 폴 투표(`pollVotesProvider` family), 가이드(`latestPartGuideProvider`), 승인 대기(`pendingUsers`/`rejectedUsers`).
- autoDispose/TTL 타이머는 쓰지 않음. 캐시는 **세 가지 트리거**로만 갱신(아래).

## 2. 다시 불러오는 3가지 트리거
1. **앱 재진입** — `MainShell`의 `AppLifecycleListener`가 백그라운드 **5분 초과** 후 복귀 시 `invalidateCacheProviders(ref)`(`lib/providers/refresh_coordinator.dart`)로 캐시 계열 일괄 무효화. 스트림은 Firestore가 자동 재연결.
2. **저장 직후** — 골든 룰대로. Future 목록 쓰기 후 해당 provider 무효화. (스트림 백킹은 자동.)
3. **당겨서 새로고침(pull-to-refresh)** — 홈/커뮤니티/승인 + 악보/영상/멤버/출석/폴. (좌석은 admin 액션 무효화 + 앱 재진입으로 커버.)

## 3. 저장 → 같이 바꿔야 할 곳 (무효화 지도)
- **내 프로필 변경**(`profile_screen._save` → `updateProfile`):
  - `updateProfile`이 `invalidateUserDataCache(uid)`로 유저 캐시 퍼지.
  - `profileProvider`,`postsProvider`,`membersProvider`,`commentsProvider`,`pollVotesProvider`,`seatingChartsProvider` 무효화.
  - 내 글/댓글/출석/좌석/투표는 **읽을 때 본인 것이면 라이브 재해석**(아래 경로)이라 옛 이름이 남지 않음. (홈 인사말·마이페이지는 `profileProvider`/`myProfileStreamProvider`로 즉시.)
  - **알려진 한계**: *다른 사용자*가 보는 피드의 내 이름은 비정규화 스냅샷이라, 그들이 새로고침/재진입하기 전까진 옛 이름일 수 있음(비용상 전체 라이브 미적용). 필요 시 Cloud Function fan-out으로 승격.
- 관리자 콘텐츠 추가/삭제(악보/영상/공지/멤버/좌석/폴)는 각 화면이 해당 FutureProvider 무효화.

### 본인 것이면 라이브 재해석하는 읽기 경로 (`userId == 현재 uid`)
`firebase_service.dart`: `_postCanUseStoredAuthor`(피드 fast/full + `_postNeedsAuthorLookup`), `getSessionAttendees`, `getPollVotes`, `getSeatAssignments`, `watchMyHarmonyPracticeSubmissions`. (이미 항상 라이브: `getComments`, 하모니 노트/릴레이 클립, 게시글 상세, 파트장 연습 뷰.)

## 4. 언제 버릴지 (discard)
- **로그아웃**: `FirebaseService.signOut()`이 서비스 캐시(`_userDataCache`/`_currentChurchIdCache`/SharedPreferences 프로필) 정리 + 핸들러가 `invalidateCacheProviders(ref)` 호출.
- **수정/삭제 직후**: 골든 룰(무효화).
- **계정 전환**: 현재는 로그아웃 경유. 완전한 전체 리셋(모든 provider·StateProvider)은 **루트 ProviderScope를 uid 기준 재마운트**(미적용, 추후).

## 5. 캐시 시간(TTL)
타이머 없음. 유일한 "유효시간"은 앱 재진입 임계 **5분**(`_resumeRefreshThreshold`). 더 실시간이 필요해지면 해당 provider를 StreamProvider로 승격(타이머 도입 X).

---
*변경 시 이 문서를 함께 갱신. 새 쓰기를 추가하면 "스트림이면 그대로, Future면 무효화" 규칙을 따를 것.*
