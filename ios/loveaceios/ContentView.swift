import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(AnnouncementViewModel.self) private var announcementVM
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var testFlightUpdate: IOSTestFlightUpdate?

    private var isAnnouncementPresented: Binding<Bool> {
        Binding(
            get: { announcementVM.currentAnnouncement != nil },
            set: { _ in }
        )
    }

    /// 有 TestFlight 新构建且当前没有公告弹窗时才显示更新提示
    private var isTestFlightUpdatePresented: Binding<Bool> {
        Binding(
            get: { testFlightUpdate != nil && announcementVM.currentAnnouncement == nil },
            set: { _ in }
        )
    }

    /// 回到前台（节流）或会话建立（强制预取，进入首页时不受 30 分钟节流）后刷新：课表与考试快照、提醒、灵动岛
    private func refreshWidgetAndReminders(force: Bool = false) async {
        await WidgetSyncCoordinator.sync(authVM: authVM, force: force)
        await ClassReminderScheduler.reschedule(snapshot: WidgetSnapshotStore.load())
        await CourseLiveActivityController.sync()
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
                AdaptiveRootView()
                    .id(authVM.sessionGeneration)
            case .unauthenticated, .error, .loading:
                // 登录中也保持登录页挂载：切到加载页会销毁表单状态（输入的密码、验证码），
                // 出错后重建会用记住的旧凭据覆盖输入并清空验证码
                LoginView()
            }
        }
        .animation(.default, value: authVM.state == .authenticated)
        .task { announcementVM.loadAnnouncements() }
        .task { testFlightUpdate = await IOSUpdateService.fetchUpdate() }
        .task(id: authVM.sessionGeneration) { await refreshWidgetAndReminders(force: true) }
        .task(id: authVM.state == .authenticated) {
            // 前台期间每分钟检查一次灵动岛时段（上课中）
            guard authVM.state == .authenticated else { return }
            while !Task.isCancelled {
                await CourseLiveActivityController.sync()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshWidgetAndReminders() }
        }
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
        .background {
            Color.clear.alert(
                testFlightUpdate?.title ?? "发现新版本",
                isPresented: isTestFlightUpdatePresented,
                presenting: testFlightUpdate
            ) { update in
                Button("前往 TestFlight") {
                    openURL(update.testflightURL)
                    testFlightUpdate = nil
                }
                Button("稍后", role: .cancel) {
                    IOSUpdateService.ignore(update)
                    testFlightUpdate = nil
                }
            } message: { update in
                Text(update.changelog)
            }
        }
    }
}
