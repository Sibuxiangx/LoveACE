import Foundation
import SwiftSoup
import os

private let teacherEvaluationLogger = Logger(subsystem: "tech.loveace.loveaceios", category: "TeacherEvaluationService")

enum EvaluationStrategy {
    case smart
    case alwaysHighest
}

actor TeacherEvaluationService {
    private let connection: AUFEConnection
    private var token: String?

    static let baseURL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    // MARK: - Course List

    func fetchCourses() async -> UniResponse<[TeacherEvaluationCourse]> {
        do {
            try await refreshEvaluationIndexState()
            let client = await connection.client!
            let (data, response) = try await client.post(
                "\(Self.baseURL)/student/teachingEvaluation/teachingEvaluation/search?sf_request_type=ajax",
                formData: ["optType": "1", "pagesize": "50"]
            )
            guard response.statusCode == 200 else {
                throw ServiceError.parseError("HTTP \(response.statusCode)")
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ServiceError.parseError("课程列表响应格式错误")
            }
            guard let list = root["data"] as? [Any] else {
                return .success([])
            }
            let courses = list.compactMap(parseCourse)
            return .success(courses)
        } catch {
            teacherEvaluationLogger.error("fetchCourses failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private func parseCourse(_ item: Any) -> TeacherEvaluationCourse? {
        guard let item = item as? [String: Any] else { return nil }
        let id = item["id"] as? [String: Any]
        let questionnaire = item["questionnaire"] as? [String: Any]
        let evaluatedNumber = stringValue(id?["evaluatedPeople"])
        let contentNumber = stringValue(id?["evaluationContentNumber"])
        let questionnaireCode = stringValue(questionnaire?["questionnaireNumber"])

        return TeacherEvaluationCourse(
            legacyId: evaluatedNumber,
            name: stringValue(item["evaluationContent"]),
            teacher: stringValue(item["evaluatedPeople"]),
            evaluatedPeople: stringValue(item["evaluatedPeople"]),
            evaluatedPeopleNumber: evaluatedNumber,
            coureSequenceNumber: stringValue(id?["coureSequenceNumber"]),
            evaluationContentNumber: contentNumber,
            questionnaireCode: questionnaireCode,
            questionnaireName: stringValue(questionnaire?["questionnaireName"]),
            isEvaluated: stringValue(item["isEvaluated"]) == "是"
        )
    }

    // MARK: - Evaluation Flow

    func prepareEvaluation(course: TeacherEvaluationCourse, totalCourses: Int, strategy: EvaluationStrategy = .smart) async -> UniResponse<[String: String]> {
        do {
            guard let html = try await accessEvaluationPage(course: course, totalCourses: totalCourses) else {
                throw ServiceError.parseError("无法访问评价页面")
            }
            let questionnaire = try parseQuestionnaire(html)
            let formData = buildFormData(questionnaire: questionnaire, course: course, totalCourses: totalCourses)
            guard formData["tokenValue"]?.isEmpty == false else {
                throw ServiceError.parseError("评价页缺少 token")
            }
            return .success(formData)
        } catch {
            teacherEvaluationLogger.error("prepareEvaluation failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private func getToken() async throws -> String? {
        if let token, !token.isEmpty { return token }
        try await refreshEvaluationIndexState()
        return token
    }

    private func refreshEvaluationIndexState() async throws {
        let client = await connection.client!
        let (data, response) = try await client.get("\(Self.baseURL)/student/teachingEvaluation/evaluation/index")
        guard response.statusCode == 200 else {
            throw ServiceError.parseError("HTTP \(response.statusCode)")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        if isEvaluationClosedPage(html) {
            token = nil
            throw ServiceError.parseError("评价暂未开启")
        }
        token = parseToken(from: html)
    }

    private func accessEvaluationPage(course: TeacherEvaluationCourse, totalCourses: Int) async throws -> String? {
        let pageToken = try await getToken() ?? ""
        let client = await connection.client!
        let (data, response) = try await client.post(
            "\(Self.baseURL)/student/teachingEvaluation/teachingEvaluation/evaluationPage",
            formData: [
                "count": String(totalCourses),
                "evaluatedPeople": course.evaluatedPeople,
                "evaluatedPeopleNumber": course.evaluatedPeopleNumber,
                "questionnaireCode": course.questionnaireCode,
                "questionnaireName": course.questionnaireName,
                "coureSequenceNumber": course.coureSequenceNumber,
                "evaluationContentNumber": course.evaluationContentNumber,
                "evaluationContentContent": "",
                "tokenValue": pageToken
            ]
        )
        guard response.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func submitEvaluation(formData: [String: String]) async -> UniResponse<TeacherEvaluationSubmitResponse> {
        do {
            let client = await connection.client!
            let (data, response) = try await client.post(
                "\(Self.baseURL)/student/teachingEvaluation/teachingEvaluation/assessment?sf_request_type=ajax",
                formData: formData
            )
            guard response.statusCode == 200 else {
                throw ServiceError.parseError("网络请求失败（\(response.statusCode)）")
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ServiceError.parseError("提交响应格式错误")
            }
            let submitResponse = TeacherEvaluationSubmitResponse(
                result: stringValue(root["result"], fallback: "error"),
                msg: stringValue(root["msg"], fallback: "未知错误")
            )
            if submitResponse.isSuccess {
                return .success(submitResponse, message: submitResponse.msg)
            }
            return .failure(submitResponse.msg, retryable: true)
        } catch {
            teacherEvaluationLogger.error("submitEvaluation failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Questionnaire Parsing

    private func parseQuestionnaire(_ html: String) throws -> TeacherQuestionnaire {
        let doc = try SwiftSoup.parse(html)
        let metadata = extractMetadata(doc)
        return TeacherQuestionnaire(
            metadata: metadata,
            radioQuestions: extractRadioQuestions(doc),
            textQuestions: extractTextQuestions(doc)
        )
    }

    private func extractMetadata(_ doc: Document) -> TeacherQuestionnaireMetadata {
        var metadata = TeacherQuestionnaireMetadata()
        metadata.title = text((try? doc.select("div.title").first()) ?? (try? doc.select("h1").first()) ?? (try? doc.select("h2").first()))
        metadata.tokenValue = attr((try? doc.select("input[name=tokenValue]").first()) ?? (try? doc.select("input#tokenValue").first()), "value")
        metadata.questionnaireCode = attr(try? doc.select("input[name=wjdm]").first(), "value")
        metadata.evaluatedPeopleNumber = attr(try? doc.select("input[name=bprdm]").first(), "value")
        metadata.evaluationContent = attr(try? doc.select("input[name=pgnr]").first(), "value")

        if let cells = try? doc.select("td").array() {
            for cell in cells {
                let cellText = text(cell)
                if cellText.contains("被评人") || cellText.contains("教师") {
                    if let next = try? cell.nextElementSibling() {
                        metadata.evaluatedPerson = text(next)
                        break
                    }
                }
            }
        }
        return metadata
    }

    private func extractRadioQuestions(_ doc: Document) -> [TeacherRadioQuestion] {
        guard let inputs = try? doc.select("input[type=radio]").array() else { return [] }
        var order: [String] = []
        var questions: [String: TeacherRadioQuestion] = [:]

        for input in inputs {
            let name = attr(input, "name")
            let value = attr(input, "value")
            guard !name.isEmpty, !value.isEmpty else { continue }

            let option = TeacherRadioOption(
                label: optionLabel(for: input, in: doc),
                value: value,
                score: parseScoreWeight(value).score,
                weight: parseScoreWeight(value).weight
            )

            if let existing = questions[name] {
                questions[name] = TeacherRadioQuestion(
                    key: existing.key,
                    questionText: existing.questionText,
                    options: existing.options + [option],
                    category: existing.category
                )
            } else {
                let extracted = questionTextAndCategory(for: input)
                questions[name] = TeacherRadioQuestion(
                    key: name,
                    questionText: extracted.text,
                    options: [option],
                    category: extracted.category
                )
                order.append(name)
            }
        }

        return order.compactMap { questions[$0] }
    }

    private func extractTextQuestions(_ doc: Document) -> [TeacherTextQuestion] {
        guard let textareas = try? doc.select("textarea").array() else { return [] }
        return textareas.compactMap { textarea in
            let name = attr(textarea, "name")
            guard !name.isEmpty else { return nil }
            let questionText = textQuestionText(for: textarea)
            return TeacherTextQuestion(
                key: name,
                questionText: questionText,
                type: analyzeTextQuestionType(questionText: questionText, fieldName: name),
                isRequired: name == "zgpj" || name.contains("zgpj")
            )
        }
    }

    // MARK: - Form Building

    private func buildFormData(questionnaire: TeacherQuestionnaire, course: TeacherEvaluationCourse, totalCourses: Int) -> [String: String] {
        var formData: [String: String] = [
            "optType": "submit",
            "tokenValue": questionnaire.tokenValue,
            "questionnaireCode": course.questionnaireCode.isEmpty ? questionnaire.questionnaireCode : course.questionnaireCode,
            "evaluationContent": course.evaluationContentNumber.isEmpty ? questionnaire.evaluationContent : course.evaluationContentNumber,
            "evaluatedPeopleNumber": course.evaluatedPeopleNumber.isEmpty ? questionnaire.evaluatedPeopleNumber : course.evaluatedPeopleNumber,
            "count": String(totalCourses)
        ]

        for question in questionnaire.radioQuestions {
            guard let selected = selectBestOption(question.options, strategy: strategy) else { continue }
            formData[question.key] = selected.value
        }

        for question in questionnaire.textQuestions {
            formData[question.key] = generateTextAnswer(for: question)
        }

        return formData
    }

    private func selectBestOption(_ options: [TeacherRadioOption], strategy: EvaluationStrategy) -> TeacherRadioOption? {
        guard !options.isEmpty else { return nil }
        let sorted = options.sorted { $0.weight > $1.weight }
        // 一键非常满意：强制选最高权重
        if strategy == .alwaysHighest {
            let fullWeightOptions = sorted.filter { $0.weight == 1.0 }
            if !fullWeightOptions.isEmpty {
                return fullWeightOptions.randomElement()
            }
            return sorted.first
        }
        let fullWeightOptions = sorted.filter { $0.weight == 1.0 }
        if !fullWeightOptions.isEmpty, Double.random(in: 0..<1) < 0.8 {
            return fullWeightOptions.randomElement()
        }
        if sorted.count > 1 {
            let highest = sorted[0].weight
            if let second = sorted.first(where: { $0.weight < highest })?.weight {
                let group = sorted.filter { $0.weight == second }
                if let option = group.randomElement() { return option }
            }
        }
        return sorted[0]
    }

    private func generateTextAnswer(for question: TeacherTextQuestion) -> String {
        var text = randomText(for: question.type)
        var attempts = 0
        while !isValidTextAnswer(text), attempts < 3 {
            text = randomText(for: question.type)
            attempts += 1
        }
        return text.replacingOccurrences(of: " ", with: "")
    }
}

// MARK: - Parser Helpers

private extension TeacherEvaluationService {
    func parseToken(from html: String) -> String? {
        if let doc = try? SwiftSoup.parse(html) {
            let token = attr((try? doc.select("input#tokenValue").first()) ?? (try? doc.select("input[name=tokenValue]").first()), "value")
            if !token.isEmpty { return token }
        }
        return firstCapture(#"(?:id|name)=["']tokenValue["'][^>]*value=["']([^"']+)["']"#, in: html)
    }

    func isEvaluationClosedPage(_ html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        let selectors = [
            "#page-content-template .alert",
            ".page-content .alert",
            ".main-content .alert"
        ]

        for selector in selectors {
            guard let alerts = try? doc.select(selector).array() else { continue }
            if alerts.contains(where: { text($0).contains("评估开关已关闭") }) {
                return true
            }
        }
        return false
    }

    func optionLabel(for input: Element, in doc: Document) -> String {
        let inputId = attr(input, "id")
        if !inputId.isEmpty,
           let label = try? doc.select("label[for=\"\(inputId)\"]").first(),
           !text(label).isEmpty {
            return text(label)
        }

        var parent = input.parent()
        while let current = parent {
            if current.tagName().lowercased() == "label" { return text(current) }
            parent = current.parent()
        }

        if let cell = ancestor(of: input, named: "td") {
            return text(cell)
        }
        return ""
    }

    func questionTextAndCategory(for input: Element) -> (text: String, category: String) {
        guard let row = ancestor(of: input, named: "tr") else { return ("", "") }
        let category = text(try? row.select("td[rowspan]").first())
        var questionText = ""

        if let cells = try? row.select("td").array() {
            for cell in cells {
                let cellText = text(cell)
                let hasRadio = ((try? cell.select("input[type=radio]").size()) ?? 0) > 0
                if !cellText.isEmpty, cellText.count > 5, !hasRadio {
                    questionText = cellText
                    break
                }
            }
        }

        if questionText.isEmpty {
            var prev = try? row.previousElementSibling()
            while let prevRow = prev, questionText.isEmpty {
                if let cells = try? prevRow.select("td").array() {
                    for cell in cells {
                        let cellText = text(cell)
                        if !cellText.isEmpty, cellText.count > 5 {
                            questionText = cellText
                            break
                        }
                    }
                }
                prev = try? prevRow.previousElementSibling()
            }
        }

        return (questionText, category)
    }

    func textQuestionText(for textarea: Element) -> String {
        guard let cell = ancestor(of: textarea, named: "td") else { return "" }
        if let prevCell = try? cell.previousElementSibling(), !text(prevCell).isEmpty {
            return text(prevCell)
        }
        let cellText = text(cell)
        if !cellText.isEmpty { return cellText }

        if let row = ancestor(of: textarea, named: "tr"), let prevRow = try? row.previousElementSibling(), let cells = try? prevRow.select("td").array() {
            for cell in cells {
                let prevText = text(cell)
                if !prevText.isEmpty, prevText.count > 3 { return prevText }
            }
        }
        return ""
    }

    func analyzeTextQuestionType(questionText: String, fieldName: String) -> TeacherTextQuestionType {
        if fieldName == "zgpj" || fieldName.contains("zgpj") { return .overall }
        if questionText.contains("启发") || questionText.contains("启示") { return .inspiration }
        if questionText.contains("建议") || questionText.contains("意见") || questionText.contains("改进") { return .suggestion }
        return .general
    }

    func ancestor(of element: Element, named tagName: String) -> Element? {
        var parent = element.parent()
        while let current = parent {
            if current.tagName().lowercased() == tagName { return current }
            parent = current.parent()
        }
        return nil
    }

    func parseScoreWeight(_ value: String) -> (score: Double, weight: Double) {
        let parts = value.split(separator: "_")
        guard parts.count >= 2 else { return (0, 0) }
        return (Double(parts[0]) ?? 0, Double(parts[1]) ?? 0)
    }
}

// MARK: - Text Generator

private extension TeacherEvaluationService {
    var inspirationTexts: [String] {
        [
            "老师授课有条理有重点，教会我做事要分清主次、抓住关键的思维方法",
            "老师善于联系实际讲解理论知识，启发我学会了理论联系实际的思维方式",
            "老师注重培养学生的自主学习能力，让我明白了授人以渔的教育真谛",
            "老师对每个问题的耐心解答，教会我做事要有耐心和责任心",
            "老师清晰的逻辑思维，启发我学会了有条理地思考和表达问题",
            "老师对教学的精心准备，让我明白了充分准备是做好工作的前提",
            "老师善于启发学生独立思考，教会我批判性思维和质疑精神的可贵",
            "老师治学严谨、循循善诱的风格，激励我要保持谦逊认真的学习态度和钻研精神"
        ]
    }

    var suggestionTexts: [String] {
        [
            "老师讲课很好，很认真负责，我没有什么建议，希望老师继续保持现有的教学方式",
            "老师授课认真，课堂效率高，我觉得一切都很好，暂时没有什么意见和建议",
            "老师上课既幽默又严格，教学方法很适合我们，没有需要改进的地方",
            "老师治学严谨，循循善诱，对老师的授课我非常满意，请老师保持这种教学状态",
            "老师授课有条理有重点，我认为已经做得很到位了，没有什么建议可提",
            "老师课堂效率高，气氛活跃，整节课学下来很有收获，暂时想不到需要改进的地方",
            "老师教学态度端正，讲课思路清晰，我觉得非常好，没有什么意见和建议",
            "老师讲课深入浅出，通俗易懂，我认为非常好，希望老师继续保持"
        ]
    }

    var overallTexts: [String] {
        [
            "老师讲课认真负责，课程内容充实丰富，理论与实践结合得很好，让我收获颇丰，对专业知识有了更深入的理解",
            "老师授课条理清晰，课程设置合理，由浅入深，循序渐进，学习过程中既有挑战性又能跟上节奏",
            "老师教学方法灵活多样，课程内容非常实用，学到的知识能够应用到实际中，让我感受到了学以致用的乐趣",
            "老师讲课生动有趣，课程内容丰富多彩，开阔了我的视野，激发了我对这个领域更浓厚的兴趣",
            "老师治学严谨，循循善诱，通过这门课程让我建立了完整的知识体系，培养了分析问题的能力",
            "老师授课重点突出，课程难度适中，既巩固了基础知识，又拓展了深度内容，满足了我的学习需求",
            "老师善于启发学生思考，课程注重培养实践能力和创新思维，让我不仅学到了知识，更学会了如何解决问题",
            "老师讲解详细透彻，课程安排紧凑合理，通过学习让我对该学科有了系统而全面的认识",
            "老师课堂气氛活跃，能调动学生积极性，这门课程很有启发性，培养了我的自主学习能力和探索精神",
            "老师教学认真，内容讲授清晰明确，课程与时俱进，整体学习体验非常好，让我受益匪浅"
        ]
    }

    func randomText(for type: TeacherTextQuestionType) -> String {
        let source: [String]
        switch type {
        case .inspiration: source = inspirationTexts
        case .suggestion: source = suggestionTexts
        case .overall, .general: source = overallTexts
        }
        return (source.randomElement() ?? "老师授课认真负责，课程内容充实，整体学习体验很好").replacingOccurrences(of: " ", with: "")
    }

    func isValidTextAnswer(_ text: String) -> Bool {
        if text.count < 4 { return false }
        if text.contains(" ") { return false }
        let chars = Array(text)
        guard chars.count >= 3 else { return true }
        for idx in 0..<(chars.count - 2) where chars[idx] == chars[idx + 1] && chars[idx] == chars[idx + 2] {
            return false
        }
        return true
    }
}

// MARK: - Small Helpers

private func stringValue(_ value: Any?, fallback: String = "") -> String {
    guard let value else { return fallback }
    if value is NSNull { return fallback }
    return String(describing: value)
}

private func attr(_ element: Element?, _ key: String) -> String {
    guard let element else { return "" }
    return ((try? element.attr(key)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func text(_ element: Element?) -> String {
    guard let element else { return "" }
    return ((try? element.text()) ?? "")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[captureRange])
}
