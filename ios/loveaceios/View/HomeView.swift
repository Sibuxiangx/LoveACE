import SwiftUI

struct HomeView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var academicVM = AcademicViewModel()
    @State private var yktVM = YKTViewModel()
    @State private var semesterVM = SemesterViewModel()
    @State private var examVM = ExamViewModel()
    @State private var currentTime = Date()
    @Namespace private var heroNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    semesterHero(at: currentTime)
                    academicGrid
                    balanceSection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("首页")
            .refreshable { refresh() }
            .onAppear {
                if let jwc = authVM.jwcService {
                    academicVM.initialize(service: jwc)
                    examVM.initialize(service: jwc)
                }
                if let ykt = authVM.yktService { yktVM.initialize(service: ykt) }
                academicVM.loadAcademicInfo()
                examVM.loadExams()
                yktVM.loadAll()
                semesterVM.loadSemesterInfo()
            }
            .onChange(of: examVM.hasLoaded) { _, _ in updateExamStatus() }
            .onChange(of: examVM.isLoading) { _, loading in
                if !loading { updateExamStatus() }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { break }
                    updateExamStatus()
                }
            }
        }
    }

    // MARK: - Semester Hero

    @ViewBuilder
    private func semesterHero(at now: Date) -> some View {
        let examOverview = ExamSchedule.homeOverview(exams: examVM.exams, now: now)
        VStack(alignment: .leading, spacing: 10) {
            switch semesterVM.status {
            case .loading:
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20)
            case .inSession(let name, let week, let total, let remaining, let isEnding):
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("第 \(week) 周")
                            .font(AppFont.heroNumber)
                            .foregroundStyle(.white)
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("还剩")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(remaining)")
                            .font(AppFont.largeNumber)
                            .foregroundStyle(.white)
                        Text("周")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                ProgressView(value: Double(week), total: Double(total))
                    .tint(.white.opacity(0.8))
            case .vacation(_, let next, _, let days):
                if authVM.jwcService != nil && (!examVM.hasLoaded || examVM.isLoading) {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("假期中").font(AppFont.largeNumber).foregroundStyle(.white)
                        if let next, let days {
                            Text("\(next)").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            Text("还有 \(days) 天开学").font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            case .finalExamWeek:
                if let examOverview {
                    finalExamHero(examOverview)
                } else {
                    Text("期末周").font(AppFont.largeNumber).foregroundStyle(.white)
                }
            case .error(let msg):
                Text(msg).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppGradient.semester)
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .teal.opacity(0.3), radius: 16, y: 8)
    }

    private func finalExamHero(_ overview: HomeExamOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("期末周").font(AppFont.largeNumber).foregroundStyle(.white)
                Spacer()
                Text("\(overview.exams.count) 场")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(overview.period.title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            ForEach(Array(overview.exams.prefix(2))) { exam in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exam.courseName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text([exam.examDate, exam.examTime, exam.examLocation]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Academic Grid

    @ViewBuilder
    private var academicGrid: some View {
        if let info = academicVM.academicInfo {
            GlassSectionHeader(title: "学业概况", icon: "chart.bar.fill")
            VStack(spacing: 12) {
                gpaRankingCard(info)
                HStack(spacing: 10) {
                    compactAcademicStat("已修", value: "\(info.completedCourses)", icon: "checkmark.circle.fill", tint: .blue)
                    compactAcademicStat("不及格", value: "\(info.failedCourses)", icon: "xmark.circle.fill", tint: .red)
                    compactAcademicStat("待修", value: "\(info.pendingCourses)", icon: "clock.fill", tint: .orange)
                }
            }

            NavigationLink { InsightsView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                        .foregroundStyle(.blue.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("学业分析")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("查看绩点趋势、成绩分布与学业洞察")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(14)
                .glassInteractiveCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)
        } else if academicVM.isLoading {
            HStack { Spacer(); ProgressView("加载学业信息..."); Spacer() }
                .padding(.vertical, 30)
                .glassCard(cornerRadius: 16)
        }
    }

    private func gpaRankingCard(_ info: AcademicInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundStyle(.green.gradient)
                Text("绩点排名")
                    .font(.headline)
                Spacer()
                if let rankBadge = rankBadgeText(info) {
                    GlassBadge(text: rankBadge, tint: .purple, icon: "number")
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", info.gpa))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("GPA")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                academicMetric("均分", value: averageScoreText(info), icon: "chart.bar.fill", tint: .blue)
                academicMetric("排名", value: rankText(info), icon: "medal.fill", tint: .purple)
                academicMetric("人数", value: rankPopulationText(info), icon: "person.3.fill", tint: .orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .green.opacity(0.08), cornerRadius: 22)
    }

    private func academicMetric(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint.opacity(0.08), cornerRadius: 12)
    }

    private func compactAcademicStat(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(AppFont.cardValue)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint.opacity(0.08), cornerRadius: 14)
    }

    private func averageScoreText(_ info: AcademicInfo) -> String {
        guard let score = info.averageScore else { return "--" }
        return String(format: "%.2f", score)
    }

    private func rankText(_ info: AcademicInfo) -> String {
        guard let rank = info.averageScoreRank else { return "--" }
        return "第 \(rank)"
    }

    private func rankPopulationText(_ info: AcademicInfo) -> String {
        guard let population = info.averageScoreRankPopulation else { return "--" }
        return "\(population) 人"
    }

    private func rankBadgeText(_ info: AcademicInfo) -> String? {
        guard let rank = info.averageScoreRank else { return nil }
        if let population = info.averageScoreRankPopulation, population > 0 {
            return "\(rank)/\(population)"
        }
        return "第 \(rank) 名"
    }

    // MARK: - Balance

    @ViewBuilder
    private var balanceSection: some View {
        GlassSectionHeader(title: "校园卡", icon: "creditcard.fill")
        NavigationLink { YKTView() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("余额").font(.subheadline).foregroundStyle(.secondary)
                    if let balance = yktVM.balance {
                        Text("¥\(String(format: "%.2f", balance.balance))")
                            .font(AppFont.largeNumber)
                            .foregroundStyle(.primary)
                    } else if yktVM.isLoading {
                        ProgressView()
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .glassInteractiveCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func refresh() {
        academicVM.loadAcademicInfo()
        examVM.loadExams()
        yktVM.loadAll()
        semesterVM.loadSemesterInfo()
    }

    private func updateExamStatus(at now: Date = Date()) {
        currentTime = now
        guard examVM.hasLoaded, !examVM.isLoading else { return }
        let overview = ExamSchedule.homeOverview(exams: examVM.exams, now: now)
        semesterVM.updatePendingExamStatus(overview != nil, now: now)
    }
}
