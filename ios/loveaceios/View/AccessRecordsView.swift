import SwiftUI

struct AccessRecordsView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = AccessRecordsViewModel()

    var body: some View {
        List {
            Section {
                Picker("门禁", selection: Binding(get: { vm.kind }, set: { vm.select(kind: $0) })) {
                    ForEach(AccessKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Picker("查询时间", selection: Binding(get: { vm.range }, set: { vm.select(range: $0) })) {
                    ForEach(AccessRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("默认只查本周。需要更早的记录，可以在这里调整查询时间。")
            }

            if vm.kind == .dormitory {
                Section {
                    Label {
                        Text("宿舍门禁数据有延迟同步，刚刷的记录可能过一段时间才会出现，结果以学校系统为准。")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                recordRows
                if vm.hasMore {
                    loadMoreRow
                }
            } header: {
                Text(vm.kind.sectionTitle)
            } footer: {
                Text(footerText)
            }
        }
        .navigationTitle("门禁查询")
        .task(id: "\(vm.kind.rawValue)-\(vm.range.id)") {
            await vm.reload(service: authVM.portalService)
        }
        .refreshable {
            await vm.reload(service: authVM.portalService)
        }
    }

    private var footerText: String {
        guard !vm.records.isEmpty else { return "" }
        return "已显示 \(vm.records.count) 条，共 \(vm.total) 条"
    }

    @ViewBuilder
    private var recordRows: some View {
        if vm.isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 16)
        } else if let error = vm.error {
            ContentUnavailableView {
                Label("无法加载门禁记录", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("重试") {
                    Task { await vm.reload(service: authVM.portalService) }
                }
            }
        } else if vm.records.isEmpty {
            ContentUnavailableView(
                "暂无门禁记录",
                systemImage: "door.left.hand.closed",
                description: Text("\(vm.range.title)没有刷卡记录。")
            )
        } else {
            ForEach(vm.records) { record in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.time)
                            .font(.body.monospacedDigit())
                        if !record.detail.isEmpty {
                            Text(record.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let direction = record.direction {
                        DirectionBadge(direction: direction)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var loadMoreRow: some View {
        Button {
            Task { await vm.loadMore(service: authVM.portalService) }
        } label: {
            HStack {
                Spacer()
                if vm.isLoadingMore {
                    ProgressView()
                } else {
                    Text("加载更多")
                }
                Spacer()
            }
        }
        .disabled(vm.isLoadingMore)

        if let loadMoreError = vm.loadMoreError {
            Text(loadMoreError)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

/// 进/出图标：进为绿色走进门的人形，出为橙色走出门的人形（安全通道样式）；带无障碍标签
private struct DirectionBadge: View {
    let direction: AccessDirection

    var body: some View {
        Image(systemName: direction.systemImage)
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: direction)
            .accessibilityLabel(direction.title)
    }

    private var tint: Color {
        switch direction {
        case .entry: .green
        case .exit: .orange
        }
    }
}
