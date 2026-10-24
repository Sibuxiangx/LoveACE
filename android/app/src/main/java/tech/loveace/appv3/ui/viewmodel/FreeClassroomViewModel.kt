package tech.loveace.appv3.ui.viewmodel

import android.content.SharedPreferences
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
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

enum class FcMode { QUERY, EXPLORE }

data class FreeClassroomUiState(
    val mode: FcMode = FcMode.QUERY,
    val initLoading: Boolean = false,
    val initError: String? = null,
    val buildings: List<FcBuilding> = emptyList(),
    val types: List<FcOption> = emptyList(),
    val currentWeek: Int? = null,
    val currentSection: Int = 1,
    val showStopped: Boolean = false,
    val settingsOpen: Boolean = false,
    /** 时段：两种模式共用 */
    val week: Int = 1,
    val weekday: Int = LocalDate.now().dayOfWeek.value,
    val sections: Set<Int> = emptySet(),
    /** 查询模式：范围条件，空字符串 = 不限 */
    val queryCampus: String = "",
    val queryBuilding: String = "",
    val queryType: String = "",
    val queryLoading: Boolean = false,
    val queryError: String? = null,
    /** null = 还没查询过（显示引导） */
    val queryResults: List<FcRoom>? = null,
    /** 探索模式 */
    val exploreBuilding: FcBuilding? = null,
    val exploreRooms: List<FcRoom> = emptyList(),
    val exploreLoading: Boolean = false,
    val exploreError: String? = null,
    val exploreColorOn: Boolean = false,
    /** 上色用：所选时段空闲的教室键；null = 不上色 */
    val exploreFree: Set<String>? = null,
    /** 楼层筛选：null = 全部，FLOOR_OTHER = 其他，其余为楼层数 */
    val exploreFloor: Int? = null,
    /** 详情 */
    val selectedRoom: FcRoom? = null,
    val occupancy: Set<String>? = null,
    val occupancyLoading: Boolean = false,
    val occupancyError: String? = null,
)

const val FLOOR_OTHER = -1

private const val PREFS_SHOW_STOPPED = "show_stopped"

class FreeClassroomViewModel : ViewModel() {
    private var service: FreeClassroomService? = null
    private var prefs: SharedPreferences? = null
    private var initialized = false
    private var queryJob: Job? = null
    private var exploreJob: Job? = null
    private var freeJob: Job? = null
    private var occupancyJob: Job? = null

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

    fun retryInit() = loadInitial()

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

    fun setMode(mode: FcMode) {
        _uiState.update { it.copy(mode = mode) }
    }

    fun setWeek(week: Int) {
        _uiState.update { it.copy(week = week) }
        afterTimeChanged()
    }

    fun setWeekday(weekday: Int) {
        _uiState.update { it.copy(weekday = weekday) }
        afterTimeChanged()
    }

    fun toggleSection(section: Int) {
        _uiState.update { st ->
            st.copy(sections = if (section in st.sections) st.sections - section else st.sections + section)
        }
        afterTimeChanged()
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
        afterTimeChanged()
        if (_uiState.value.mode == FcMode.QUERY) runQuery()
    }

    /** 时段变化后：查询结果作废，探索上色重算。 */
    private fun afterTimeChanged() {
        _uiState.update { it.copy(queryResults = null, queryError = null) }
        val st = _uiState.value
        if (st.exploreColorOn && st.exploreBuilding != null) refreshExploreFree()
    }

    fun setQueryCampus(campusNo: String) {
        _uiState.update { it.copy(queryCampus = campusNo, queryBuilding = "", queryResults = null) }
    }

    fun setQueryBuilding(buildingNo: String) {
        _uiState.update { it.copy(queryBuilding = buildingNo, queryResults = null) }
    }

    fun setQueryType(typeCode: String) {
        _uiState.update { it.copy(queryType = typeCode, queryResults = null) }
    }

    fun runQuery() {
        val svc = service ?: return
        val st = _uiState.value
        if (st.sections.isEmpty()) {
            _uiState.update { it.copy(queryResults = null, queryError = "先选一个节次，再查询") }
            return
        }
        val query = FcQuery(
            weeks = listOf(st.week),
            slots = st.sections.sorted().map { FcSlot(st.weekday, it) },
            campusNo = st.queryCampus,
            buildingNo = st.queryBuilding,
            typeCode = st.queryType,
        )
        queryJob?.cancel()
        _uiState.update { it.copy(queryLoading = true, queryError = null) }
        queryJob = viewModelScope.launch {
            val result = svc.search(query, typeNameMap(st.types))
            val rooms = result.data
            if (result.success && rooms != null) {
                _uiState.update { it.copy(queryLoading = false, queryResults = rooms) }
            } else {
                _uiState.update {
                    it.copy(queryLoading = false, queryResults = null, queryError = result.error ?: "查询失败")
                }
            }
        }
    }

    fun setSettingsOpen(open: Boolean) {
        _uiState.update { it.copy(settingsOpen = open) }
    }

    fun setShowStopped(show: Boolean) {
        prefs?.edit()?.putBoolean(PREFS_SHOW_STOPPED, show)?.apply()
        _uiState.update { it.copy(showStopped = show) }
    }

    fun openBuilding(building: FcBuilding) {
        val svc = service ?: return
        exploreJob?.cancel()
        _uiState.update {
            it.copy(
                exploreBuilding = building,
                exploreRooms = emptyList(),
                exploreLoading = true,
                exploreError = null,
                exploreFloor = null,
                exploreFree = null,
            )
        }
        exploreJob = viewModelScope.launch {
            val result = svc.listRooms(building, typeNameMap(_uiState.value.types))
            val rooms = result.data
            if (result.success && rooms != null) {
                _uiState.update { it.copy(exploreLoading = false, exploreRooms = rooms) }
                if (_uiState.value.exploreColorOn) refreshExploreFree()
            } else {
                _uiState.update { it.copy(exploreLoading = false, exploreError = result.error ?: "获取教室失败") }
            }
        }
    }

    fun closeBuilding() {
        exploreJob?.cancel()
        freeJob?.cancel()
        _uiState.update {
            it.copy(
                exploreBuilding = null,
                exploreRooms = emptyList(),
                exploreLoading = false,
                exploreError = null,
                exploreFree = null,
                exploreFloor = null,
            )
        }
    }

    fun setExploreColor(on: Boolean) {
        _uiState.update { it.copy(exploreColorOn = on, exploreFree = if (on) it.exploreFree else null) }
        if (on) refreshExploreFree()
    }

    fun setExploreFloor(floor: Int?) {
        _uiState.update { it.copy(exploreFloor = floor) }
    }

    /** 探索上色：用当前时段查一次该楼的空闲教室，空闲的标绿色。 */
    private fun refreshExploreFree() {
        val svc = service ?: return
        val st = _uiState.value
        val building = st.exploreBuilding ?: return
        if (st.sections.isEmpty()) {
            _uiState.update { it.copy(exploreFree = null) }
            return
        }
        freeJob?.cancel()
        freeJob = viewModelScope.launch {
            val query = FcQuery(
                weeks = listOf(st.week),
                slots = st.sections.sorted().map { FcSlot(st.weekday, it) },
                campusNo = building.campusNo,
                buildingNo = building.no,
            )
            val result = svc.search(query, typeNameMap(st.types))
            val free = result.data
            if (result.success && free != null) {
                _uiState.update { it.copy(exploreFree = free.map { room -> roomKey(room) }.toSet()) }
            } else {
                _uiState.update { it.copy(exploreFree = null) }
            }
        }
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

/** 可见楼宇：停用楼默认隐藏；正常楼在前，停用楼在后。 */
internal fun visibleBuildings(buildings: List<FcBuilding>, showStopped: Boolean): List<FcBuilding> =
    buildings
        .filter { showStopped || !it.stopped }
        .sortedWith(compareBy<FcBuilding>({ it.stopped }, { it.campusNo }, { it.no }))

/** 可见教室：停用楼的教室、状态码 02 / 03 的教室默认隐藏；名称含停用的教室始终显示，停用标记由 UI 处理。 */
internal fun visibleRooms(rooms: List<FcRoom>, buildings: List<FcBuilding>, showStopped: Boolean): List<FcRoom> {
    val stoppedKeys = buildings.filter { it.stopped }.map { buildingKey(it.campusNo, it.no) }.toSet()
    return rooms
        .filter { showStopped || (!it.statusHidden && buildingKey(it.campusNo, it.buildingNo) !in stoppedKeys) }
        .sortedWith(
            compareBy<FcRoom>(
                { buildingKey(it.campusNo, it.buildingNo) in stoppedKeys },
                { it.campusNo },
                { it.buildingName },
                { it.floor ?: Int.MAX_VALUE },
                { it.code },
            ),
        )
}

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
