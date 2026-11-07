import Foundation
import SwiftSoup
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "ISIMService")

actor ISIMService {
    private let connection: AUFEConnection
    private var isimClient: HTTPClient?
    private var jsessionId: String?
    private var sessionInitialized = false
    static let baseURL = "http://hqkd-aufe-edu-cn.vpn2.aufe.edu.cn"

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    private func ensureSession() async throws {
        if sessionInitialized && jsessionId != nil { return }
        let mainClient = await connection.client!
        let client = HTTPClient(baseUrl: Self.baseURL, timeoutInterval: 90, cookieStorage: mainClient.cookieStorage)
        self.isimClient = client
        let userId = await connection.userId
        let url = "\(Self.baseURL)/go?openid=\(userId)&sn=sn"
        let (_, response) = try await client.get(url)
        if let respUrl = response.url?.absoluteString,
           let range = respUrl.range(of: "jsessionid=([^?&;]+)", options: [.regularExpression, .caseInsensitive]) {
            jsessionId = String(respUrl[range]).replacingOccurrences(of: "jsessionid=", with: "", options: .caseInsensitive)
        }
        logger.info("ISIM session: jsessionId=\(self.jsessionId ?? "nil")")
        guard jsessionId != nil else { throw ServiceError.parseError("无法获取 JSESSIONID") }
        sessionInitialized = true
    }

    private func sessionHeaders() async -> [String: String] {
        let twfId = await connection.twfId ?? ""
        var cookie = "TWFID=\(twfId)"
        if let jid = jsessionId { cookie = "JSESSIONID=\(jid); \(cookie)" }
        return ["Cookie": cookie]
    }

    func getBuildings() async -> UniResponse<[[String: String]]> {
        do {
            try await ensureSession()
            guard let client = isimClient else { throw ServiceError.emptyResponse }
            let headers = await sessionHeaders()
            let (data, _) = try await client.get("\(Self.baseURL)/about", headers: headers)
            let html = String(data: data, encoding: .utf8) ?? ""
            let doc = try SwiftSoup.parse(html)
            var buildings: [[String: String]] = []
            for script in try doc.select("script").array() {
                let content = try script.data()
                guard content.contains("pickerBuilding") else { continue }
                if let valuesMatch = content.range(of: "values:\\s*\\[(.*?)\\]", options: .regularExpression),
                   let displayMatch = content.range(of: "displayValues:\\s*\\[(.*?)\\]", options: .regularExpression) {
                    let valuesStr = String(content[valuesMatch]).replacingOccurrences(of: "values:", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                    let displaysStr = String(content[displayMatch]).replacingOccurrences(of: "displayValues:", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                    let values = valuesStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "") }
                    let displays = displaysStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "") }
                    for i in 0..<min(values.count, displays.count) {
                        let code = values[i], name = displays[i]
                        if !code.isEmpty && !name.isEmpty && name != "请选择" {
                            buildings.append(["code": code, "name": name])
                        }
                    }
                }
                break
            }
            return .success(buildings)
        } catch {
            logger.error("getBuildings failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getFloors(buildingCode: String) async -> UniResponse<[[String: String]]> {
        do {
            try await ensureSession()
            guard let client = isimClient else { throw ServiceError.emptyResponse }
            var headers = await sessionHeaders()
            headers["X-Requested-With"] = "XMLHttpRequest"
            let (data, _) = try await client.get("\(Self.baseURL)/about/floors/\(buildingCode)", headers: headers)
            let body = String(data: data, encoding: .utf8) ?? "[]"
            logger.info("getFloors(\(buildingCode)): body=\(body.prefix(300))")
            return .success(parseFloorRoomJSON(body, codeKey: "floordm", nameKey: "floorname"))
        } catch {
            logger.error("getFloors failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getRooms(floorCode: String) async -> UniResponse<[[String: String]]> {
        do {
            try await ensureSession()
            guard let client = isimClient else { throw ServiceError.emptyResponse }
            var headers = await sessionHeaders()
            headers["X-Requested-With"] = "XMLHttpRequest"
            let (data, _) = try await client.get("\(Self.baseURL)/about/rooms/\(floorCode)", headers: headers)
            let body = String(data: data, encoding: .utf8) ?? "[]"
            return .success(parseFloorRoomJSON(body, codeKey: "roomdm", nameKey: "roomname"))
        } catch {
            logger.error("getRooms failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    func getElectricityInfo(roomCode: String, displayText: String? = nil) async -> UniResponse<ElectricityInfo> {
        do {
            try await ensureSession()
            guard let client = isimClient else { throw ServiceError.emptyResponse }
            let userId = await connection.userId
            let headers = await sessionHeaders()
            _ = try await client.post("\(Self.baseURL)/about/rebinding", formData: [
                "roomdm": roomCode, "room": displayText ?? roomCode,
                "openid": userId, "sn": "sn", "mode": "u"
            ], headers: headers)

            async let usageResult = client.get("\(Self.baseURL)/use/record", headers: headers)
            async let paymentResult = client.get("\(Self.baseURL)/pay/record", headers: headers)
            let (usageData, _) = try await usageResult
            let (paymentData, _) = try await paymentResult
            let usageHtml = String(data: usageData, encoding: .utf8) ?? ""
            let paymentHtml = String(data: paymentData, encoding: .utf8) ?? ""

            let balance = parseBalance(usageHtml)
            let usageRecords = parseUsageRecords(usageHtml)
            let paymentRecords = parsePaymentRecords(paymentHtml)
            return .success(ElectricityInfo(balance: balance, usageRecords: usageRecords, payments: paymentRecords))
        } catch {
            logger.error("getElectricityInfo failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    private func parseFloorRoomJSON(_ body: String, codeKey: String, nameKey: String) -> [[String: String]] {
        var result: [[String: String]] = []
        let normalized = body.replacingOccurrences(of: "([a-zA-Z_][a-zA-Z0-9_]*)\\s*:", with: "\"$1\":", options: .regularExpression)
        guard let data = normalized.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let obj = arr.first,
              let codes = obj[codeKey] as? [Any],
              let names = obj[nameKey] as? [Any] else { return result }
        let count = min(codes.count, names.count)
        guard count > 1 else { return result }
        for i in 1..<count {
            let code = "\(codes[i])"
            let name = "\(names[i])"
            guard !code.isEmpty, name != "请选择" else { continue }
            result.append(["code": code, "name": name])
        }
        return result
    }

    private func parseBalance(_ html: String) -> ElectricityBalance {
        var purchased = 0.0, subsidy = 0.0
        guard let doc = try? SwiftSoup.parse(html) else { return ElectricityBalance() }
        let selectors = "li.item-content, li.item, .item-content"
        guard let items = try? doc.select(selectors) else { return ElectricityBalance() }
        for item in items {
            guard let title = try? item.select(".item-title, .title, dt, .label").first()?.text().trimmingCharacters(in: .whitespaces),
                  let value = try? item.select(".item-after, .value, dd, .amount").first()?.text().trimmingCharacters(in: .whitespaces) else { continue }
            guard let amountMatch = value.range(of: "([\\d.]+)", options: .regularExpression),
                  let amount = Double(value[amountMatch]) else { continue }
            if title.contains("购电") { purchased = amount }
            else if title.contains("补助") { subsidy = amount }
        }
        return ElectricityBalance(remainingPurchased: purchased, remainingSubsidy: subsidy)
    }

    private func parseUsageRecords(_ html: String) -> [ElectricityUsageRecord] {
        guard let doc = try? SwiftSoup.parse(html),
              let items = try? doc.select("#divRecord ul li") else { return [] }
        return items.compactMap { item in
            guard let time = try? item.select(".item-title").first()?.text().trimmingCharacters(in: .whitespaces),
                  let usageText = try? item.select(".item-after").first()?.text().trimmingCharacters(in: .whitespaces),
                  let usageMatch = usageText.range(of: "([\\d.]+)度", options: .regularExpression) else { return nil }
            let usageStr = usageText[usageMatch].replacingOccurrences(of: "度", with: "")
            guard let usage = Double(usageStr) else { return nil }
            let meterText = (try? item.select(".item-subtitle").first()?.text().trimmingCharacters(in: .whitespaces)) ?? ""
            let meter = meterText.range(of: "电表:\\s*(.+)", options: .regularExpression).map { String(meterText[$0]).replacingOccurrences(of: "电表:", with: "").trimmingCharacters(in: .whitespaces) } ?? meterText
            return ElectricityUsageRecord(recordTime: time, usageAmount: usage, meterName: meter)
        }
    }

    private func parsePaymentRecords(_ html: String) -> [PaymentRecord] {
        guard let doc = try? SwiftSoup.parse(html),
              let items = try? doc.select("#divRecord ul li") else { return [] }
        return items.compactMap { item in
            guard let time = try? item.select(".item-title").first()?.text().trimmingCharacters(in: .whitespaces),
                  let amountText = try? item.select(".item-after").first()?.text().trimmingCharacters(in: .whitespaces),
                  let amountMatch = amountText.range(of: "(-?[\\d.]+)元", options: .regularExpression) else { return nil }
            let amountStr = amountText[amountMatch].replacingOccurrences(of: "元", with: "")
            guard let amount = Double(amountStr) else { return nil }
            let typeText = (try? item.select(".item-subtitle").first()?.text().trimmingCharacters(in: .whitespaces)) ?? ""
            let payType = typeText.range(of: "类型:\\s*(.+)", options: .regularExpression).map { String(typeText[$0]).replacingOccurrences(of: "类型:", with: "").trimmingCharacters(in: .whitespaces) } ?? typeText
            return PaymentRecord(paymentTime: time, amount: amount, paymentType: payType)
        }
    }
}
