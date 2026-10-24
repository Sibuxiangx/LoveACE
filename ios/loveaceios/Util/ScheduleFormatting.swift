import Foundation

/// 课表相关的文字格式化，开课查询与空教室共用。
enum ScheduleFormatting {
    static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 1...7 → 周一...周日；其它值返回空串。
    static func weekdayName(_ day: Int) -> String {
        (1...7).contains(day) ? weekdayNames[day - 1] : ""
    }

    /// 周次压缩显示：[1,2,3,4,5,6,9,10] → "1–6、9–10"。
    static func formatWeeks(_ weeks: [Int]) -> String {
        let sorted = Array(Set(weeks)).sorted()
        guard var start = sorted.first else { return "" }
        var end = start
        var parts: [String] = []
        for week in sorted.dropFirst() {
            if week == end + 1 {
                end = week
                continue
            }
            parts.append(rangeText(start, end))
            start = week
            end = week
        }
        parts.append(rangeText(start, end))
        return parts.joined(separator: "、")
    }

    private static func rangeText(_ start: Int, _ end: Int) -> String {
        start == end ? "\(start)" : "\(start)–\(end)"
    }
}
