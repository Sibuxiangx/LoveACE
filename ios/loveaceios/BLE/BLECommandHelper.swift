import Foundation

enum BLECommandHelper {
    static let serviceUUID = "0000FFE0-0000-1000-8000-00805F9B34FB"
    static let characteristicUUID = "0000FFE1-0000-1000-8000-00805F9B34FB"

    static func bcc(_ hex: String) -> String {
        guard !hex.isEmpty else { return "00" }
        let len = hex.count / 2
        var result = 0
        for i in 0..<len {
            let start = hex.index(hex.startIndex, offsetBy: i * 2)
            let end = hex.index(start, offsetBy: 2)
            let byteStr = String(hex[start..<end])
            result ^= Int(byteStr, radix: 16) ?? 0
        }
        return String(format: "%02X", result)
    }

    static func buildOpenDoorCommand(sKey: String, schoolId: String) -> Data {
        let opCode = schoolId == "340301" ? "05FF" : "0503"
        let cmd = opCode + sKey
        let full = cmd + bcc(cmd)
        return hexToBytes(full)
    }

    static func buildAddCardCommand(cardId: String, sn: Int, sKey: String, endDateTime: String) -> Data {
        let snHex = String(format: "%04d", sn)
        let cmd = "1007\(cardId)\(snHex)\(sKey)\(endDateTime)"
        let full = cmd + bcc(cmd)
        return hexToBytes(full)
    }

    static func buildFreezeCardCommand(sn: Int, sKey: String, endDateTime: String) -> Data {
        let snHex = String(format: "%04d", sn)
        let cmd = "100700000000\(snHex)\(sKey)\(endDateTime)"
        let full = cmd + bcc(cmd)
        return hexToBytes(full)
    }

    static func buildCheckTimeCommand() -> Data {
        let bcdTime = bleTimeBCD()
        let cmd = "0810\(bcdTime)"
        let full = cmd + bcc(cmd)
        return hexToBytes(full)
    }

    static func buildAlwaysOpenCommand(sKey: String, schoolId: String) -> Data {
        let opCode = schoolId == "340301" ? "05FF" : "0511"
        let cmd = opCode + sKey
        let full = cmd + bcc(cmd)
        return hexToBytes(full)
    }

    static func buildAlwaysOffCommand(sKey: String, schoolId: String) -> Data {
        let opCode = schoolId == "340301" ? "05FF" : "0512"
        let cmd = opCode + sKey
        let full = cmd + bcc(cmd)
        return hexToBytes(full)
    }

    private static func bleTimeBCD() -> String {
        let cal = Calendar.current
        let now = Date()
        let y = max(cal.component(.year, from: now) - 2000, 0)
        let m = cal.component(.month, from: now)
        let d = cal.component(.day, from: now)
        let h = cal.component(.hour, from: now)
        let min = cal.component(.minute, from: now)
        let s = cal.component(.second, from: now)
        return String(format: "%02d%02d%02d%02d%02d%02d", y, m, d, h, min, s)
    }

    static func hexToBytes(_ hex: String) -> Data {
        var data = Data()
        let len = hex.count / 2
        for i in 0..<len {
            let start = hex.index(hex.startIndex, offsetBy: i * 2)
            let end = hex.index(start, offsetBy: 2)
            if let byte = UInt8(hex[start..<end], radix: 16) { data.append(byte) }
        }
        return data
    }

    static func bytesToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func parseOpenDoorResponse(_ hex: String) -> (recordNum: Int, power: Int)? {
        let lower = hex.lowercased()
        guard let idx = lower.range(of: "0703")?.lowerBound else { return nil }
        let startOffset = lower.distance(from: lower.startIndex, to: idx) + 4
        guard startOffset + 8 <= hex.count else { return nil }
        let numStart = hex.index(hex.startIndex, offsetBy: startOffset)
        let numEnd = hex.index(numStart, offsetBy: 4)
        let powerEnd = hex.index(numEnd, offsetBy: 4)
        guard let num = Int(hex[numStart..<numEnd], radix: 16),
              let power = Int(hex[numEnd..<powerEnd], radix: 16) else { return nil }
        return (num, power)
    }
}
