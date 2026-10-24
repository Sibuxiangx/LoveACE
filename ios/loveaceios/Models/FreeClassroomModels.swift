import Foundation

// MARK: - Free Classroom Models

/// 教学楼（TeachBuildingName 接口）。stopped = 备注或名称含"停用"。
struct FcBuilding: Identifiable, Hashable, Sendable {
    let campusNo: String
    let campusName: String
    let no: String
    let name: String
    let stopped: Bool

    var id: String { "\(campusNo)|\(no)" }
}

/// 停用原因。名称含"停用"的房间始终显示并带标记；状态码 02 / 03 默认隐藏，打开"显示停用教室"后显示。
nonisolated enum FcStopReason: Hashable, Sendable {
    case name
    case status02
    case status03
}

/// 合并后的教室（按楼宇 + 房号去重）。
struct FcRoom: Identifiable, Hashable, Sendable {
    let campusNo: String
    let campusName: String
    let buildingNo: String
    let buildingName: String
    /// 详情页使用的编号（classroomNumber）
    let number: String
    /// 展示名：去掉"（停用）"等后缀
    let title: String
    /// 房号，如 302、1001；取不到时为原始编号
    let code: String
    /// 推测楼层：三位数取首位，四位数取前两位；取不到或超过 12 为 nil（归入"其他"）
    let floor: Int?
    let seats: Int?
    let typeCode: String?
    let typeName: String?
    let stopReasons: Set<FcStopReason>

    var id: String { roomKey }
    var roomKey: String { "\(campusNo)|\(buildingNo)|\(code)" }
    var buildingKey: String { "\(campusNo)|\(buildingNo)" }
    var stopped: Bool { !stopReasons.isEmpty }
    /// 状态码 02 或 03：默认隐藏
    var statusHidden: Bool { stopReasons.contains(.status02) || stopReasons.contains(.status03) }
}

/// 合并前的原始行（classroomJson 或 search 结果的一条）。
struct FcRawRoom: Sendable {
    let campusNo: String
    let campusName: String
    let buildingNo: String
    let buildingName: String
    let number: String
    let name: String
    let statusCode: String
    let typeCode: String?
    let typeName: String?
    let seats: Int?
}

/// 下拉选项（教室类型等）。
struct FcOption: Identifiable, Hashable, Sendable {
    let code: String
    let name: String

    var id: String { code }
}

/// 元信息：当前教学周（查询页头部"第 N 周"）与教室类型选项。
struct FcMeta: Sendable {
    let currentWeek: Int?
    let types: [FcOption]
}

/// 时段：weekday 1...7（周一...周日），section 1...10。
struct FcSlot: Hashable, Sendable {
    let weekday: Int
    let section: Int
}

/// 空闲查询条件。空字符串表示不限。
struct FcQuery: Sendable {
    var weeks: [Int]
    var slots: [FcSlot]
    var campusNo: String = ""
    var buildingNo: String = ""
    var typeCode: String = ""
}

/// 楼层分组：floor 为 nil 的归入"其他"。
struct FcFloorGroup: Identifiable {
    let floor: Int?
    let rooms: [FcRoom]

    var id: Int { floor ?? -1 }
    var title: String { floor.map { "\($0) 层" } ?? "其他（推测不出楼层）" }
}

/// 一栋楼的查询结果：范围内的全部教室按楼层分组，并统计空闲数量。
struct FcBuildingDistribution: Identifiable {
    let building: FcBuilding
    let freeCount: Int
    let totalCount: Int
    let floors: [FcFloorGroup]

    var id: String { building.id }
}
