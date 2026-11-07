import Foundation

@MainActor @Observable
final class YKTViewModel {
    var isLoading = false
    var balance: CardBalance?
    var consumption: [ConsumptionRecord] = []
    private(set) var consumptionTotal = 0
    private(set) var consumptionPage = 0
    var isConsumptionLoading = false
    var consumptionError: String?
    var error: String?
    var isPaymentUnlocked = false
    var studentInfo: StudentInfo?
    var dorms: [SelectOption] = []
    var buildings: [SelectOption] = []
    var floors: [SelectOption] = []
    var rooms: [SelectOption] = []
    var selectedDorm: SelectOption?
    var selectedBuilding: SelectOption?
    var selectedFloor: SelectOption?
    var selectedRoom: SelectOption?
    var loadingOptions = false
    var isPaying = false
    var paymentResult: UtilityPaymentResult?
    var purchaseHistory: ElectricPurchaseQueryResult?
    private var service: YKTService?
    private var portal: PortalService?
    /// 每次重新加载消费流水时递增；旧请求返回时丢弃
    private var consumptionGeneration = 0

    func initialize(service: YKTService, portal: PortalService?) { self.service = service; self.portal = portal }

    /// 一卡通页：余额（ykt）与消费流水（门户）各自加载，互不等待
    func loadAll() {
        loadBalance()
        reloadConsumption()
    }

    /// 首页只需要余额，不加载消费流水
    func loadBalance() {
        guard let svc = service else { return }
        Task {
            isLoading = true; error = nil
            await svc.initSession()
            let result = await svc.getBalance()
            balance = result.data; error = result.error; isLoading = false
        }
    }

    /// 消费流水第一页（门户，本月）。重新加载时清空旧结果，旧请求返回后丢弃。
    func reloadConsumption() {
        guard let portal else { consumptionError = "请先登录"; return }
        consumptionGeneration += 1
        let current = consumptionGeneration
        consumption = []
        consumptionTotal = 0
        consumptionPage = 0
        consumptionError = nil
        Task {
            isConsumptionLoading = true
            defer { if current == consumptionGeneration { isConsumptionLoading = false } }
            do {
                let page = try await portal.consumptionRecords(page: 1)
                guard current == consumptionGeneration else { return }
                consumption = page.records
                consumptionTotal = page.total
                consumptionPage = 1
            } catch {
                guard current == consumptionGeneration, !Task.isCancelled else { return }
                consumptionError = PortalErrorMessage.text(for: error)
            }
        }
    }

    /// 加载下一页；服务端返回空页时停止翻页
    func loadMoreConsumption() {
        guard let portal, consumption.count < consumptionTotal, !isConsumptionLoading else { return }
        let current = consumptionGeneration
        let next = consumptionPage + 1
        Task {
            isConsumptionLoading = true
            defer { if current == consumptionGeneration { isConsumptionLoading = false } }
            do {
                let page = try await portal.consumptionRecords(page: next)
                guard current == consumptionGeneration else { return }
                if page.records.isEmpty {
                    consumptionTotal = consumption.count
                } else {
                    consumption += page.records
                    consumptionTotal = page.total
                    consumptionPage = next
                }
            } catch {
                guard current == consumptionGeneration, !Task.isCancelled else { return }
                consumptionError = PortalErrorMessage.text(for: error)
            }
        }
    }

    func unlockPayment() { isPaymentUnlocked = true; loadStudentInfo() }
    func lockPayment() {
        isPaymentUnlocked = false; studentInfo = nil
        dorms = []; buildings = []; floors = []; rooms = []
        selectedDorm = nil; selectedBuilding = nil; selectedFloor = nil; selectedRoom = nil
        purchaseHistory = nil
    }

    private func loadStudentInfo() {
        guard let svc = service else { return }
        Task {
            let result = await svc.getPageInfo()
            if result.success { studentInfo = result.data; loadDorms() }
        }
    }

    private func loadDorms() {
        guard let svc = service else { return }
        Task { loadingOptions = true; dorms = (await svc.getDormList()).data ?? []; loadingOptions = false }
    }

    func selectDorm(_ option: SelectOption) {
        guard let svc = service else { return }
        selectedDorm = option; selectedBuilding = nil; selectedFloor = nil; selectedRoom = nil
        buildings = []; floors = []; rooms = []
        Task { loadingOptions = true; buildings = (await svc.getBuildingList(dormId: option.value, dormName: option.name)).data ?? []; loadingOptions = false }
    }

    func selectBuilding(_ option: SelectOption) {
        guard let svc = service, let dorm = selectedDorm else { return }
        selectedBuilding = option; selectedFloor = nil; selectedRoom = nil; floors = []; rooms = []
        Task { loadingOptions = true; floors = (await svc.getFloorList(dormId: dorm.value, buildingId: option.value, dormName: dorm.name)).data ?? []; loadingOptions = false }
    }

    func selectFloor(_ option: SelectOption) {
        guard let svc = service, let dorm = selectedDorm, let building = selectedBuilding else { return }
        selectedFloor = option; selectedRoom = nil; rooms = []
        Task { loadingOptions = true; rooms = (await svc.getRoomList(dormId: dorm.value, buildingId: building.value, floorId: option.value, dormName: dorm.name)).data ?? []; loadingOptions = false }
    }

    func selectRoom(_ option: SelectOption) { selectedRoom = option }

    func payElectricity(amount: Int) {
        guard let svc = service, let info = studentInfo, let dorm = selectedDorm,
              let building = selectedBuilding, let floor = selectedFloor, let room = selectedRoom else { return }
        Task {
            isPaying = true; paymentResult = nil
            let request = UtilityPaymentRequest(
                roomId: room.value, dormId: dorm.value, dormName: dorm.name,
                buildName: building.name, floorName: floor.name, roomName: room.name,
                accId: info.accId, balances: String(format: "%.2f", info.balance), money: amount)
            let result = await svc.payElectricity(request: request)
            paymentResult = result.data ?? UtilityPaymentResult(success: false, message: result.error ?? "充值失败")
            isPaying = false
            if result.data?.success == true { loadAll() }
        }
    }

    func clearPaymentResult() { paymentResult = nil }
}
