import SwiftUI

struct AACView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.wideLayout) private var wideLayout
    @State private var vm = AACViewModel()
    @State private var expandedCategoryId: String?

    private let categoryColors: [Color] = [.blue, .green, .orange, .pink, .teal, .red, .cyan, .mint]

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    LoadingView(message: "加载爱安财...")
                } else if let error = vm.error, vm.creditInfo == nil {
                    ErrorView(message: error) { vm.loadAll() }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let info = vm.creditInfo { creditHeader(info) }
                            categoryGrid
                        }
                        .readableWidth(wideLayout ? 1000 : 680)
                        .padding()
                    }
                }
            }
            .navigationTitle("爱安财")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { vm.loadAll() }
            .detailPanel(item: Binding(
                get: { expandedCategoryId.flatMap { id in vm.categories.first { $0.id == id } } },
                set: { _ in expandedCategoryId = nil }
            )) { category in
                CategoryDetailSheet(category: category, color: colorFor(category))
            }
            .onAppear {
                if let aac = authVM.aacService { vm.initialize(service: aac); vm.loadAll() }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func creditHeader(_ info: AACCreditInfo) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("第二课堂").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", info.totalScore))
                        .font(AppFont.heroNumber)
                    Text("学分")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                GlassBadge(
                    text: info.isTypeAdopt ? "类型达标" : (info.typeAdoptResult.isEmpty ? "未达标" : info.typeAdoptResult),
                    tint: info.isTypeAdopt ? .green : .orange,
                    icon: info.isTypeAdopt ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(info.totalScore / 10.0, 1.0))
                    .stroke(Color.green.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: info.isTypeAdopt ? "checkmark" : "star.fill")
                    .font(.title3)
                    .foregroundStyle(info.isTypeAdopt ? .green : .orange)
            }
            .frame(width: 64, height: 64)
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    // MARK: - Category Grid

    @ViewBuilder
    private var categoryGrid: some View {
        CompatGlassContainer {
            LazyVGrid(columns: wideLayout ? [GridItem(.adaptive(minimum: 260), spacing: 12)] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(vm.categories) { category in
                    let color = colorFor(category)
                    Button { expandedCategoryId = category.id } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: iconFor(category))
                                    .font(.title3)
                                    .foregroundStyle(color.gradient)
                                Spacer()
                                Text("\(category.children.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(category.typeName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", category.totalScore))
                                    .font(AppFont.cardValue)
                                    .foregroundStyle(color)
                                Text("分")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 120)
                        .glassInteractiveCard(tint: color.opacity(0.08), cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func colorFor(_ category: AACCreditCategory) -> Color {
        guard let idx = vm.categories.firstIndex(where: { $0.id == category.id }) else { return .blue }
        return categoryColors[idx % categoryColors.count]
    }

    private func iconFor(_ category: AACCreditCategory) -> String {
        let name = category.typeName
        if name.contains("思想") || name.contains("政治") { return "brain.head.profile" }
        if name.contains("学术") || name.contains("科技") { return "lightbulb.fill" }
        if name.contains("文体") || name.contains("艺术") { return "theatermasks.fill" }
        if name.contains("实践") || name.contains("志愿") { return "hands.sparkles.fill" }
        if name.contains("工作") || name.contains("履历") { return "briefcase.fill" }
        if name.contains("技能") || name.contains("证书") { return "medal.fill" }
        return "star.fill"
    }
}

// MARK: - Category Detail Sheet

struct CategoryDetailSheet: View {
    let category: AACCreditCategory
    let color: Color
    @DetailDismiss private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.typeName).font(.title3).fontWeight(.bold)
                            Text("\(category.children.count) 项记录").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", category.totalScore))
                            .font(AppFont.largeNumber)
                            .foregroundStyle(color)
                        Text("分").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("明细") {
                    ForEach(category.children) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline)
                                    .lineLimit(3)
                                Text(item.addTime)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(String(format: "+%.1f", item.score))
                                .font(AppFont.cardTitle)
                                .foregroundStyle(color)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(category.typeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
