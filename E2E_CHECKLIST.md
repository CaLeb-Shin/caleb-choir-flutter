# 멀티 교회 플로우 E2E 검증 체크리스트

Phase 1~7에서 구현한 멀티 교회 가입/승인 플로우를 실제로 돌려보며 확인하는 시나리오 8종.

## 준비물

| 항목 | 설명 |
|---|---|
| Firebase 프로젝트 | `caleb-choir-2026` (rules/indexes 최신으로 배포 완료) |
| Admin 웹 | 로컬: `http://localhost:3001` 또는 배포본 |
| Flutter 앱 | iOS/Android 시뮬레이터 또는 실기기 2대 |
| Google 계정 | 플랫폼 관리자 1개 + 교회 관리자 2개 + 단원 2개 (총 5개) |
| Firestore 초기 상태 | 컬렉션 비어있음 (Phase 0 완료) |

앱 실행 명령:
```bash
# Admin 웹 (이미 실행 중이면 스킵)
cd caleb-choir-admin && npm run dev

# Flutter 앱
cd caleb-choir-flutter && flutter run -d <device-id>
```

---

## 시나리오 1 — Platform Admin 부트스트랩

**목표**: 최초로 `sinbun001@gmail.com`이 어드민 웹에 로그인하면 자동으로 platform admin 문서 생성

1. [ ] Admin 웹(`http://localhost:3001`) 접속 → `/login`으로 자동 이동
2. [ ] "Google로 로그인" 클릭 → `sinbun001@gmail.com` 선택
3. [ ] **기대**: 대시보드로 리디렉션. 사이드바에 "교회 관리" 메뉴만 노출(기존 단원/출석/공지/악보/일정 메뉴는 숨겨짐)
4. [ ] Firebase 콘솔 → Firestore → `users/{sinbun-uid}` 문서 확인:
   - `isPlatformAdmin: true`
   - `email: sinbun001@gmail.com`
   - `name`, `createdAt` 존재
5. [ ] `/dashboard/churches` 접속 → "승인 대기 / 승인됨 / 거부됨" 탭 모두 빈 리스트

---

## 시나리오 2 — 새 교회 등록 (Flutter)

**목표**: 일반 Google 계정 A가 Flutter 앱에서 새 교회를 등록 신청

1. [ ] 시뮬A에서 Flutter 앱 실행 → `LoginScreen`
2. [ ] Google로 로그인 (테스트 계정 A: 예 `testpastor@example.com`)
3. [ ] **기대**: `ChurchSelectionScreen`으로 이동 (3개 카드 노출)
4. [ ] "새 교회 등록" 카드 탭
5. [ ] `ChurchRegisterScreen`:
   - 교회명: "테스트교회"
   - 주소/연락처/이메일 입력 (선택)
   - "다음: 프로필 작성" 탭
6. [ ] `ProfileSetupScreen`:
   - 상단에 **`"테스트교회" 등록 신청`** 배너 노출
   - "신청 유형: 교회 관리자" 카드 노출 (변경 불가)
   - 이름, 파트 등 입력 → "가입 신청" 탭
7. [ ] **기대**: `PendingApprovalScreen`으로 자동 전환
   - 상단 문구: "교회 등록 심사 중"
   - 아이콘: 🏢 (add_business)
   - 신청 정보 카드에 "교회: 테스트교회" 행 존재
8. [ ] Firestore 확인:
   - `churches/{X}.status == 'pending'`, `requestedBy == <A uid>`, `adminUids: []`
   - `users/{A uid}.approvalScope == 'platform'`, `requestedRole == 'church_admin'`, `requestedChurchId == X`, `churchId == null`, `approvalStatus == 'pending'`

---

## 시나리오 3 — Platform Admin이 교회 승인

**목표**: 어드민 웹에서 교회 승인 → 시뮬A가 자동으로 MainShell 진입

1. [ ] Admin 웹 → `/dashboard/churches` → "승인 대기" 탭
2. [ ] "테스트교회" 행 확인 (신청자 이메일, 연락처 표시)
3. [ ] "승인" 버튼 클릭 → 확인 다이얼로그 "OK"
4. [ ] **기대**: "승인 대기" 탭에서 사라지고 "승인됨" 탭에 나타남
5. [ ] Firestore 확인:
   - `churches/{X}.status == 'approved'`, `adminUids == [<A uid>]`, `approvedAt` 타임스탬프
   - `users/{A uid}.churchId == X`, `role == 'church_admin'`, `approvalStatus == 'approved'`, `approvalScope == 'church'`, `rejectionReason == null`
6. [ ] 시뮬A Flutter 앱 → **자동으로 MainShell로 전환** (새로고침 불필요)
7. [ ] 홈 화면 확인 — 공지/악보 등 전부 비어있음 (방금 생성된 교회라)

---

## 시나리오 4 — Church Admin 어드민 웹 접속

**목표**: A 계정으로 어드민 웹 접속 시 Church Admin 뷰 노출

1. [ ] Admin 웹에서 로그아웃 → Google로 `testpastor@example.com` 재로그인
2. [ ] **기대**: 사이드바에 기존 메뉴(단원/출석/공지/악보/일정) 노출, "교회 관리" 메뉴는 **숨겨짐**
3. [ ] 헤더 서브타이틀: "CHURCH ADMIN"
4. [ ] `/dashboard/members` → 대기 0명 / 승인 1명 (본인)
5. [ ] `/dashboard/announcements` → 빈 리스트, "새 공지" 가능
6. [ ] 테스트로 공지 1개 작성: 제목 "테스트 공지 1"
7. [ ] Firestore: `announcements/{id}.churchId == X`

---

## 시나리오 5 — 다른 계정이 교회 단원 가입

**목표**: B 계정이 "테스트교회"에 찬양대원으로 가입 신청 → A가 승인

1. [ ] 시뮬B에서 Flutter 앱 → Google B로 로그인 (예 `testsop@example.com`)
2. [ ] `ChurchSelectionScreen` → "찬양대원으로 가입"
3. [ ] `ChurchSearchScreen` → "테스트" 입력 → "테스트교회" 결과 나타남
4. [ ] 테스트교회 탭 → `ProfileSetupScreen`
5. [ ] 배너: "테스트교회 찬양대원 신청", 역할 고정 "찬양대원"
6. [ ] 이름 "박소프라노", 파트 soprano → "가입 신청"
7. [ ] **기대**: `PendingApprovalScreen`
   - 문구: "테스트교회 관리자가 가입 신청을 검토하고 있어요"
8. [ ] Firestore: `users/{B uid}.churchId == X`, `approvalScope == 'church'`, `requestedRole == 'member'`, `approvalStatus == 'pending'`
9. [ ] Admin 웹(A 로그인) → `/dashboard/members` → "승인 대기" 탭 1명
10. [ ] "박소프라노" 행의 "승인" 버튼 클릭
11. [ ] Firestore: `users/{B uid}.role == 'member'`, `approvalStatus == 'approved'`
12. [ ] 시뮬B → **자동으로 MainShell** 진입
13. [ ] 시뮬B 공지 화면 → "테스트 공지 1" 노출 확인

---

## 시나리오 6 — 데이터 격리 (다른 교회)

**목표**: 다른 교회 C의 멤버는 테스트교회 데이터를 볼 수 없음

1. [ ] 시뮬C에서 Google C로 로그인 (예 `otherpastor@example.com`)
2. [ ] "새 교회 등록" → "다른교회" 이름으로 등록 신청
3. [ ] Admin 웹(`sinbun001`) → 교회 관리에서 "다른교회" 승인
4. [ ] 시뮬C → MainShell 진입
5. [ ] 공지 탭 확인 → **"테스트 공지 1"이 보이지 않음** ← 핵심 격리 확인
6. [ ] Firebase 콘솔에서 직접 시뮬C 계정 context로 `announcements/` 읽기 시도(아니면 다른 교회의 공지 ID로 직접 URL 접근) → **permission-denied** 예상

---

## 시나리오 7 — 중복 교회명 차단

**목표**: 같은 이름의 pending/approved 교회는 중복 등록 불가

1. [ ] 시뮬D(또는 시뮬A에서 로그아웃 후 새 계정)에서 Flutter 실행
2. [ ] "새 교회 등록" → 교회명에 **"테스트교회"** 입력 (시나리오 3에서 이미 승인됨)
3. [ ] "다음: 프로필 작성" 클릭
4. [ ] **기대**: 화면에 "이미 등록 신청된 이름입니다" 에러 SnackBar/메시지
5. [ ] "테스트교회 2" 등 다른 이름으로 변경 → 정상 진행

---

## 시나리오 8 — 거부 후 재신청 플로우

**목표**: 교회 등록/단원 가입 거부 후 RejectedScreen의 2가지 경로 검증

**파트 A: 교회 가입 거부 → 같은 정보 재신청**
1. [ ] 시뮬E에서 새 계정 → "테스트교회" 찬양대원 신청 (pending)
2. [ ] Admin 웹(A 로그인) → 멤버 관리 → 해당 유저 "거부" + 사유 입력
3. [ ] 시뮬E → **RejectedScreen 자동 전환**
   - 제목: "가입이 거절되었습니다"
   - 2 버튼: "같은 정보로 다시 신청"(주), "다른 교회에 가입"(보)
   - 거절 사유 표시
4. [ ] "같은 정보로 다시 신청" 클릭 → `ProfileSetupScreen(reapply)` (churchId는 유지)
5. [ ] 이름 등 일부 수정 → "다시 신청"
6. [ ] **기대**: `PendingApprovalScreen`으로 전환, Firestore에 `rejectionReason` 삭제됨, `approvalStatus == 'pending'`

**파트 B: 교회 등록 거부 → 다른 교회 가입**
1. [ ] 시뮬F에서 새 계정 → "임시교회" 등록 신청 (platform scope pending)
2. [ ] Admin 웹(`sinbun001`) → 교회 관리 → "임시교회" 거부 + 사유 입력
3. [ ] 시뮬F → **RejectedScreen**
   - 제목: "교회 등록이 거절되었습니다"
   - 버튼 1개: "다른 교회에 가입 또는 재등록"("같은 정보 재신청"은 platform scope에선 숨김)
4. [ ] 클릭 → ChurchSelectionScreen
5. [ ] "찬양대원" → "테스트교회" 선택 → 프로필 제출
6. [ ] **기대**: `PendingApprovalScreen`, Firestore에 `churchId == 테스트교회 id`, `approvalScope == 'church'`, `requestedRole == 'member'`, `rejectionReason` 삭제

---

## 결과 기록

각 시나리오 옆 체크박스에 진행하면서 ✅ / ❌ 표시.

실패 케이스 발견 시:
- 시나리오 번호
- 어떤 단계에서 실패?
- 실제 결과 vs 기대 결과
- 콘솔 에러(있다면)

를 메모해서 공유 → 수정 반영 후 재검증.

---

## Known Limitations (이번 스콥 외)

- **네이버 로그인**: 미구현 (Google/Kakao만)
- **교회 soft-delete**: Platform Admin이 교회를 비활성화하는 UI 없음
- **멀티 교회 멤버십**: 한 UID는 한 교회에만 속할 수 있음 (B 계정이 테스트교회+다른교회 동시 소속 불가)
- **Cloud Function 검증**: 중복 교회명, 승인 트랜잭션 등은 클라이언트+rules 2중 방어만, Function 검증은 없음
