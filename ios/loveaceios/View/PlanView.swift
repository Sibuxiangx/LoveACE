import SwiftUI

struct PlanView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = PlanViewModel()
    @Environment(\.wideLayout) private var wideLayout
    @State private var selectedCategoryId: String?
    /// 宽屏右栏内点击子分类后的显示对象；与分类选择分开，切换分类时清除
    @State private var wideSubCategory: PlanCategory?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading { LoadingView(message: "加载培养方案...") }
                else if let error = vm.error { ErrorView(message: error) { vm.loadPlan() } }
                else if let plan = vm.planInfo {
                    if wideLayout {
                        wideContent(plan)
                    } else {
                        List {
                            summarySection(plan)
                            Section("分类") {
                                ForEach(plan.categories) { cat in
                                    NavigationLink { PlanCategoryDetailView(category: cat) } label: {
                                        categoryRow(cat)
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                else { LoadingView(message: "加载培养方案...") }
            }
            .onChange(of: vm.planInfo?.categories.first?.id) { _, newValue in
                selectedCategoryId = newValue
            }
            .navigationTitle("培养方案")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let svc = authVM.planService { vm.initialize(service: svc); vm.loadPlan() }
            }
        }
    }

    /// 宽屏两栏：摘要与分类列表 | 所选分类详情
    private func wideContent(_ plan: PlanCompletionInfo) -> some View {
        HStack(spacing: 0) {
            List {
                summarySection(plan)
                Section("分类") {
                    ForEach(plan.categories) { cat in
                        Button { selectedCategoryId = cat.id } label: {
                            categoryRow(cat).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .wideRowSelection(selectedCategoryId == cat.id)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(width: 340)
            .onChange(of: selectedCategoryId) { _, _ in
                wideSubCategory = nil
            }

            Divider()

            wideDetail(plan)
                .frame(maxWidth: .infinity)
        }
    }

    /// 宽屏右栏：所选分类（或其子分类）的详情；无选择时显示占位
    @ViewBuilder
    private func wideDetail(_ plan: PlanCompletionInfo) -> some View {
        if let top = plan.categories.first(where: { $0.id == selectedCategoryId }) {
            if let sub = wideSubCategory {
                VStack(spacing: 0) {
                    HStack {
                        Button { wideSubCategory = nil } label: {
                            Label(top.categoryName, systemImage: "chevron.left")
                                .font(.subheadline)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    Divider()
                    PlanCategoryDetailView(category: sub, onSelectSub: { wideSubCategory = $0 }, showsTitle: false)
                        .id(sub.id)
                }
            } else {
                PlanCategoryDetailView(category: top, onSelectSub: { wideSubCategory = $0 }, showsTitle: false)
                    .id(top.id)
            }
        } else {
            EmptyStateView(title: "选择一个分类查看课程", systemImage: "square.grid.2x2")
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


// MARK: - Category Detail (push destination)

struct PlanCategoryDetailView: View {
    let category: PlanCategory
    /// 宽屏右栏传入：点击子分类时回调（替代推入）；nil 时子分类用 NavigationLink 推入
    var onSelectSub: ((PlanCategory) -> Void)? = nil
    /// 推入时以分类名作标题；宽屏右栏传 false，保留页面标题"培养方案"
    var showsTitle: Bool = true

    var body: some View {
        let list = List {
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
                        subcategoryLink(sub)
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

        if showsTitle {
            list
                .navigationTitle(category.categoryName)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            list
        }
    }

    @ViewBuilder
    private func subcategoryLink(_ sub: PlanCategory) -> some View {
        if let onSelectSub {
            Button { onSelectSub(sub) } label: {
                HStack {
                    subcategoryRow(sub).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { PlanCategoryDetailView(category: sub) } label: {
                subcategoryRow(sub)
            }
        }
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
