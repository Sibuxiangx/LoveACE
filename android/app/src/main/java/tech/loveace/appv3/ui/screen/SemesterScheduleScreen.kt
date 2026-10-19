package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ScheduleViewModel
import tech.loveace.appv3.ui.viewmodel.SemesterStatus
import tech.loveace.appv3.ui.viewmodel.SemesterViewModel

/**
 * 学期课表（分周视图）：只看教务当前学期（TermItem.isCurrent），按教学周切换。
 * 与「课表总览」（ScheduleScreen，整学期）是两个入口。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SemesterScheduleScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: ScheduleViewModel = viewModel(),
    semesterVm: SemesterViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val semesterState by semesterVm.uiState.collectAsStateWithLifecycle()
    var selectedWeek by remember { mutableIntStateOf(0) }
    var selectedCell by remember { mutableStateOf<GridCell?>(null) }

    val semStatus = semesterState.status
    val currentWeek = (semStatus as? SemesterStatus.InSession)?.currentWeek ?: 0
    val totalWeeks = (semStatus as? SemesterStatus.InSession)?.totalWeeks ?: 0
    // 教学周数据到位后定位到本周（仅首次/学期周变化时）
    LaunchedEffect(currentWeek) {
        if (currentWeek > 0) selectedWeek = currentWeek
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
            title = { Text("学期课表") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
        )
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Text(
                state.selectedTerm?.termName ?: "本学期",
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when {
                state.isLoading -> LoadingScreen()
                state.error != null -> RibbonState(
                    kind = RibbonStateKind.ERROR,
                    title = "加载失败",
                    description = state.error,
                    actionText = "重试",
                    onAction = { state.selectedTerm?.let { vm.loadSchedule(it.termCode) } },
                )
                state.courses.isEmpty() -> RibbonState(kind = RibbonStateKind.EMPTY, title = "本学期暂无课表")
                else -> {
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
                }
            }
        }
    }

    selectedCell?.let { cell -> CourseDetailSheet(cell = cell, onDismiss = { selectedCell = null }) }
}

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
                        if (selected) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent,
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

/** 按教学周过滤课程：classWeek 是 01 串（第 i 位 = 第 i+1 周），空/越界视为不限周 */
private fun filterCoursesByWeek(courses: List<tech.loveace.appv3.data.model.ScheduleCourse>, week: Int): List<tech.loveace.appv3.data.model.ScheduleCourse> =
    courses.mapNotNull { course ->
        val filtered = course.timeAndPlaceList.filter { tp ->
            tp.classWeek.isEmpty() || week <= 0 || week > tp.classWeek.length || tp.classWeek[week - 1] == '1'
        }
        if (filtered.isEmpty()) null else course.copy(timeAndPlaceList = filtered)
    }
