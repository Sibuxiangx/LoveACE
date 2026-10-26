package tech.loveace.appv3.ui.screen

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.service.FcRoom
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonSlotGrid
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.FreeClassroomUiState
import tech.loveace.appv3.ui.viewmodel.FreeClassroomViewModel
import tech.loveace.appv3.ui.viewmodel.buildingKey
import tech.loveace.appv3.ui.viewmodel.roomKey
import tech.loveace.appv3.ui.viewmodel.weekdayName

internal const val PREFS_NAME = "free_classroom"

/** 节次：教务系统 1..10 节 */
private val SECTION_OPTIONS = (1..10).map { it to "$it" }

/** 星期：1..7，显示单字 */
private val WEEKDAY_OPTIONS = (1..7).map { it to weekdayName(it).removePrefix("周") }

/**
 * 空闲教室（更多 → 教务服务）。与 iOS 同一结构：时段（周次、星期、节次）→ 范围（可不选）→ 查询；
 * 结果直接按楼、楼层列出全部教室并标出空闲或占用；右上角“现在有空”一键查询，设置里控制停用教室。
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
                    IconButton(onClick = vm::useNow) { Icon(Icons.Default.AccessTime, "现在有空") }
                    IconButton(onClick = { vm.setSettingsOpen(true) }) { Icon(Icons.Default.Settings, "设置") }
                },
            )
        },
    ) { padding ->
        val modifier = Modifier.fillMaxSize().padding(padding)
        val initError = state.initError
        when {
            state.initLoading && state.buildings.isEmpty() -> Box(modifier, contentAlignment = Alignment.Center) {
                LoadingScreen("正在加载教学楼…")
            }
            initError != null && state.buildings.isEmpty() -> RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "加载失败",
                description = initError,
                actionText = "重试",
                onAction = vm::retryInit,
                modifier = modifier,
            )
            else -> Box(modifier, contentAlignment = Alignment.TopCenter) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().widthIn(max = 720.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    freeClassroomControlItems(state, vm)
                    freeClassroomResultItems(state, vm)
                }
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

/** 时段与范围条件 + 查询按钮。竖屏与横屏共用。 */
internal fun LazyListScope.freeClassroomControlItems(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    item(key = "week") {
        FcWeekPicker(week = state.week, currentWeek = state.currentWeek, onSelect = vm::setWeek)
    }
    item(key = "weekday") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            FcSubLabel("星期")
            RibbonSlotGrid(
                options = WEEKDAY_OPTIONS,
                selected = setOf(state.weekday),
                columns = 7,
                onToggle = vm::setWeekday,
            )
        }
    }
    item(key = "sections") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                FcSubLabel("节次（可多选）")
                Spacer(Modifier.weight(1f))
                if (state.sections.isNotEmpty()) {
                    RibbonChip(text = "已选 ${state.sections.size} 节", tone = RibbonTone.PRIMARY)
                }
            }
            RibbonSlotGrid(
                options = SECTION_OPTIONS,
                selected = state.sections,
                columns = 5,
                onToggle = vm::toggleSection,
            )
            Text(
                "节次可多选；教室需要在所选的每一节都空闲才算空闲。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    item(key = "range") {
        FcRangeSection(state = state, vm = vm)
    }
    item(key = "search") {
        Button(
            onClick = vm::search,
            enabled = state.sections.isNotEmpty() && !state.searching,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = MaterialTheme.shapes.large,
        ) {
            Text("查询空教室", style = MaterialTheme.typography.titleMedium)
        }
    }
}

/**
 * 结果：查询中、未查询引导、整页失败、空结果，或按楼分组（楼头 → 楼层 → 教室格子）。
 * 竖屏与横屏共用。
 */
internal fun LazyListScope.freeClassroomResultItems(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    val distribution = state.distribution
    val searchError = state.searchError
    when {
        state.searching -> item(key = "searching") { FcLoadingRow("正在查询…") }
        distribution == null && searchError != null -> item(key = "error") {
            RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "查询失败",
                description = searchError,
                actionText = "重试",
                onAction = vm::search,
            )
        }
        distribution == null -> item(key = "guide") {
            RibbonState(
                kind = RibbonStateKind.EMPTY,
                title = "选择时段后查询",
                description = "默认是本周和今天的当前节次，结果按楼和楼层展示。",
            )
        }
        else -> {
            if (searchError != null) {
                item(key = "partial-error") {
                    Text(
                        searchError,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            if (distribution.isEmpty()) {
                item(key = "none") {
                    RibbonState(
                        kind = RibbonStateKind.EMPTY,
                        title = "没有可显示的教室",
                        description = "换个节次或范围试试，也可以在设置里打开“显示停用教室”。",
                    )
                }
            } else {
                distribution.forEach { entry ->
                    val bk = buildingKey(entry.building.campusNo, entry.building.no)
                    item(key = "b_$bk") {
                        FcBuildingHeader(distribution = entry)
                    }
                    entry.floors.forEach { group ->
                        item(key = "f_${bk}_${group.floor ?: "other"}") {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                FcSubLabel(floorLabel(group.floor))
                                FlowRow(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    group.rooms.forEach { room ->
                                        FcRoomTile(
                                            room = room,
                                            free = roomKey(room) in state.freeKeys,
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
    }
}

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
            Text(
                "高级设置",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
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
                fontWeight = FontWeight.Bold,
            )
            Text(
                "${room.campusName} · ${room.buildingName} · ${room.seats ?: "-"} 座 · ${room.typeName ?: "类型待定"}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            stopText(room)?.let { text ->
                Text(
                    "停用标记：$text",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
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
