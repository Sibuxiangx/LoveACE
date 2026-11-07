import Foundation

/// 企业邮箱初始密码。只保存在内存中，页面离开时清除；不写日志、不落盘。
struct MailInitialPassword: Sendable {
    let loginId: String
    let password: String
}

enum AccessKind: String, CaseIterable, Identifiable, Sendable {
    case dormitory
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dormitory: "宿舍"
        case .library: "图书馆"
        }
    }

    var sectionTitle: String {
        switch self {
        case .dormitory: "宿舍门禁"
        case .library: "图书馆门禁"
        }
    }
}

/// 日期范围。编码为 cube 日期字段的取值，已在门户页面逐项抓取（门禁、一卡通消费通用）。
enum AccessRange: CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今天"
        case .yesterday: "昨天"
        case .thisWeek: "本周"
        case .thisMonth: "本月"
        case .all: "全部"
        }
    }

    /// 本周的编码：页面默认加载时发送 "2,,"（图书馆门禁、一卡通消费），切换到本周时发送 "2"（宿舍门禁）。
    func code(commaWeek: Bool) -> String {
        switch self {
        case .today: "1"
        case .yesterday: "9"
        case .thisWeek: commaWeek ? "2,," : "2"
        case .thisMonth: "3"
        case .all: "0"
        }
    }
}

/// 宿舍门禁的通过方向。接口返回 0/1，门户页面显示为 进/出（2026-11-05 截图逐条核对：0=进，1=出）。
enum AccessDirection: Sendable {
    case entry
    case exit

    var title: String {
        switch self {
        case .entry: "进"
        case .exit: "出"
        }
    }

    var systemImage: String {
        switch self {
        case .entry: "figure.walk.arrival"
        case .exit: "figure.walk.departure"
        }
    }
}

struct AccessRecord: Identifiable, Sendable {
    let id: String
    let time: String
    /// 只有宿舍门禁有通过方向；图书馆门禁的接口不返回该字段
    let direction: AccessDirection?
    /// 次要信息：宿舍为系统名称，图书馆为"校区 · 日期"
    let detail: String
}

struct AccessPage: Sendable {
    let records: [AccessRecord]
    let total: Int
}

/// 一卡通消费一条记录。门户只提供日期、时间、地点、金额；不含交易后余额与交易类型。
struct ConsumptionRecord: Identifiable, Sendable {
    let id: String
    let date: String
    let time: String
    let area: String
    let amount: String
}

struct ConsumptionPage: Sendable {
    let records: [ConsumptionRecord]
    let total: Int
}

struct BorrowRecord: Identifiable, Sendable {
    let id: String
    let title: String
    let borrowedAt: String
    let returnedAt: String?
}
