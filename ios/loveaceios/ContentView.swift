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
            case .reconnecting:
                LoadingView(message: "正在恢复连接...")
            case .authenticated:
                MainTabView()
                    .id(authVM.sessionGeneration)
            case .unauthenticated, .error, .loading:
                // 登录中也保持登录页挂载：切到加载页会销毁表单状态（输入的密码、验证码），
                // 出错后重建会用记住的旧凭据覆盖输入并清空验证码
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
