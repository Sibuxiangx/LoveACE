import Foundation

@MainActor @Observable
final class FreeClassroomViewModel {
    private static let showStoppedKey = "free_classroom.show_stopped"

    // 元信息与教学楼
    private(set) var currentWeek: Int?
    private(set) var types: [FcOption] = []
    private(set) var buildings: [FcBuilding] = []
    private(set) var isLoadingInit = false
    private(set) var initError: String?

    // 时段与范围（页面直接编辑）
    var week = 1
    var weekday = 1
    var sections: Set<Int> = []
    var campusNo = ""
    var buildingNo = ""
    var typeCode = ""

    // 查询结果：范围内各楼的全部教室（按楼层分组），空闲状态来自空闲查询；nil 表示还没查询
    private(set) var distribution: [FcBuildingDistribution]?
    private(set) var freeKeys: Set<String> = []
    private(set) var isSearching = false
    private(set) var searchError: String?

    // 设置：是否显示停用教室（持久化）
    private(set) var showStopped: Bool

    // 教室占用
    private(set) var occupancy: Set<String>?
    private(set) var occupancyRoomKey: String?
    private(set) var isLoadingOccupancy = false
    private(set) var occupancyError: String?

    private var service: FreeClassroomService?
    private var typeNames: [String: String] = [:]
    private var nowSection = 1
    private var searchGeneration = 0
    /// 每栋楼的全部教室（教室课表），会话内缓存，避免重复请求
    private var roomCache: [String: [FcRoom]] = [:]

    init() {
        showStopped = UserDefaults.standard.bool(forKey: Self.showStoppedKey)
    }

    func initialize(service: FreeClassroomService) {
        self.service = service
    }

    /// 切换"显示停用教室"；已有查询结果时按新设置重新计算。
    func setShowStopped(_ value: Bool) {
        showStopped = value
        UserDefaults.standard.set(value, forKey: Self.showStoppedKey)
        if distribution != nil {
            Task { await search() }
        }
    }

    /// 首次进入：当前周、教室类型、教学楼、当前节次。
    func loadInitial() async {
        guard let service, buildings.isEmpty, !isLoadingInit else { return }
        isLoadingInit = true
        initError = nil
        async let metaResult = service.loadMeta()
        async let buildingResult = service.loadBuildings()
        async let sectionNow = service.currentSection()
        let meta = await metaResult
        let buildingList = await buildingResult
        let section = await sectionNow
        isLoadingInit = false

        if let info = meta.data {
            currentWeek = info.currentWeek
            if let week = info.currentWeek { self.week = week }
            types = info.types
            typeNames = Dictionary(info.types.map { ($0.code, $0.name) }, uniquingKeysWith: { first, _ in first })
        }
        if let list = buildingList.data {
            buildings = list
        } else {
            initError = buildingList.error ?? "获取教学楼失败"
        }
        if let section, (1...10).contains(section) {
            nowSection = section
        }
        weekday = Self.todayWeekday()
        if sections.isEmpty { sections = [nowSection] }
    }

    func retryInit() async {
        buildings = []
        await loadInitial()
    }

    /// 查询：先取所选时段的空闲教室（未选校区时两个校区分别查询），再取范围内各楼的全部教室，按楼、楼层展示。
    func search() async {
        guard let service, !sections.isEmpty else { return }
        searchGeneration += 1
        let token = searchGeneration
        isSearching = true
        searchError = nil

        let slots = sections.sorted().map { FcSlot(weekday: weekday, section: $0) }
        let campuses = campusNo.isEmpty ? ["2", "1"] : [campusNo]
        var free: Set<String> = []
        var errors: [String] = []
        for campus in campuses {
            let query = FcQuery(
                weeks: [week],
                slots: slots,
                campusNo: campus,
                buildingNo: buildingNo,
                typeCode: typeCode
            )
            let result = await service.search(query, typeNames: typeNames)
            if let rooms = result.data {
                free.formUnion(rooms.map(\.roomKey))
            } else {
                errors.append(result.error ?? "查询空闲教室失败")
            }
        }

        let scope = scopeBuildings()
        let failed = await loadRooms(for: scope, service: service)
        guard token == searchGeneration else { return }

        isSearching = false
        freeKeys = free
        distribution = makeDistribution(scope)
        if !failed.isEmpty {
            errors.append("\(failed.count) 栋楼的教室加载失败")
        }
        searchError = errors.isEmpty ? nil : errors.joined(separator: "；")
    }

    /// 现在有空的教室：本周、今天、当前节次。
    func useNow() async {
        if let currentWeek { week = currentWeek }
        weekday = Self.todayWeekday()
        sections = [nowSection]
        await search()
    }

    func setCampus(_ no: String) {
        campusNo = no
        if !buildingNo.isEmpty, !no.isEmpty,
           buildings.first(where: { $0.no == buildingNo })?.campusNo != no {
            buildingNo = ""
        }
    }

    func setBuilding(_ building: FcBuilding?) {
        buildingNo = building?.no ?? ""
        if let building { campusNo = building.campusNo }
    }

    /// 教学楼下拉的可选项：当前校区下，停用楼只在打开"显示停用教室"时出现。
    var buildingOptions: [FcBuilding] {
        buildings
            .filter { (campusNo.isEmpty || $0.campusNo == campusNo) && (showStopped || !$0.stopped) }
            .sorted { ($0.campusNo, $0.name) < ($1.campusNo, $1.name) }
    }

    /// 教室的空闲状态；还没查询时为 nil。
    func isFree(_ room: FcRoom) -> Bool? {
        distribution == nil ? nil : freeKeys.contains(room.roomKey)
    }

    func loadOccupancy(for room: FcRoom) async {
        guard let service else { return }
        isLoadingOccupancy = true
        occupancyError = nil
        occupancy = nil
        occupancyRoomKey = room.roomKey
        let result = await service.occupancy(of: room)
        isLoadingOccupancy = false
        if let busy = result.data {
            occupancy = busy
        } else {
            occupancyError = result.error ?? "获取占用信息失败"
        }
    }

    /// 今天的星期，周一为 1…周日为 7。
    static func todayWeekday() -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    /// 楼层分组，楼层升序，推不出楼层的放最后；同层内按房号自然排序。
    static func floorGroups(_ rooms: [FcRoom]) -> [FcFloorGroup] {
        let grouped = Dictionary(grouping: rooms, by: \.floor)
        return grouped.keys
            .sorted { ($0 ?? Int.max) < ($1 ?? Int.max) }
            .map { floor in
                let sorted = (grouped[floor] ?? []).sorted {
                    $0.code.localizedStandardCompare($1.code) == .orderedAscending
                }
                return FcFloorGroup(floor: floor, rooms: sorted)
            }
    }

    /// 查询范围内的教学楼：按校区、教学楼筛选；停用楼只在打开"显示停用教室"时包含。
    private func scopeBuildings() -> [FcBuilding] {
        buildings
            .filter {
                (campusNo.isEmpty || $0.campusNo == campusNo)
                    && (buildingNo.isEmpty || $0.no == buildingNo)
                    && (showStopped || !$0.stopped)
            }
            .sorted { ($0.campusNo, $0.name) < ($1.campusNo, $1.name) }
    }

    /// 为尚未缓存的楼加载全部教室，最多 4 栋并发；返回加载失败的楼。
    private func loadRooms(for scope: [FcBuilding], service: FreeClassroomService) async -> [FcBuilding] {
        let names = typeNames
        let missing = scope.filter { roomCache[$0.id] == nil }
        var failed: [FcBuilding] = []
        for start in stride(from: 0, to: missing.count, by: 4) {
            let batch = Array(missing[start..<min(start + 4, missing.count)])
            await withTaskGroup(of: (FcBuilding, [FcRoom]?).self) { group in
                for building in batch {
                    group.addTask {
                        let result = await service.listRooms(building, typeNames: names)
                        return (building, result.data)
                    }
                }
                for await (building, rooms) in group {
                    if let rooms {
                        roomCache[building.id] = rooms
                    } else {
                        failed.append(building)
                    }
                }
            }
        }
        return failed
    }

    /// 把范围内的楼转成分布：按类型筛选，隐藏规则与设置一致，没有可显示教室的楼不出现。
    private func makeDistribution(_ scope: [FcBuilding]) -> [FcBuildingDistribution] {
        scope.compactMap { building in
            guard let rooms = roomCache[building.id] else { return nil }
            let visible = rooms
                .filter { showStopped || !$0.statusHidden }
                .filter { typeCode.isEmpty || $0.typeCode == typeCode }
            guard !visible.isEmpty else { return nil }
            return FcBuildingDistribution(
                building: building,
                freeCount: visible.filter { freeKeys.contains($0.roomKey) }.count,
                totalCount: visible.count,
                floors: Self.floorGroups(visible)
            )
        }
    }
}
