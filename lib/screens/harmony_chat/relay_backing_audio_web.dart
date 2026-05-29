import 'dart:js_interop';

@JS('CCNoteRelayAudio.prime')
external JSBoolean _primeRelayBackingAudio(JSString url, JSNumber startSeconds);

@JS('CCNoteRelayAudio.start')
external JSBoolean _startRelayBackingAudio(JSString url, JSNumber startSeconds);

@JS('CCNoteRelayAudio.stop')
external void _stopRelayBackingAudio();

@JS('CCNoteRelayAudio.currentTime')
external JSNumber _currentTimeRelayBackingAudio();

@JS('CCNoteRelayAudio.isPlaying')
external JSBoolean _isRelayBackingAudioPlaying();

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

/// Real playback position of the MR `<audio>` element in seconds, or a negative
/// value when no backing track is loaded. Used as the master clock so lyrics
/// and layered clip playback follow the actual audio instead of a timer.
double relayBackingAudioSeconds() {
  try {
    return _currentTimeRelayBackingAudio().toDartDouble;
  } catch (_) {
    return -1;
  }
}

bool relayBackingAudioPlaying() {
  try {
    return _isRelayBackingAudioPlaying().toDart;
  } catch (_) {
    return false;
  }
}
