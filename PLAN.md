# 갈렙 찬양대 Flutter 앱 - 개발 계획

## 목표
- 단원용 모바일 앱 (iOS/Android 스토어 출시용)
- 관리자 패널은 기존 웹(Vercel) 유지
- 기존 백엔드 API(tRPC/Express/MySQL)에 연결

## 구현 화면
1. **로그인** - OAuth 로그인
2. **프로필 설정** - 기수/파트/연락처 입력
3. **대시보드** (홈) - 프로필 카드, 빠른 메뉴, 최신 공지
4. **악보 도서관** (영상) - YouTube 영상 목록
5. **연습 일정** (출석) - 출석 체크인, 통계, 기록
6. **커뮤니티** - 게시물 피드, 공지 배너
7. **마이페이지** - 프로필, 통계, 설정

## 기술 스택
- Flutter 3.41 + Dart 3.11
- HTTP: `dio` (API 통신)
- 상태관리: `riverpod`
- 네비게이션: `go_router`
- 보안저장: `flutter_secure_storage`
- URL런처: `url_launcher`

## 디자인 시스템
- Primary: #000e24 (Navy), Accent: #775a19 / #fed488 (Gold)
- Font: System default (iOS: SF Pro, Android: Roboto)
- Material 3 기반
