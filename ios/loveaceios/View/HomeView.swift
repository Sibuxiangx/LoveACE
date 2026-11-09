import SwiftUI
import Combine

struct HomeView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.wideLayout) private var wideLayout
    @State private var academicVM = AcademicViewModel()
    @State private var yktVM = YKTViewModel()
    @State private var semesterVM = SemesterViewModel()
    @Namespace private var heroNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if wideLayout {
                        wideDashboard
                    } else {
                        VStack(spacing: 20) {
                            semesterHero
                            academicGrid
                            balanceSection
                        }
                    }
                }
                .readableWidth(wideLayout ? 1200 : 680)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("首页")
            .refreshable { refresh() }
            .onAppear {
                if let jwc = authVM.jwcService { academicVM.initialize(service: jwc) }
                if let ykt = authVM.yktService { yktVM.initialize(service: ykt, portal: authVM.portalService) }
                academicVM.loadAcademicInfo()
                yktVM.loadBalance()
                semesterVM.loadSemesterInfo()
            }
            .onReceive(NotificationCenter.default.publisher(for: WidgetSyncCoordinator.snapshotDidChange)) { _ in
                semesterVM.loadSemesterInfo()
            }
        }
    }

    // MARK: - Semester Hero

    @ViewBuilder
    private var semesterHero: some View {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("假期中").font(AppFont.largeNumber).foregroundStyle(.white)
                    if let next, let days {
                        Text("\(next)").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        Text("还有 \(days) 天开学").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
            case .examWeek(let exam, let days):
                VStack(alignment: .leading, spacing: 6) {
                    Text("考试周").font(AppFont.largeNumber).foregroundStyle(.white)
                    Text(exam.courseName).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                    Text([exam.date, exam.rangeText, exam.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text(days == 0 ? "今天考试" : "还有 \(days) 天考试")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
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

    // MARK: - Academic Grid

    @ViewBuilder
    private var academicGrid: some View {
        if let info = academicVM.academicInfo {
            GlassSectionHeader(title: "学业概况", icon: "chart.bar.fill")
            VStack(spacing: 12) {
                gpaRankingCard(info)
                academicStatRow(info)
            }
            insightsLink
        } else if academicVM.isLoading {
            loadingCard
        }
    }

    /// 宽屏：学期横幅通栏；下面左边是绩点卡（撑满剩余高度），右边是校园卡、三项状态和学业分析入口
    private var wideDashboard: some View {
        VStack(spacing: 20) {
            semesterHero
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    if let info = academicVM.academicInfo {
                        GlassSectionHeader(title: "学业概况", icon: "chart.bar.fill")
                        gpaRankingCard(info)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else if academicVM.isLoading {
                        loadingCard
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(spacing: 20) {
                    balanceSection
                    if let info = academicVM.academicInfo {
                        academicStatRow(info)
                        insightsLink
                    }
                }
                .frame(width: 340)
            }
        }
    }

    private func academicStatRow(_ info: AcademicInfo) -> some View {
        HStack(spacing: 10) {
            compactAcademicStat("已修", value: "\(info.completedCourses)", icon: "checkmark.circle.fill", tint: .blue)
            compactAcademicStat("不及格", value: "\(info.failedCourses)", icon: "xmark.circle.fill", tint: .red)
            compactAcademicStat("待修", value: "\(info.pendingCourses)", icon: "clock.fill", tint: .orange)
        }
    }

    private var insightsLink: some View {
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
    }

    private var loadingCard: some View {
        HStack { Spacer(); ProgressView("加载学业信息..."); Spacer() }
            .padding(.vertical, 30)
            .glassCard(cornerRadius: 16)
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

            Spacer(minLength: 0)
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
        yktVM.loadBalance()
        semesterVM.loadSemesterInfo()
    }
}
