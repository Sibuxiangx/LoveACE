import SwiftUI

struct TeacherEvaluationView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = TeacherEvaluationViewModel()
    @State private var showStartConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.courses.isEmpty {
                    LoadingView(message: "加载教师评价...")
                } else if vm.isEvaluationClosed {
                    closedState
                } else if let error = vm.error, vm.courses.isEmpty {
                    ErrorView(message: error) { vm.loadCourses() }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerCard
                            if let error = vm.error { inlineError(error) }
                            if let result = vm.lastResult { resultCard(result) }
                            if vm.isEvaluating || !vm.tasks.isEmpty { taskSection }
                            courseSection
                            if !vm.logs.isEmpty { logSection }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("教师评价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isEvaluating {
                        Button("停止") { showCancelConfirmation = true }
                            .foregroundStyle(.red)
                    } else {
                        Button { vm.loadCourses() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { vm.loadCourses() }
            .alert("开始并发评教？", isPresented: $showStartConfirmation) {
                Button("开始", role: .destructive) { vm.startConcurrentEvaluation() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将每 6 秒启动一个评价任务，每门课程等待 140 秒后自动提交。请保持 App 前台，并确认评价内容符合你的真实意愿。")
            }
            .alert("中断评教？", isPresented: $showCancelConfirmation) {
                Button("中断", role: .destructive) { vm.cancelEvaluation() }
                Button("继续", role: .cancel) { }
            } message: {
                Text("已提交的评价无法撤回，正在等待或未开始的任务会被标记为已取消。")
            }
            .onAppear {
                if let service = authVM.teacherEvaluationService {
                    vm.initialize(service: service)
                    if vm.courses.isEmpty, !vm.isLoading { vm.loadCourses() }
                } else {
                    vm.error = "教师评价服务未初始化，请重新登录后再试"
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist.checked")
                            .font(.title3)
                            .foregroundStyle(.purple.gradient)
                        Text("智能评价")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.12), in: .capsule)
                    }

                    Text("自动教师评价")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("从教务系统读取待评课程，自动生成问卷答案，并按安全间隔提交评价。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                GlassProgressRing(
                    progress: vm.totalCount > 0 ? Double(vm.evaluatedCount) / Double(vm.totalCount) : 0,
                    size: 82,
                    lineWidth: 7,
                    tint: .purple,
                    label: "已评"
                )
            }

            HStack(spacing: 10) {
                miniStat("总计", value: vm.totalCount, tint: .blue)
                miniStat("待评", value: vm.pendingCount, tint: .orange)
                miniStat("已评", value: vm.evaluatedCount, tint: .green)
            }

            Button {
                showStartConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: vm.isEvaluating ? "hourglass" : "bolt.horizontal.circle.fill")
                    Text(vm.isEvaluating ? "评教进行中" : "开始并发评教")
                        .fontWeight(.semibold)
                    Spacer()
                    if vm.isEvaluating {
                        Text("\(vm.completedTaskCount)/\(vm.tasks.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .glassInteractiveCard(tint: .purple.opacity(0.12), cornerRadius: 16)
            }
            .buttonStyle(.plain)
            .disabled(vm.pendingCount == 0 || vm.isEvaluating)
            .opacity(vm.pendingCount == 0 || vm.isEvaluating ? 0.55 : 1)
        }
        .padding(18)
        .glassCard(tint: .purple.opacity(0.08), cornerRadius: 22)
    }

    private func miniStat(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(AppFont.cardValue)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint.opacity(0.08), cornerRadius: 14)
    }

    private var closedState: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.purple)
                            Text("评价暂未开启")
                        }
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("当前不在教师评价开放时间。开放后可在这里查看待评课程并完成评价。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button { vm.loadCourses() } label: {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .glassCapsule(tint: .purple.opacity(0.18), interactive: true)
                    }
                    .buttonStyle(.plain)

                    Text("开放后刷新页面即可查看待评课程。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .glassCard(tint: .purple.opacity(0.08), cornerRadius: 24)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
        }
    }

    // MARK: - Sections

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GlassSectionHeader(title: "并发任务", icon: "rectangle.stack.badge.play")
                Spacer()
                if vm.isEvaluating {
                    Text("\(Int(vm.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: vm.progress)
                .tint(.purple)
            LazyVStack(spacing: 10) {
                ForEach(vm.tasks) { task in
                    TeacherEvaluationTaskCard(task: task)
                }
            }
        }
    }

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "课程列表", icon: "person.crop.rectangle.stack")
            if vm.courses.isEmpty {
                EmptyStateView(title: "暂无评教课程", systemImage: "checkmark.seal", description: "当前教务系统没有返回待评或已评课程。")
                    .frame(minHeight: 220)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(sortedCourses) { course in
                        TeacherEvaluationCourseCard(course: course)
                    }
                }
            }
        }
    }

    private var logSection: some View {
        DisclosureGroup(isExpanded: $showLogs) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(vm.logs.suffix(16)), id: \.self) { log in
                    Text(log)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("运行日志", systemImage: "terminal")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    private func resultCard(_ result: TeacherEvaluationBatchResult) -> some View {
        HStack(spacing: 14) {
            Image(systemName: result.failed == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(result.failed == 0 ? .green : .orange)
                .frame(width: 42, height: 42)
                .glassCircle()
            VStack(alignment: .leading, spacing: 4) {
                Text(result.failed == 0 ? "评教完成" : "评教完成（部分失败）")
                    .font(.headline)
                Text("成功 \(result.success)/\(result.total) · 失败 \(result.failed) · 用时 \(result.durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(tint: (result.failed == 0 ? Color.green : Color.orange).opacity(0.08), cornerRadius: 16)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .glassCard(tint: .orange.opacity(0.08), cornerRadius: 14)
    }

    private var sortedCourses: [TeacherEvaluationCourse] {
        vm.courses.sorted {
            if $0.isEvaluated != $1.isEvaluated { return !$0.isEvaluated }
            return $0.displayName < $1.displayName
        }
    }
}

// MARK: - Cards

private struct TeacherEvaluationTaskCard: View {
    let task: TeacherEvaluationTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("#\(task.taskId)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(statusTint)
                    .frame(width: 34, height: 34)
                    .glassCircle()
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.course.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(task.course.displayTeacher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassBadge(text: task.statusText, tint: statusTint, icon: task.status.systemImage)
            }

            ProgressView(value: task.progress)
                .tint(statusTint)

            if let error = task.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .glassCard(tint: statusTint.opacity(0.08), cornerRadius: 16)
    }

    private var statusTint: Color {
        switch task.status {
        case .waiting: return .gray
        case .preparing: return .blue
        case .countdown: return .purple
        case .submitting: return .orange
        case .verifying: return .teal
        case .completed: return .green
        case .failed: return .red
        }
    }
}

private struct TeacherEvaluationCourseCard: View {
    let course: TeacherEvaluationCourse

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: course.isEvaluated ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(course.isEvaluated ? .green : .orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(course.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(course.displayTeacher, systemImage: "person.fill")
                    if !course.questionnaireName.isEmpty {
                        Label(course.questionnaireName, systemImage: "doc.text")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            GlassBadge(
                text: course.isEvaluated ? "已评" : "待评",
                tint: course.isEvaluated ? .green : .orange,
                icon: course.isEvaluated ? "checkmark" : "hourglass"
            )
        }
        .padding(14)
        .glassCard(tint: (course.isEvaluated ? Color.green : Color.orange).opacity(0.06), cornerRadius: 16)
    }
}
