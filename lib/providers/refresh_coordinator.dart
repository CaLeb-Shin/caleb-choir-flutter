import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';
import 'awards_provider.dart';

/// Invalidates the "cache class" providers — reference/list data fetched once
/// and held until invalidated (FutureProviders). Realtime StreamProviders
/// (posts, events, polls, attendance session, harmony…) are deliberately left
/// alone: Firestore reconnects them automatically, so re-invalidating would
/// only cause a needless reload flicker.
///
/// Call this on app resume after a long background and on logout, so the user
/// never stares at stale reference data they can't pull-to-refresh away.
void invalidateCacheProviders(WidgetRef ref) {
  ref.invalidate(profileProvider);
  ref.invalidate(currentChurchProvider);
  ref.invalidate(announcementsProvider);
  ref.invalidate(sheetMusicProvider);
  ref.invalidate(videosProvider);
  ref.invalidate(recentSheetMusicProvider);
  ref.invalidate(recentVideosProvider);
  ref.invalidate(membersProvider);
  ref.invalidate(myHistoryProvider);
  ref.invalidate(recentSessionsProvider);
  ref.invalidate(seatingChartsProvider);
  ref.invalidate(seatingPresetsProvider);
  ref.invalidate(latestPartGuideProvider);
  ref.invalidate(awardsProvider);
}
