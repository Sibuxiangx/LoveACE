import Foundation

struct DoorCardUserInfo: Codable {
    let personId: String
    let personName: String
    let cardId: String
    let personKind: Int

    enum CodingKeys: String, CodingKey {
        case personId = "PersonID"
        case personName = "PersonName"
        case cardId = "CardID"
        case personKind = "PersonKind"
    }

    init(personId: String = "", personName: String = "", cardId: String = "", personKind: Int = 0) {
        self.personId = personId; self.personName = personName
        self.cardId = cardId; self.personKind = personKind
    }
}

struct DoorCardRoom: Codable, Identifiable {
    var id: String { roomId }
    let roomId: String
    let roomName: String
    let buildName: String
    let btMac: String
    let sKey: String
    let sn: Int
    let power: Int
    let endDateTime: String
    let personId: String
    let schoolId: String

    enum CodingKeys: String, CodingKey {
        case roomId = "RoomID"
        case roomName = "RoomName"
        case buildName = "BuildName"
        case btMac = "BtMac"
        case sKey
        case sn = "SN"
        case power = "Power"
        case endDateTime = "EndDateTime"
        case personId = "PersonID"
        case schoolId = "SchoolID"
    }

    init(roomId: String = "", roomName: String = "", buildName: String = "",
         btMac: String = "", sKey: String = "", sn: Int = 0, power: Int = 0,
         endDateTime: String = "", personId: String = "", schoolId: String = "") {
        self.roomId = roomId; self.roomName = roomName; self.buildName = buildName
        self.btMac = btMac; self.sKey = sKey; self.sn = sn; self.power = power
        self.endDateTime = endDateTime; self.personId = personId; self.schoolId = schoolId
    }
}

struct DoorCardCredentials: Codable {
    let username: String
    let userno: String
    let password: String

    init(username: String = "", userno: String = "", password: String = "") {
        self.username = username; self.userno = userno; self.password = password
    }
}

enum BleConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    case error
}

enum DoorOperation: CaseIterable {
    case openDoor
    case addCard
    case freezeCard
    case checkTime
    case alwaysOpen
    case alwaysOff
    case checkDaily

    var label: String {
        switch self {
        case .openDoor: return "手机开门"
        case .addCard: return "发卡"
        case .freezeCard: return "冻结卡"
        case .checkTime: return "校时"
        case .alwaysOpen: return "常开设置"
        case .alwaysOff: return "常闭设置"
        case .checkDaily: return "考勤"
        }
    }

    var systemImage: String {
        switch self {
        case .openDoor: return "lock.open.fill"
        case .addCard: return "creditcard.fill"
        case .freezeCard: return "snowflake"
        case .checkTime: return "clock.fill"
        case .alwaysOpen: return "lock.open"
        case .alwaysOff: return "lock.fill"
        case .checkDaily: return "checkmark.circle.fill"
        }
    }
}
