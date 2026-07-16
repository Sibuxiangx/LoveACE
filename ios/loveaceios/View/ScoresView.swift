import SwiftUI

struct ScoresView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = AcademicViewModel()
    @State private var selectedScore: ScoreRecord?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.terms.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.terms) { term in
                                Button { withAnimation(.snappy) { vm.selectTerm(term) } } label: {
                                    Text(term.termName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                }
                .glassCapsule(tint: vm.selectedTerm?.termCode == term.termCode ? .blue.opacity(0.3) : nil, interactive: vm.selectedTerm?.termCode == term.termCode)
                                .foregroundStyle(vm.selectedTerm?.termCode == term.termCode ? .blue : .secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                if vm.scoresLoading {
                    LoadingView(message: "加载成绩...")
                } else if let scores = vm.scores {
                    if scores.records.isEmpty {
                        EmptyStateView(title: "暂无成绩", systemImage: "doc.text.magnifyingglass", description: "该学期暂无成绩数据")
                    } else {
                        scoreCarousel(scores.records)
                    }
                }
            }
            .navigationTitle("成绩查询")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedScore, onDismiss: vm.dismissScoreDetail) { record in
                ScoreDetailSheet(
                    record: record,
                    detail: vm.scoreDetail,
                    isLoading: vm.scoreDetailLoading,
                    error: vm.scoreDetailError
                )
            }
            .onAppear {
                if let jwc = authVM.jwcService {
                    vm.initialize(service: jwc)
                    vm.loadTerms()
                }
            }
        }
    }

    @ViewBuilder
    private func scoreCarousel(_ records: [ScoreRecord]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 14) {
                ForEach(records) { record in
                    ScoreCardView(
                        record: record,
                        onTap: vm.selectedTerm?.isCurrent == true && record.hasPublishedScore ? {
                            selectedScore = record
                            vm.loadScoreDetail(record)
                        } : nil
                    )
                        .compatScrollTransition()
                }
            }
            .compatScrollTargetLayout()
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
        .compatScrollTargetBehavior()
    }
}

struct ScoreCardView: View {
    let record: ScoreRecord
    var onTap: (() -> Void)? = nil

    private var color: Color { scoreColor(for: record.score) }

    var body: some View {
        if let onTap {
            Button(action: onTap) { cardContent }
                .buttonStyle(.plain)
                .accessibilityHint("查看成绩明细")
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.courseNameCn)
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 10) {
                        Label(record.credits + " 学分", systemImage: "book.closed.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let type = record.courseType {
                            GlassBadge(text: type, tint: .blue)
                        }
                        if let type = record.examType, !type.isEmpty {
                            GlassBadge(text: type, tint: .orange)
                        }
                    }

                    if !record.courseNameEn.isEmpty {
                        Text(record.courseNameEn)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    Text(record.hasPublishedScore ? record.score : "暂无成绩")
                        .font(AppFont.heroNumber)
                        .foregroundStyle(record.hasPublishedScore ? color.gradient : Color.secondary.gradient)
                    Text(record.hasPublishedScore ? "分" : "成绩未发布")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if record.retakeScore != nil || record.makeupScore != nil {
                Divider().padding(.vertical, 8)
                HStack(spacing: 16) {
                    if let retake = record.retakeScore, !retake.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("补考: \(retake)")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let makeup = record.makeupScore, !makeup.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.2.squarepath")
                            Text("重修: \(makeup)")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(color.opacity(0.06))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(color.opacity(0.08))
                        .frame(width: 100, height: 100)
                        .offset(x: 30, y: -30)
                }
                .clipShape(.rect(cornerRadius: 20))
        }
        .glassCard(cornerRadius: 20)
    }
}

private struct ScoreDetailSheet: View {
    let record: ScoreRecord
    let detail: ScoreDetail?
    let isLoading: Bool
    let error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingView(message: "加载成绩明细...")
                } else if let error {
                    ContentUnavailableView("无法加载成绩明细", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let detail, !detail.items.isEmpty {
                    List {
                        ForEach(detail.items) { item in
                            Section(item.scoreType) {
                                ScoreDetailRow(label: "平时", value: item.usualScore)
                                ScoreDetailRow(label: "期中", value: item.midtermScore)
                                ScoreDetailRow(label: "期末", value: item.finalScore)
                                ScoreDetailRow(label: "分类总成绩", value: item.categoryScore)
                                if !item.remark.isEmpty {
                                    ScoreDetailRow(label: "备注", value: item.remark)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("暂无成绩明细", systemImage: "list.bullet.rectangle")
                }
            }
            .navigationTitle(record.courseNameCn)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ScoreDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label, value: value.isEmpty ? "-" : value)
    }
}
