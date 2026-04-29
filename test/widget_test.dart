import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:caleb_choir/main.dart';
import 'package:caleb_choir/providers/app_providers.dart';

void main() {
  testWidgets('Logged-out app renders login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const CalebChoirApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('C.C Note'), findsOneWidget);
    expect(find.text('Google로 시작하기'), findsOneWidget);
  });
}
