class ScheduleCardInterval<T> {
  final T item;
  final int weekday;
  final int startSession;
  final int endSession;

  const ScheduleCardInterval({
    required this.item,
    required this.weekday,
    required this.startSession,
    required this.endSession,
  }) : assert(weekday > 0),
       assert(startSession > 0),
       assert(endSession >= startSession);
}

class ScheduleCardPlacement<T> {
  final ScheduleCardInterval<T> interval;
  final int lane;
  final int laneCount;

  const ScheduleCardPlacement({
    required this.interval,
    required this.lane,
    required this.laneCount,
  });
}

/// Assigns horizontally separated lanes to cards whose session ranges overlap.
///
/// Lane counts are scoped to each connected overlap group so unrelated cards on
/// the same weekday still use the full column width.
List<ScheduleCardPlacement<T>> layoutScheduleCardIntervals<T>(
  Iterable<ScheduleCardInterval<T>> intervals,
) {
  final indexed = intervals
      .toList()
      .asMap()
      .entries
      .map((entry) => _IndexedInterval(entry.key, entry.value))
      .toList();
  final byWeekday = <int, List<_IndexedInterval<T>>>{};

  for (final entry in indexed) {
    byWeekday.putIfAbsent(entry.interval.weekday, () => []).add(entry);
  }

  final placements = <_IndexedPlacement<T>>[];
  for (final dayIntervals in byWeekday.values) {
    dayIntervals.sort((a, b) {
      final startCompare = a.interval.startSession.compareTo(
        b.interval.startSession,
      );
      if (startCompare != 0) return startCompare;

      final endCompare = a.interval.endSession.compareTo(b.interval.endSession);
      return endCompare != 0 ? endCompare : a.index.compareTo(b.index);
    });

    var component = <_IndexedInterval<T>>[];
    int? componentEnd;

    void flushComponent() {
      if (component.isEmpty) return;

      final laneEndSessions = <int>[];
      final assignments = <_LaneAssignment<T>>[];
      for (final entry in component) {
        var lane = laneEndSessions.indexWhere(
          (endSession) => endSession < entry.interval.startSession,
        );
        if (lane == -1) {
          lane = laneEndSessions.length;
          laneEndSessions.add(entry.interval.endSession);
        } else {
          laneEndSessions[lane] = entry.interval.endSession;
        }
        assignments.add(_LaneAssignment(entry, lane));
      }

      final laneCount = laneEndSessions.length;
      for (final assignment in assignments) {
        placements.add(
          _IndexedPlacement(
            assignment.entry.index,
            ScheduleCardPlacement(
              interval: assignment.entry.interval,
              lane: assignment.lane,
              laneCount: laneCount,
            ),
          ),
        );
      }

      component = <_IndexedInterval<T>>[];
      componentEnd = null;
    }

    for (final entry in dayIntervals) {
      if (componentEnd != null && entry.interval.startSession > componentEnd!) {
        flushComponent();
      }
      component.add(entry);
      componentEnd =
          componentEnd == null || entry.interval.endSession > componentEnd!
          ? entry.interval.endSession
          : componentEnd;
    }
    flushComponent();
  }

  placements.sort((a, b) => a.index.compareTo(b.index));
  return placements.map((entry) => entry.placement).toList();
}

class _IndexedInterval<T> {
  final int index;
  final ScheduleCardInterval<T> interval;

  const _IndexedInterval(this.index, this.interval);
}

class _LaneAssignment<T> {
  final _IndexedInterval<T> entry;
  final int lane;

  const _LaneAssignment(this.entry, this.lane);
}

class _IndexedPlacement<T> {
  final int index;
  final ScheduleCardPlacement<T> placement;

  const _IndexedPlacement(this.index, this.placement);
}
