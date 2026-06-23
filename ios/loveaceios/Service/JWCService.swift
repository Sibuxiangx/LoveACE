import Foundation
import SwiftSoup
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "JWCService")

actor JWCService {
    private let connection: AUFEConnection
    private var cachedTerms: UniResponse<[TermItem]>?
    private var termsCacheTimestamp: Date = .distantPast
    static let baseURL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
    private static let cacheTTL: TimeInterval = 30

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    // MARK: - Academic Info

    func getAcademicInfo() async -> UniResponse<AcademicInfo> {
        do {
            let url = "\(Self.baseURL)/main/academicInfo?sf_request_type=ajax"
            let client = await connection.client!
            let (data, _) = try await client.post(url, formData: ["flag": ""], headers: [
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Referer": "\(Self.baseURL)/index.jsp",
                "X-Requested-With": "XMLHttpRequest"
            ])
            let body = String(data: data, encoding: .utf8) ?? ""
            guard !body.isEmpty else { throw ServiceError.emptyResponse }
            guard let jsonData = body.data(using: .utf8),
                  let arr = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
                  let obj = arr.first else { throw ServiceError.parseError("数据为空") }

            let info = AcademicInfo(
                completedCourses: intValue(obj["courseNum"]) ?? 0,
                failedCourses: intValue(obj["coursePas"]) ?? 0,
                gpa: doubleValue(obj["gpa"]) ?? 0.0,
                averageScore: doubleValue(obj["sspjf_jd"]),
                averageScoreRank: intValue(obj["sspjf_pm"]),
                averageScoreRankPopulation: intValue(obj["sspjf_rs"]),
                pendingCourses: intValue(obj["courseNum_bxqyxd"]) ?? 0,
                currentTerm: stringValue(obj["zxjxjhh"])
            )
            return .success(info)
        } catch {
            logger.error("getAcademicInfo failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Terms

    func getAllTerms() async -> UniResponse<[TermItem]> {
        if let cached = cachedTerms, cached.success,
           Date().timeIntervalSince(termsCacheTimestamp) < Self.cacheTTL {
            return cached
        }

        do {
            let url = "\(Self.baseURL)/student/courseSelect/calendarSemesterCurriculum/index"
            let client = await connection.client!
            let (data, _) = try await client.get(url)
            let html = String(data: data, encoding: .utf8) ?? ""
            let doc = try SwiftSoup.parse(html)
            guard let select = try doc.select("select#planCode").first() else {
                throw ServiceError.parseError("未找到学期选择框")
            }
            let options = try select.select("option")
            var parsedTerms: [TermItem] = []
            for option in options.array() {
                let code = try option.attr("value")
                guard !code.isEmpty else { continue }
                let rawName = try option.text().trimmingCharacters(in: .whitespaces)
                let name = rawName
                    .replacingOccurrences(of: "春", with: "下")
                    .replacingOccurrences(of: "秋", with: "上")
                let isCurrent = option.hasAttr("selected") || rawName.contains("当前")
                parsedTerms.append(TermItem(termCode: code, termName: name, isCurrent: isCurrent))
            }
            let terms: [TermItem]
            if parsedTerms.contains(where: { $0.isCurrent }) {
                terms = parsedTerms
            } else {
                terms = parsedTerms.enumerated().map { index, term in
                    TermItem(termCode: term.termCode, termName: term.termName, isCurrent: index == 0)
                }
            }
            let result: UniResponse<[TermItem]> = .success(terms)
            cachedTerms = result
            termsCacheTimestamp = Date()
            return result
        } catch {
            logger.error("getAllTerms failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Scores

    func getTermScore(termCode: String) async -> UniResponse<TermScoreResponse> {
        do {
            let client = await connection.client!
            let preUrl = "\(Self.baseURL)/student/integratedQuery/scoreQuery/allTermScores/index"
            let (preData, _) = try await client.get(preUrl)
            let preHtml = String(data: preData, encoding: .utf8) ?? ""
            guard let pathRange = preHtml.range(of: "/([A-Za-z0-9]+)/allTermScores/data", options: .regularExpression),
                  let match = preHtml[pathRange].range(of: "[A-Za-z0-9]+", options: .regularExpression) else {
                throw ServiceError.parseError("未能提取动态路径")
            }
            let dynamicPath = String(preHtml[pathRange][match])

            let scoreUrl = "\(Self.baseURL)/student/integratedQuery/scoreQuery/\(dynamicPath)/allTermScores/data"
            let (scoreData, _) = try await client.post(scoreUrl, formData: [
                "zxjxjhh": termCode, "kch": "", "kcm": "",
                "pageNum": "1", "pageSize": "100", "sf_request_type": "ajax"
            ], headers: ["Referer": preUrl])

            let body = String(data: scoreData, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return .success(TermScoreResponse())
            }
            guard let listData = json["list"] as? [String: Any],
                  let recordsArr = listData["records"] as? [[Any]] else {
                return .success(TermScoreResponse())
            }
            let records = recordsArr.compactMap { parseScoreRecord($0) }
            let total = (listData["pageContext"] as? [String: Any])?["totalCount"] as? Int ?? records.count
            return .success(TermScoreResponse(totalCount: total, records: records))
        } catch {
            logger.error("getTermScore failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private func parseScoreRecord(_ arr: [Any]) -> ScoreRecord? {
        guard arr.count >= 11 else { return nil }
        func str(_ idx: Int) -> String { "\(arr[idx])" == "<null>" ? "" : "\(arr[idx])" }
        func optStr(_ idx: Int) -> String? { idx < arr.count && "\(arr[idx])" != "<null>" ? "\(arr[idx])" : nil }
        return ScoreRecord(
            sequence: arr[0] as? Int ?? Int(str(0)) ?? 0,
            termId: str(1), courseCode: str(2), courseClass: str(3),
            courseNameCn: str(4), courseNameEn: str(5),
            credits: str(6), hours: arr[7] as? Int ?? Int(str(7)) ?? 0,
            courseType: optStr(8), examType: optStr(9), score: str(10),
            retakeScore: optStr(11), makeupScore: optStr(12)
        )
    }

    // MARK: - Exams

    func getExamInfo() async -> UniResponse<[UnifiedExamInfo]> {
        do {
            let academicResp = await getAcademicInfo()
            guard academicResp.success, let academicData = academicResp.data else {
                throw ServiceError.parseError("无法获取学期信息")
            }
            let termCode = academicData.currentTerm
            let now = Date()
            let cal = Calendar.current
            let startDate = Self.dateString(now)
            let year = cal.component(.year, from: now)
            let endDate = termCode.hasSuffix("1") ? "\(year + 1)-03-30" : "\(year)-09-30"

            let client = await connection.client!
            let preUrl = "\(Self.baseURL)/student/examinationManagement/examPlan/index"
            _ = try await client.get(preUrl)

            let ts = Int(Date().timeIntervalSince1970 * 1000)
            let examUrl = "\(Self.baseURL)/student/examinationManagement/examPlan/detail?start=\(startDate)&end=\(endDate)&_=\(ts)"
            let (examData, _) = try await client.get(examUrl, headers: [
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "X-Requested-With": "XMLHttpRequest"
            ])
            let examBody = String(data: examData, encoding: .utf8) ?? "[]"
            var schoolExams: [UnifiedExamInfo] = []
            if !examBody.trimmingCharacters(in: .whitespaces).isEmpty,
               examBody.trimmingCharacters(in: .whitespaces) != "]",
               let jsonData = examBody.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                schoolExams = arr.compactMap { parseSchoolExam($0) }
            }

            let otherUrl = "\(Self.baseURL)/student/examinationManagement/othersExamPlan/queryScores?sf_request_type=ajax"
            let (otherData, _) = try await client.post(otherUrl, formData: [
                "zxjxjhh": termCode, "tab": "0", "pageNum": "1", "pageSize": "30"
            ])
            var otherExams: [UnifiedExamInfo] = []
            if let otherBody = String(data: otherData, encoding: .utf8),
               let jsonData = otherBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let list = json["list"] as? [String: Any],
               let records = list["records"] as? [[Any]] {
                otherExams = records.compactMap { parseOtherExam($0) }
            }

            let all = (schoolExams + otherExams).sorted { ($0.examDate, $0.examTime) < ($1.examDate, $1.examTime) }
            return .success(all)
        } catch {
            logger.error("getExamInfo failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private func parseSchoolExam(_ obj: [String: Any]) -> UnifiedExamInfo? {
        guard let title = obj["title"] as? String else { return nil }
        let lines = title.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return UnifiedExamInfo(
            courseName: lines.first ?? "",
            examDate: obj["start"] as? String ?? "",
            examTime: lines.count > 1 ? lines[1] : "",
            examLocation: lines.count > 2 ? lines.dropFirst(2).joined(separator: " ") : "",
            examType: "校统考"
        )
    }

    private func parseOtherExam(_ arr: [Any]) -> UnifiedExamInfo? {
        guard arr.count >= 8 else { return nil }
        func str(_ i: Int) -> String { "\(arr[i])" == "<null>" ? "" : "\(arr[i])" }
        return UnifiedExamInfo(
            courseName: str(2), examDate: str(4), examTime: str(5),
            examLocation: str(6), examType: "其他考试", note: str(7)
        )
    }

    // MARK: - Training Plan

    func getTrainingPlanInfo() async -> UniResponse<TrainingPlanInfo> {
        do {
            let client = await connection.client!
            let url = "\(Self.baseURL)/main/showPyfaInfo?sf_request_type=ajax"
            let (data, _) = try await client.get(url)
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let dataList = json["data"] as? [[Any]],
                  let planArr = dataList.first,
                  let planName = planArr.first as? String else {
                throw ServiceError.parseError("无培养方案数据")
            }
            let gradeRegex = try NSRegularExpression(pattern: "(\\d{4})级")
            let grade = gradeRegex.firstMatch(in: planName, range: NSRange(planName.startIndex..., in: planName))
                .flatMap { Range($0.range(at: 1), in: planName) }.map { String(planName[$0]) } ?? ""
            let majorName = planName
                .replacingOccurrences(of: "\\d{4}级", with: "", options: .regularExpression)
                .replacingOccurrences(of: "本科培养方案", with: "")
                .replacingOccurrences(of: "培养方案", with: "")
                .trimmingCharacters(in: .whitespaces)
            return .success(TrainingPlanInfo(planName: planName, majorName: majorName, grade: grade))
        } catch {
            logger.error("getTrainingPlanInfo failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private func stringValue(_ value: Any?, fallback: String = "") -> String {
    guard let value, !(value is NSNull) else { return fallback }
    return String(describing: value)
}

private func intValue(_ value: Any?) -> Int? {
    guard let value, !(value is NSNull) else { return nil }
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    if let string = value as? String { return Int(string) }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    guard let value, !(value is NSNull) else { return nil }
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    if let string = value as? String { return Double(string) }
    return nil
}

enum ServiceError: Error, LocalizedError {
    case emptyResponse
    case parseError(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "响应为空"
        case .parseError(let msg): return msg
        case .sessionExpired: return "会话已过期"
        }
    }
}
