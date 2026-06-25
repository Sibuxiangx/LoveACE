import Foundation

/// 用户手动添加的俱乐部本地存储
///
/// 使用 UserDefaults 存储 JSON 序列化后的列表。
/// 俱乐部数量极少（通常 < 20），UserDefaults 足够且无需引入 SwiftData。
@MainActor
final class UserClubStore {
    static let shared = UserClubStore()
    private let key = "loveace.userclubs"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func getAll() -> [UserClub] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            let clubs = try decoder.decode([UserClub].self, from: data)
            return clubs.filter { $0.status == .active && $0.source == .manual }
        } catch {
            return []
        }
    }

    func getAllIncludingHidden() -> [UserClub] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            return try decoder.decode([UserClub].self, from: data)
        } catch {
            return []
        }
    }

    func addClub(_ club: UserClub) -> Bool {
        var current = getAllIncludingHidden()
        guard !current.contains(where: { $0.clubId == club.clubId }) else { return false }
        current.append(club)
        save(current)
        return true
    }

    func removeClub(clubId: String) {
        let current = getAllIncludingHidden().filter { $0.clubId != clubId }
        save(current)
    }

    func updateStatus(clubId: String, status: ClubStatus) {
        var current = getAllIncludingHidden()
        if let index = current.firstIndex(where: { $0.clubId == clubId }) {
            current[index] = UserClub(
                clubId: current[index].clubId,
                name: current[index].name,
                typeName: current[index].typeName,
                source: current[index].source,
                status: status,
                createdAt: current[index].createdAt,
                note: current[index].note
            )
            save(current)
        }
    }

    private func save(_ clubs: [UserClub]) {
        do {
            let data = try encoder.encode(clubs)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("UserClubStore save failed: \(error)")
        }
    }
}
