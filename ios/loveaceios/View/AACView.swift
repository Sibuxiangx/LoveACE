import SwiftUI

struct AACView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.wideLayout) private var wideLayout
    @State private var vm = AACViewModel()
    @State private var expandedCategoryId: String?
    @State private var wideSelectedCategoryId: String?

    private let categoryColors: [Color] = [.blue, .green, .orange, .pink, .teal, .red, .cyan, .mint]

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    LoadingView(message: "加载爱安财...")
                } else if let error = vm.error, vm.creditInfo == nil {
                    ErrorView(message: error) { vm.loadAll() }
                } else if wideLayout {
                    wideBody
                } else {
                    compactBody
                }
            }
            .navigationTitle("爱安财")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { vm.loadAll() }
            .onChange(of: vm.categories.map(\.id)) { syncWideSelection() }
            .onAppear {
                if let aac = authVM.aacService { vm.initialize(service: aac); vm.loadAll() }
            }
        }
    }

    // MARK: - Compact

    private var compactBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let info = vm.creditInfo { creditHeader(info) }
                categoryGrid
            }
            .readableWidth(680)
            .padding()
        }
        .detailPanel(item: Binding(
            get: { expandedCategoryId.flatMap { id in vm.categories.first { $0.id == id } } },
            set: { _ in expandedCategoryId = nil }
        )) { category in
            CategoryDetailSheet(category: category, color: colorFor(category))
        }
    }

    // MARK: - Wide

    private var wideBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let info = vm.creditInfo {
                    creditHeader(info)
                        .padding(16)
                }
                List {
                    ForEach(vm.categories) { category in
                        wideCategoryRow(category)
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: 340)

            Divider()

            wideDetail
                .frame(maxWidth: .infinity)
        }
        .onAppear { syncWideSelection() }
    }

    @ViewBuilder
    private func wideCategoryRow(_ category: AACCreditCategory) -> some View {
        let color = colorFor(category)
        let isSelected = category.id == wideSelectedCategoryId
        Button { wideSelectedCategoryId = category.id } label: {
            HStack(spacing: 12) {
                Image(systemName: iconFor(category))
                    .font(.title3)
                    .foregroundStyle(color.gradient)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.typeName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(category.children.count) 项记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", category.totalScore))
                        .font(AppFont.cardTitle)
                        .foregroundStyle(color)
                    Text("分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .wideRowSelection(isSelected, tint: color)
    }

    @ViewBuilder
    private var wideDetail: some View {
        if let category = selectedWideCategory {
            CategoryDetailContent(category: category, color: colorFor(category))
                .id(category.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("选择一个分类查看明细")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(cornerRadius: 18)
            .padding(16)
        }
    }

    private var selectedWideCategory: AACCreditCategory? {
        guard let id = wideSelectedCategoryId else { return nil }
        return vm.categories.first { $0.id == id }
    }

    /// 宽屏默认选中第一个分类；已选分类仍存在时保持不变。
    private func syncWideSelection() {
        if let id = wideSelectedCategoryId, vm.categories.contains(where: { $0.id == id }) { return }
        wideSelectedCategoryId = vm.categories.first?.id
    }

    // MARK: - Header

    @ViewBuilder
    private func creditHeader(_ info: AACCreditInfo) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    creditScoreText(info)
                    creditBadge(info)
                }
                Spacer()
                creditRing(info)
            }
            graduationRows
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    /// 毕业统计两项：社会实践、劳动实践（与 Android 毕业进度一致）
    @ViewBuilder
    private var graduationRows: some View {
        let practice = AACGraduationStats.practiceScore(vm.categories)
        let labor = AACGraduationStats.laborScore(vm.categories)
        HStack(spacing: 12) {
            graduationItem(title: "社会实践", current: practice, required: AACGraduationStats.practiceMin)
            graduationItem(title: "劳动实践", current: labor, required: AACGraduationStats.laborRequired)
        }
    }

    private func graduationItem(title: String, current: Double, required: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", current))
                    .font(.headline)
                Text("/ \(String(format: "%.0f", required)) 分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(current / required, 1.0))
                .tint(current >= required ? .green : .orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func creditScoreText(_ info: AACCreditInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第二课堂").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", info.totalScore))
                    .font(AppFont.heroNumber)
                Text("学分")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func creditBadge(_ info: AACCreditInfo) -> some View {
        GlassBadge(
            text: info.isTypeAdopt ? "类型达标" : (info.typeAdoptResult.isEmpty ? "未达标" : info.typeAdoptResult),
            tint: info.isTypeAdopt ? .green : .orange,
            icon: info.isTypeAdopt ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
    }

    @ViewBuilder
    private func creditRing(_ info: AACCreditInfo) -> some View {
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

    // MARK: - Category Grid

    @ViewBuilder
    private var categoryGrid: some View {
        CompatGlassContainer {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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

// MARK: - Category Detail Content

/// 分类明细列表主体。不含 NavigationStack、工具栏与弹出修饰器，供 sheet 和宽屏右栏复用。
struct CategoryDetailContent: View {
    let category: AACCreditCategory
    let color: Color

    var body: some View {
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
    }
}

// MARK: - Category Detail Sheet

struct CategoryDetailSheet: View {
    let category: AACCreditCategory
    let color: Color
    @DetailDismiss private var dismiss

    var body: some View {
        NavigationStack {
            CategoryDetailContent(category: category, color: color)
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
