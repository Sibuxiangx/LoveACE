import SwiftUI
import UniformTypeIdentifiers

struct MailInitialPasswordView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = MailPasswordViewModel()
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var copiedNotice = false

    private static let cardHeight: CGFloat = 132

    var body: some View {
        List {
            Section {
                content
            } footer: {
                Text("初始密码只在本页显示，离开页面后自动清除。拷贝的内容 60 秒后从剪贴板失效。")
            }
        }
        .navigationTitle("企业邮箱初始密码")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(service: authVM.portalService) }
        .refreshable { await vm.load(service: authVM.portalService) }
        .onDisappear {
            vm.clear()
            resetCover()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let info = vm.password {
            scratchCard(info)
        } else if !vm.hasLoaded || vm.isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 24)
        } else if let error = vm.error {
            ContentUnavailableView {
                Label("无法获取初始密码", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("重试") {
                    Task { await vm.load(service: authVM.portalService) }
                }
            }
        } else {
            ContentUnavailableView(
                "暂无初始密码",
                systemImage: "envelope.badge.shield.half.filled",
                description: Text("学校系统中没有这条记录。")
            )
        }
    }

    private func scratchCard(_ info: MailInitialPassword) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !info.loginId.isEmpty {
                Label(info.loginId, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Text(info.password)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Self.cardHeight)

                ScratchCover(strokes: strokes, current: currentStroke)

                if strokes.isEmpty && currentStroke.isEmpty {
                    Label("按住并滑动，刮开密码", systemImage: "hand.draw")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: Self.cardHeight)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.tertiarySystemFill)))
            .clipShape(.rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
            .highPriorityGesture(scratchGesture)
            .contextMenu {
                Button {
                    copyPassword(info.password)
                } label: {
                    Label("拷贝密码", systemImage: "doc.on.doc")
                }
            }
            .accessibilityAction(named: "拷贝密码") {
                copyPassword(info.password)
            }

            HStack {
                if copiedNotice {
                    Label("已拷贝", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("重新遮盖") { resetCover() }
                    .disabled(strokes.isEmpty)
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private var scratchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                currentStroke.append(value.location)
            }
            .onEnded { _ in
                if !currentStroke.isEmpty { strokes.append(currentStroke) }
                currentStroke = []
            }
    }

    private func resetCover() {
        strokes = []
        currentStroke = []
    }

    /// 拷贝后 60 秒自动从剪贴板过期，不依赖用户手动清理
    private func copyPassword(_ password: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: password]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copiedNotice = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedNotice = false
        }
    }
}

/// 磨砂遮罩：材质层用手指轨迹做 alpha 蒙版，轨迹经过的地方透出下面的密码
private struct ScratchCover: View {
    let strokes: [[CGPoint]]
    let current: [CGPoint]

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    context.blendMode = .destinationOut
                    for points in strokes + [current] {
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        if points.count == 1 {
                            path.addLine(to: first)
                        }
                        context.stroke(
                            path,
                            with: .color(.white),
                            style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
    }
}
