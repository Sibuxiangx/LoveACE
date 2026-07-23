import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(AnnouncementViewModel.self) private var announcementVM

    private var isAnnouncementPresented: Binding<Bool> {
        Binding(
            get: { announcementVM.currentAnnouncement != nil },
            set: { _ in }
        )
    }

    var body: some View {
        Group {
            switch authVM.state {
            case .initial:
                LoadingView(message: "正在恢复会话...")
                    .onAppear { authVM.restoreSession() }
            case .loading:
                LoadingView(message: "登录中...")
            case .authenticated:
                MainTabView()
            case .unauthenticated, .error:
                LoginView()
            }
        }
        .animation(.default, value: authVM.state == .authenticated)
        .task { announcementVM.loadAnnouncements() }
        .alert(
            announcementVM.currentAnnouncement?.title.isEmpty == false
                ? announcementVM.currentAnnouncement?.title ?? "公告"
                : "公告",
            isPresented: isAnnouncementPresented,
            presenting: announcementVM.currentAnnouncement
        ) { announcement in
            Button("我知道了") {
                announcementVM.dismissAnnouncement(id: announcement.id)
            }
        } message: { announcement in
            Text(announcement.content)
        }
    }
}
