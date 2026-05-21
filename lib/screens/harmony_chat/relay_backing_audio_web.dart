import 'dart:js_interop';

@JS('CCNoteRelayAudio.prime')
external JSBoolean _primeRelayBackingAudio(JSString url, JSNumber startSeconds);

@JS('CCNoteRelayAudio.start')
external JSBoolean _startRelayBackingAudio(JSString url, JSNumber startSeconds);

@JS('CCNoteRelayAudio.stop')
external void _stopRelayBackingAudio();

bool primeRelayBackingAudio(String url, Duration position) {
  return _primeRelayBackingAudio(
    url.toJS,
    (position.inMilliseconds / 1000).toJS,
  ).toDart;
}

bool startRelayBackingAudio(String url, Duration position) {
  return _startRelayBackingAudio(
    url.toJS,
    (position.inMilliseconds / 1000).toJS,
  ).toDart;
}

void stopRelayBackingAudio() {
  _stopRelayBackingAudio();
}
