// Mobile relies on the OS-level mic permission flow, so the web "already
// granted?" probe simply reports unknown and callers fall back to the recorder.
Future<bool> microphonePermissionGranted() async => false;

bool primeRelayBackingAudio(String url, Duration position) => false;

bool startRelayBackingAudio(String url, Duration position) => false;

void stopRelayBackingAudio() {}

// Mobile uses the audioplayers backing player as its own clock, so the web
// bridge accessors report "unavailable" and callers fall back accordingly.
double relayBackingAudioSeconds() => -1;

bool relayBackingAudioPlaying() => false;
