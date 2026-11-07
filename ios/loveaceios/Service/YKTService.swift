import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "YKTService")

actor YKTService {
    private let connection: AUFEConnection
    static let baseURL = "http://ykt-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118"

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    func initSession() async -> UniResponse<Void> {
        do {
            let client = await connection.client!
            _ = try await client.get("\(Self.baseURL)/casLogin.jsp")
            return .success(())
        } catch {
            logger.error("initSession failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getBalance() async -> UniResponse<CardBalance> {
        do {
            let client = await connection.client!
            let (data, _) = try await client.get("\(Self.baseURL)/queryUserBalances.action")
            let html = String(data: data, encoding: .utf8) ?? ""
            let patterns = [
                "余额[：:]?\\s*</label>\\s*<label>\\s*([\\d.]+)\\s*元",
                "余额[：:]?\\s*([\\d.]+)\\s*元"
            ]
            var balanceStr: String?
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let range = Range(match.range(at: 1), in: html) {
                    balanceStr = String(html[range])
                    break
                }
            }
            guard let bs = balanceStr, let balance = Double(bs) else {
                throw ServiceError.parseError("无法解析余额")
            }
            return .success(CardBalance(balance: balance, balanceText: "\(bs)元"))
        } catch {
            logger.error("getBalance failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Electricity Payment

    func getPageInfo() async -> UniResponse<StudentInfo> {
        do {
            let client = await connection.client!
            let (data, _) = try await client.get("\(Self.baseURL)/utilityUnBindUserPowerPayInit.action")
            let html = String(data: data, encoding: .utf8) ?? ""
            return .success(StudentInfo.fromHTML(html))
        } catch {
            logger.error("getPageInfo failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getDormList() async -> UniResponse<[SelectOption]> { await getOptions(dormId: "", buildingId: "", floorId: "", dormName: "") }
    func getBuildingList(dormId: String, dormName: String) async -> UniResponse<[SelectOption]> { await getOptions(dormId: dormId, buildingId: "", floorId: "", dormName: dormName) }
    func getFloorList(dormId: String, buildingId: String, dormName: String) async -> UniResponse<[SelectOption]> { await getOptions(dormId: dormId, buildingId: buildingId, floorId: "", dormName: dormName) }
    func getRoomList(dormId: String, buildingId: String, floorId: String, dormName: String) async -> UniResponse<[SelectOption]> { await getOptions(dormId: dormId, buildingId: buildingId, floorId: floorId, dormName: dormName) }

    private func getOptions(dormId: String, buildingId: String, floorId: String, dormName: String) async -> UniResponse<[SelectOption]> {
        do {
            let client = await connection.client!
            let (data, _) = try await client.post("\(Self.baseURL)/utilitBindXiaoQuData.action",
                                                   formData: ["dormId": dormId, "buildingId": buildingId, "floorId": floorId, "dormName": dormName])
            let body = String(data: data, encoding: .utf8) ?? ""
            return .success(SelectOption.parseList(body))
        } catch {
            logger.error("getOptions failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func payElectricity(request: UtilityPaymentRequest) async -> UniResponse<UtilityPaymentResult> {
        do {
            let client = await connection.client!
            logger.info("payElectricity request: \(request.toFormData())")
            let (data, _) = try await client.post("\(Self.baseURL)/utilityUnBindUserPowerPay.action", formData: request.toFormData())
            let html = String(data: data, encoding: .utf8) ?? ""
            logger.info("payElectricity response length: \(html.count)")
            logger.info("payElectricity response preview: \(String(html.prefix(500)))")
            let result = UtilityPaymentResult.fromHTML(html)
            logger.info("payElectricity result: success=\(result.success), message=\(result.message)")
            return .success(result)
        } catch {
            logger.error("payElectricity failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getPurchaseHistory(startDate: String, endDate: String) async -> UniResponse<ElectricPurchaseQueryResult> {
        do {
            let client = await connection.client!
            let (data, _) = try await client.post("\(Self.baseURL)/utilityQueryRunningAccountInfo.action",
                                                   formData: ["startDate": "\(startDate) 00:00:00", "endDate": "\(endDate) 23:59:59"])
            let html = String(data: data, encoding: .utf8) ?? ""
            return .success(Self.parsePurchaseHistory(html: html, startDate: startDate, endDate: endDate))
        } catch {
            logger.error("getPurchaseHistory failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    private static func parsePurchaseHistory(html: String, startDate: String, endDate: String) -> ElectricPurchaseQueryResult {
        var records: [ElectricPurchaseRecord] = []
        let pattern = "<tr>\\s*<td>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td[^>]*>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td[^>]*>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*</tr>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return ElectricPurchaseQueryResult(startDate: startDate, endDate: endDate, records: [])
        }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            var groups: [String] = []
            for i in 1...7 {
                guard let range = Range(match.range(at: i), in: html) else { groups.append(""); continue }
                groups.append(String(html[range]).trimmingCharacters(in: .whitespaces))
            }
            guard groups[0] != "姓名", !groups[0].isEmpty else { continue }
            records.append(ElectricPurchaseRecord(
                name: groups[0], studentId: groups[1], area: groups[2], roomInfo: groups[3],
                amount: Double(groups[4]) ?? 0.0, purchaseDate: groups[5], department: groups[6]
            ))
        }
        return ElectricPurchaseQueryResult(startDate: startDate, endDate: endDate, records: records)
    }
}
