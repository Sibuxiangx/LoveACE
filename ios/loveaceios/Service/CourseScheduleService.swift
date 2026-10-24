import Foundation
import SwiftSoup
import os

nonisolated private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "CourseScheduleService")

/// 下拉选项（学期、开课院系、校区、教学楼、课程类别）。
struct CourseScheduleOption: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    /// 仅学期列表使用：页面默认选中的学期
    var isSelected: Bool = false

    var id: String { code }
}

/// 学期与下拉选项。页面里缺少对应 select 时列表为空，UI 据此隐藏该筛选项。
struct CourseScheduleIndex: Sendable {
    let terms: [CourseScheduleOption]
    let departments: [CourseScheduleOption]
    let campuses: [CourseScheduleOption]
    let buildings: [CourseScheduleOption]
    let categories: [CourseScheduleOption]
}

/// 查询条件。空字符串或 nil 表示不限。
struct CourseScheduleQuery: Equatable, Sendable {
    var termCode: String
    var courseNo = ""
    var courseName = ""
    var teacher = ""
    var departmentCode = ""
    var campusCode = ""
    var buildingCode = ""
    var categoryCode = ""
    var weekday: Int?
    var startSection: Int?
}

struct CourseSchedulePage: Sendable {
    let records: [CourseScheduleRecord]
    let totalCount: Int
}

/// 课程开课查询：学期与筛选项来自 index 页，结果按页请求（每页 20 条）。接口与 Android `CourseScheduleService` 一致。
actor CourseScheduleService {
    static let baseURL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
    static let pageSize = 20

    private let connection: AUFEConnection

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    func loadIndex() async -> UniResponse<CourseScheduleIndex> {
        do {
            let client = await connection.client!
            let (data, _) = try await client.get("\(Self.baseURL)/student/integratedQuery/course/courseSchdule/index")
            let html = String(data: data, encoding: .utf8) ?? ""
            let doc = try SwiftSoup.parse(html)
            let terms = try options(in: doc, name: "zxjxjhh", includeSelection: true)
            guard !terms.isEmpty else { throw ServiceError.parseError("未能解析出任何学期信息") }
            let departments = try options(in: doc, name: "kkxsh")
            let campuses = try options(in: doc, name: "kkxqh")
            let buildings = try options(in: doc, name: "jxlh")
            let categories = try options(in: doc, name: "kclb")
            return .success(CourseScheduleIndex(
                terms: terms,
                departments: departments,
                campuses: campuses,
                buildings: buildings,
                categories: categories
            ))
        } catch {
            logger.error("loadIndex failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    /// 分页查询开课记录。调用方在列表接近末尾时请求下一页，不做整学期全量拉取。
    func queryPage(_ query: CourseScheduleQuery, pageNum: Int, pageSize: Int = CourseScheduleService.pageSize) async -> UniResponse<CourseSchedulePage> {
        do {
            let client = await connection.client!
            let url = "\(Self.baseURL)/student/integratedQuery/course/courseSchdule/courseInfo?sf_request_type=ajax"
            let form: [String: String] = [
                "zxjxjhh": query.termCode,
                "kch": query.courseNo,
                "kcm": query.courseName,
                "kkxsh": query.departmentCode,
                "kkxqh": query.campusCode,
                "jxlh": query.buildingCode,
                "jash": "",
                "skxq": query.weekday.map { String($0) } ?? "",
                "skjc": query.startSection.map { String($0) } ?? "",
                "kclb": query.categoryCode,
                "skjs": query.teacher,
                "xqname": "",
                "jcname": "",
                "jxlname": "",
                "jasname": "",
                "pageNum": String(pageNum),
                "pageSize": String(pageSize),
            ]
            let (data, _) = try await client.post(url, formData: form, headers: Self.ajaxHeaders)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["list"] as? [String: Any] else {
                throw ServiceError.parseError("开课查询结果格式异常")
            }
            let pageContext = list["pageContext"] as? [String: Any]
            let total = jsonInt(pageContext?["totalCount"]) ?? jsonInt(list["totalCount"]) ?? 0
            let rows = list["records"] as? [[String: Any]] ?? []
            return .success(CourseSchedulePage(records: rows.map(Self.parseRecord), totalCount: total))
        } catch {
            logger.error("queryPage failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private static let ajaxHeaders = [
        "X-Requested-With": "XMLHttpRequest",
        "Accept": "application/json, text/javascript, */*; q=0.01",
    ]

    // MARK: - Parsing

    private func options(in doc: Document, name: String, includeSelection: Bool = false) throws -> [CourseScheduleOption] {
        guard let select = try doc.select("select#\(name)").first() ?? doc.select("select[name=\(name)]").first() else {
            return []
        }
        var result: [CourseScheduleOption] = []
        for option in try select.select("option").array() {
            let code = try option.attr("value")
            guard !code.isEmpty else { continue }
            let label = try option.text().trimmingCharacters(in: .whitespaces)
            let selected = includeSelection && option.hasAttr("selected")
            result.append(CourseScheduleOption(code: code, name: label, isSelected: selected))
        }
        return result
    }

    private static func parseRecord(_ obj: [String: Any]) -> CourseScheduleRecord {
        CourseScheduleRecord(
            kch: jsonText(obj["kch"]), kxh: jsonText(obj["kxh"]),
            kcm: jsonText(obj["kcm"]), xf: jsonInt(obj["xf"]),
            xs: jsonInt(obj["xs"]), kkxsjc: jsonText(obj["kkxsjc"]),
            kslxmc: jsonText(obj["kslxmc"]), skjs: jsonText(obj["skjs"]),
            bkskrl: jsonInt(obj["bkskrl"]), bkskyl: jsonInt(obj["bkskyl"]),
            xkmssm: jsonText(obj["xkmssm"]), kkxqm: jsonText(obj["kkxqm"]),
            skzc: jsonText(obj["skzc"]), skxq: jsonInt(obj["skxq"]),
            skjc: jsonInt(obj["skjc"]), cxjc: jsonInt(obj["cxjc"]),
            zcsm: jsonText(obj["zcsm"]), kclbmc: jsonText(obj["kclbmc"]),
            xqm: jsonText(obj["xqm"]), jxlm: jsonText(obj["jxlm"]),
            jasm: jsonText(obj["jasm"]), mxbj: jsonText(obj["mxbj"]),
            xss: jsonInt(obj["xss"])
        )
    }
}
