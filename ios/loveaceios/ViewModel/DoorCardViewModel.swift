import Foundation
import Combine

@MainActor @Observable
final class DoorCardViewModel {
    var isBound = false
    var isBinding = false
    var bindError: String?
    var userInfo: DoorCardUserInfo?
    var isLoadingRooms = false
    var rooms: [DoorCardRoom] = []
    var roomsError: String?
    var selectedRoom: DoorCardRoom?
    var bleState: BleConnectionState = .disconnected
    var operationMessage: String?
    var isOperating = false

    private let store = DoorCardStore()
    private let service = DoorCardService()
    let bleManager = DoorLockBLEManager()
    private var appUserId = ""
    private var cancellables = Set<AnyCancellable>()

    func initialize(userId: String) {
        appUserId = userId
        let creds = store.loadCredentials(appUserId: userId)
        let info = store.loadUserInfo(appUserId: userId)
        isBound = creds != nil; userInfo = info
        if creds != nil, let info { loadRooms(personId: info.personId) }

        bleManager.$connectionState.receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.bleState = state }.store(in: &cancellables)
        bleManager.$lastResponse.compactMap { $0 }.receive(on: DispatchQueue.main)
            .sink { [weak self] hex in self?.handleBleResponse(hex) }.store(in: &cancellables)
    }

    func bind(userno: String, username: String, rawPassword: String) {
        Task {
            isBinding = true; bindError = nil
            let result = await service.login(userno: userno, username: username, rawPassword: rawPassword)
            if result.success, let data = result.data {
                let creds = DoorCardCredentials(username: username, userno: userno, password: rawPassword)
                store.saveCredentials(appUserId: appUserId, credentials: creds)
                store.saveUserInfo(appUserId: appUserId, userInfo: data)
                userInfo = data; isBound = true; isBinding = false
                loadRooms(personId: data.personId)
            } else { bindError = result.error ?? "绑定失败"; isBinding = false }
        }
    }

    func unbind() { bleManager.disconnect(); store.unbind(appUserId: appUserId); isBound = false; userInfo = nil; rooms = []; selectedRoom = nil }

    func loadRooms(personId: String? = nil) {
        guard let pid = personId ?? userInfo?.personId else { return }
        Task {
            isLoadingRooms = true; roomsError = nil
            let result = await service.getRoomList(personId: pid)
            if result.success { rooms = result.data ?? []; selectedRoom = rooms.first }
            else { roomsError = result.error }
            isLoadingRooms = false
        }
    }

    func selectRoom(_ room: DoorCardRoom) { bleManager.disconnect(); selectedRoom = room; operationMessage = nil }
    func connectBle() { guard let room = selectedRoom ?? rooms.first else { return }; if selectedRoom == nil { selectedRoom = room }; bleManager.connect(macAddress: room.btMac) }
    func disconnectBle() { bleManager.disconnect(); operationMessage = nil }

    func openDoor() {
        guard let room = selectedRoom else { return }
        isOperating = true; operationMessage = "开锁中..."
        let cmd = BLECommandHelper.buildOpenDoorCommand(sKey: room.sKey, schoolId: room.schoolId)
        if !bleManager.sendCommand(cmd) { isOperating = false; operationMessage = "发送指令失败"; return }
        Task { if let info = userInfo { await service.reportOperationLog(cardId: info.cardId, roomId: room.roomId, personId: room.personId, schoolId: room.schoolId, openType: 9, detail: "手机开锁") } }
    }

    func addCard() {
        guard let room = selectedRoom, let info = userInfo else { return }
        isOperating = true; operationMessage = "发卡中..."
        let cmd = BLECommandHelper.buildAddCardCommand(cardId: info.cardId, sn: room.sn, sKey: room.sKey, endDateTime: room.endDateTime)
        if !bleManager.sendCommand(cmd) { isOperating = false; operationMessage = "发送指令失败" }
    }

    func freezeCard() {
        guard let room = selectedRoom else { return }
        isOperating = true; operationMessage = "冻结中..."
        let cmd = BLECommandHelper.buildFreezeCardCommand(sn: room.sn, sKey: room.sKey, endDateTime: room.endDateTime)
        if !bleManager.sendCommand(cmd) { isOperating = false; operationMessage = "发送指令失败" }
    }

    func checkTime() {
        isOperating = true; operationMessage = "校时中..."
        let cmd = BLECommandHelper.buildCheckTimeCommand()
        if !bleManager.sendCommand(cmd) { isOperating = false; operationMessage = "发送指令失败" }
    }

    private func handleBleResponse(_ hex: String) {
        if let parsed = BLECommandHelper.parseOpenDoorResponse(hex) {
            operationMessage = parsed.recordNum == 0 ? "开锁成功" : "开锁成功（有 \(parsed.recordNum) 条记录）"
            isOperating = false
            if let room = selectedRoom { Task { await service.updatePower(roomId: room.roomId, power: parsed.power) } }
            return
        }
        if isOperating {
            Task {
                try? await Task.sleep(for: .seconds(2))
                if isOperating { isOperating = false; operationMessage = "操作完成" }
            }
        }
    }

    func clearMessage() { operationMessage = nil }
}
