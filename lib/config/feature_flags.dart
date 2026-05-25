class FeatureFlags {
  static const harmonyChatEnabled = bool.fromEnvironment(
    'ENABLE_HARMONY_CHAT',
    defaultValue: true,
  );
}
