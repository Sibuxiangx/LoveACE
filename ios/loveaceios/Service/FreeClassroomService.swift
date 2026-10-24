import Foundation
import SwiftSoup
import os

nonisolated private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "FreeClassroomService")

/// 空闲教室服务：教务系统"空闲教室查询"与"教室课表"接口，接口与 Android `FreeClassroomService` 一致。
actor FreeClassroomService {
    static let baseURL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
    private static let searchPageSize = 200
    private static let maxSearchPages = 10
    private static let ajaxHeaders = [
        "X-Requested-With": "XMLHttpRequest",
        "Accept": "application/json, text/javascript, */*; q=0.01",
    ]

    private let connection: AUFEConnection

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    /// 两个校区的全部教学楼（西校 2、东校 1）。
    func loadBuildings() async -> UniResponse<[FcBuilding]> {
        do {
            let client = await connection.client!
            let url = "\(Self.baseURL)/student/teachingResources/freeClassroomQuery/TeachBuildingName"
            var buildings: [FcBuilding] = []
            for campusNo in ["2", "1"] {
                let (data, _) = try await client.post(url, formData: ["codeCamListName": campusNo], headers: Self.ajaxHeaders)
                for row in try jsonObjectArray(data) {
                    guard let id = row["id"] as? [String: Any], let no = jsonText(id["teachingBuildingNumber"]) else { continue }
                    let name = jsonText(row["teachingBuildingName"]) ?? ""
                    let remark = jsonText(row["remark"]) ?? ""
                    buildings.append(FcBuilding(
                        campusNo: campusNo,
                        campusName: Self.campusName(campusNo),
                        no: no,
                        name: name,
                        stopped: remark.contains("停用") || name.contains("停用")
                    ))
                }
            }
            return .success(buildings)
        } catch {
            logger.error("loadBuildings failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    /// 当前教学周与教室类型选项，都在查询页的静态 HTML 中。
    func loadMeta() async -> UniResponse<FcMeta> {
        do {
            let client = await connection.client!
            let (data, _) = try await client.get("\(Self.baseURL)/student/teachingResources/freeClassroomQuery/custom")
            let html = String(data: data, encoding: .utf8) ?? ""
            let week = html.firstMatch(of: /第\s*(\d+)\s*周/).flatMap { Int($0.1) }
            let doc = try SwiftSoup.parse(html)
            var types: [FcOption] = []
            for option in try doc.select("select#jslxdm option").array() {
                let code = try option.attr("value")
                guard !code.isEmpty else { continue }
                let name = try option.text().trimmingCharacters(in: .whitespaces)
                types.append(FcOption(code: code, name: name))
            }
            return .success(FcMeta(currentWeek: week, types: types))
        } catch {
            logger.error("loadMeta failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    /// 今天的当前节次（"今天"页面里的 sec）。取不到返回 nil。
    func currentSection() async -> Int? {
        do {
            let client = await connection.client!
            let (data, _) = try await client.get("\(Self.baseURL)/student/teachingResources/freeClassroom/today")
            let html = String(data: data, encoding: .utf8) ?? ""
            return html.firstMatch(of: /var sec = parseInt\('(\d+)'\)/).flatMap { Int($0.1) }
        } catch {
            logger.warning("currentSection failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// 某楼的全部教室（教室课表接口，不受周次和节次影响）。
    func listRooms(_ building: FcBuilding, typeNames: [String: String]) async -> UniResponse<[FcRoom]> {
        do {
            let client = await connection.client!
            let url = "\(Self.baseURL)/student/teachingResources/classroomCurriculum/\(building.campusNo)/\(building.no)/classroomJson"
            let (data, _) = try await client.get(url)
            let rows = try jsonObjectArray(data).compactMap { parseRoomJson($0, building: building, typeNames: typeNames) }
            return .success(FreeClassroomRules.merge(rows))
        } catch {
            logger.error("listRooms failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    /// 空闲查询：只返回所选周次与节次全部空闲的教室（服务端只给"可用"状态的房间）。按页取完，最多 maxSearchPages 页。
    func search(_ query: FcQuery, typeNames: [String: String]) async -> UniResponse<[FcRoom]> {
        do {
            let client = await connection.client!
            let url = "\(Self.baseURL)/student/teachingResources/freeClassroomQuery/search"
            let weeks = query.weeks.sorted().map(String.init).joined(separator: ",")
            let wSection = query.slots
                .sorted { ($0.weekday, $0.section) < ($1.weekday, $1.section) }
                .map { "\($0.weekday)/\($0.section)" }
                .joined(separator: ",")
            var raw: [FcRawRoom] = []
            for page in 1...Self.maxSearchPages {
                let (data, _) = try await client.post(url, formData: [
                    "weeks": weeks,
                    "jslxdm": query.typeCode,
                    "codeCampusListNumber": query.campusNo,
                    "teaNum": query.buildingNo,
                    "wSection": wSection,
                    "pageNum": String(page),
                    "pageSize": String(Self.searchPageSize),
                ], headers: Self.ajaxHeaders)
                guard let first = try jsonObjectArray(data).first else {
                    throw ServiceError.parseError("查询结果格式异常")
                }
                let total = jsonInt((first["pageContext"] as? [String: Any])?["totalCount"]) ?? 0
                let records = first["records"] as? [[String: Any]] ?? []
                raw += records.compactMap { parseSearchRecord($0, typeNames: typeNames) }
                if records.isEmpty || raw.count >= total { break }
            }
            return .success(FreeClassroomRules.merge(raw))
        } catch {
            logger.error("search failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    /// 单间教室的占用：返回 "weekday_week_section" 集合，空集合表示整周空闲。
    func occupancy(of room: FcRoom) async -> UniResponse<Set<String>> {
        do {
            let client = await connection.client!
            var components = URLComponents(string: "\(Self.baseURL)/student/teachingResources/freeClassroomQuery/classroomQuery")
            components?.queryItems = [
                URLQueryItem(name: "campusName", value: room.campusName),
                URLQueryItem(name: "teachingBuildingName", value: room.buildingName),
                URLQueryItem(name: "classroomName", value: room.number),
                URLQueryItem(name: "campusNumber", value: room.campusNo),
                URLQueryItem(name: "teachingBuildingNumber", value: room.buildingNo),
                URLQueryItem(name: "classroomNumber", value: room.number),
            ]
            guard let url = components?.url else { throw ServiceError.parseError("教室详情地址异常") }
            let (data, _) = try await client.get(url.absoluteString)
            let html = String(data: data, encoding: .utf8) ?? ""
            let doc = try SwiftSoup.parse(html)
            guard let value = try doc.getElementById("wsSection")?.attr("value") else {
                throw ServiceError.parseError("占用信息缺失")
            }
            let tokens = value.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .success(Set(tokens))
        } catch {
            logger.error("occupancy failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Parsing

    private func parseRoomJson(_ obj: [String: Any], building: FcBuilding, typeNames: [String: String]) -> FcRawRoom? {
        guard let id = obj["id"] as? [String: Any], let number = jsonText(id["classroomNumber"]) else { return nil }
        let typeCode = jsonText(obj["classroomTypeCode"])
        return FcRawRoom(
            campusNo: building.campusNo,
            campusName: building.campusName,
            buildingNo: building.no,
            buildingName: building.name,
            number: number,
            name: jsonText(obj["classroomName"]) ?? number,
            statusCode: jsonText(obj["classroomStatusCode"]) ?? "",
            typeCode: typeCode,
            typeName: typeCode.flatMap { typeNames[$0] },
            seats: jsonInt(obj["placeNum"])
        )
    }

    private func parseSearchRecord(_ obj: [String: Any], typeNames: [String: String]) -> FcRawRoom? {
        guard let id = obj["id"] as? [String: Any], let number = jsonText(id["classroomNumber"]) else { return nil }
        let typeCode = jsonText(obj["classroomTypeCode"])
        return FcRawRoom(
            campusNo: jsonText(id["campusNumber"]) ?? "",
            campusName: jsonText(obj["campusName"]) ?? "",
            buildingNo: jsonText(id["teachingBuildingNumber"]) ?? "",
            buildingName: jsonText(obj["teachingBuildingName"]) ?? "",
            number: number,
            name: jsonText(obj["classroomName"]) ?? number,
            statusCode: jsonText(obj["classroomStatusCode"]) ?? "",
            typeCode: typeCode,
            typeName: jsonText(obj["classroomTypeName"]) ?? typeCode.flatMap { typeNames[$0] },
            seats: jsonInt(obj["classNumberOfSeats"])
        )
    }

    private static func campusName(_ campusNo: String) -> String {
        switch campusNo {
        case "2": return "西校"
        case "1": return "东校"
        default: return campusNo
        }
    }
}
