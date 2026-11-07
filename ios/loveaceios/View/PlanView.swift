import SwiftUI

struct PlanView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = PlanViewModel()
    @Environment(\.wideLayout) private var wideLayout
    @State private var selectedCategory: PlanCategory?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading { LoadingView(message: "加载培养方案...") }
                else if let error = vm.error { ErrorView(message: error) { vm.loadPlan() } }
                else if let plan = vm.planInfo {
                    List {
                        summarySection(plan)
                        Section("分类") {
                            ForEach(plan.categories) { cat in
                                categoryLink(cat)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .detailPanel(item: $selectedCategory) { category in
                        PlanCategoryPanel(category: category)
                    }
                }
            }
            .navigationTitle("培养方案")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let svc = authVM.planService { vm.initialize(service: svc); vm.loadPlan() }
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ plan: PlanCompletionInfo) -> some View {
        Section {
            if !plan.planName.isEmpty {
                Text(plan.planName).font(.headline).lineLimit(3)
            }
            if !plan.major.isEmpty || !plan.grade.isEmpty {
                HStack(spacing: 8) {
                    if !plan.major.isEmpty { infoPill("专业", plan.major) }
                    if !plan.grade.isEmpty { infoPill("年级", plan.grade) }
                }
            }
            if plan.estimatedGraduationCredits > 0 {
                let totalPassed = plan.categories.reduce(0.0) { $0 + $1.completedCredits }
                let progress = min(totalPassed / plan.estimatedGraduationCredits, 1.0)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", totalPassed))
                            .font(AppFont.largeNumber)
                            .foregroundStyle(planProgressColor(progress * 100))
                        Text("/ \(String(format: "%.1f", plan.estimatedGraduationCredits)) 学分")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(planProgressColor(progress * 100))
                    }
                    ProgressView(value: progress).tint(planProgressColor(progress * 100))
                }
            }
            HStack(spacing: 12) {
                statPill("\(plan.passedCourses)/\(plan.totalCourses) 门已过", .green)
                if plan.failedCourses > 0 { statPill("\(plan.failedCourses) 不及格", .red) }
                if plan.missingRequiredCourses > 0 { statPill("\(plan.missingRequiredCourses) 缺修", .orange) }
            }
        }
    }

    private func categoryRow(_ cat: PlanCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(cat.categoryName).font(.body)
                Spacer()
                if cat.isCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
                }
            }
            if cat.minCredits > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: cat.completionPercentage / 100.0)
                        .tint(planProgressColor(cat.completionPercentage))
                    Text(String(format: "%.1f/%.1f", cat.completedCredits, cat.minCredits))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 分类行：竖屏推入详情；横屏改为选中后由 inspector 显示（推入会挤掉列表）
    @ViewBuilder
    private func categoryLink(_ cat: PlanCategory) -> some View {
        if wideLayout {
            Button { selectedCategory = cat } label: {
                HStack {
                    categoryRow(cat).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { PlanCategoryDetailView(category: cat) } label: {
                categoryRow(cat)
            }
        }
    }

    private func infoPill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):").font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).fontWeight(.semibold)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.fill.quaternary, in: .capsule)
    }

    private func statPill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.1), in: .capsule)
    }
}

/// 横屏 inspector 里的分类详情：自带导航栏和"关闭"按钮（推入模式下由导航栏提供返回）
private struct PlanCategoryPanel: View {
    let category: PlanCategory
    @DetailDismiss private var dismiss

    var body: some View {
        NavigationStack {
            PlanCategoryDetailView(category: category)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                }
        }
    }
}

// MARK: - Category Detail (push destination)

struct PlanCategoryDetailView: View {
    let category: PlanCategory

    var body: some View {
        List {
            if category.minCredits > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("学分进度").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if category.isCompleted {
                                Label("已达标", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        HStack(spacing: 8) {
                            ProgressView(value: category.completionPercentage / 100.0)
                                .tint(planProgressColor(category.completionPercentage))
                            Text(String(format: "%.0f%%", category.completionPercentage))
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundStyle(planProgressColor(category.completionPercentage))
                        }
                        HStack(spacing: 16) {
                            LabeledContent("最低", value: String(format: "%.1f", category.minCredits))
                            LabeledContent("已通过", value: String(format: "%.1f", category.completedCredits))
                        }
                        .font(.caption)
                    }
                }
            }

            if !category.subcategories.isEmpty {
                Section("子分类") {
                    ForEach(category.subcategories) { sub in
                        NavigationLink { PlanCategoryDetailView(category: sub) } label: {
                            subcategoryRow(sub)
                        }
                    }
                }
            }

            if !category.courses.isEmpty {
                Section("课程（\(category.courses.count)）") {
                    ForEach(category.courses) { course in
                        PlanCourseRow(course: course)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.categoryName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subcategoryRow(_ sub: PlanCategory) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.categoryName).font(.body)
                if sub.minCredits > 0 {
                    Text(String(format: "%.1f/%.1f 学分", sub.completedCredits, sub.minCredits))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if sub.isCompleted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
            } else if sub.minCredits > 0 {
                Text(String(format: "%.0f%%", sub.completionPercentage))
                    .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PlanCourseRow: View {
    let course: PlanCourse

    private var color: Color {
        switch course.statusDescription {
        case "已通过": .green
        case "未通过": .red
        default: .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: course.isPassed ? "checkmark.circle.fill" :
                    course.statusDescription == "未通过" ? "xmark.circle.fill" : "circle")
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName).font(.body).lineLimit(2)
                HStack(spacing: 10) {
                    if let c = course.credits {
                        Text(String(format: "%.1f 学分", c)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !course.courseType.isEmpty {
                        Text(course.courseType).font(.caption).foregroundStyle(.secondary)
                    }
                    if let s = course.score {
                        Text(s).font(.caption).fontWeight(.medium)
                            .foregroundStyle(scoreColor(for: s))
                    }
                }
            }

            Spacer()

            Text(course.statusDescription)
                .font(.caption2).fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        var name = ""
        if !course.courseCode.isEmpty { name += "[\(course.courseCode)] " }
        name += course.courseName.isEmpty ? course.courseCode : course.courseName
        return name
    }
}

private func planProgressColor(_ percentage: Double) -> Color {
    if percentage >= 100 { return .green }
    if percentage >= 80 { return .blue }
    return .orange
}
