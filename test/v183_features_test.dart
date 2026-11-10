import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';

void main() {
  group('Autoplay Countdown Trigger Logic', () {
    test('Credits marker takes precedence over manual autoplay trigger seconds', () {
      const itemWithCredits = PlexMediaItem(
        ratingKey: '101',
        key: '/library/metadata/101',
        title: 'Episode With Credits',
        type: 'episode',
        duration: 1800000, // 30 min (1,800,000 ms)
        markers: [
          PlexMarker(
            id: 1,
            type: 'credits',
            startTimeOffset: 1750000, // 50 seconds before end
            endTimeOffset: 1800000,
          ),
        ],
      );

      final credits = itemWithCredits.creditsMarker;
      expect(credits, isNotNull);
      expect(credits!.startTimeOffset, equals(1750000));

      const autoplayTriggerSeconds = 20;
      final durationMs = itemWithCredits.duration ?? 0;
      final int triggerMs;
      if (credits.startTimeOffset > 0) {
        triggerMs = credits.startTimeOffset;
      } else if (durationMs > (autoplayTriggerSeconds * 1000)) {
        triggerMs = durationMs - (autoplayTriggerSeconds * 1000);
      } else {
        triggerMs = -1;
      }

      // Credits marker should override manual 20s timing (1,750,000 vs 1,780,000)
      expect(triggerMs, equals(1750000));
    });

    test('Manual autoplay trigger seconds is used when no credits marker exists', () {
      const itemWithoutCredits = PlexMediaItem(
        ratingKey: '102',
        key: '/library/metadata/102',
        title: 'Episode Without Credits',
        type: 'episode',
        duration: 1800000, // 30 min (1,800,000 ms)
        markers: [],
      );

      final credits = itemWithoutCredits.creditsMarker;
      expect(credits, isNull);

      const autoplayTriggerSeconds = 20; // 20s default
      final durationMs = itemWithoutCredits.duration ?? 0;
      final int triggerMs;
      if (credits != null && credits.startTimeOffset > 0) {
        triggerMs = credits.startTimeOffset;
      } else if (durationMs > (autoplayTriggerSeconds * 1000)) {
        triggerMs = durationMs - (autoplayTriggerSeconds * 1000);
      } else {
        triggerMs = -1;
      }

      // Should trigger 20 seconds before end (1,800,000 - 20,000 = 1,780,000)
      expect(triggerMs, equals(1780000));
    });

    test('Custom autoplay trigger seconds (e.g. 45s) properly scales triggerMs', () {
      const item = PlexMediaItem(
        ratingKey: '103',
        key: '/library/metadata/103',
        title: 'Episode Custom Timing',
        type: 'episode',
        duration: 1200000, // 20 min (1,200,000 ms)
        markers: [],
      );

      const customSeconds = 45;
      final durationMs = item.duration ?? 0;
      final int triggerMs;
      final credits = item.creditsMarker;
      if (credits != null && credits.startTimeOffset > 0) {
        triggerMs = credits.startTimeOffset;
      } else if (durationMs > (customSeconds * 1000)) {
        triggerMs = durationMs - (customSeconds * 1000);
      } else {
        triggerMs = -1;
      }

      expect(triggerMs, equals(1200000 - 45000)); // 1,155,000 ms
    });
  });
}
