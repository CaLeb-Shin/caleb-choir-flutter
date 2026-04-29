# Caleb Choir Flutter

갈렙 찬양대 모바일/웹 Flutter 앱입니다.

## 개발 시작

```sh
flutter pub get
flutter run
```

웹으로 확인할 때:

```sh
flutter run -d chrome
```

## 검증 명령

Codex나 로컬 작업 후 기본으로 아래 명령을 확인합니다.

```sh
flutter analyze --no-fatal-infos
flutter test
flutter build web --release
```

Firebase Functions 의존성을 확인할 때:

```sh
npm --prefix functions ci
```

## 배포

이 저장소는 GitHub `main` 브랜치에 push되면 Vercel이 `vercel.json` 설정으로 Flutter web을 빌드해 자동 배포합니다.

- Build command: `flutter/bin/flutter build web --release`
- Output directory: `build/web`
- Production URL: https://caleb-choir-flutter.vercel.app

기존 편의 스크립트도 사용할 수 있습니다.

```sh
./deploy.sh "chore: deploy"
```

## Firebase

- Firebase project: `caleb-choir-2026`
- Flutter Firebase options: `lib/firebase_options.dart`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Cloud Functions: `functions/`

Firebase 앱 설정이 바뀌면 FlutterFire CLI로 다시 생성합니다.

```sh
flutterfire configure
```

## Codex 작업 메모

Codex 작업 지침은 `AGENTS.md`에 정리되어 있습니다. 관리자 웹 프로젝트는 Flutter 앱 내부가 아니라 형제 폴더/별도 저장소로 관리하는 것을 기본으로 합니다.
