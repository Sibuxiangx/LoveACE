import SwiftUI

struct CompetitionView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = CompetitionViewModel()
    @State private var selectedAward: AwardProject?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading { LoadingView(message: "加载竞赛信息...") }
                else if let error = vm.error { ErrorView(message: error) { vm.loadCompetitionInfo() } }
                else if let data = vm.data {
                    List {
                        if let summary = data.creditsSummary {
                            Section { creditHeader(summary) }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)

                            Section("学分明细") {
                                creditRow("学科竞赛", summary.disciplineCompetitionCredits, "books.vertical.fill", .blue)
                                creditRow("科学研究", summary.scientificResearchCredits, "flask.fill", .green)
                                creditRow("可转竞赛", summary.transferableCompetitionCredits, "arrow.triangle.swap", .pink)
                                creditRow("创新实践", summary.innovationPracticeCredits, "lightbulb.fill", .orange)
                                creditRow("能力资格", summary.abilityCertificationCredits, "medal.fill", .teal)
                                creditRow("其他项目", summary.otherProjectCredits, "ellipsis.circle.fill", .gray)
                            }
                        }

                        Section("获奖项目（\(data.awards.count)）") {
                            ForEach(data.awards) { award in
                                Button { selectedAward = award } label: {
                                    awardRow(award)
                                }
                                .tint(.primary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("竞赛信息")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { vm.loadCompetitionInfo() }
            .detailPanel(item: $selectedAward) { award in
                AwardDetailSheet(award: award)
            }
            .onAppear {
                if let svc = authVM.competitionService { vm.initialize(service: svc); vm.loadCompetitionInfo() }
            }
        }
    }

    @ViewBuilder
    private func creditHeader(_ summary: CreditsSummary) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("竞赛总学分").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", summary.totalCredits))
                        .font(AppFont.heroNumber)
                    Text("分").font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange.gradient)
        }
        .padding(20)
    }

    private func creditRow(_ title: String, _ value: Double?, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value.map { String(format: "%.1f", $0) } ?? "--")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(value != nil ? tint : .secondary)
        }
    }

    private func awardRow(_ award: AwardProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(award.projectName)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(award.level)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.12), in: .capsule)
                    .foregroundStyle(.orange)

                Text(award.grade)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: .capsule)
                    .foregroundStyle(.blue)

                Spacer()

                Text("+\(String(format: "%.1f", award.credits))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AwardDetailSheet: View {
    let award: AwardProject
    @DetailDismiss private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange.gradient)
                        Text(award.projectName)
                            .font(.title3).fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 8) {
                            Text(award.level)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.orange.opacity(0.12), in: .capsule)
                                .foregroundStyle(.orange)
                            Text(award.grade)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.blue.opacity(0.12), in: .capsule)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("详细信息") {
                    LabeledContent("获奖日期", value: award.awardDate)
                    LabeledContent("获得学分", value: String(format: "%.1f", award.credits))
                    if award.bonus > 0 {
                        LabeledContent("奖金", value: String(format: "%.0f 元", award.bonus))
                    }
                    LabeledContent("申报人", value: award.applicantName)
                    LabeledContent("学号", value: award.applicantId)
                    if award.order > 0 {
                        LabeledContent("排名", value: "第 \(award.order) 位")
                    }
                }

                Section("状态") {
                    LabeledContent("审核状态", value: award.status)
                    HStack {
                        Text("认定状态")
                        Spacer()
                        Text(award.verificationStatus)
                            .foregroundStyle(award.verificationStatus.contains("通过") ? .green : .orange)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("获奖详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
