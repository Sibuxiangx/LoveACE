import 'package:flutter_test/flutter_test.dart';
import 'package:loveace/winui/layout/schedule_card_layout.dart';

void main() {
  group('layoutScheduleCardIntervals', () {
    test('separates courses with the same weekday and sessions', () {
      final placements = layoutScheduleCardIntervals([
        const ScheduleCardInterval(
          item: 'weeks-1-9',
          weekday: 1,
          startSession: 1,
          endSession: 2,
        ),
        const ScheduleCardInterval(
          item: 'weeks-9-18',
          weekday: 1,
          startSession: 1,
          endSession: 2,
        ),
      ]);

      expect(placements.map((item) => item.lane), [0, 1]);
      expect(placements.map((item) => item.laneCount), [2, 2]);
    });

    test('keeps non-overlapping cards at full width', () {
      final placements = layoutScheduleCardIntervals([
        const ScheduleCardInterval(
          item: 'morning',
          weekday: 2,
          startSession: 1,
          endSession: 2,
        ),
        const ScheduleCardInterval(
          item: 'afternoon',
          weekday: 2,
          startSession: 3,
          endSession: 4,
        ),
      ]);

      expect(placements.map((item) => item.lane), [0, 0]);
      expect(placements.map((item) => item.laneCount), [1, 1]);
    });

    test('uses the minimum lanes for a connected overlap group', () {
      final placements = layoutScheduleCardIntervals([
        const ScheduleCardInterval(
          item: 'long',
          weekday: 3,
          startSession: 1,
          endSession: 3,
        ),
        const ScheduleCardInterval(
          item: 'early',
          weekday: 3,
          startSession: 1,
          endSession: 1,
        ),
        const ScheduleCardInterval(
          item: 'late',
          weekday: 3,
          startSession: 2,
          endSession: 2,
        ),
      ]);

      final byItem = {for (final item in placements) item.interval.item: item};
      expect(byItem['long']?.lane, 1);
      expect(byItem['early']?.lane, 0);
      expect(byItem['late']?.lane, 0);
      expect(placements.map((item) => item.laneCount), everyElement(2));
    });

    test('lays out different weekdays independently', () {
      final placements = layoutScheduleCardIntervals([
        const ScheduleCardInterval(
          item: 'monday',
          weekday: 1,
          startSession: 5,
          endSession: 6,
        ),
        const ScheduleCardInterval(
          item: 'tuesday',
          weekday: 2,
          startSession: 5,
          endSession: 6,
        ),
      ]);

      expect(placements.map((item) => item.lane), [0, 0]);
      expect(placements.map((item) => item.laneCount), [1, 1]);
    });
  });
}
