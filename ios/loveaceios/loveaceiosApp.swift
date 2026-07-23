import SwiftUI

@main
struct loveaceiosApp: App {
    @State private var authVM = AuthViewModel()
    @State private var announcementVM = AnnouncementViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authVM)
                .environment(announcementVM)
                .onAppear { Analytics.shared.trackAppStart(launchSource: "cold_start") }
        }
    }
}
