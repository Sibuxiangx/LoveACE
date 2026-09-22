import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "LaborClubService")

actor LaborClubService {
    private let connection: AUFEConnection
    private var ticket: String?
    static let baseURL = "http://api-ldjlb-ac-acxk-net.vpn2.aufe.edu.cn:8118"
    static let loginServiceURL = "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.ldjlb.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue"
    private static let formURLEncodedUTF8 = "application/x-www-form-urlencoded;charset=UTF-8"

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    private func ensureTicket() async throws {
        if ticket != nil { return }
        ticket = try await fetchTicket()
    }

    private func fetchTicket() async throws -> String? {
        var nextUrl = Self.loginServiceURL
        var redirectCount = 0
        let noRedirectClient = await connection.noRedirectClient!
        while redirectCount < 20 {
            let (data, response) = try await noRedirectClient.get(nextUrl)
            let code = response.statusCode
            let location = response.value(forHTTPHeaderField: "Location")
            if (301...308).contains(code), let location = location {
                nextUrl = location
                if nextUrl.contains("register?ticket=") || nextUrl.contains("#/register?ticket="),
                   let range = nextUrl.range(of: "ticket=([^&#]+)", options: .regularExpression) {
                    let ticketStr = String(nextUrl[range]).replacingOccurrences(of: "ticket=", with: "")
                    return ticketStr.removingPercentEncoding ?? ticketStr
                }
                redirectCount += 1
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                if let range = body.range(of: "ticket=([^&\"#'\\s]+)", options: .regularExpression) {
                    let ticketStr = String(body[range]).replacingOccurrences(of: "ticket=", with: "")
                    return ticketStr.removingPercentEncoding ?? ticketStr
                }
                break
            }
        }
        return nil
    }

    private func apiHeaders() async -> [String: String] {
        var headers: [String: String] = [:]
        if let t = ticket { headers["ticket"] = t }
        if let twf = await connection.twfId { headers["sdp-app-session"] = twf }
        return headers
    }

    private func parseRoot(_ body: String) throws -> [String: Any] {
        guard let data = body.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.parseError("响应格式错误")
        }
        let code = root["code"] as? Int
        if code != 0 {
            let msg = root["msg"] as? String ?? ""
            throw ServiceError.parseError("服务器返回错误代码: \(code ?? -1), msg: \(msg)")
        }
        return root
    }

    private func decodeRows<T: Decodable>(_ root: [String: Any], type: T.Type) throws -> [T] {
        let dataElement = root["data"]
        let rows: Any
        if let arr = dataElement as? [Any] { rows = arr }
        else if let obj = dataElement as? [String: Any], let r = obj["rows"] { rows = r }
        else { rows = [] as [Any] }
        let jsonData = try JSONSerialization.data(withJSONObject: rows)
        return try JSONDecoder().decode([T].self, from: jsonData)
    }

    func getProgress() async -> UniResponse<LaborClubProgressInfo> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Center/DoGetScoreInfo", formData: [:], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            let root = try parseRoot(body)
            guard let dataObj = root["data"] else { throw ServiceError.parseError("缺少data") }
            let jsonData = try JSONSerialization.data(withJSONObject: dataObj)
            let info = try JSONDecoder().decode(LaborClubProgressInfo.self, from: jsonData)
            return .success(info)
        } catch {
            logger.error("getProgress: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getJoinedActivities() async -> UniResponse<[LaborClubActivity]> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Activity/DoGetJoinPageList",
                                                   formData: ["pageIndex": "1", "pageSize": "100"], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            let root = try parseRoot(body)
            return .success(try decodeRows(root, type: LaborClubActivity.self))
        } catch {
            logger.error("getJoinedActivities: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getJoinedClubs() async -> UniResponse<[LaborClubInfo]> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Club/DoGetJoinList", formData: [:], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            let root = try parseRoot(body)
            return .success(try decodeRows(root, type: LaborClubInfo.self))
        } catch {
            logger.error("getJoinedClubs: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getClubDirectory() async -> UniResponse<[LaborClubDirectoryItem]> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let pageSize = 100
            var pageIndex = 1
            var totalItemCount = Int.max
            var clubs: [LaborClubDirectoryItem] = []

            while clubs.count < totalItemCount {
                var headers = await apiHeaders()
                headers["Content-Type"] = Self.formURLEncodedUTF8
                let (data, _) = try await client.post(
                    "\(Self.baseURL)/User/Club/DoGetPageList?sf_request_type=ajax",
                    formData: ["pageIndex": "\(pageIndex)", "pageSize": "\(pageSize)"],
                    headers: headers
                )
                let root = try parseRoot(String(data: data, encoding: .utf8) ?? "")
                let rows = rowsFrom(root)
                let pageInfo = root["pageInfo"] as? [String: Any]
                totalItemCount = pageInfo?["TotalItemCount"] as? Int ?? clubs.count + rows.count
                let pageData = try JSONSerialization.data(withJSONObject: rows)
                clubs.append(contentsOf: try JSONDecoder().decode([LaborClubDirectoryItem].self, from: pageData))
                if rows.isEmpty || pageIndex >= 1_000 { break }
                pageIndex += 1
            }

            var seen = Set<String>()
            let uniqueClubs = clubs.filter {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seen.insert($0.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
            }
            return .success(uniqueClubs)
        } catch {
            logger.error("getClubDirectory: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getLatestClubApplication() async -> UniResponse<LaborClubApplication?> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post(
                "\(Self.baseURL)/User/Center/DoGetApplyClubList",
                formData: ["pageIndex": "1", "pageSize": "10"],
                headers: await apiHeaders()
            )
            let root = try parseRoot(String(data: data, encoding: .utf8) ?? "")
            let jsonData = try JSONSerialization.data(withJSONObject: rowsFrom(root))
            let applications = try JSONDecoder().decode([LaborClubApplication].self, from: jsonData)
            return .success(latestLaborClubApplication(applications))
        } catch {
            logger.error("getLatestClubApplication: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func applyClub(clubId: String, reason: String) async -> UniResponse<String> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post(
                "\(Self.baseURL)/User/Club/DoApplyJoin",
                formData: ["clubID": clubId, "Reason": reason],
                headers: await apiHeaders()
            )
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ServiceError.parseError("响应格式错误")
            }
            let code = root["code"] as? Int
            let message = (root["msg"] as? String) ?? ""
            if code == 0 {
                return .success(message.isEmpty ? "申请已提交" : message, message: message)
            }
            return .failure(message.isEmpty ? "申请提交失败" : message)
        } catch {
            logger.error("applyClub: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getClubActivities(clubId: String) async -> UniResponse<[LaborClubActivity]> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Activity/DoGetPageList",
                                                   formData: ["clubID": clubId, "pageIndex": "1", "pageSize": "100"], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            let root = try parseRoot(body)
            return .success(try decodeRows(root, type: LaborClubActivity.self))
        } catch {
            logger.error("getClubActivities: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func applyActivity(activityId: String) async -> UniResponse<String> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Activity/DoApplyJoin",
                                                   formData: ["activityID": activityId, "reason": ""], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw ServiceError.parseError("响应格式错误")
            }
            let code = root["code"] as? Int
            let msg = root["msg"] as? String ?? "报名成功"
            if code != 0 { return .failure(msg) }
            return .success(msg, message: msg)
        } catch {
            logger.error("applyActivity: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getSignList(activityId: String) async -> UniResponse<[SignItem]> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Activity/DoGetSignList",
                                                   formData: ["activityID": activityId, "type": "1", "pageIndex": "1", "pageSize": "100"], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            let root = try parseRoot(body)
            let dataElement = root["data"]
            let rows: Any = (dataElement as? [Any]) ?? ([] as [Any])
            let jsonData = try JSONSerialization.data(withJSONObject: rows)
            return .success(try JSONDecoder().decode([SignItem].self, from: jsonData))
        } catch {
            logger.error("getSignList: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getActivityDetail(activityId: String) async -> UniResponse<ActivityDetail> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Activity/DoGetDetail",
                                                   formData: ["id": activityId], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            let root = try parseRoot(body)
            guard let dataObj = root["data"] as? [String: Any] else { throw ServiceError.parseError("缺少data") }
            let formDataArr = root["formData"] as? [[String: Any]] ?? []
            let teacherArr = root["teacherList"] as? [[String: Any]] ?? []

            let formFields: [ActivityFormField] = formDataArr.compactMap { obj in
                guard let id = obj["ID"] as? String, let name = obj["Name"] as? String else { return nil }
                return ActivityFormField(fieldId: id, name: name, value: obj["Value"] as? String ?? "",
                                         isMust: obj["IsMust"] as? Bool ?? false, fieldType: obj["FieldType"] as? Int ?? 1)
            }
            let teachers: [ActivityTeacher] = teacherArr.compactMap { obj in
                guard let name = obj["UserName"] as? String else { return nil }
                return ActivityTeacher(userName: name, userNo: obj["UserNo"] as? String ?? "")
            }

            let detail = ActivityDetail(
                id: dataObj["ID"] as? String ?? activityId,
                title: dataObj["Title"] as? String ?? "",
                startTime: dataObj["StartTime"] as? String ?? "",
                endTime: dataObj["EndTime"] as? String ?? "",
                chargeUserName: dataObj["ChargeUserName"] as? String ?? "",
                clubName: dataObj["ClubName"] as? String ?? "",
                memberNum: dataObj["MemberNum"] as? Int ?? 0,
                peopleNum: dataObj["PeopleNum"] as? Int ?? 0,
                signUpStartTime: dataObj["SignUpStartTime"] as? String ?? "",
                signUpEndTime: dataObj["SignUpEndTime"] as? String ?? "",
                formData: formFields, teacherList: teachers
            )
            return .success(detail)
        } catch {
            logger.error("getActivityDetail: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func scanSignIn(qrData: String, location: String) async -> UniResponse<SignInResponse> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取劳动俱乐部 ticket") }
            let client = await connection.simpleClient!
            let (data, _) = try await client.post("\(Self.baseURL)/User/Center/DoScanSignQRImage",
                                                   formData: ["content": qrData, "location": location], headers: await apiHeaders())
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8) else { throw ServiceError.emptyResponse }
            let result = try JSONDecoder().decode(SignInResponse.self, from: jsonData)
            return .success(result)
        } catch {
            logger.error("scanSignIn: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    static let defaultClubApplicationReason = "希望加入俱乐部参与劳动实践活动。"

    private func rowsFrom(_ root: [String: Any]) -> [Any] {
        if let rows = root["data"] as? [Any] { return rows }
        if let data = root["data"] as? [String: Any], let rows = data["rows"] as? [Any] { return rows }
        return []
    }
}
