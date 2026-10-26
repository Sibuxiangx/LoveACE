package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.data.service.FcRoom
import tech.loveace.appv3.data.service.FcStopReason
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.md3e.RibbonWeekStrip
import tech.loveace.appv3.ui.viewmodel.FcBuildingDistribution
import tech.loveace.appv3.ui.viewmodel.FreeClassroomUiState
import tech.loveace.appv3.ui.viewmodel.FreeClassroomViewModel
import tech.loveace.appv3.ui.viewmodel.busyWeeksFor
import tech.loveace.appv3.ui.viewmodel.formatWeeks
import tech.loveace.appv3.ui.viewmodel.scopeBuildings
import tech.loveace.appv3.ui.viewmodel.weekdayName

/** 小节标题（星期、节次等选择项的说明）。 */
@Composable
internal fun FcSubLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** 教学周：标题行显示“第 N 周”与“本周”标记，下面是 1–24 周的横向条。 */
@Composable
internal fun FcWeekPicker(week: Int, currentWeek: Int?, onSelect: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FcSubLabel("教学周")
            Spacer(Modifier.weight(1f))
            Text(
                "第 $week 周",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (week == currentWeek) RibbonChip(text = "本周", tone = RibbonTone.PRIMARY)
        }
        RibbonWeekStrip(selected = week, currentWeek = currentWeek, onSelect = onSelect)
    }
}

/** 范围条件折叠区：标题行显示已选数量，展开后才渲染下拉。 */
@Composable
internal fun FcRangeSection(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val activeCount = listOf(state.queryCampus, state.queryBuilding, state.queryType).count { it.isNotEmpty() }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(MaterialTheme.shapes.large)
                .clickable { expanded = !expanded }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                "范围（可不选）",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            if (activeCount > 0) {
                RibbonChip(text = "已选 $activeCount", tone = RibbonTone.PRIMARY)
            }
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = if (expanded) "收起范围" else "展开范围",
            )
        }
        if (expanded) {
            FcRangeFilters(state = state, vm = vm)
        }
    }
}

/** 范围：校区 → 教学楼（选了校区才可选，避免两校楼号相同时混淆）→ 教室类型 */
@Composable
internal fun FcRangeFilters(state: FreeClassroomUiState, vm: FreeClassroomViewModel) {
    val campusOptions = listOf("" to "全部校区", "2" to "西校", "1" to "东校")
    val buildingOptions = listOf("" to "全部教学楼") +
        scopeBuildings(state.buildings, state.queryCampus, "", state.showStopped)
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

/** 通用下拉。选项中代码为空字符串的是"不限"；未选时字段为空、只显示标签。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FcDropdown(
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

/** 楼头：楼名（校区 · 楼）、空闲数 /可见数；停用楼带标记。 */
@Composable
internal fun FcBuildingHeader(distribution: FcBuildingDistribution) {
    RibbonSectionTitle(
        text = "${distribution.building.campusName} · ${distribution.building.name}",
        trailing = {
            if (distribution.building.stopped) RibbonChip(text = "停用楼", tone = RibbonTone.ERROR)
            RibbonChip(
                text = "空闲 ${distribution.freeCount}/${distribution.totalCount}",
                tone = RibbonTone.PRIMARY,
            )
        },
    )
}

/** 楼层标签：数字楼层为“N 层”，推不出楼层为“其他”。 */
internal fun floorLabel(floor: Int?): String = if (floor == null) "其他（推测不出楼层）" else "$floor 层"

/**
 * 教室格子：空闲为主色容器，占用为中性容器；带停用标记时附小标签。
 * 状态同时用文字表达，不只靠颜色。
 */
@Composable
internal fun FcRoomTile(room: FcRoom, free: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier
            .width(96.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(if (free) scheme.primaryContainer else scheme.surfaceContainerHigh)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            room.code,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (free) scheme.onPrimaryContainer else scheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            if (free) "空闲" else "占用",
            style = MaterialTheme.typography.labelMedium,
            color = if (free) scheme.onPrimaryContainer else scheme.onSurfaceVariant,
        )
        roomChipText(room)?.let { RibbonChip(text = it, tone = RibbonTone.ERROR) }
    }
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

/** 加载中：居中的花形 loader 与说明文字。 */
@Composable
internal fun FcLoadingRow(text: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AppCircularProgressIndicator(modifier = Modifier.size(48.dp))
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
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
