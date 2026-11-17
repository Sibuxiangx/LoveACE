/// A block on the timetable grid: its weekday and the sessions it spans, inclusive.
typedef ScheduleSlot = ({int weekday, int start, int end});

/// A block's share of its weekday column. [offset] and [width] are fractions of the column
/// width. [focused] marks the block shown at full size in its cluster.
typedef ScheduleSpan = ({double offset, double width, bool focused});

/// Splits each weekday column among the blocks that overlap in sessions.
///
/// Blocks on one weekday form clusters: a run of blocks linked by session overlap. A cluster
/// of n blocks shares the column side by side, ordered by start session. One block is focused
/// and gets weight `n >= 4 ? 2 : 6 - n`; the others get weight 1. So one block fills the
/// column, two split 4:1, three split 3:1:1, and four or more keep the focused block at 2:1.
///
/// The focused block is [focused] (an index into [slots]) when that block is in the cluster,
/// otherwise the cluster's first block. Blocks overlap in sessions, not weeks, because the
/// grid shows every week at once. The result is in the order of [slots].
List<ScheduleSpan> layoutSpans(List<ScheduleSlot> slots, {int? focused}) {
  final result = List<ScheduleSpan>.filled(
    slots.length,
    (offset: 0.0, width: 1.0, focused: true),
  );

  final byWeekday = <int, List<int>>{};
  for (var i = 0; i < slots.length; i++) {
    byWeekday.putIfAbsent(slots[i].weekday, () => []).add(i);
  }

  for (final indices in byWeekday.values) {
    indices.sort((a, b) {
      final byStart = slots[a].start.compareTo(slots[b].start);
      if (byStart != 0) return byStart;
      final byEnd = slots[a].end.compareTo(slots[b].end);
      return byEnd != 0 ? byEnd : a.compareTo(b);
    });

    var cluster = <int>[];
    var clusterEnd = 0;

    void placeCluster() {
      final n = cluster.length;
      final focusedHere = focused != null && cluster.contains(focused)
          ? focused
          : cluster.first;
      final focusWeight = n >= 4 ? 2 : 6 - n;
      final total = focusWeight + n - 1;
      var offset = 0;
      for (final i in cluster) {
        final weight = i == focusedHere ? focusWeight : 1;
        result[i] = (
          offset: offset / total,
          width: weight / total,
          focused: i == focusedHere,
        );
        offset += weight;
      }
      cluster = <int>[];
    }

    for (final i in indices) {
      final slot = slots[i];
      if (cluster.isNotEmpty && slot.start > clusterEnd) placeCluster();
      cluster.add(i);
      if (slot.end > clusterEnd) clusterEnd = slot.end;
    }
    if (cluster.isNotEmpty) placeCluster();
  }

  return result;
}
