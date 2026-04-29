# Codex Guide

## Project

Caleb Choir Flutter app. The web build is deployed by Vercel from GitHub pushes.

## Common Commands

- Install Flutter packages: `flutter pub get`
- Analyze without failing on existing info-level lints: `flutter analyze --no-fatal-infos`
- Run tests: `flutter test`
- Build web: `flutter build web --release`
- Install Firebase Functions packages: `npm --prefix functions ci`
- Deploy by GitHub/Vercel: push to `main`

## Notes

- Keep admin code in a sibling repository/folder, not inside this Flutter project.
- Do not commit generated dependency folders such as `functions/node_modules/`, `.dart_tool/`, `build/`, `.firebase/`, or `.vercel/`.
- Firebase app config is generated in `lib/firebase_options.dart`; update it through FlutterFire CLI when Firebase apps change.
- Vercel uses `vercel.json` and publishes `build/web`.

## Verification Before Handoff

Run these for normal app changes:

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build web --release
```

Run this when `functions/` changes:

```sh
npm --prefix functions ci
```
