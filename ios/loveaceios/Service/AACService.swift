import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "AACService")

actor AACService {
    private let connection: AUFEConnection
    private var ticket: String?
    static let baseURL = "http://api-dekt-ac-acxk-net.vpn2.aufe.edu.cn:8118"
    static let loginServiceURL = "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.dekt.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue"

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
        var callbackBaseUrl: String?

        while redirectCount < 20 {
            let (data, response) = try await noRedirectClient.get(nextUrl)
            let code = response.statusCode
            let location = response.value(forHTTPHeaderField: "Location")
            logger.info("fetchTicket[\(redirectCount)]: code=\(code), location=\(location?.prefix(120) ?? "nil")")

            if (301...308).contains(code), let location = location {
                nextUrl = location
                if nextUrl.contains("CoreLoginCallback") && callbackBaseUrl == nil {
                    callbackBaseUrl = nextUrl
                }
                if nextUrl.contains("register?ticket=") || nextUrl.contains("#/register?ticket=") {
                    if let ticketRange = nextUrl.range(of: "ticket=([^&#]+)", options: .regularExpression) {
                        let ticketStr = String(nextUrl[ticketRange]).replacingOccurrences(of: "ticket=", with: "")
                        let decoded = ticketStr.removingPercentEncoding ?? ticketStr
                        logger.info("fetchTicket: found app ticket")

                        let client = await connection.client!
                        logger.info("fetchTicket: establishing AAC session via CAS redirect...")
                        _ = try? await client.get(Self.loginServiceURL)
                        return decoded
                    }
                }
                redirectCount += 1
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.info("fetchTicket: final response code=\(code), body length=\(body.count)")
                if let ticketRange = body.range(of: "ticket=([^&\"#'\\s]+)", options: .regularExpression) {
                    let ticketStr = String(body[ticketRange]).replacingOccurrences(of: "ticket=", with: "")
                    let decoded = ticketStr.removingPercentEncoding ?? ticketStr
                    logger.info("fetchTicket: found ticket in body")
                    return decoded
                }
                break
            }
        }
        logger.warning("fetchTicket: no ticket found after \(redirectCount) redirects")
        return nil
    }

    private func apiHeaders() async -> [String: String] {
        var headers: [String: String] = [:]
        if let t = ticket { headers["ticket"] = t }
        if let twf = await connection.twfId { headers["sdp-app-session"] = twf }
        return headers
    }

    func getCreditInfo() async -> UniResponse<AACCreditInfo> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取AAC ticket") }
            let client = await connection.simpleClient!
            let headers = await apiHeaders()
            let (data, response) = try await client.post(
                "\(Self.baseURL)/User/Center/DoGetScoreInfo?sf_request_type=ajax",
                formData: [:], headers: headers
            )
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.info("getCreditInfo: HTTP \(response.statusCode)")
            if response.statusCode != 200 {
                logger.error("getCreditInfo 500 body: \(body.prefix(800))")
                throw ServiceError.parseError("HTTP \(response.statusCode)")
            }
            guard let jsonData = body.data(using: .utf8),
                  let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let code = root["code"] as? Int, code == 0,
                  let dataObj = root["data"] as? [String: Any] else {
                throw ServiceError.parseError("响应格式错误")
            }
            let info = AACCreditInfo(
                totalScore: dataObj["TotalScore"] as? Double ?? 0.0,
                isTypeAdopt: dataObj["IsTypeAdopt"] as? Bool ?? false,
                typeAdoptResult: dataObj["TypeAdoptResult"] as? String ?? ""
            )
            return .success(info)
        } catch {
            logger.error("getCreditInfo failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getCreditList() async -> UniResponse<[AACCreditCategory]> {
        do {
            try await ensureTicket()
            guard ticket != nil else { throw ServiceError.parseError("无法获取AAC ticket") }
            let client = await connection.simpleClient!
            let headers = await apiHeaders()
            let (data, response) = try await client.post(
                "\(Self.baseURL)/User/Center/DoGetScoreList?sf_request_type=ajax",
                formData: ["pageIndex": "1", "pageSize": "100"], headers: headers
            )
            guard response.statusCode == 200 else { throw ServiceError.parseError("HTTP \(response.statusCode)") }
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let code = root["code"] as? Int, code == 0 else {
                throw ServiceError.parseError("响应格式错误")
            }
            guard let listData = root["data"] else { throw ServiceError.parseError("响应缺少data字段") }
            let listJsonData = try JSONSerialization.data(withJSONObject: listData)
            let categories = try JSONDecoder().decode([AACCreditCategory].self, from: listJsonData)
            return .success(categories)
        } catch {
            logger.error("getCreditList failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }
}
