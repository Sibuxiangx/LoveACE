import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var profileVM = ProfileViewModel()
    @State private var showLogoutAlert = false
    @State private var networkLoggingEnabled = NetworkLogStore.isLoggingEnabled
    @State private var logArchiveURL: URL?
    @State private var isExportingLogs = false
    @State private var logExportError: String?

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("个人设置") {
                    HStack {
                        Label("昵称", systemImage: "pencil.line")
                        Spacer()
                        TextField("设置昵称", text: Binding(
                            get: { profileVM.nickname },
                            set: { profileVM.setNickname($0) }
                        ))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("数据说明") {
                    Label {
                        Text("所有业务数据均来自安徽财经大学校内系统，通过学校加密通道获取，并仅存储在您的设备本地。应用会上传匿名使用统计（本地随机 ID、学号前四位与加盐哈希、版本和基础设备信息），不会上传密码、完整学号或业务内容。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("网络诊断") {
                    Toggle(isOn: $networkLoggingEnabled) {
                        Label("记录网络日志", systemImage: "waveform.path.ecg")
                    }
                    .onChange(of: networkLoggingEnabled) { _, enabled in
                        NetworkLogStore.setLoggingEnabled(enabled)
                    }

                    Button {
                        exportNetworkLogs()
                    } label: {
                        Label(isExportingLogs ? "正在整理网络日志..." : "导出网络日志 ZIP", systemImage: "doc.zipper")
                    }
                    .disabled(isExportingLogs || !networkLoggingEnabled)
                    .foregroundStyle(networkLoggingEnabled ? Color.accentColor : Color.secondary)
                    .opacity(networkLoggingEnabled ? 1 : 0.45)

                    if let logArchiveURL {
                        Button {
                            self.logArchiveURL = logArchiveURL
                        } label: {
                            Label("分享最近的网络日志 ZIP", systemImage: "square.and.arrow.up")
                        }
                    }

                    Text(networkLoggingEnabled
                         ? "日志只保存在本机。请求参数中的密码、Cookie、令牌和票据会脱敏；超过 256 KB 的响应会作为独立文件放入 ZIP。"
                         : "日志默认关闭。开启后才会记录新的网络请求，关闭时不会保存请求和响应内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("法律信息") {
                    Link(destination: URL(string: "https://linota.cn/loveace/privacy")!) {
                        Label("隐私政策", systemImage: "hand.raised.fill")
                    }
                    Link(destination: URL(string: "https://linota.cn/loveace/terms")!) {
                        Label("使用条款", systemImage: "doc.text.fill")
                    }
                    Link(destination: URL(string: "mailto:support@linota.cn")!) {
                        Label("联系我们", systemImage: "envelope.fill")
                    }
                }

                Section("关于") {
                    LabeledContent {
                        Text(appVersion)
                    } label: {
                        Label("版本", systemImage: "info.circle.fill")
                    }
                    LabeledContent {
                        Text("SwiftUI")
                    } label: {
                        Label("框架", systemImage: "swift")
                    }
                    LabeledContent {
                        Text("iOS 17+")
                    } label: {
                        Label("兼容", systemImage: "iphone")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right.fill")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .alert("确认退出", isPresented: $showLogoutAlert) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { authVM.logout() }
            } message: { Text("退出后需要重新登录") }
            .alert("日志导出失败", isPresented: Binding(
                get: { logExportError != nil },
                set: { if !$0 { logExportError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(logExportError ?? "未知错误")
            }
            .sheet(isPresented: Binding(
                get: { logArchiveURL != nil && !isExportingLogs },
                set: { if !$0 { logArchiveURL = nil } }
            )) {
                if let logArchiveURL {
                    NetworkLogShareSheet(archiveURL: logArchiveURL)
                }
            }
            .onAppear { profileVM.setActiveUserId(authVM.userId) }
        }
    }

    private func exportNetworkLogs() {
        isExportingLogs = true
        Task {
            do {
                let archiveURL = try await NetworkLogStore.shared.exportZip()
                await MainActor.run {
                    isExportingLogs = false
                    logArchiveURL = archiveURL
                }
            } catch {
                await MainActor.run {
                    isExportingLogs = false
                    logExportError = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var profileCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.9))
            Text(profileVM.nickname.isEmpty ? authVM.userId : profileVM.nickname)
                .font(.title2).fontWeight(.bold).foregroundStyle(.white)
            Text("学号: \(authVM.userId)")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            LinearGradient(colors: [.blue, .cyan, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .blue.opacity(0.3), radius: 16, y: 8)
        .padding(.horizontal, -4)
    }
}
