package tech.loveace.appv3.ui.screen

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.SwipeLeft
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.ScheduleCourse
import tech.loveace.appv3.data.model.ScheduleTimePlace
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ScheduleViewModel
import tech.loveace.appv3.ui.viewmodel.SemesterStatus
import tech.loveace.appv3.ui.viewmodel.SemesterViewModel
import tech.loveace.appv3.util.ScheduleImageExporter

// DataStore for schedule tips preference
private val android.content.Context.scheduleTipsStore by preferencesDataStore("schedule_tips")
private val KEY_HIDE_TIPS = booleanPreferencesKey("hide_schedule_tips")

private val WEEKDAYS = listOf("一", "二", "三", "四", "五", "六", "日")
private const val MAX_SESSION = 12
private const val TOTAL_DAYS = 7
private val TIME_COL_WIDTH = 36.dp
private val ROW_HEIGHT = 62.dp
private val HEADER_HEIGHT = 32.dp
private val DAY_COL_WIDTH = 72.dp

private data class CourseColor(val bg: Color, val border: Color, val text: Color)

private val COURSE_COLORS = listOf(
    CourseColor(Color(0x2E0078D4), Color(0x800078D4), Color(0xFF0063B1.toInt())),
    CourseColor(Color(0x2E107C10), Color(0x80107C10), Color(0xFF0E6E0E.toInt())),
    CourseColor(Color(0x2E881798), Color(0x80881798), Color(0xFF6B1076.toInt())),
    CourseColor(Color(0x2ECA5010), Color(0x80CA5010), Color(0xFFA34D0A.toInt())),
    CourseColor(Color(0x2E0063B1), Color(0x800063B1), Color(0xFF004E8C.toInt())),
    CourseColor(Color(0x2EE3008C), Color(0x80E3008C), Color(0xFFB3006E.toInt())),
    CourseColor(Color(0x2E008575), Color(0x80008575), Color(0xFF006A5D.toInt())),
    CourseColor(Color(0x2E8E562E), Color(0x808E562E), Color(0xFF6E4224.toInt())),
    CourseColor(Color(0x2E0099BC), Color(0x800099BC), Color(0xFF007A96.toInt())),
    CourseColor(Color(0x2E7A7574), Color(0x807A7574), Color(0xFF3B3A39.toInt())),
)

private data class GridCell(
    val course: ScheduleCourse,
    val timePlace: ScheduleTimePlace,
    val rowSpan: Int,
    val colorIndex: Int,
    val mergedWeeks: String,
)

private fun buildGrid(courses: List<ScheduleCourse>): Map<String, List<GridCell>> {
    val courseColorMap = mutableMapOf<String, Int>()
    var colorIdx = 0
    data class TempEntry(val course: ScheduleCourse, val tp: ScheduleTimePlace)
    val tempGrid = mutableMapOf<String, MutableList<TempEntry>>()
    for (course in courses) {
        if (!courseColorMap.containsKey(course.courseCode)) {
            courseColorMap[course.courseCode] = colorIdx % COURSE_COLORS.size
            colorIdx++
        }
        for (tp in course.timeAndPlaceList) {
            val key = "${tp.classDay}-${tp.classSessions}"
            tempGrid.getOrPut(key) { mutableListOf() }.add(TempEntry(course, tp))
        }
    }
    val grid = mutableMapOf<String, List<GridCell>>()
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
            GridCell(entry.course, entry.tp, gk.span, courseColorMap[entry.course.courseCode] ?: 0, mergeWeeks(weeks))
        }
    }
    return grid
}

private fun mergeWeeks(weeks: List<String>): String {
    val unique = weeks.distinct()
    if (unique.size == 1) return unique[0]
    val joined = unique.joinToString(",")
    return if (joined.length > 15) "${unique[0]}等" else joined
}

private fun isCoveredByAbove(grid: Map<String, List<GridCell>>, day: Int, session: Int): Boolean {
    for (s in (session - 1) downTo 1) {
        val cells = grid["$day-$s"] ?: continue
        if (cells.any { s + it.rowSpan > session }) return true
    }
    return false
}

/** 按教学周过滤课程：classWeek 是 01 串（第 i 位 = 第 i+1 周），空/越界视为不限周 */
private fun filterCoursesByWeek(courses: List<ScheduleCourse>, week: Int): List<ScheduleCourse> =
    courses.mapNotNull { course ->
        val filtered = course.timeAndPlaceList.filter { tp ->
            tp.classWeek.isEmpty() || week <= 0 || week > tp.classWeek.length || tp.classWeek[week - 1] == '1'
        }
        if (filtered.isEmpty()) null else course.copy(timeAndPlaceList = filtered)
    }

/** 今天是周几（1=周一 … 7=周日） */
private fun todayDayIndex(): Int {
    val dow = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_WEEK)
    return if (dow == 1) 7 else dow - 1
}

private fun getMaxUsedSession(grid: Map<String, List<GridCell>>): Int {
    var max = 0
    for ((key, cells) in grid) {
        val session = key.split("-").getOrNull(1)?.toIntOrNull() ?: continue
        for (cell in cells) { val end = session + cell.rowSpan - 1; if (end > max) max = end }
    }
    return max.coerceIn(8, MAX_SESSION)
}

// ==================== 主界面 ====================
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: ScheduleViewModel = viewModel(),
    semesterVm: SemesterViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val semesterState by semesterVm.uiState.collectAsStateWithLifecycle()
    var selectedCell by remember { mutableStateOf<GridCell?>(null) }
    var showTipsDialog by remember { mutableStateOf(false) }
    var showExportDialog by remember { mutableStateOf(false) }
    // 0 = 整学期总览（默认），1 = 分周视图
    var viewMode by remember { mutableIntStateOf(0) }
    var selectedWeek by remember { mutableIntStateOf(0) }

    val semStatus = semesterState.status
    val currentWeek = (semStatus as? SemesterStatus.InSession)?.currentWeek ?: 0
    val totalWeeks = (semStatus as? SemesterStatus.InSession)?.totalWeeks ?: 0
    // 教学周数据到位后把分周视图定位到本周（仅首次/学期周变化时）
    LaunchedEffect(currentWeek) {
        if (currentWeek > 0) selectedWeek = currentWeek
    }

    // 读取"不再提示"偏好
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val hideTips by context.scheduleTipsStore.data
        .map { it[KEY_HIDE_TIPS] ?: false }
        .collectAsState(initial = true) // 默认 true 避免闪烁，加载后会更新

    // 首次进入自动弹出教学（如果没有永久关闭）
    var tipsChecked by remember { mutableStateOf(false) }
    LaunchedEffect(hideTips) {
        if (!tipsChecked && !hideTips) {
            showTipsDialog = true
            tipsChecked = true
        } else if (!tipsChecked) {
            tipsChecked = true
        }
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

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("课程表") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
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
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
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
                    // 视图切换：整学期总览 / 分周视图
                    SingleChoiceSegmentedButtonRow(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        SegmentedButton(
                            selected = viewMode == 0,
                            onClick = { viewMode = 0 },
                            shape = SegmentedButtonDefaults.itemShape(0, 2),
                        ) { Text("整学期") }
                        SegmentedButton(
                            selected = viewMode == 1,
                            onClick = { viewMode = 1 },
                            shape = SegmentedButtonDefaults.itemShape(1, 2),
                        ) { Text("分周") }
                    }
                    if (viewMode == 1) {
                        val effectiveWeek = selectedWeek.coerceAtLeast(1)
                        val weekCourses = remember(state.courses, effectiveWeek) {
                            filterCoursesByWeek(state.courses, effectiveWeek)
                        }
                        val grid = remember(weekCourses) { buildGrid(weekCourses) }
                        val maxSession = remember(grid) { getMaxUsedSession(grid) }
                        WeekPicker(
                            selectedWeek = effectiveWeek,
                            currentWeek = currentWeek,
                            totalWeeks = totalWeeks.coerceAtLeast(effectiveWeek),
                            onSelect = { selectedWeek = it },
                        )
                        // 周统计条：第 X 周 · N 门课 · M 节 + 本周标记
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                "第 $effectiveWeek 周 · ${weekCourses.size} 门课 · ${weekCourses.sumOf { it.timeAndPlaceList.size }} 节",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (currentWeek == effectiveWeek) {
                                RibbonChip("本周", tone = RibbonTone.PRIMARY, filled = true)
                            }
                        }
                        ScheduleGrid(
                            grid = grid,
                            maxSession = maxSession,
                            highlightToday = currentWeek == effectiveWeek,
                            onCellClick = { selectedCell = it },
                        )
                    } else {
                        val grid = remember(state.courses) { buildGrid(state.courses) }
                        val maxSession = remember(grid) { getMaxUsedSession(grid) }
                        SwipeHintRow(courseCount = state.courses.size, totalUnits = state.totalUnits)
                        ScheduleGrid(grid = grid, maxSession = maxSession, onCellClick = { selectedCell = it })
                    }
                }
            }
        }
    }

    selectedCell?.let { cell -> CourseDetailSheet(cell = cell, onDismiss = { selectedCell = null }) }

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
        ScheduleTipsDialog(
            onDismiss = { showTipsDialog = false },
            onDismissForever = {
                showTipsDialog = false
                scope.launch { context.scheduleTipsStore.edit { it[KEY_HIDE_TIPS] = true } }
            },
        )
    }
}

/** 使用教学弹窗 */
@Composable
private fun ScheduleTipsDialog(onDismiss: () -> Unit, onDismissForever: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Default.HelpOutline, null) },
        title = { Text("课程表使用提示") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TipItem("👆 点击课程格子", "查看课程详情")
                TipItem("👆 重叠课程（底部彩色条）", "点击可切换不同课程，底部色条显示课程数量和当前选中")
                TipItem("👆 长按重叠课程", "直接查看当前课程详情")
                TipItem("👈👉 左右滑动", "查看周六、周日的课程")
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("知道了") } },
        dismissButton = { TextButton(onClick = onDismissForever) { Text("不再提示") } },
    )
}

@Composable
private fun TipItem(action: String, desc: String) {
    Column {
        Text(action, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Text(desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** 统计信息 + 首次滑动提示 */
@Composable
private fun SwipeHintRow(courseCount: Int, totalUnits: Double) {
    var showHint by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) { delay(3000); showHint = false }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("共 ${courseCount} 门课 · $totalUnits 学分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        AnimatedVisibility(visible = showHint, exit = fadeOut() + shrinkHorizontally()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.SwipeLeft, null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(4.dp))
                Text("左右滑动查看更多", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

// ==================== 网格组件 ====================

/** 分周模式的周选择器：横向 pill，当前周描边、选中填充，自动滚动居中 */
@Composable
private fun WeekPicker(
    selectedWeek: Int,
    currentWeek: Int,
    totalWeeks: Int,
    onSelect: (Int) -> Unit,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(selectedWeek, totalWeeks) {
        if (totalWeeks > 0) {
            listState.animateScrollToItem(index = (selectedWeek - 1).coerceIn(0, totalWeeks - 1))
        }
    }
    LazyRow(
        state = listState,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(count = totalWeeks) { index ->
            val week = index + 1
            val selected = week == selectedWeek
            val isCurrent = week == currentWeek
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        if (selected) MaterialTheme.colorScheme.primary else Color.Transparent,
                    )
                    .then(
                        if (!selected && isCurrent) {
                            Modifier.border(
                                1.5.dp,
                                MaterialTheme.colorScheme.primary,
                                RoundedCornerShape(10.dp),
                            )
                        } else {
                            Modifier
                        }
                    )
                    .clickable { onSelect(week) }
                    .size(width = 36.dp, height = 44.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "$week",
                        fontSize = 14.sp,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary
                            else if (isCurrent) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "周",
                        fontSize = 9.sp,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun ScheduleGrid(
    grid: Map<String, List<GridCell>>,
    maxSession: Int,
    onCellClick: (GridCell) -> Unit,
    highlightToday: Boolean = false,
) {
    val horizontalScroll = rememberScrollState()
    val verticalScroll = rememberScrollState()
    val today = if (highlightToday) todayDayIndex() else 0
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth()) {
            Box(Modifier.width(TIME_COL_WIDTH).height(HEADER_HEIGHT), contentAlignment = Alignment.Center) {}
            Row(Modifier.horizontalScroll(horizontalScroll)) {
                for (d in 1..TOTAL_DAYS) {
                    val isToday = d == today
                    Column(
                        Modifier.width(DAY_COL_WIDTH).height(HEADER_HEIGHT),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            "周${WEEKDAYS[d - 1]}",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = if (isToday) MaterialTheme.colorScheme.primary else Color.Unspecified,
                        )
                        if (isToday) {
                            Box(Modifier.size(4.dp).background(MaterialTheme.colorScheme.primary, CircleShape))
                        }
                    }
                }
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        Row(Modifier.fillMaxSize().verticalScroll(verticalScroll)) {
            Column(Modifier.width(TIME_COL_WIDTH)) {
                for (s in 1..maxSession) {
                    Box(Modifier.height(ROW_HEIGHT).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Text("$s", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            Row(Modifier.horizontalScroll(horizontalScroll)) {
                for (day in 1..TOTAL_DAYS) { ScheduleDayColumn(grid, day, maxSession, DAY_COL_WIDTH, ROW_HEIGHT, onCellClick) }
            }
        }
    }
}

@Composable
private fun ScheduleDayColumn(grid: Map<String, List<GridCell>>, day: Int, maxSession: Int, colWidth: Dp, rowHeight: Dp, onCellClick: (GridCell) -> Unit) {
    Column(Modifier.width(colWidth)) {
        var session = 1
        while (session <= maxSession) {
            val cells = grid["$day-$session"]
            if (cells != null && cells.isNotEmpty()) {
                val span = cells[0].rowSpan
                val cellHeight = rowHeight * span
                if (cells.size == 1) {
                    CourseBlock(cells[0], Modifier.fillMaxWidth().height(cellHeight).padding(1.dp)) { onCellClick(cells[0]) }
                } else {
                    MultiCourseBlock(cells, Modifier.fillMaxWidth().height(cellHeight).padding(1.dp), onCellClick)
                }
                session += span
            } else if (isCoveredByAbove(grid, day, session)) { session++ }
            else { Spacer(Modifier.fillMaxWidth().height(rowHeight)); session++ }
        }
    }
}

/** 多课程切换块：底部数字指示重叠，点击切换，长按详情 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MultiCourseBlock(cells: List<GridCell>, modifier: Modifier, onLongClick: (GridCell) -> Unit) {
    var currentIndex by remember { mutableIntStateOf(0) }
    val idx = currentIndex % cells.size
    val cell = cells[idx]
    val color = COURSE_COLORS[cell.colorIndex % COURSE_COLORS.size]
    val shape = RoundedCornerShape(6.dp)
    Column(modifier.clip(shape).background(color.bg).combinedClickable(
        onClick = { currentIndex = (currentIndex + 1) % cells.size },
        onLongClick = { onLongClick(cell) },
    )) {
        // 课程内容区
        Box(Modifier.weight(1f).fillMaxWidth().padding(start = 3.dp)) {
            Box(Modifier.align(Alignment.CenterStart).width(3.dp).fillMaxHeight()
                .padding(vertical = 3.dp).clip(RoundedCornerShape(2.dp)).background(color.border))
            Column(Modifier.padding(start = 6.dp, end = 3.dp, top = 3.dp, bottom = 2.dp)) {
                CourseBlockContent(cell, color)
            }
        }
        // 底部页码
        Text(
            "${idx + 1}/${cells.size}",
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp, lineHeight = 10.sp),
            color = color.text.copy(alpha = 0.55f),
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 2.dp),
        )
    }
}

@Composable
private fun CourseBlock(cell: GridCell, modifier: Modifier, onClick: () -> Unit) {
    val color = COURSE_COLORS[cell.colorIndex % COURSE_COLORS.size]
    Box(modifier.clip(RoundedCornerShape(6.dp)).background(color.bg).clickable(onClick = onClick).padding(start = 3.dp)) {
        Box(Modifier.align(Alignment.CenterStart).width(3.dp).fillMaxHeight().padding(vertical = 4.dp).clip(RoundedCornerShape(2.dp)).background(color.border))
        Column(Modifier.padding(start = 6.dp, end = 3.dp, top = 3.dp, bottom = 3.dp)) { CourseBlockContent(cell, color) }
    }
}

@Composable
private fun CourseBlockContent(cell: GridCell, color: CourseColor) {
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

// ==================== 课程详情 BottomSheet ====================
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CourseDetailSheet(cell: GridCell, onDismiss: () -> Unit) {
    val color = COURSE_COLORS[cell.colorIndex % COURSE_COLORS.size]
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(4.dp).height(24.dp).clip(RoundedCornerShape(2.dp)).background(color.border))
                Spacer(Modifier.width(10.dp))
                Text(cell.course.courseName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
            DetailRow("👤 教师", cell.course.attendClassTeacher)
            DetailRow("📚 学分", "${cell.course.unit}")
            DetailRow("📋 课程性质", cell.course.coursePropertiesName)
            cell.course.courseCategoryName?.let { DetailRow("🏷️ 类别", it) }
            DetailRow("📍 地点", cell.timePlace.locationDescription)
            DetailRow("📅 周次", cell.mergedWeeks)
            val weekdays = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")
            val dayStr = if (cell.timePlace.classDay in 1..7) weekdays[cell.timePlace.classDay] else ""
            DetailRow("🕐 时间", "$dayStr 第${cell.timePlace.classSessions}-${cell.timePlace.endSession}节")
            DetailRow("📝 考试方式", cell.course.examTypeName)
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    if (value.isBlank()) return
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(90.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
