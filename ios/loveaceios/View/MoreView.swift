import SwiftUI

struct MoreView: View {
    @Environment(AuthViewModel.self) private var authVM

    private let features: [(title: String, icon: String, tint: Color, tag: String)] = [
        ("学业分析", "chart.line.uptrend.xyaxis", .blue, "insights"),
        ("成绩查询", "list.clipboard.fill", .green, "scores"),
        ("考试安排", "clock.badge.exclamationmark.fill", .orange, "exam"),
        ("课程表", "calendar", .blue, "schedule"),
        ("学期课表", "calendar.badge.clock", .teal, "semesterSchedule"),
        ("培养方案", "chart.bar.doc.horizontal.fill", .mint, "plan"),
        ("一卡通", "creditcard.fill", .teal, "ykt"),
        ("宿舍电费", "bolt.fill", .yellow, "electricity"),
        ("报修", "wrench.and.screwdriver.fill", .red, "repair"),
        ("教师评价", "checklist.checked", .purple, "teacherEvaluation"),
        ("竞赛信息", "trophy.fill", .orange, "competition"),
        ("劳动俱乐部", "figure.walk", .pink, "labor"),
        ("开课查询", "book.closed.fill", .indigo, "courseSchedule"),
        ("空教室", "building.2.fill", .cyan, "freeClassroom"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                // 非懒加载的两列行：功能数量少，全部直接布局，避免懒加载网格漏画后半部分
                VStack(spacing: 12) {
                    ForEach(0..<(features.count + 1) / 2, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(features.dropFirst(row * 2).prefix(2), id: \.tag) { feature in
                                NavigationLink { destinationView(for: feature.tag) } label: {
                                    FeatureCard(title: feature.title, icon: feature.icon, tint: feature.tint)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("更多功能")
        }
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
        case "teacherEvaluation": TeacherEvaluationView()
        case "competition": CompetitionView()
        case "labor": LaborClubView()
        case "courseSchedule": CourseScheduleQueryView()
        case "freeClassroom": FreeClassroomView()
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
