import Foundation

@MainActor
@Observable
final class AnnouncementViewModel {
    private static let dismissedIDsKey = "dismissed_manifest_announcement_ids"

    private(set) var currentAnnouncement: AppAnnouncement?

    private var pendingAnnouncements: [AppAnnouncement] = []
    private var loadTask: Task<Void, Never>?

    func loadAnnouncements() {
        guard loadTask == nil else { return }
        loadTask = Task {
            defer { loadTask = nil }
            do {
                let announcements = try await AnnouncementService.fetchAnnouncements()
                let dismissedIDs = Set(
                    UserDefaults.standard.stringArray(forKey: Self.dismissedIDsKey) ?? []
                )
                let unread = announcements.filter { !dismissedIDs.contains($0.id) }
                currentAnnouncement = unread.first
                pendingAnnouncements = Array(unread.dropFirst())
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func dismissAnnouncement(id: String) {
        guard currentAnnouncement?.id == id else { return }
        var dismissedIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.dismissedIDsKey) ?? []
        )
        dismissedIDs.insert(id)
        UserDefaults.standard.set(dismissedIDs.sorted(), forKey: Self.dismissedIDsKey)

        currentAnnouncement = pendingAnnouncements.first
        if !pendingAnnouncements.isEmpty {
            pendingAnnouncements.removeFirst()
        }
    }
}
