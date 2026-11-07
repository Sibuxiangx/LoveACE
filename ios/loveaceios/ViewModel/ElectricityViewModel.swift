import Foundation

@MainActor @Observable
final class ElectricityViewModel {
    var isLoading = false
    var isLoadingOptions = false
    var buildings: [[String: String]] = []
    var floors: [[String: String]] = []
    var rooms: [[String: String]] = []
    var selectedBuilding: (code: String, name: String)?
    var selectedFloor: (code: String, name: String)?
    var selectedRoom: (code: String, name: String)?
    var electricityInfo: ElectricityInfo?
    var error: String?
    var boundRoomCode: String?
    var boundRoomDisplay: String?
    private var service: ISIMService?

    func initialize(service: ISIMService) {
        self.service = service
        boundRoomCode = UserDefaults.standard.string(forKey: "elec_room_code")
        boundRoomDisplay = UserDefaults.standard.string(forKey: "elec_room_display")
    }

    func autoLoad() {
        guard let code = boundRoomCode else { return }
        loadElectricityInfo(roomCode: code, displayText: boundRoomDisplay)
    }

    func loadBuildings() {
        guard let svc = service else { return }
        guard !isLoadingOptions else { return }
        Task {
            isLoadingOptions = true; error = nil
            let result = await svc.getBuildings()
            buildings = result.data ?? []; isLoadingOptions = false
            if !result.success { error = result.error }
        }
    }

    func selectBuilding(code: String, name: String) {
        selectedBuilding = (code, name); selectedFloor = nil; selectedRoom = nil; floors = []; rooms = []
        guard let svc = service else { return }
        Task { isLoadingOptions = true; floors = (await svc.getFloors(buildingCode: code)).data ?? []; isLoadingOptions = false }
    }

    func selectFloor(code: String, name: String) {
        selectedFloor = (code, name); selectedRoom = nil; rooms = []
        guard let svc = service else { return }
        Task { isLoadingOptions = true; rooms = (await svc.getRooms(floorCode: code)).data ?? []; isLoadingOptions = false }
    }

    func selectRoom(code: String, name: String) { selectedRoom = (code, name) }

    func getService() -> ISIMService? { service }

    func bindRoom(code: String, display: String) {
        UserDefaults.standard.set(code, forKey: "elec_room_code")
        UserDefaults.standard.set(display, forKey: "elec_room_display")
        boundRoomCode = code; boundRoomDisplay = display
        loadElectricityInfo(roomCode: code, displayText: display)
    }

    func confirmBinding() {
        guard let building = selectedBuilding, let floor = selectedFloor, let room = selectedRoom else { return }
        let display = "\(building.name) \(floor.name) \(room.name)"
        bindRoom(code: room.code, display: display)
    }

    func loadElectricityInfo(roomCode: String, displayText: String? = nil) {
        guard let svc = service else { return }
        Task {
            isLoading = true; error = nil
            let result = await svc.getElectricityInfo(roomCode: roomCode, displayText: displayText)
            electricityInfo = result.data; isLoading = false
            if !result.success { error = result.error }
        }
    }

    func clearBinding() {
        UserDefaults.standard.removeObject(forKey: "elec_room_code")
        UserDefaults.standard.removeObject(forKey: "elec_room_display")
        boundRoomCode = nil; boundRoomDisplay = nil; electricityInfo = nil
        buildings = []; floors = []; rooms = []
        selectedBuilding = nil; selectedFloor = nil; selectedRoom = nil
    }
}
