import Foundation

struct LaborClubDirectoryItem: Codable, Identifiable {
    let id: String
    let name: String
    let typeId: String
    let projectId: String
    let peopleNum: Int
    let memberNum: Int
    let projectName: String
    let typeName: String
    let iconUrl: String?
    let description: String?
    let isEnabled: Bool
    let isJoined: Bool

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case typeId = "TypeID"
        case projectId = "ProjectID"
        case peopleNum = "PeopleNum"
        case memberNum = "MemberNum"
        case projectName = "PorjectName"
        case typeName = "TypeName"
        case iconUrl = "Ico"
        case description = "Desc"
        case isEnabled = "IsEnable"
        case isJoined = "IsJoin"
    }

    var canApply: Bool { isEnabled && !isJoined }
}

struct LaborClubApplication: Codable, Identifiable {
    let id: String
    let clubId: String
    let clubName: String
    let reason: String
    let addTime: String
    let replyComment: String
    let isAgree: Bool?
    let statusText: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case clubId = "ClubID"
        case clubName = "ClubName"
        case reason = "Reason"
        case addTime = "AddTime"
        case replyComment = "ReplyComment"
        case isAgree = "IsAgree"
        case statusText = "StateName"
    }

    init(
        id: String = "",
        clubId: String = "",
        clubName: String = "",
        reason: String = "",
        addTime: String = "",
        replyComment: String = "",
        isAgree: Bool? = nil,
        statusText: String = ""
    ) {
        self.id = id
        self.clubId = clubId
        self.clubName = clubName
        self.reason = reason
        self.addTime = addTime
        self.replyComment = replyComment
        self.isAgree = isAgree
        self.statusText = statusText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        clubId = try container.decodeIfPresent(String.self, forKey: .clubId) ?? ""
        clubName = try container.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        addTime = try container.decodeIfPresent(String.self, forKey: .addTime) ?? ""
        replyComment = try container.decodeIfPresent(String.self, forKey: .replyComment) ?? ""
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText) ?? ""
        isAgree = container.decodeFlexibleBoolIfPresent(forKey: .isAgree)
    }

    var reviewStatus: LaborClubApplicationReviewStatus {
        let normalized = statusText.lowercased()
        let rejectedWords = ["拒绝", "驳回", "未通过", "失效", "过期", "invalid", "expired"]
        if rejectedWords.contains(where: normalized.contains) { return .rejected }
        switch isAgree {
        case true: return .approved
        case false: return .rejected
        case nil: return .pending
        }
    }
}

enum LaborClubApplicationReviewStatus {
    case pending
    case approved
    case rejected
}

enum LaborClubMembershipStatus {
    case joined
    case pending
    case approvedSyncing
    case notJoined
    case rejected
    case submitting
}

struct LaborClubMembershipState {
    let status: LaborClubMembershipStatus
    let latestApplication: LaborClubApplication?

    static let notJoined = LaborClubMembershipState(status: .notJoined, latestApplication: nil)
}

struct LaborClubSubmissionResolution {
    let membership: LaborClubMembershipState
    let isStatusSyncing: Bool
}

func resolveLaborClubMembership(
    joinedClubs: [LaborClubInfo],
    latestApplication: LaborClubApplication?,
    isSubmitting: Bool = false
) -> LaborClubMembershipState {
    if !joinedClubs.isEmpty {
        return LaborClubMembershipState(status: .joined, latestApplication: latestApplication)
    }
    if isSubmitting {
        return LaborClubMembershipState(status: .submitting, latestApplication: latestApplication)
    }
    let status: LaborClubMembershipStatus
    switch latestApplication?.reviewStatus {
    case .pending: status = .pending
    case .approved: status = .approvedSyncing
    case .rejected: status = .rejected
    case nil: status = .notJoined
    }
    return LaborClubMembershipState(status: status, latestApplication: latestApplication)
}

func resolveLaborClubSubmission(
    joinedClubs: [LaborClubInfo],
    latestApplication: LaborClubApplication?,
    expectedClubId: String,
    previousApplication: LaborClubApplication? = nil
) -> LaborClubSubmissionResolution {
    let normalizedClubId = expectedClubId.trimmingCharacters(in: .whitespacesAndNewlines)
    let confirmedApplication: LaborClubApplication? = latestApplication.flatMap { application -> LaborClubApplication? in
        guard application.clubId.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(normalizedClubId) == .orderedSame else { return nil }
        if let previousApplication, sameApplicationRecord(application, previousApplication) {
            return nil
        }
        return application
    }
    if !joinedClubs.isEmpty {
        return LaborClubSubmissionResolution(
            membership: resolveLaborClubMembership(
                joinedClubs: joinedClubs,
                latestApplication: confirmedApplication
            ),
            isStatusSyncing: false
        )
    }
    guard let confirmedApplication else {
        return LaborClubSubmissionResolution(
            membership: LaborClubMembershipState(status: .pending, latestApplication: nil),
            isStatusSyncing: true
        )
    }
    return LaborClubSubmissionResolution(
        membership: resolveLaborClubMembership(
            joinedClubs: [],
            latestApplication: confirmedApplication
        ),
        isStatusSyncing: false
    )
}

private func sameApplicationRecord(
    _ current: LaborClubApplication,
    _ previous: LaborClubApplication
) -> Bool {
    let currentId = current.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let previousId = previous.id.trimmingCharacters(in: .whitespacesAndNewlines)
    if !currentId.isEmpty, !previousId.isEmpty {
        return currentId.caseInsensitiveCompare(previousId) == .orderedSame
    }
    return current.clubId.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(previous.clubId.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame &&
        current.addTime.trimmingCharacters(in: .whitespacesAndNewlines) ==
            previous.addTime.trimmingCharacters(in: .whitespacesAndNewlines) &&
        current.reason.trimmingCharacters(in: .whitespacesAndNewlines) ==
            previous.reason.trimmingCharacters(in: .whitespacesAndNewlines)
}

func latestLaborClubApplication(_ applications: [LaborClubApplication]) -> LaborClubApplication? {
    applications.max { applicationTimeKey($0.addTime) < applicationTimeKey($1.addTime) }
}

private func applicationTimeKey(_ value: String) -> String {
    let digits = value.filter(\.isNumber)
    return String((digits + String(repeating: "0", count: 20)).prefix(20))
}

private extension KeyedDecodingContainer {
    func decodeFlexibleBoolIfPresent(forKey key: Key) -> Bool? {
        if (try? decodeNil(forKey: key)) == true { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "approved", "agree", "通过", "同意": return true
        case "false", "0", "no", "rejected", "refused", "拒绝", "驳回", "未通过", "失效": return false
        default: return nil
        }
    }
}
