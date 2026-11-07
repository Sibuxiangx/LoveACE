import SwiftUI

/// 功能清单：更多页与 iPad 横屏侧栏共用，只在这里定义一次
struct FeatureItem: Identifiable, Hashable {
    let title: String
    let icon: String
    let tint: Color
    let tag: String
    var id: String { tag }
}

struct FeatureSection: Identifiable {
    let title: String
    let systemImage: String
    let items: [FeatureItem]
    var id: String { title }
}

enum AppCatalog {
    /// 分组与 Android 横屏导航保持一致：教务服务 / 校园生活 / 素质拓展
    static let sections: [FeatureSection] = [
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

    @ViewBuilder
    static func destinationView(for tag: String) -> some View {
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
