package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.ScheduleCourse
import tech.loveace.appv3.data.model.ScheduleTimePlace
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ScheduleViewModel
import tech.loveace.appv3.util.ScheduleImageExporter

private val android.content.Context.landscapeScheduleTipsStore by preferencesDataStore("landscape_schedule_tips")
private val KEY_HIDE_LANDSCAPE_TIPS = booleanPreferencesKey("hide_landscape_schedule_tips")

private val WEEKDAYS = listOf("一", "二", "三", "四", "五", "六", "日")
private const val MAX_SESSION = 12
private const val TOTAL_DAYS = 7
private val L_TIME_COL_WIDTH = 40.dp
private val L_ROW_HEIGHT = 56.dp
private val L_HEADER_HEIGHT = 36.dp

private data class LCourseColor(val bg: Color, val border: Color, val text: Color)
private val L_COURSE_COLORS = listOf(
    LCourseColor(Color(0x2E0078D4), Color(0x800078D4), Color(0xFF0063B1.toInt())),
    LCourseColor(Color(0x2E107C10), Color(0x80107C10), Color(0xFF0E6E0E.toInt())),
    LCourseColor(Color(0x2E881798), Color(0x80881798), Color(0xFF6B1076.toInt())),
    LCourseColor(Color(0x2ECA5010), Color(0x80CA5010), Color(0xFFA34D0A.toInt())),
    LCourseColor(Color(0x2E0063B1), Color(0x800063B1), Color(0xFF004E8C.toInt())),
    LCourseColor(Color(0x2EE3008C), Color(0x80E3008C), Color(0xFFB3006E.toInt())),
    LCourseColor(Color(0x2E008575), Color(0x80008575), Color(0xFF006A5D.toInt())),
    LCourseColor(Color(0x2E8E562E), Color(0x808E562E), Color(0xFF6E4224.toInt())),
    LCourseColor(Color(0x2E0099BC), Color(0x800099BC), Color(0xFF007A96.toInt())),
    LCourseColor(Color(0x2E7A7574), Color(0x807A7574), Color(0xFF3B3A39.toInt())),
)

private data class LGridCell(
    val course: ScheduleCourse,
    val timePlace: ScheduleTimePlace,
    val rowSpan: Int,
    val colorIndex: Int,
    val mergedWeeks: String,
)

private fun buildLGrid(courses: List<ScheduleCourse>): Map<String, List<LGridCell>> {
    val courseColorMap = mutableMapOf<String, Int>()
    var colorIdx = 0
    data class TempEntry(val course: ScheduleCourse, val tp: ScheduleTimePlace)
    val tempGrid = mutableMapOf<String, MutableList<TempEntry>>()
    for (course in courses) {
        if (!courseColorMap.containsKey(course.courseCode)) { courseColorMap[course.courseCode] = colorIdx % L_COURSE_COLORS.size; colorIdx++ }
        for (tp in course.timeAndPlaceList) {
            val key = "${tp.classDay}-${tp.classSessions}"
            tempGrid.getOrPut(key) { mutableListOf() }.add(TempEntry(course, tp))
        }
    }
    val grid = mutableMapOf<String, List<LGridCell>>()
    for ((key, entries) in tempGrid) {
        data class GroupKey(val courseCode: String, val classroom: String, val span: Int)
        val grouped = mutableMapOf<GroupKey, MutableList<String>>()
        val groupData = mutableMapOf<GroupKey, TempEntry>()
        for (entry in entries) {
            val gk = GroupKey(entry.course.courseCode, entry.tp.classroomName, entry.tp.continuingSession)
            grouped.getOrPut(gk) { mutableListOf() }.add(entry.tp.weekDescription)
            if (!groupData.containsKey(gk)) groupData[gk] = entry
        }
        grid[key] = grouped.map { (gk, weeks) ->
            val entry = groupData[gk]!!
            val unique = weeks.distinct()
            val merged = if (unique.size == 1) unique[0] else unique.joinToString(",").let { if (it.length > 15) "${unique[0]}等" else it }
            LGridCell(entry.course, entry.tp, gk.span, courseColorMap[entry.course.courseCode] ?: 0, merged)
        }
    }
    return grid
}

private fun isCoveredByAboveL(grid: Map<String, List<LGridCell>>, day: Int, session: Int): Boolean {
    for (s in (session - 1) downTo 1) {
        val cells = grid["$day-$s"] ?: continue
        if (cells.any { s + it.rowSpan > session }) return true
    }
    return false
}

private fun getMaxUsedSessionL(grid: Map<String, List<LGridCell>>): Int {
    var max = 0
    for ((key, cells) in grid) {
        val session = key.split("-").getOrNull(1)?.toIntOrNull() ?: continue
        for (cell in cells) { val end = session + cell.rowSpan - 1; if (end > max) max = end }
    }
    return max.coerceIn(8, MAX_SESSION)
}

/**
 * 横屏课表：全部7天平铺显示，支持课程重叠切换、使用提示
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeScheduleScreen(authViewModel: AuthViewModel, vm: ScheduleViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var selectedCell by remember { mutableStateOf<LGridCell?>(null) }
    var showTipsDialog by remember { mutableStateOf(false) }
    var showExportDialog by remember { mutableStateOf(false) }

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val hideTips by context.landscapeScheduleTipsStore.data
        .map { it[KEY_HIDE_LANDSCAPE_TIPS] ?: false }
        .collectAsState(initial = true)

    var tipsChecked by remember { mutableStateOf(false) }
    LaunchedEffect(hideTips) {
        if (!tipsChecked && !hideTips) { showTipsDialog = true; tipsChecked = true }
        else if (!tipsChecked) tipsChecked = true
    }

    LaunchedEffect(authViewModel.jwcService, authViewModel.studentScheduleService) {
        val jwc = authViewModel.jwcService
        val sch = authViewModel.studentScheduleService
        if (jwc != null && sch != null) {
            vm.setActiveUserId(authViewModel.uiState.value.userId)
            vm.init(jwc, sch)
            vm.loadTerms()
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("课程表") },
            actions = {
                if (state.courses.isNotEmpty()) {
                    IconButton(onClick = { showExportDialog = true }) {
                        Icon(Icons.Default.FileDownload, "导出图片")
                    }
                }
                IconButton(onClick = { showTipsDialog = true }) {
                    Icon(Icons.Default.HelpOutline, "使用帮助")
                }
            },
        )

        if (state.terms.isNotEmpty()) {
            PrimaryScrollableTabRow(
                selectedTabIndex = state.terms.indexOf(state.selectedTerm).coerceAtLeast(0),
                edgePadding = 16.dp,
            ) {
                state.terms.forEach { term ->
                    Tab(selected = term == state.selectedTerm, onClick = { vm.selectTerm(term) },
                        text = { Text(term.termName, maxLines = 1) })
                }
            }
        }

        when {
            state.isLoading -> LoadingScreen()
            state.error != null -> RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "加载失败",
                description = state.error,
                actionText = "重试",
                onAction = { state.selectedTerm?.let { vm.loadSchedule(it.termCode) } },
            )
            state.courses.isEmpty() -> RibbonState(kind = RibbonStateKind.EMPTY, title = "该学期暂无课表")
            else -> {
                val grid = remember(state.courses) { buildLGrid(state.courses) }
                val maxSession = remember(grid) { getMaxUsedSessionL(grid) }

                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("共 ${state.courses.size} 门课 · ${state.totalUnits} 学分",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }

                LandscapeScheduleGrid(grid, maxSession) { selectedCell = it }
            }
        }
    }

    selectedCell?.let { cell -> LandscapeCourseDetailSheet(cell) { selectedCell = null } }

    if (showExportDialog && state.courses.isNotEmpty() && state.selectedTerm != null) {
        ExportDialog(
            title = "导出课程表图片",
            description = "将 ${state.selectedTerm!!.termName} 课程表导出为精美图片，保存到相册。",
            onExport = {
                ScheduleImageExporter.exportScheduleImage(
                    context = context,
                    courses = state.courses,
                    termName = state.selectedTerm!!.termName,
                    courseCount = state.courses.size,
                    totalUnits = state.totalUnits,
                )
            },
            onDismiss = { showExportDialog = false },
        )
    }

    if (showTipsDialog) {
        LandscapeScheduleTipsDialog(
            onDismiss = { showTipsDialog = false },
            onDismissForever = {
                showTipsDialog = false
                scope.launch { context.landscapeScheduleTipsStore.edit { it[KEY_HIDE_LANDSCAPE_TIPS] = true } }
            },
        )
    }
}

@Composable
private fun LandscapeScheduleTipsDialog(onDismiss: () -> Unit, onDismissForever: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Default.HelpOutline, null) },
        title = { Text("课程表使用提示") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                LandscapeTipItem("👆 点击课程格子", "查看课程详情")
                LandscapeTipItem("👆 重叠课程（底部彩色条）", "点击可切换不同课程，底部色条显示课程数量和当前选中")
                LandscapeTipItem("👆 长按重叠课程", "直接查看当前课程详情")
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("知道了") } },
        dismissButton = { TextButton(onClick = onDismissForever) { Text("不再提示") } },
    )
}

@Composable
private fun LandscapeTipItem(action: String, desc: String) {
    Column {
        Text(action, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Text(desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun LandscapeScheduleGrid(grid: Map<String, List<LGridCell>>, maxSession: Int, onCellClick: (LGridCell) -> Unit) {
    val verticalScroll = rememberScrollState()
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth()) {
            Box(Modifier.width(L_TIME_COL_WIDTH).height(L_HEADER_HEIGHT), contentAlignment = Alignment.Center) {}
            for (d in 1..TOTAL_DAYS) {
                Box(Modifier.weight(1f).height(L_HEADER_HEIGHT), contentAlignment = Alignment.Center) {
                    Text("周${WEEKDAYS[d - 1]}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))

        Row(Modifier.fillMaxSize().verticalScroll(verticalScroll)) {
            Column(Modifier.width(L_TIME_COL_WIDTH)) {
                for (s in 1..maxSession) {
                    Box(Modifier.height(L_ROW_HEIGHT).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Text("$s", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            for (day in 1..TOTAL_DAYS) {
                Column(Modifier.weight(1f)) {
                    var session = 1
                    while (session <= maxSession) {
                        val cells = grid["$day-$session"]
                        if (cells != null && cells.isNotEmpty()) {
                            val span = cells[0].rowSpan
                            val cellHeight = L_ROW_HEIGHT * span
                            if (cells.size == 1) {
                                LandscapeCourseBlock(cells[0], Modifier.fillMaxWidth().height(cellHeight).padding(1.dp)) { onCellClick(cells[0]) }
                            } else {
                                LandscapeMultiCourseBlock(cells, Modifier.fillMaxWidth().height(cellHeight).padding(1.dp), onCellClick)
                            }
                            session += span
                        } else if (isCoveredByAboveL(grid, day, session)) { session++ }
                        else { Spacer(Modifier.fillMaxWidth().height(L_ROW_HEIGHT)); session++ }
                    }
                }
            }
        }
    }
}

/** 多课程切换块：底部页码指示重叠，点击切换，长按详情 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LandscapeMultiCourseBlock(cells: List<LGridCell>, modifier: Modifier, onLongClick: (LGridCell) -> Unit) {
    var currentIndex by remember { mutableIntStateOf(0) }
    val idx = currentIndex % cells.size
    val cell = cells[idx]
    val color = L_COURSE_COLORS[cell.colorIndex % L_COURSE_COLORS.size]
    val shape = RoundedCornerShape(6.dp)
    Column(modifier.clip(shape).background(color.bg).combinedClickable(
        onClick = { currentIndex = (currentIndex + 1) % cells.size },
        onLongClick = { onLongClick(cell) },
    )) {
        Box(Modifier.weight(1f).fillMaxWidth().padding(start = 3.dp)) {
            Box(Modifier.align(Alignment.CenterStart).width(3.dp).fillMaxHeight()
                .padding(vertical = 3.dp).clip(RoundedCornerShape(2.dp)).background(color.border))
            Column(Modifier.padding(start = 6.dp, end = 3.dp, top = 3.dp, bottom = 2.dp)) {
                LandscapeCourseBlockContent(cell, color)
            }
        }
        Text(
            "${idx + 1}/${cells.size}",
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp, lineHeight = 10.sp),
            color = color.text.copy(alpha = 0.55f),
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 2.dp),
        )
    }
}

@Composable
private fun LandscapeCourseBlock(cell: LGridCell, modifier: Modifier, onClick: () -> Unit) {
    val color = L_COURSE_COLORS[cell.colorIndex % L_COURSE_COLORS.size]
    Box(modifier.clip(RoundedCornerShape(6.dp)).background(color.bg).clickable(onClick = onClick).padding(start = 3.dp)) {
        Box(Modifier.align(Alignment.CenterStart).width(3.dp).fillMaxHeight().padding(vertical = 4.dp).clip(RoundedCornerShape(2.dp)).background(color.border))
        Column(Modifier.padding(start = 6.dp, end = 3.dp, top = 3.dp, bottom = 3.dp)) {
            LandscapeCourseBlockContent(cell, color)
        }
    }
}

@Composable
private fun LandscapeCourseBlockContent(cell: LGridCell, color: LCourseColor) {
    val infoStyle = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp, lineHeight = 10.sp)
    Text(
        cell.course.courseName,
        style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, lineHeight = 13.sp),
        color = color.text,
        maxLines = if (cell.rowSpan >= 2) 2 else 1,
        overflow = TextOverflow.Ellipsis,
    )
    Spacer(Modifier.height(1.dp))
    val location = listOf(cell.timePlace.teachingBuildingName, cell.timePlace.classroomName)
        .filter { it.isNotEmpty() }.joinToString(" ")
    Text(location, style = infoStyle, color = color.text.copy(alpha = 0.7f), maxLines = 2, overflow = TextOverflow.Ellipsis)
    Text(cell.course.attendClassTeacher, style = infoStyle, color = color.text.copy(alpha = 0.65f), maxLines = 1, overflow = TextOverflow.Ellipsis)
    if (cell.rowSpan >= 2) {
        Text(cell.mergedWeeks, style = infoStyle, color = color.text.copy(alpha = 0.55f), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LandscapeCourseDetailSheet(cell: LGridCell, onDismiss: () -> Unit) {
    val color = L_COURSE_COLORS[cell.colorIndex % L_COURSE_COLORS.size]
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(4.dp).height(24.dp).clip(RoundedCornerShape(2.dp)).background(color.border))
                Spacer(Modifier.width(10.dp))
                Text(cell.course.courseName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
            LandscapeDetailRow("👤 教师", cell.course.attendClassTeacher)
            LandscapeDetailRow("📚 学分", "${cell.course.unit}")
            LandscapeDetailRow("📋 课程性质", cell.course.coursePropertiesName)
            cell.course.courseCategoryName?.let { LandscapeDetailRow("🏷️ 类别", it) }
            LandscapeDetailRow("📍 地点", cell.timePlace.locationDescription)
            LandscapeDetailRow("📅 周次", cell.mergedWeeks)
            val weekdays = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")
            val dayStr = if (cell.timePlace.classDay in 1..7) weekdays[cell.timePlace.classDay] else ""
            LandscapeDetailRow("🕐 时间", "$dayStr 第${cell.timePlace.classSessions}-${cell.timePlace.endSession}节")
            LandscapeDetailRow("📝 考试方式", cell.course.examTypeName)
        }
    }
}

@Composable
private fun LandscapeDetailRow(label: String, value: String) {
    if (value.isBlank()) return
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(90.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
