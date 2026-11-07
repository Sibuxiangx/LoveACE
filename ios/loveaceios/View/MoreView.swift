import SwiftUI

struct MoreView: View {
    @Environment(AuthViewModel.self) private var authVM

    @State private var query = ""

    /// 搜索时把匹配项平铺为一组；无关键字时按分组显示
    private var visibleSections: [FeatureSection] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return AppCatalog.sections }
        let matched = AppCatalog.sections.flatMap(\.items).filter { $0.title.localizedCaseInsensitiveContains(keyword) }
        return matched.isEmpty ? [] : [FeatureSection(title: "搜索结果", systemImage: "magnifyingglass", items: matched)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 非懒加载布局：功能数量少，全部直接布局，避免懒加载网格漏画后半部分
                VStack(alignment: .leading, spacing: 24) {
                    if visibleSections.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(visibleSections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            GlassSectionHeader(title: section.title, icon: section.systemImage)
                            let pairs = rows(of: section.items)
                            ForEach(pairs.indices, id: \.self) { index in
                                HStack(spacing: 12) {
                                    ForEach(pairs[index]) { item in
                                        NavigationLink { AppCatalog.destinationView(for: item.tag) } label: {
                                            FeatureCard(title: item.title, icon: item.icon, tint: item.tint)
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
                .readableWidth(680)
                .padding()
            }
            .searchable(text: $query, prompt: "搜索功能")
            .navigationTitle("更多功能")
        }
    }

    private func rows(of items: [FeatureItem]) -> [[FeatureItem]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }
}

struct FeatureCard: View {
    let title: String
    let icon: String
    var tint: Color = .blue

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(tint.gradient)
                .frame(width: 36, height: 36)
            Text(title)
                .font(AppFont.cardTitle)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard(cornerRadius: 18)
    }
}
