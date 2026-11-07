import SwiftUI

struct MoreView: View {
    @Environment(AuthViewModel.self) private var authVM

    @State private var query = ""

    private struct FeatureItem: Identifiable {
        let title: String
        let icon: String
        let tint: Color
        let tag: String
        var id: String { tag }
    }

    private struct FeatureSection: Identifiable {
        let title: String
        let systemImage: String
        let items: [FeatureItem]
        var id: String { title }
    }

    /// 分组与 Android 横屏导航保持一致：教务服务 / 校园生活 / 素质拓展
    private var sections: [FeatureSection] {
        [
            FeatureSection(title: "教务服务", systemImage: "graduationcap.fill", items: [
                FeatureItem(title: "学业分析", icon: "chart.line.uptrend.xyaxis", tint: .blue, tag: "insights"),
                FeatureItem(title: "成绩查询", icon: "list.clipboard.fill", tint: .green, tag: "scores"),
                FeatureItem(title: "考试安排", icon: "clock.badge.exclamationmark.fill", tint: .orange, tag: "exam"),
                FeatureItem(title: "课程表", icon: "calendar", tint: .blue, tag: "schedule"),
                FeatureItem(title: "学期课表", icon: "calendar.badge.clock", tint: .teal, tag: "semesterSchedule"),
                FeatureItem(title: "培养方案", icon: "chart.bar.doc.horizontal.fill", tint: .mint, tag: "plan"),
                FeatureItem(title: "教师评价", icon: "checklist.checked", tint: .purple, tag: "teacherEvaluation"),
                FeatureItem(title: "开课查询", icon: "book.closed.fill", tint: .indigo, tag: "courseSchedule"),
                FeatureItem(title: "空教室", icon: "building.2.fill", tint: .cyan, tag: "freeClassroom"),
            ]),
            FeatureSection(title: "校园生活", systemImage: "building.columns.fill", items: [
                FeatureItem(title: "一卡通", icon: "creditcard.fill", tint: .teal, tag: "ykt"),
                FeatureItem(title: "宿舍电费", icon: "bolt.fill", tint: .yellow, tag: "electricity"),
                FeatureItem(title: "报修", icon: "wrench.and.screwdriver.fill", tint: .red, tag: "repair"),
                FeatureItem(title: "门卡", icon: "key.fill", tint: .teal, tag: "doorcard"),
                FeatureItem(title: "门禁查询", icon: "door.left.hand.closed", tint: .orange, tag: "accessRecords"),
                FeatureItem(title: "我的借阅", icon: "books.vertical.fill", tint: .brown, tag: "borrowing"),
            ]),
            FeatureSection(title: "素质拓展", systemImage: "star.circle.fill", items: [
                FeatureItem(title: "竞赛信息", icon: "trophy.fill", tint: .orange, tag: "competition"),
                FeatureItem(title: "劳动俱乐部", icon: "figure.walk", tint: .pink, tag: "labor"),
            ]),
        ]
    }

    /// 搜索时把匹配项平铺为一组；无关键字时按分组显示
    private var visibleSections: [FeatureSection] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return sections }
        let matched = sections.flatMap(\.items).filter { $0.title.localizedCaseInsensitiveContains(keyword) }
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
                                        NavigationLink { destinationView(for: item.tag) } label: {
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
                .padding()
            }
            .searchable(text: $query, prompt: "搜索功能")
            .navigationTitle("更多功能")
        }
    }

    private func rows(of items: [FeatureItem]) -> [[FeatureItem]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    @ViewBuilder
    private func destinationView(for tag: String) -> some View {
        switch tag {
        case "insights": InsightsView()
        case "scores": ScoresView()
        case "exam": ExamView()
        case "schedule": ScheduleView()
        case "semesterSchedule": SemesterScheduleView()
        case "plan": PlanView()
        case "ykt": YKTView()
        case "electricity": ElectricityView()
        case "repair": RepairView()
        case "doorcard": DoorCardView()
        case "teacherEvaluation": TeacherEvaluationView()
        case "competition": CompetitionView()
        case "labor": LaborClubView()
        case "courseSchedule": CourseScheduleQueryView()
        case "freeClassroom": FreeClassroomView()
        case "accessRecords": AccessRecordsView()
        case "borrowing": BorrowingView()
        default: EmptyView()
        }
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
