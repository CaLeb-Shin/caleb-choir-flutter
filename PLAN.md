# 갈렙 찬양대 Flutter 앱 - 작업 내역

## GitHub
- Flutter 앱: https://github.com/CaLeb-Shin/caleb-choir-flutter
- 백엔드 (Expo): https://github.com/CaLeb-Shin/caleb-choir-APP
- 관리자 웹: https://caleb-choir-cy8rf21rt-sinbun001s-projects.vercel.app

## 구현 완료 (2026-04-09)

### 화면 (7개 탭)
1. **대시보드** - 프로필 카드, 빠른 메뉴, 공지 피드
2. **악보 도서관** - PDF 악보 열람/뷰어
3. **찬양 영상** - YouTube 영상 재생
4. **출석** - QR 스캔, 버튼 체크인, 출석 통계, 엑셀 내보내기
5. **커뮤니티** - 게시물/사진/댓글, 공지 배너
6. **이벤트 & 시상** - 우수 출석자, 이벤트, 마일스톤
7. **마이페이지** - 프로필, 통계, 설정

### 핵심 기능
- **출석**: QR 스캔 (mobile_scanner) + 버튼 체크인 + 엑셀(CSV) 내보내기
- **악보**: PDF 업로드/열람 (flutter_pdfview)
- **영상**: YouTube 재생 (url_launcher)
- **커뮤니티**: 사진 게시/댓글 (image_picker)
- **이벤트**: 우수 출석자 시상, 이벤트 관리
- **공지**: 일정 공지 + 읽음 표시

### 백엔드 API 추가
- `sheetMusic.list/add/delete` - 악보 CRUD
- `events.list/create/delete` - 이벤트 CRUD
- `attendanceExport.csv` - 출석 데이터 CSV 내보내기
- DB 테이블: `sheet_music`, `events`

## 기술 스택
- Flutter 3.41 + Dart 3.11
- Riverpod (상태관리) + Dio (HTTP)
- mobile_scanner (QR), flutter_pdfview (PDF), share_plus (공유)
- Navy/Gold Material 3 디자인 시스템

## 다음 단계
- [ ] OAuth 로그인 연동 (서버 URL 설정)
- [ ] iOS/Android 앱스토어 출시 (flutter build)
- [ ] 푸시 알림 (FCM)
