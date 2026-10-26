package tech.loveace.appv3.ui.viewmodel

import android.content.SharedPreferences
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.service.FcBuilding
import tech.loveace.appv3.data.service.FcOption
import tech.loveace.appv3.data.service.FcQuery
import tech.loveace.appv3.data.service.FcRoom
import tech.loveace.appv3.data.service.FcSlot
import tech.loveace.appv3.data.service.FreeClassroomService
import java.time.LocalDate

/** 一层楼的教室；floor = null 表示推不出楼层，排在最后。 */
data class FcFloorGroup(val floor: Int?, val rooms: List<FcRoom>)

/** 一栋楼的分布：空闲数 / 可见教室数，以及按楼层分组的全部教室。 */
data class FcBuildingDistribution(
    val building: FcBuilding,
    val freeCount: Int,
    val totalCount: Int,
    val floors: List<FcFloorGroup>,
)

data class FreeClassroomUiState(
    val initLoading: Boolean = false,
    val initError: String? = null,
    val buildings: List<FcBuilding> = emptyList(),
    val types: List<FcOption> = emptyList(),
    val currentWeek: Int? = null,
    val currentSection: Int = 1,
    val showStopped: Boolean = false,
    val settingsOpen: Boolean = false,
    /** 时段 */
    val week: Int = 1,
    val weekday: Int = LocalDate.now().dayOfWeek.value,
    val sections: Set<Int> = emptySet(),
    /** 范围条件，空字符串 = 不限 */
    val queryCampus: String = "",
    val queryBuilding: String = "",
    val queryType: String = "",
    /** 查询结果；null = 还没查询过（显示引导） */
    val distribution: List<FcBuildingDistribution>? = null,
    /** 所选时段全部空闲的教室键（roomKey） */
    val freeKeys: Set<String> = emptySet(),
    val searching: Boolean = false,
    val searchError: String? = null,
    /** 详情 */
    val selectedRoom: FcRoom? = null,
    val occupancy: Set<String>? = null,
    val occupancyLoading: Boolean = false,
    val occupancyError: String? = null,
)

private const val PREFS_SHOW_STOPPED = "show_stopped"

class FreeClassroomViewModel : ViewModel() {
    private var service: FreeClassroomService? = null
    private var prefs: SharedPreferences? = null
    private var initialized = false
    private var searchJob: Job? = null
    private var occupancyJob: Job? = null

    /** 每栋楼的全部教室（教室课表），会话内缓存，避免重复请求。键为 buildingKey。 */
    private val roomCache = mutableMapOf<String, List<FcRoom>>()

    private val _uiState = MutableStateFlow(FreeClassroomUiState())
    val uiState: StateFlow<FreeClassroomUiState> = _uiState.asStateFlow()

    fun init(service: FreeClassroomService, prefs: SharedPreferences) {
        this.service = service
        this.prefs = prefs
        _uiState.update { it.copy(showStopped = prefs.getBoolean(PREFS_SHOW_STOPPED, false)) }
        if (!initialized) {
            initialized = true
            loadInitial()
        }
    }

    fun retryInit() {
        loadInitial()
    }

    /** 首次进入：当前周、教室类型、教学楼、当前节次。 */
    private fun loadInitial() {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(initLoading = true, initError = null) }
            val buildings = svc.loadBuildings()
            val list = buildings.data
            if (!buildings.success || list == null) {
                _uiState.update { it.copy(initLoading = false, initError = buildings.error ?: "获取教学楼失败") }
                return@launch
            }
            val meta = svc.loadMeta().data
            val section = svc.currentSection()?.takeIf { it in 1..10 } ?: 1
            _uiState.update { st ->
                st.copy(
                    initLoading = false,
                    buildings = list,
                    types = meta?.types.orEmpty(),
                    currentWeek = meta?.currentWeek,
                    currentSection = section,
                    week = meta?.currentWeek ?: st.week,
                    weekday = LocalDate.now().dayOfWeek.value,
                    sections = if (st.sections.isEmpty()) setOf(section) else st.sections,
                )
            }
        }
    }

    fun setWeek(week: Int) {
        _uiState.update { it.copy(week = week) }
    }

    fun setWeekday(weekday: Int) {
        _uiState.update { it.copy(weekday = weekday) }
    }

    fun toggleSection(section: Int) {
        _uiState.update { st ->
            st.copy(sections = if (section in st.sections) st.sections - section else st.sections + section)
        }
    }

    fun setQueryCampus(campusNo: String) {
        _uiState.update { it.copy(queryCampus = campusNo, queryBuilding = "") }
    }

    fun setQueryBuilding(buildingNo: String) {
        _uiState.update { it.copy(queryBuilding = buildingNo) }
    }

    fun setQueryType(typeCode: String) {
        _uiState.update { it.copy(queryType = typeCode) }
    }

    /** "现在有空的教室"：当前周、今天、当前节次，并直接查询。 */
    fun useNow() {
        _uiState.update { st ->
            st.copy(
                week = st.currentWeek ?: st.week,
                weekday = LocalDate.now().dayOfWeek.value,
                sections = setOf(st.currentSection),
            )
        }
        search()
    }

    fun setSettingsOpen(open: Boolean) {
        _uiState.update { it.copy(settingsOpen = open) }
    }

    /** 切换"显示停用教室"并持久化；已有结果时按新设置重新查询。 */
    fun setShowStopped(show: Boolean) {
        prefs?.edit()?.putBoolean(PREFS_SHOW_STOPPED, show)?.apply()
        _uiState.update { it.copy(showStopped = show) }
        if (_uiState.value.distribution != null) search()
    }

    /**
     * 查询：先取所选时段的空闲教室（未选校区时西校、东校分别查询），
     * 再取范围内各楼的全部教室，按楼、楼层展示；教室的空闲状态来自第一步。
     */
    fun search() {
        val svc = service ?: return
        val st = _uiState.value
        if (st.sections.isEmpty()) {
            _uiState.update { it.copy(searchError = "先选一个节次，再查询") }
            return
        }
        searchJob?.cancel()
        _uiState.update { it.copy(searching = true, searchError = null) }
        searchJob = viewModelScope.launch {
            val names = typeNameMap(st.types)
            val slots = st.sections.sorted().map { FcSlot(st.weekday, it) }
            val campuses = if (st.queryCampus.isEmpty()) listOf("2", "1") else listOf(st.queryCampus)
            val free = mutableSetOf<String>()
            val errors = mutableListOf<String>()
            for (campus in campuses) {
                val result = svc.search(
                    FcQuery(
                        weeks = listOf(st.week),
                        slots = slots,
                        campusNo = campus,
                        buildingNo = st.queryBuilding,
                        typeCode = st.queryType,
                    ),
                    names,
                )
                val rooms = result.data
                if (result.success && rooms != null) {
                    rooms.forEach { free.add(roomKey(it)) }
                } else {
                    errors.add(result.error ?: "查询空闲教室失败")
                }
            }
            val scope = scopeBuildings(st.buildings, st.queryCampus, st.queryBuilding, st.showStopped)
            val failed = loadRooms(scope, svc, names)
            if (failed > 0) errors.add("$failed 栋楼的教室加载失败")
            _uiState.update { cur ->
                cur.copy(
                    searching = false,
                    freeKeys = free,
                    distribution = buildDistribution(scope, free, cur.showStopped, cur.queryType),
                    searchError = errors.joinToString("；").ifEmpty { null },
                )
            }
        }
    }

    /** 为尚未缓存的楼加载全部教室，最多 4 栋并发；返回加载失败的楼数。 */
    private suspend fun loadRooms(
        scope: List<FcBuilding>,
        svc: FreeClassroomService,
        names: Map<String, String>,
    ): Int {
        val missing = scope.filter { buildingKey(it.campusNo, it.no) !in roomCache }
        var failed = 0
        missing.chunked(4).forEach { batch ->
            val loaded = coroutineScope {
                batch.map { building ->
                    async {
                        val result = svc.listRooms(building, names)
                        val rooms = result.data
                        if (result.success && rooms != null) {
                            roomCache[buildingKey(building.campusNo, building.no)] = rooms
                            true
                        } else {
                            false
                        }
                    }
                }.awaitAll()
            }
            failed += loaded.count { !it }
        }
        return failed
    }

    /** 把范围内的楼转成分布：类型与停用规则与设置一致，没有可显示教室的楼不出现。 */
    private fun buildDistribution(
        scope: List<FcBuilding>,
        free: Set<String>,
        showStopped: Boolean,
        typeCode: String,
    ): List<FcBuildingDistribution> =
        scope.mapNotNull { building ->
            val rooms = roomCache[buildingKey(building.campusNo, building.no)] ?: return@mapNotNull null
            val visible = rooms
                .filter { showStopped || !it.statusHidden }
                .filter { typeCode.isEmpty() || it.typeCode == typeCode }
            if (visible.isEmpty()) return@mapNotNull null
            FcBuildingDistribution(
                building = building,
                freeCount = visible.count { roomKey(it) in free },
                totalCount = visible.size,
                floors = floorGroups(visible),
            )
        }

    fun selectRoom(room: FcRoom) {
        val svc = service ?: return
        occupancyJob?.cancel()
        _uiState.update {
            it.copy(selectedRoom = room, occupancy = null, occupancyLoading = true, occupancyError = null)
        }
        occupancyJob = viewModelScope.launch {
            val result = svc.occupancy(room)
            val tokens = result.data
            _uiState.update { st ->
                when {
                    st.selectedRoom?.let { roomKey(it) } != roomKey(room) -> st
                    result.success && tokens != null -> st.copy(occupancyLoading = false, occupancy = tokens)
                    else -> st.copy(occupancyLoading = false, occupancyError = result.error ?: "获取占用失败")
                }
            }
        }
    }

    fun retryOccupancy() {
        _uiState.value.selectedRoom?.let { selectRoom(it) }
    }

    fun dismissRoom() {
        occupancyJob?.cancel()
        _uiState.update {
            it.copy(selectedRoom = null, occupancy = null, occupancyLoading = false, occupancyError = null)
        }
    }

    private fun typeNameMap(types: List<FcOption>): Map<String, String> =
        types.associate { it.code to it.name }
}

/** 房间键：校区 | 楼号 | 房号。同一间房的多行记录共用一个键。 */
internal fun roomKey(room: FcRoom): String = "${room.campusNo}|${room.buildingNo}|${room.code}"

internal fun buildingKey(campusNo: String, buildingNo: String): String = "$campusNo|$buildingNo"

/**
 * 查询范围内的教学楼：按校区、教学楼筛选，按校区与名称排序；
 * 停用楼只在打开"显示停用教室"时包含。
 */
internal fun scopeBuildings(
    buildings: List<FcBuilding>,
    campusNo: String,
    buildingNo: String,
    showStopped: Boolean,
): List<FcBuilding> =
    buildings
        .filter {
            (campusNo.isEmpty() || it.campusNo == campusNo) &&
                (buildingNo.isEmpty() || it.no == buildingNo) &&
                (showStopped || !it.stopped)
        }
        .sortedWith(compareBy<FcBuilding>({ it.campusNo }, { it.name }))

/** 楼层分组：楼层升序，推不出楼层的放最后；同层内按房号排序。 */
internal fun floorGroups(rooms: List<FcRoom>): List<FcFloorGroup> =
    rooms
        .groupBy { it.floor }
        .map { (floor, list) -> FcFloorGroup(floor = floor, rooms = list.sortedBy { it.code }) }
        .sortedBy { it.floor ?: Int.MAX_VALUE }

/** 某个时段（星期 + 节次）在哪些周被占用。occupancy 的格式为 weekday_week_section。 */
internal fun busyWeeksFor(occupancy: Set<String>, weekday: Int, section: Int): List<Int> =
    occupancy.mapNotNull { token ->
        val parts = token.split("_")
        if (parts.size == 3 && parts[0] == weekday.toString() && parts[2] == section.toString()) {
            parts[1].toIntOrNull()
        } else {
            null
        }
    }.sorted()

/** 周次压缩显示：[1,2,3,4,5,6,9,10] → "1–6、9–10"。 */
internal fun formatWeeks(weeks: List<Int>): String {
    if (weeks.isEmpty()) return ""
    val sorted = weeks.distinct().sorted()
    val ranges = mutableListOf<String>()
    var start = sorted.first()
    var prev = start
    for (w in sorted.drop(1)) {
        if (w == prev + 1) {
            prev = w
            continue
        }
        ranges.add(if (start == prev) "$start" else "$start–$prev")
        start = w
        prev = w
    }
    ranges.add(if (start == prev) "$start" else "$start–$prev")
    return ranges.joinToString("、")
}

internal fun weekdayName(weekday: Int): String = when (weekday) {
    1 -> "周一"
    2 -> "周二"
    3 -> "周三"
    4 -> "周四"
    5 -> "周五"
    6 -> "周六"
    7 -> "周日"
    else -> ""
}
