package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.data.service.FcBuilding
import tech.loveace.appv3.data.service.FcRoom
import tech.loveace.appv3.data.service.FcStopReason
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.FLOOR_OTHER
import tech.loveace.appv3.ui.viewmodel.FcMode
import tech.loveace.appv3.ui.viewmodel.FreeClassroomUiState
import tech.loveace.appv3.ui.viewmodel.FreeClassroomViewModel
import tech.loveace.appv3.ui.viewmodel.buildingKey
import tech.loveace.appv3.ui.viewmodel.busyWeeksFor
import tech.loveace.appv3.ui.viewmodel.formatWeeks
import tech.loveace.appv3.ui.viewmodel.roomKey
import tech.loveace.appv3.ui.viewmodel.visibleBuildings
import tech.loveace.appv3.ui.viewmodel.weekdayName

private val SECTION_NUMBERS = (1..10).toList()
private val WEEKDAY_NUMBERS = (1..7).toList()

/** 模式切换：按时间找 / 逐楼探索 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FcModeSwitch(mode: FcMode, onChange: (FcMode) -> Unit) {
    val options = listOf(FcMode.QUERY to "按时间找", FcMode.EXPLORE to "逐楼探索")
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        options.forEachIndexed { index, (value, label) ->
            SegmentedButton(
                selected = mode == value,
                onClick = { onChange(value) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
            ) {
                Text(label)
            }
        }
    }
}

/** 时段选择：教学周（下拉）、星期（单选）、节次（多选，所选节次都空闲的教室才会出现）。 */
@Composable
internal fun FcTimePicker(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FcWeekDropdown(week = state.week, currentWeek = state.currentWeek, onSelect = vm::setWeek)
        FcSubLabel("星期")
        FcChipRow {
            WEEKDAY_NUMBERS.forEach { day ->
                FilterChip(
                    selected = state.weekday == day,
                    onClick = { vm.setWeekday(day) },
                    label = { Text(weekdayName(day).removePrefix("周")) },
                )
            }
        }
        FcSubLabel("节次（可多选，所选节次都空闲的教室才会出现）")
        FcChipRow {
            SECTION_NUMBERS.forEach { section ->
                FilterChip(
                    selected = section in state.sections,
                    onClick = { vm.toggleSection(section) },
                    label = { Text("$section") },
                )
            }
        }
        Text(
            "学校的课最少连着两节（如 1-2 节），把要用的节次都选上，才会显示这些节次都空的教室。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FcWeekDropdown(week: Int, currentWeek: Int?, onSelect: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = weekLabel(week, currentWeek),
            onValueChange = {},
            readOnly = true,
            label = { Text("教学周") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(),
            singleLine = true,
            shape = MaterialTheme.shapes.large,
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            (1..24).forEach { w ->
                DropdownMenuItem(
                    text = { Text(weekLabel(w, currentWeek)) },
                    onClick = {
                        onSelect(w)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** 通用下拉。选项中代码为空字符串的是"不限"；未选时字段为空、只显示标签。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FcDropdown(
    label: String,
    options: List<Pair<String, String>>,
    selectedCode: String,
    onSelect: (String) -> Unit,
    enabled: Boolean = true,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = if (selectedCode.isEmpty()) {
        ""
    } else {
        options.firstOrNull { it.first == selectedCode }?.second.orEmpty()
    }
    ExposedDropdownMenuBox(expanded = expanded && enabled, onExpandedChange = { if (enabled) expanded = it }) {
        OutlinedTextField(
            value = selectedName,
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded && enabled) },
            modifier = Modifier.fillMaxWidth().menuAnchor(),
            singleLine = true,
            shape = MaterialTheme.shapes.large,
        )
        ExposedDropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false }) {
            options.forEach { (code, name) ->
                DropdownMenuItem(
                    text = { Text(name) },
                    onClick = {
                        onSelect(code)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** 范围条件：校区 → 教学楼（选了校区才可选，避免两校楼号相同时混淆）→ 教室类型 */
@Composable
internal fun FcRangeFilters(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    val campusOptions = listOf("" to "全部校区", "2" to "西校", "1" to "东校")
    val buildingOptions = listOf("" to "全部教学楼") +
        visibleBuildings(state.buildings, state.showStopped)
            .filter { it.campusNo == state.queryCampus }
            .map { it.no to if (it.stopped) "${it.name}（停用）" else it.name }
    val typeOptions = listOf("" to "全部类型") + state.types.map { it.code to it.name }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FcDropdown(
            label = "校区",
            options = campusOptions,
            selectedCode = state.queryCampus,
            onSelect = vm::setQueryCampus,
        )
        FcDropdown(
            label = "教学楼",
            options = buildingOptions,
            selectedCode = state.queryBuilding,
            onSelect = vm::setQueryBuilding,
            enabled = state.queryCampus.isNotEmpty(),
        )
        FcDropdown(
            label = "教室类型",
            options = typeOptions,
            selectedCode = state.queryType,
            onSelect = vm::setQueryType,
        )
    }
}

/** 查询结果的一个楼宇分组标题 */
@Composable
internal fun FcBuildingHeader(campusName: String, buildingName: String, stopped: Boolean) {
    Row(
        Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "$campusName · $buildingName",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        if (stopped) RibbonChip(text = "停用楼", tone = RibbonTone.ERROR)
    }
}

/** 教室列表卡片（查询结果） */
@Composable
internal fun FcRoomCard(room: FcRoom, onClick: () -> Unit) {
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 20.dp,
        padding = PaddingValues(14.dp),
        interactive = true,
        onClick = onClick,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                room.title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            roomChipText(room)?.let { RibbonChip(text = it, tone = RibbonTone.ERROR) }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            "${room.seats ?: "-"} 座 · ${room.typeName ?: "类型待定"}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        val stop = stopText(room)
        if (stop != null) {
            Spacer(Modifier.height(2.dp))
            Text(stop, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }
}

/** 探索用的教室格子：上色时空闲为主色容器，占用为次要色，未上色为中性色。 */
@Composable
internal fun FcRoomTile(room: FcRoom, free: Boolean?, onClick: () -> Unit) {
    val container = when (free) {
        true -> MaterialTheme.colorScheme.primaryContainer
        false -> MaterialTheme.colorScheme.surfaceContainerHighest
        null -> MaterialTheme.colorScheme.surfaceContainerHigh
    }
    Card(
        onClick = onClick,
        modifier = Modifier.width(104.dp),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = container),
    ) {
        Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            Text(
                room.code,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "${room.seats ?: "-"} 座",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when (free) {
                true -> Text(
                    "空闲",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                false -> Text(
                    "占用",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                null -> Unit
            }
            roomChipText(room)?.let {
                Spacer(Modifier.height(4.dp))
                RibbonChip(text = it, tone = RibbonTone.ERROR)
            }
        }
    }
}

/** 楼层分组：1..12 层按数字排序，推测不出楼层的归入"其他"。 */
internal fun floorGroups(rooms: List<FcRoom>): List<Pair<Int, List<FcRoom>>> =
    rooms
        .groupBy { it.floor ?: FLOOR_OTHER }
        .toList()
        .sortedBy { (floor, _) -> if (floor == FLOOR_OTHER) Int.MAX_VALUE else floor }

/** 探索模式的楼层筛选芯片：全部 / 各层 / 其他 */
@Composable
internal fun FcFloorChips(floors: List<Int>, hasOther: Boolean, selected: Int?, onSelect: (Int?) -> Unit) {
    FcChipRow {
        FilterChip(selected = selected == null, onClick = { onSelect(null) }, label = { Text("全部") })
        floors.forEach { floor ->
            FilterChip(
                selected = selected == floor,
                onClick = { onSelect(floor) },
                label = { Text("${floor}层") },
            )
        }
        if (hasOther) {
            FilterChip(
                selected = selected == FLOOR_OTHER,
                onClick = { onSelect(FLOOR_OTHER) },
                label = { Text("其他") },
            )
        }
    }
}

/** 查询条件摘要：结果页顶部使用。 */
internal fun summaryText(state: FreeClassroomUiState, roomCount: Int): String {
    val sections = formatWeeks(state.sections.sorted())
    val campus = when (state.queryCampus) {
        "2" -> "西校"
        "1" -> "东校"
        else -> "全部校区"
    }
    val building = state.buildings.firstOrNull {
        it.campusNo == state.queryCampus && it.no == state.queryBuilding
    }?.name ?: "全部教学楼"
    return "第 ${state.week} 周 · ${weekdayName(state.weekday)} 第 $sections 节 · $campus · $building · 共 $roomCount 间"
}

/** 占用说明：列出所选每个节次在哪些周被占用，并标出所选教学周的状态。 */
@Composable
internal fun FcOccupancyText(state: FreeClassroomUiState) {
    val occupancy = state.occupancy
    when {
        state.occupancyLoading -> Text(
            "正在读取占用情况…",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        state.occupancyError != null -> Text(
            state.occupancyError,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error,
        )
        occupancy == null -> Unit
        state.sections.isEmpty() -> Text(
            "选择周次、星期和节次后，这里会显示占用情况。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        else -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            state.sections.sorted().forEach { section ->
                val busy = busyWeeksFor(occupancy, state.weekday, section)
                val busyNow = state.week in busy
                val line = when {
                    busy.isEmpty() -> "全周空闲"
                    busyNow -> "第 ${state.week} 周占用 · 占用周次 ${formatWeeks(busy)}"
                    else -> "第 ${state.week} 周空闲 · 占用周次 ${formatWeeks(busy)}"
                }
                Text(
                    "${weekdayName(state.weekday)} 第 $section 节：$line",
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (busyNow) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

/** 楼宇卡片（探索模式的楼宇列表） */
@Composable
internal fun FcBuildingCard(building: FcBuilding, onClick: () -> Unit) {
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 20.dp,
        padding = PaddingValues(14.dp),
        interactive = true,
        onClick = onClick,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                building.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            if (building.stopped) RibbonChip(text = "停用楼", tone = RibbonTone.ERROR)
        }
    }
}

/** 可折叠标题行：点击切换展开/收起。 */
@Composable
internal fun FcCollapsibleHeader(title: String, expanded: Boolean, onToggle: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
        Icon(
            imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
            contentDescription = if (expanded) "收起" else "展开",
        )
    }
}

/** 教室标记文字：状态 02 优先；其它停用（名称含停用、状态 03）显示"停用"；无停用返回 null。 */
internal fun roomChipText(room: FcRoom): String? = when {
    FcStopReason.STATUS_02 in room.stopReasons -> "状态 02"
    room.stopped -> "停用"
    else -> null
}

/** 教室的停用原因文字；无停用返回 null。 */
internal fun stopText(room: FcRoom): String? {
    if (room.stopReasons.isEmpty()) return null
    val parts = mutableListOf<String>()
    if (FcStopReason.NAME in room.stopReasons) parts.add("房间名称含\"停用\"")
    if (FcStopReason.STATUS_02 in room.stopReasons) parts.add("状态码 02")
    if (FcStopReason.STATUS_03 in room.stopReasons) parts.add("状态码 03")
    return parts.joinToString("；")
}

/** 探索上色时的空闲判断：未上色返回 null。 */
internal fun freeFlag(state: FreeClassroomUiState, room: FcRoom): Boolean? =
    state.exploreFree?.let { roomKey(room) in it }

internal fun weekLabel(week: Int, currentWeek: Int?): String =
    "第 $week 周" + if (week == currentWeek) "（本周）" else ""

/** 按楼宇分组，保持输入顺序。 */
internal fun groupByBuilding(rooms: List<FcRoom>): List<Pair<String, List<FcRoom>>> {
    val order = LinkedHashMap<String, MutableList<FcRoom>>()
    rooms.forEach { order.getOrPut(buildingKey(it.campusNo, it.buildingNo)) { mutableListOf() }.add(it) }
    return order.map { it.key to it.value }
}

@Composable
internal fun FcSubLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
internal fun FcChipRow(content: @Composable FlowRowScope.() -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}
