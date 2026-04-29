// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:js' as js;

Future<String?> openOfficialAddressSearch() {
  final bridge = js.context['CalebAddressSearch'];
  if (bridge == null) return Future.value(null);

  final completer = Completer<String?>();
  try {
    bridge.callMethod('open', [
      js.JsFunction.withThis((_, dynamic address) {
        if (completer.isCompleted) return;
        completer.complete(address?.toString());
      }),
    ]);
  } catch (_) {
    if (!completer.isCompleted) completer.complete(null);
  }

  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => null,
  );
}
