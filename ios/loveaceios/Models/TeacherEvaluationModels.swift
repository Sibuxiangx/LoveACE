import Foundation

// MARK: - First-Visit Protection

/// 评教首页“首次访问须知/倒计时”保护状态。
/// 仅解析脱敏的结构字段（隐藏 input 与 JS 状态变量），不含任何个人数据。
struct TeacherEvaluationIndexProtection: Hashable {
    var schoolId: String = ""
    var infoOff: String = ""
    var infoTimeSeconds: Int = 0
    var isFinished: String = ""
    var isFinishedResolved: Bool = false
    var isFirstVisit: String = ""
    var isFirstVisitResolved: Bool = false
    var hasAhcjTimer: Bool = false

    /// 命中条件：infoOff=1 且存在倒计时且未见“已完成/已访问”的明确证据。
    /// 状态变量解析失败时保守走等待，避免过早 search/提交。
    var requiresInitialWait: Bool {
        guard infoOff == "1", infoTimeSeconds > 0, hasAhcjTimer else { return false }
        let finishedKnown = isFinishedResolved && isFinished != "unfinished"
        let visitedKnown = isFirstVisitResolved && isFirstVisit != "unVisit"
        return !(finishedKnown || visitedKnown)
    }

    /// 保护等待秒数：倒计时 + 安全余量
    var waitSeconds: Int { infoTimeSeconds > 0 ? infoTimeSeconds + Self.safetySeconds : 0 }

    static let safetySeconds = 5
    static let none = TeacherEvaluationIndexProtection()
}

// MARK: - Teacher Evaluation Course

struct TeacherEvaluationCourse: Codable, Identifiable, Hashable {
    var id: String { stableId }

    let legacyId: String
    let name: String
    let teacher: String
    let evaluatedPeople: String
    let evaluatedPeopleNumber: String
    let coureSequenceNumber: String
    let evaluationContentNumber: String
    let questionnaireCode: String
    let questionnaireName: String
    let isEvaluated: Bool

    var stableId: String {
        [evaluatedPeopleNumber, coureSequenceNumber, evaluationContentNumber, questionnaireCode]
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    var displayName: String { name.isEmpty ? "未命名课程" : name }
    var displayTeacher: String { teacher.isEmpty ? evaluatedPeople : teacher }

    func matches(_ other: TeacherEvaluationCourse) -> Bool {
        if !stableId.isEmpty, stableId == other.stableId { return true }
        return legacyId == other.legacyId && evaluationContentNumber == other.evaluationContentNumber
    }
}

// MARK: - Questionnaire

enum TeacherTextQuestionType: String, Codable {
    case inspiration
    case suggestion
    case overall
    case general
}

struct TeacherQuestionnaireMetadata: Codable, Hashable {
    var title: String = ""
    var evaluatedPerson: String = ""
    var evaluationContent: String = ""
    var tokenValue: String = ""
    var questionnaireCode: String = ""
    var evaluatedPeopleNumber: String = ""
}

struct TeacherRadioOption: Codable, Hashable {
    let label: String
    let value: String
    let score: Double
    let weight: Double
}

struct TeacherRadioQuestion: Codable, Hashable {
    let key: String
    let questionText: String
    let options: [TeacherRadioOption]
    let category: String
}

struct TeacherTextQuestion: Codable, Hashable {
    let key: String
    let questionText: String
    let type: TeacherTextQuestionType
    let isRequired: Bool
}

struct TeacherQuestionnaire: Codable, Hashable {
    let metadata: TeacherQuestionnaireMetadata
    let radioQuestions: [TeacherRadioQuestion]
    let textQuestions: [TeacherTextQuestion]

    var tokenValue: String { metadata.tokenValue }
    var questionnaireCode: String { metadata.questionnaireCode }
    var evaluationContent: String { metadata.evaluationContent }
    var evaluatedPeopleNumber: String { metadata.evaluatedPeopleNumber }
}

// MARK: - Submission Results

struct TeacherEvaluationSubmitResponse: Codable, Hashable {
    let result: String
    let msg: String

    var isSuccess: Bool { result == "success" }
}

struct TeacherEvaluationResult: Identifiable, Hashable {
    let id = UUID()
    let course: TeacherEvaluationCourse
    let success: Bool
    let errorMessage: String?
    let timestamp: Date

    init(course: TeacherEvaluationCourse, success: Bool, errorMessage: String? = nil, timestamp: Date = Date()) {
        self.course = course
        self.success = success
        self.errorMessage = errorMessage
        self.timestamp = timestamp
    }
}

struct TeacherEvaluationBatchResult: Hashable {
    let total: Int
    let success: Int
    let failed: Int
    let results: [TeacherEvaluationResult]
    let duration: TimeInterval

    var successRate: Double { total > 0 ? Double(success) / Double(total) : 0 }
    var durationText: String {
        let seconds = Int(duration)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0 ? "\(minutes)分\(remainder)秒" : "\(remainder)秒"
    }
}

// MARK: - Concurrent Task

enum TeacherEvaluationTaskStatus: String, Codable, Hashable {
    case waiting
    case preparing
    case countdown
    case submitting
    case verifying
    case completed
    case failed

    var displayText: String {
        switch self {
        case .waiting: return "等待开始"
        case .preparing: return "准备评教"
        case .countdown: return "等待提交"
        case .submitting: return "提交中"
        case .verifying: return "验证中"
        case .completed: return "完成"
        case .failed: return "失败"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: return "clock"
        case .preparing: return "doc.text.magnifyingglass"
        case .countdown: return "timer"
        case .submitting: return "paperplane.fill"
        case .verifying: return "checkmark.seal"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

struct TeacherEvaluationTask: Identifiable, Hashable {
    var id: Int { taskId }

    let taskId: Int
    let course: TeacherEvaluationCourse
    var status: TeacherEvaluationTaskStatus = .waiting
    var statusMessage: String?
    var countdownRemaining: Int = 0
    var countdownTotal: Int = 0
    var errorMessage: String?
    /// 轻量错误分类：prepareFailed / submitFailed / verifyMismatch / unknown
    var errorKind: String?
    var startTime: Date?
    var endTime: Date?

    var statusText: String {
        if let statusMessage, !statusMessage.isEmpty { return statusMessage }
        if status == .countdown, countdownRemaining > 0 { return "等待提交（\(countdownRemaining)s）" }
        return status.displayText
    }

    var isFinished: Bool { status == .completed || status == .failed }
    var isSuccess: Bool { status == .completed }

    var progress: Double {
        switch status {
        case .waiting:
            return 0
        case .preparing:
            return 0.1
        case .countdown:
            guard countdownTotal > 0 else { return 0.1 }
            return 0.1 + 0.7 * Double(countdownTotal - countdownRemaining) / Double(countdownTotal)
        case .submitting:
            return 0.85
        case .verifying:
            return 0.95
        case .completed, .failed:
            return 1
        }
    }
}
