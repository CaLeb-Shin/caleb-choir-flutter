bool primeRelayBackingAudio(String url, Duration position) => false;

bool startRelayBackingAudio(String url, Duration position) => false;

void stopRelayBackingAudio() {}

// Mobile uses the audioplayers backing player as its own clock, so the web
// bridge accessors report "unavailable" and callers fall back accordingly.
double relayBackingAudioSeconds() => -1;

bool relayBackingAudioPlaying() => false;
