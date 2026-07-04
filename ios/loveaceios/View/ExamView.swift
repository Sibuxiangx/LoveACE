import SwiftUI

struct ExamView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = ExamViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    LoadingView(message: "加载考试安排...")
                } else if let error = vm.error {
                    ErrorView(message: error) { vm.loadExams() }
                } else if vm.exams.isEmpty {
                    EmptyStateView(title: "暂无考试", systemImage: "checkmark.seal.fill", description: "当前没有考试安排")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(vm.exams.enumerated()), id: \.element.id) { index, exam in
                                ExamTimelineRow(exam: exam, isLast: index == vm.exams.count - 1)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("考试安排")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { vm.loadExams() }
            .onAppear {
                if let jwc = authVM.jwcService { vm.initialize(service: jwc); vm.loadExams() }
            }
        }
    }
}

struct ExamTimelineRow: View {
    let exam: UnifiedExamInfo
    var isLast: Bool = false

    private var daysUntil: Int? {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: String(exam.examDate.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day
    }

    private var badgeColor: Color {
        guard let days = daysUntil else { return .gray }
        if days < 0 { return .gray }
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        return .blue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(badgeColor.gradient)
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(exam.courseName)
                        .font(.body).fontWeight(.semibold)
                    Spacer()
                    if let days = daysUntil {
                        GlassBadge(
                            text: days == 0 ? "今天" : days > 0 ? "\(days)天后" : "已结束",
                            tint: badgeColor
                        )
                    }
                }

                HStack(spacing: 14) {
                    Label(exam.examDate, systemImage: "calendar")
                    Label(exam.examTime, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !exam.examLocation.isEmpty {
                    Label(exam.examLocation, systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !exam.note.isEmpty {
                    Label(exam.note, systemImage: "number.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GlassBadge(text: exam.examType, tint: .accentColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14)
            .padding(.bottom, 10)
        }
    }
}
