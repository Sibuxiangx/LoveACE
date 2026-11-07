import SwiftUI

/// 根导航选中项。底部 Tab 与侧栏共用，横竖屏切换时保持同一页面。
enum AppDestination: Hashable {
    case home
    case aac
    case more
    case settings
    case feature(String)
}

/// 横屏（iPad）用侧栏，竖屏（iPad 与 iPhone）用底部 Tab 栏
struct AdaptiveRootView: View {
    @State private var selection: AppDestination = .home

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .onAppear { track(selection) }
        .onChange(of: selection) { _, newValue in track(newValue) }
    }

    // MARK: - 竖屏：底部 Tab 栏

    private var tabLayout: some View {
        TabView(selection: tabSelection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppDestination.home)
            AACView()
                .tabItem { Label("爱安财", systemImage: "star.fill") }
                .tag(AppDestination.aac)
            MoreView()
                .tabItem { Label("更多", systemImage: "square.grid.2x2.fill") }
                .tag(AppDestination.more)
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(AppDestination.settings)
        }
    }

    /// 横屏侧栏里选中的功能页，切回竖屏时归到"更多"Tab
    private var tabSelection: Binding<AppDestination> {
        Binding(
            get: {
                if case .feature = selection { return .more }
                return selection
            },
            set: { selection = $0 }
        )
    }

    // MARK: - 横屏：侧栏

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    Label("首页", systemImage: "house.fill").tag(AppDestination.home)
                    Label("爱安财", systemImage: "star.fill").tag(AppDestination.aac)
                }
                ForEach(AppCatalog.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Label(item.title, systemImage: item.icon)
                                .tag(AppDestination.feature(item.tag))
                        }
                    }
                }
                Section {
                    Label("我的", systemImage: "person.fill").tag(AppDestination.settings)
                }
            }
            .navigationTitle("彩带小工具")
        } detail: {
            detail(for: selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<AppDestination?> {
        Binding(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )
    }

    @ViewBuilder
    private func detail(for destination: AppDestination) -> some View {
        switch destination {
        case .home: HomeView()
        case .aac: AACView()
        case .more: MoreView()
        case .settings: SettingsView()
        case .feature(let tag):
            NavigationStack { AppCatalog.destinationView(for: tag) }
        }
    }

    // MARK: - 统计

    /// 首页、爱安财、更多、我的沿用原来的统计名称；侧栏里的功能页不新增统计
    private func track(_ destination: AppDestination) {
        switch destination {
        case .home: Analytics.shared.trackScreen("首页")
        case .aac: Analytics.shared.trackScreen("爱安财")
        case .more: Analytics.shared.trackScreen("更多")
        case .settings: Analytics.shared.trackScreen("我的")
        case .feature: break
        }
    }
}
