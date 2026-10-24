import Foundation

/// 空教室纯规则，与 Android `FreeClassroomRules` 保持一致；不做网络请求。
nonisolated enum FreeClassroomRules {
    /// 虚拟考场（如"在线考试虚拟考场"，座位数 50000）不是实体教室。
    static func isVirtual(name: String, seats: Int?) -> Bool {
        name.contains("虚拟") || (seats ?? 0) > 1000
    }

    /// 去掉"（停用）"这类括号，保留其它文字。
    static func cleanName(_ name: String) -> String {
        name.replacing(/[（(][^）)]*停用[^）)]*[）)]/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 房号：先从名称末尾取 3–4 位数字（去掉停用后缀和 -1、-2 之类的重复标记），取不到再从编号取，都取不到用原始编号。
    static func roomCode(number: String, name: String) -> String {
        let base = cleanName(name).replacing(/-\d$/, with: "")
        if let match = base.firstMatch(of: /(\d{3,4})\s*$/) { return String(match.1) }
        if let match = number.firstMatch(of: /-(\d{3,4})(-[A-Za-z])?$/) { return String(match.1) }
        if let match = number.firstMatch(of: /(\d{3,4})$/) { return String(match.1) }
        return number
    }

    /// 推测楼层：三位数取首位，四位数取前两位（通慧楼 1001–1005 为 10 层）。超过 12 层或推不出返回 nil。
    static func floorOf(_ code: String) -> Int? {
        guard !code.isEmpty, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let floor: Int?
        switch code.count {
        case 3: floor = Int(code.prefix(1))
        case 4: floor = Int(code.prefix(2))
        default: return nil
        }
        guard let floor, (1...12).contains(floor) else { return nil }
        return floor
    }

    static func stopReasons(name: String, statusCode: String) -> Set<FcStopReason> {
        var reasons: Set<FcStopReason> = []
        if name.contains("停用") { reasons.insert(.name) }
        switch statusCode {
        case "02": reasons.insert(.status02)
        case "03": reasons.insert(.status03)
        default: break
        }
        return reasons
    }

    /// 同一楼宇、同一房号的多行合并为一间。任一行停用即视为停用，并保留原因。
    static func merge(_ rows: [FcRawRoom]) -> [FcRoom] {
        var order: [(key: String, code: String)] = []
        var groups: [String: [FcRawRoom]] = [:]
        for row in rows where !isVirtual(name: row.name, seats: row.seats) {
            let code = roomCode(number: row.number, name: row.name)
            let key = "\(row.campusNo)|\(row.buildingNo)|\(code)"
            if groups[key] == nil { order.append((key: key, code: code)) }
            groups[key, default: []].append(row)
        }
        return order.compactMap { entry in
            guard let list = groups[entry.key], let first = list.first else { return nil }
            let preferred = list.first { !$0.name.contains("停用") } ?? first
            let cleaned = cleanName(preferred.name)
            return FcRoom(
                campusNo: first.campusNo,
                campusName: first.campusName,
                buildingNo: first.buildingNo,
                buildingName: first.buildingName,
                number: preferred.number,
                title: cleaned.isEmpty ? preferred.number : cleaned,
                code: entry.code,
                floor: floorOf(entry.code),
                seats: list.compactMap(\.seats).first,
                typeCode: list.compactMap(\.typeCode).first,
                typeName: list.compactMap(\.typeName).first,
                stopReasons: Set(list.flatMap { stopReasons(name: $0.name, statusCode: $0.statusCode) })
            )
        }
    }

    /// 某个时段（星期 + 节次）在哪些周被占用。占用集合的元素格式为 weekday_week_section。
    static func busyWeeks(in occupancy: Set<String>, weekday: Int, section: Int) -> [Int] {
        occupancy.compactMap { token -> Int? in
            let parts = token.split(separator: "_")
            guard parts.count == 3, parts[0] == "\(weekday)", parts[2] == "\(section)" else { return nil }
            return Int(parts[1])
        }
        .sorted()
    }
}
