package tech.loveace.appv3.ui.screen

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import tech.loveace.appv3.data.service.FcBuilding
import tech.loveace.appv3.data.service.FcRoom
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.FLOOR_OTHER
import tech.loveace.appv3.ui.viewmodel.FcMode
import tech.loveace.appv3.ui.viewmodel.FreeClassroomUiState
import tech.loveace.appv3.ui.viewmodel.FreeClassroomViewModel
import tech.loveace.appv3.ui.viewmodel.buildingKey
import tech.loveace.appv3.ui.viewmodel.formatWeeks
import tech.loveace.appv3.ui.viewmodel.visibleBuildings
import tech.loveace.appv3.ui.viewmodel.visibleRooms
import tech.loveace.appv3.ui.viewmodel.weekdayName
import tech.loveace.appv3.ui.viewmodel.roomKey
import androidx.compose.foundation.layout.PaddingValues

internal const val PREFS_NAME = "free_classroom"

/**
 * 空闲教室（更多 → 教务服务）。两种模式：
 * - 按时间找：选教学周、星期、节次，列出所选时段全部空闲的教室（默认"现在有空的教室"）。
 * - 逐楼探索：选一栋楼，按楼层看每间教室；可选时段上色。
 * 右上角设置里可以打开"显示停用教室"。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FreeClassroomScreen(
    authViewModel: AuthViewModel,
    onBack: (() -> Unit)? = null,
    vm: FreeClassroomViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    LaunchedEffect(authViewModel.freeClassroomService) {
        authViewModel.freeClassroomService?.let { service ->
            vm.init(service, context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("空闲教室") },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") }
                    }
                },
                actions = {
                    IconButton(onClick = { vm.setSettingsOpen(true) }) {
                        Icon(Icons.Default.Settings, "设置")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            FcModeSwitch(mode = state.mode, onChange = vm::setMode)
            val initError = state.initError
            when {
                state.initLoading && state.buildings.isEmpty() -> Box(
                    Modifier.fillMaxWidth().weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    LoadingScreen("正在加载教学楼…")
                }
                initError != null && state.buildings.isEmpty() -> RibbonState(
                    kind = RibbonStateKind.ERROR,
                    title = "加载失败",
                    description = initError,
                    actionText = "重试",
                    onAction = vm::retryInit,
                )
                state.mode == FcMode.QUERY -> QueryPane(state, vm, Modifier.weight(1f))
                else -> ExplorePane(state, vm, Modifier.weight(1f))
            }
        }
    }

    if (state.settingsOpen) {
        SettingsSheet(
            showStopped = state.showStopped,
            onShowStopped = vm::setShowStopped,
            onDismiss = { vm.setSettingsOpen(false) },
        )
    }

    state.selectedRoom?.let { room ->
        RoomDetailSheet(room = room, state = state, vm = vm)
    }
}

/* ============================ 按时间找 ============================ */

@Composable
private fun QueryPane(state: FreeClassroomUiState, vm: FreeClassroomViewModel, modifier: Modifier) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        queryControlItems(state, vm)
        queryResultItems(state, vm)
    }
}

/** 按时间找的筛选区：现在有空、时段、范围、查询按钮。竖屏与横屏共用。 */
internal fun LazyListScope.queryControlItems(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    if (state.queryResults == null && state.queryError == null && !state.queryLoading) {
        item { GuideCard() }
    }
    item {
        FilledTonalButton(
            onClick = vm::useNow,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = MaterialTheme.shapes.large,
        ) {
            Text("现在有空的教室", style = MaterialTheme.typography.titleMedium)
        }
    }
    item { RibbonSectionTitle("① 选时段") }
    item { FcTimePicker(state = state, vm = vm) }
    item { RibbonSectionTitle("② 范围（可不选）") }
    item { FcRangeFilters(state = state, vm = vm) }
    item {
        Button(
            onClick = vm::runQuery,
            enabled = state.sections.isNotEmpty() && !state.queryLoading,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = MaterialTheme.shapes.large,
        ) {
            Text("查询", style = MaterialTheme.typography.titleMedium)
        }
    }
}

/** 按时间找的结果区：加载、错误、空结果、按楼分组的教室。竖屏与横屏共用。 */
internal fun LazyListScope.queryResultItems(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    val results = state.queryResults
    val visible = if (results == null) {
        emptyList()
    } else {
        visibleRooms(results, state.buildings, state.showStopped)
    }
    when {
        state.queryLoading -> item {
            Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                AppCircularProgressIndicator()
            }
        }
        state.queryError != null -> item {
            RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "查询失败",
                description = state.queryError,
                actionText = "重试",
                onAction = vm::runQuery,
            )
        }
        results == null -> Unit
        visible.isEmpty() -> item {
            RibbonState(
                kind = RibbonStateKind.EMPTY,
                title = "这个时段没有空闲教室",
                description = "换个节次试试，或切到“逐楼探索”看看教室分布。",
            )
        }
        else -> {
            item { Text(summaryText(state, visible.size), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            groupByBuilding(visible).forEach { (key, rooms) ->
                val first = rooms.first()
                val stopped = state.buildings.any { it.stopped && buildingKey(it.campusNo, it.no) == key }
                item(key = "h_$key") {
                    FcBuildingHeader(
                        campusName = first.campusName,
                        buildingName = first.buildingName,
                        stopped = stopped,
                    )
                }
                items(rooms, key = { roomKey(it) }) { room ->
                    FcRoomCard(room = room, onClick = { vm.selectRoom(room) })
                }
            }
        }
    }
}

@Composable
private fun GuideCard() {
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 24.dp,
        padding = PaddingValues(16.dp),
    ) {
        Text("第一次用？", style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(6.dp))
        Text("1. 选教学周和节次（默认是本周和当前节）", style = MaterialTheme.typography.bodyMedium)
        Text("2. 需要的话，选校区或教学楼", style = MaterialTheme.typography.bodyMedium)
        Text("3. 点查询，列出所选时段全部空闲的教室", style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(6.dp))
        Text(
            "也可以直接点“现在有空的教室”；想逐楼看分布，切到“逐楼探索”。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/* ============================ 逐楼探索 ============================ */

@Composable
private fun ExplorePane(state: FreeClassroomUiState, vm: FreeClassroomViewModel, modifier: Modifier) {
    val building = state.exploreBuilding
    if (building == null) {
        BuildingList(state = state, vm = vm, modifier = modifier)
    } else {
        RoomExplorer(state = state, vm = vm, building = building, modifier = modifier)
    }
}

@Composable
internal fun BuildingList(state: FreeClassroomUiState, vm: FreeClassroomViewModel, modifier: Modifier) {
    val buildings = visibleBuildings(state.buildings, state.showStopped)
    val normal = buildings.filter { !it.stopped }
    val stopped = buildings.filter { it.stopped }
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Text(
                "点一栋楼，逐层看每间教室。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        normal.groupBy { it.campusNo }.forEach { (campusNo, list) ->
            item(key = "c_$campusNo") {
                RibbonSectionTitle(if (campusNo == "2") "西校" else "东校")
            }
            items(list, key = { buildingKey(it.campusNo, it.no) }) { building ->
                FcBuildingCard(building = building, onClick = { vm.openBuilding(building) })
            }
        }
        if (stopped.isNotEmpty()) {
            item(key = "stopped_title") { RibbonSectionTitle("停用楼") }
            items(stopped, key = { buildingKey(it.campusNo, it.no) }) { building ->
                FcBuildingCard(building = building, onClick = { vm.openBuilding(building) })
            }
        }
    }
}

@Composable
internal fun RoomExplorer(
    state: FreeClassroomUiState,
    vm: FreeClassroomViewModel,
    building: FcBuilding,
    modifier: Modifier,
) {
    var timeOpen by rememberSaveable { mutableStateOf(false) }
    val rooms = visibleRooms(state.exploreRooms, state.buildings, state.showStopped)
    val floors = rooms.mapNotNull { it.floor }.distinct().sorted()
    val hasOther = rooms.any { it.floor == null }
    val shown = if (state.exploreFloor == null) {
        rooms
    } else {
        rooms.filter { (it.floor ?: FLOOR_OTHER) == state.exploreFloor }
    }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            TextButton(onClick = vm::closeBuilding) { Text("← 全部教学楼") }
            Text(
                "${building.campusName} · ${building.name}",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
            )
        }
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("用所选时段上色", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "绿色 = 所选时段全部空闲",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = state.exploreColorOn, onCheckedChange = vm::setExploreColor)
            }
        }
        item {
            FcCollapsibleHeader(
                title = timeSummary(state),
                expanded = timeOpen,
                onToggle = { timeOpen = !timeOpen },
            )
        }
        if (timeOpen) {
            item { FcTimePicker(state = state, vm = vm) }
        }

        when {
            state.exploreLoading -> item {
                Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                    AppCircularProgressIndicator()
                }
            }
            state.exploreError != null && state.exploreRooms.isEmpty() -> item {
                RibbonState(
                    kind = RibbonStateKind.ERROR,
                    title = "读取教室失败",
                    description = state.exploreError,
                    actionText = "重试",
                    onAction = { vm.openBuilding(building) },
                )
            }
            rooms.isEmpty() -> item {
                RibbonState(
                    kind = RibbonStateKind.EMPTY,
                    title = "这栋楼暂时没有可显示的教室",
                )
            }
            else -> {
                item {
                    FcFloorChips(
                        floors = floors,
                        hasOther = hasOther,
                        selected = state.exploreFloor,
                        onSelect = vm::setExploreFloor,
                    )
                }
                floorGroups(shown).forEach { (floor, group) ->
                    item(key = "f_$floor") {
                        RibbonSectionTitle(if (floor == FLOOR_OTHER) "其他（推测不出楼层）" else "${floor} 层")
                    }
                    item(key = "g_$floor") {
                        FcChipRow {
                            group.forEach { room ->
                                FcRoomTile(
                                    room = room,
                                    free = freeFlag(state, room),
                                    onClick = { vm.selectRoom(room) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun timeSummary(state: FreeClassroomUiState): String =
    if (state.sections.isEmpty()) {
        "时段（可选，用于上色）"
    } else {
        "时段：第 ${state.week} 周 · ${weekdayName(state.weekday)} 第 ${formatWeeks(state.sections.sorted())} 节"
    }

/* ============================ 弹层 ============================ */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsSheet(
    showStopped: Boolean,
    onShowStopped: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("高级设置", style = MaterialTheme.typography.headlineSmall, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("显示停用教室", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "默认隐藏停用教学楼的教室，以及状态码为 02 或 03 的教室。打开后全部显示：停用楼的教室排在最后；状态码 02、03 和名称含“停用”的教室带标记。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = showStopped, onCheckedChange = onShowStopped)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RoomDetailSheet(room: FcRoom, state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = vm::dismissRoom, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                room.title,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
            )
            Text(
                "${room.campusName} · ${room.buildingName} · ${room.seats ?: "-"} 座 · ${room.typeName ?: "类型待定"}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            stopText(room)?.let { text ->
                Text("停用标记：$text", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            RibbonSectionTitle("占用情况")
            FcOccupancyText(state = state)
            if (state.occupancyError != null) {
                TextButton(onClick = vm::retryOccupancy) { Text("重试") }
            }
        }
    }
}
