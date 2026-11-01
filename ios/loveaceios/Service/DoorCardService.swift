import Foundation
import CommonCrypto
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "DoorCardService")

actor DoorCardService {
    static let baseURL = "https://www.spoyn.cn"

    func login(userno: String, username: String, rawPassword: String) async -> UniResponse<DoorCardUserInfo> {
        do {
            let md5Password = md5(rawPassword).uppercased()
            let url = "\(Self.baseURL)/ble/loginOn?openid=&username=\(username)&userno=\(userno)&password=\(md5Password)"
            guard let requestURL = URL(string: url) else { throw ServiceError.parseError("URL无效") }
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let code = obj["code"] as? Int, code == 200,
                  let dataObj = obj["data"] as? [String: Any] else {
                return .failure("用户名、密码或姓名错误")
            }
            let userInfo = DoorCardUserInfo(
                personId: dataObj["PersonID"] as? String ?? "",
                personName: dataObj["PersonName"] as? String ?? "",
                cardId: dataObj["CardID"] as? String ?? "",
                personKind: dataObj["PersonKind"] as? Int ?? 0
            )
            return .success(userInfo)
        } catch {
            logger.error("login failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func getRoomList(personId: String) async -> UniResponse<[DoorCardRoom]> {
        do {
            let url = "\(Self.baseURL)/ble/getRoomList?personid=\(personId)"
            guard let requestURL = URL(string: url) else { throw ServiceError.parseError("URL无效") }
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let dataArr = obj["data"] as? [[String: Any]] else {
                return .success([])
            }
            let rooms = dataArr.map { r in
                DoorCardRoom(
                    roomId: r["RoomID"] as? String ?? "",
                    roomName: r["RoomName"] as? String ?? "",
                    buildName: r["BuildName"] as? String ?? "",
                    btMac: r["BtMac"] as? String ?? "",
                    sKey: r["sKey"] as? String ?? "",
                    sn: r["SN"] as? Int ?? 0,
                    power: min(r["Power"] as? Int ?? 0, 100),
                    endDateTime: r["EndDateTime"] as? String ?? "",
                    personId: r["PersonID"] as? String ?? "",
                    schoolId: r["SchoolID"] as? String ?? ""
                )
            }
            return .success(rooms)
        } catch {
            logger.error("getRoomList failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription, retryable: true)
        }
    }

    func reportOperationLog(cardId: String, roomId: String, personId: String, schoolId: String, openType: Int, detail: String) async -> Bool {
        do {
            let url = "\(Self.baseURL)/ble/operateLog?cardid=\(cardId)&roomid=\(roomId)&personid=\(personId)&schoolid=\(schoolId)&opentype=\(openType)&detail=\(detail)"
            guard let requestURL = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else { return false }
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return false }
            return obj["code"] as? Int == 200
        } catch {
            logger.error("reportOperationLog failed: \(error.localizedDescription)")
            return false
        }
    }

    func updatePower(roomId: String, power: Int) async -> Bool {
        do {
            let url = "\(Self.baseURL)/ble/updatePower?roomid=\(roomId)&power=\(power)"
            guard let requestURL = URL(string: url) else { return false }
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            let body = String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = body.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return false }
            return obj["code"] as? Int == 200
        } catch {
            logger.error("updatePower failed: \(error.localizedDescription)")
            return false
        }
    }

    private func md5(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_MD5($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
