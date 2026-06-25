import Foundation

// MARK: - UserClub

/// 用户手动添加的俱乐部信息
///
/// 与服务器返回的 LaborClubInfo 共用 clubId 作为唯一标识，
/// 通过 source 区分数据来源，通过 status 管理显隐状态。
struct UserClub: Codable, Identifiable {
    var id: String { clubId }
    let clubId: String
    let name: String
    let typeName: String?
    let source: ClubSource
    let status: ClubStatus
    let createdAt: TimeInterval
    let note: String?

    init(
        clubId: String,
        name: String,
        typeName: String? = nil,
        source: ClubSource = .manual,
        status: ClubStatus = .active,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        note: String? = nil
    ) {
        self.clubId = clubId
        self.name = name
        self.typeName = typeName
        self.source = source
        self.status = status
        self.createdAt = createdAt
        self.note = note
    }

    func toLaborClubInfo() -> LaborClubInfo {
        LaborClubInfo(
            clubInfoId: clubId,
            name: name,
            typeName: typeName,
            ico: nil,
            chairmanName: nil,
            memberNum: 0
        )
    }
}

enum ClubSource: String, Codable {
    case server
    case manual
}

enum ClubStatus: String, Codable {
    case active
    case hidden
}
