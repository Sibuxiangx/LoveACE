import Foundation

struct TermGPAPoint: Identifiable {
    var id: String { termName }
    let termName: String
    let termCode: String
    let gpa: Double
    let courseCount: Int
    let totalCredits: Double
}

struct ScoreDistBucket: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let color: String
}

@MainActor
@Observable
final class AcademicViewModel {
    var isLoading = false
    var academicInfo: AcademicInfo?
    var terms: [TermItem] = []
    var selectedTerm: TermItem?
    var scores: TermScoreResponse?
    var scoresLoading = false
    var selectedScore: ScoreRecord?
    var scoreDetail: ScoreDetail?
    var scoreDetailLoading = false
    var scoreDetailError: String?
    var error: String?

    var allTermGPA: [TermGPAPoint] = []
    var allScores: [ScoreRecord] = []
    var insightsLoading = false

    private var service: JWCService?

    func initialize(service: JWCService) { self.service = service }

    func loadAcademicInfo() {
        guard let svc = service else { return }
        Task {
            isLoading = true; error = nil
            let result = await svc.getAcademicInfo()
            isLoading = false
            if result.success { academicInfo = result.data } else { error = result.error }
        }
    }

    func loadTerms() {
        guard let svc = service else { return }
        Task {
            let result = await svc.getAllTerms()
            if result.success, let data = result.data {
                terms = data
                let current = data.first { $0.isCurrent } ?? data.first
                selectedTerm = current
                if let tc = current { loadScores(termCode: tc.termCode) }
            }
        }
    }

    func selectTerm(_ term: TermItem) {
        selectedTerm = term
        selectedScore = nil
        scoreDetail = nil
        scoreDetailError = nil
        loadScores(termCode: term.termCode)
    }

    func loadScores(termCode: String) {
        guard let svc = service else { return }
        Task {
            scoresLoading = true
            let result = selectedTerm?.isCurrent == true
                ? await svc.getThisTermScores()
                : await svc.getTermScore(termCode: termCode)
            scoresLoading = false
            if result.success { scores = result.data } else { error = result.error }
        }
    }

    func loadScoreDetail(_ record: ScoreRecord) {
        guard let svc = service else { return }
        selectedScore = record
        scoreDetail = nil
        scoreDetailLoading = true
        scoreDetailError = nil
        Task {
            let result = await svc.getScoreDetail(record: record)
            scoreDetailLoading = false
            if result.success { scoreDetail = result.data } else { scoreDetailError = result.error }
        }
    }

    func dismissScoreDetail() {
        selectedScore = nil
        scoreDetail = nil
        scoreDetailLoading = false
        scoreDetailError = nil
    }

    func loadInsightsData() {
        guard let svc = service, !insightsLoading else { return }
        Task {
            insightsLoading = true
            if terms.isEmpty {
                let result = await svc.getAllTerms()
                if result.success, let data = result.data { terms = data }
            }

            var points: [TermGPAPoint] = []
            var allRecords: [ScoreRecord] = []

            for term in terms.reversed() {
                let result = await svc.getTermScore(termCode: term.termCode)
                guard result.success, let data = result.data, !data.records.isEmpty else { continue }
                allRecords.append(contentsOf: data.records)

                var totalWeighted = 0.0
                var totalCredits = 0.0
                for r in data.records {
                    guard let score = Double(r.score), let credit = Double(r.credits), credit > 0 else { continue }
                    let gp: Double
                    if score >= 60 { gp = (score - 50) / 10.0 }
                    else { gp = 0.0 }
                    totalWeighted += gp * credit
                    totalCredits += credit
                }
                if totalCredits > 0 {
                    points.append(TermGPAPoint(
                        termName: term.termName, termCode: term.termCode,
                        gpa: totalWeighted / totalCredits,
                        courseCount: data.records.count, totalCredits: totalCredits
                    ))
                }
            }

            allTermGPA = points
            allScores = allRecords
            insightsLoading = false
        }
    }

    var scoreDistribution: [ScoreDistBucket] {
        var buckets = [
            "90+": 0, "80-89": 0, "70-79": 0, "60-69": 0, "<60": 0
        ]
        for r in allScores {
            guard let s = Double(r.score) else { continue }
            if s >= 90 { buckets["90+", default: 0] += 1 }
            else if s >= 80 { buckets["80-89", default: 0] += 1 }
            else if s >= 70 { buckets["70-79", default: 0] += 1 }
            else if s >= 60 { buckets["60-69", default: 0] += 1 }
            else { buckets["<60", default: 0] += 1 }
        }
        return [
            ScoreDistBucket(label: "90+", count: buckets["90+"]!, color: "green"),
            ScoreDistBucket(label: "80-89", count: buckets["80-89"]!, color: "blue"),
            ScoreDistBucket(label: "70-79", count: buckets["70-79"]!, color: "orange"),
            ScoreDistBucket(label: "60-69", count: buckets["60-69"]!, color: "yellow"),
            ScoreDistBucket(label: "<60", count: buckets["<60"]!, color: "red"),
        ]
    }

    var bestSubject: ScoreRecord? {
        allScores.compactMap { r -> (ScoreRecord, Double)? in
            guard let s = Double(r.score) else { return nil }; return (r, s)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    var worstSubject: ScoreRecord? {
        allScores.compactMap { r -> (ScoreRecord, Double)? in
            guard let s = Double(r.score), s > 0 else { return nil }; return (r, s)
        }.min(by: { $0.1 < $1.1 })?.0
    }

    var averageScore: Double {
        let valid = allScores.compactMap { Double($0.score) }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }
}
