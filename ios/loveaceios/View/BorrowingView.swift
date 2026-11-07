import SwiftUI

struct BorrowingView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = BorrowingViewModel()

    var body: some View {
        List {
            if vm.loaded {
                if let error = vm.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await vm.load(service: authVM.portalService) }
                        }
                    }
                }
                loadedSections
            } else {
                Section {
                    if let error = vm.error {
                        ContentUnavailableView {
                            Label("无法加载借阅记录", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("重试") {
                                Task { await vm.load(service: authVM.portalService) }
                            }
                        }
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .navigationTitle("我的借阅")
        .task {
            await vm.load(service: authVM.portalService)
        }
        .refreshable {
            await vm.load(service: authVM.portalService)
        }
    }

    @ViewBuilder
    private var loadedSections: some View {
        Section {
            if vm.current.isEmpty {
                Text("暂无在借图书")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.current) { record in
                    BorrowRow(record: record, status: .borrowing)
                }
            }
        } header: {
            Text("正在借阅")
        } footer: {
            if !vm.current.isEmpty {
                Text("共 \(vm.current.count) 本")
            }
        }

        Section {
            if vm.history.isEmpty {
                Text("暂无借阅历史")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.history) { record in
                    BorrowRow(record: record, status: .returned)
                }
            }
        } header: {
            Text("借阅历史")
        } footer: {
            if !vm.history.isEmpty {
                Text("共 \(vm.history.count) 条")
            }
        }
    }
}

/// 借阅状态由所在分组决定：正在借阅为绿色打开的书，已还为橙色合上的书
private enum BorrowStatus {
    case borrowing
    case returned

    var systemImage: String {
        switch self {
        case .borrowing: "book.fill"
        case .returned: "book.closed.fill"
        }
    }

    var tint: Color {
        switch self {
        case .borrowing: .green
        case .returned: .orange
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .borrowing: "借阅中"
        case .returned: "已还"
        }
    }
}

private struct BorrowRow: View {
    let record: BorrowRecord
    let status: BorrowStatus

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title.isEmpty ? "未知书名" : record.title)
                    .font(.body)
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: status.systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.tint)
                .accessibilityLabel(status.accessibilityLabel)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = ["借 \(record.borrowedAt)"]
        if let returnedAt = record.returnedAt, !returnedAt.isEmpty {
            parts.append("还 \(returnedAt)")
        }
        return parts.joined(separator: " · ")
    }
}
