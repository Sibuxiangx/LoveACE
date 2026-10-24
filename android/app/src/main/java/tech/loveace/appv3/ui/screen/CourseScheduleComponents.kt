package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material3.*
import kotlinx.coroutines.flow.collect
import tech.loveace.appv3.data.model.CourseScheduleRecord
import tech.loveace.appv3.data.service.CourseScheduleService.CourseScheduleOption
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.CourseScheduleUiState
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel
import tech.loveace.appv3.ui.viewmodel.courseRecordKey

private val WEEKDAY_OPTIONS = listOf(
    "" to "全部", "1" to "周一", "2" to "周二", "3" to "周三", "4" to "周四",
    "5" to "周五", "6" to "周六", "7" to "周日",
)

/** 教务系统固定 10 节（11–12 节不排课），与桌面智能排课时间网格一致 */
private val SESSION_OPTIONS = listOf("" to "全部") + (1..10).map { "$it" to "第${it}节" }

/** 距离列表末尾还剩几条时开始加载下一页 */
private const val LOAD_MORE_THRESHOLD = 3

/**
 * 查询表单：学期 → 课程信息 → 开课范围（页面无对应 select 时整组隐藏）→ 上课时间 → 查询/重置
 */
@Composable
internal fun CourseFormPane(
    state: CourseScheduleUiState,
    vm: CourseScheduleViewModel,
    modifier: Modifier = Modifier,
) {
    if (state.terms.isEmpty()) {
        Box(modifier, contentAlignment = Alignment.Center) {
            val error = state.indexError
            if (error != null) {
                RibbonState(
                    kind = RibbonStateKind.ERROR,
                    title = "学期加载失败",
                    description = error,
                    actionText = "重试",
                    onAction = vm::retryIndex,
                )
            } else {
                LoadingScreen("正在加载学期…")
            }
        }
        return
    }

    val form = state.form
    val options = state.options
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RibbonSectionTitle("学期与课程")
        FilterDropdown(
            label = "学期",
            options = state.terms.map { it.termCode to it.termName },
            selectedCode = form.termCode,
            onSelect = { code -> vm.updateForm { it.copy(termCode = code) } },
        )
        FormTextField("课程号", form.kch) { value -> vm.updateForm { it.copy(kch = value) } }
        FormTextField("课程名", form.kcm) { value -> vm.updateForm { it.copy(kcm = value) } }
        FormTextField("授课教师", form.skjs) { value -> vm.updateForm { it.copy(skjs = value) } }

        val hasScope = options.departments.isNotEmpty() || options.campuses.isNotEmpty() ||
            options.buildings.isNotEmpty() || options.categories.isNotEmpty()
        if (hasScope) {
            RibbonSectionTitle("开课范围")
            if (options.departments.isNotEmpty()) {
                FilterDropdown(
                    label = "开课院系",
                    options = withAll(options.departments),
                    selectedCode = form.kkxsh,
                    onSelect = { code -> vm.updateForm { it.copy(kkxsh = code) } },
                )
            }
            if (options.campuses.isNotEmpty()) {
                FilterDropdown(
                    label = "开课校区",
                    options = withAll(options.campuses),
                    selectedCode = form.kkxqh,
                    onSelect = { code -> vm.updateForm { it.copy(kkxqh = code) } },
                )
            }
            if (options.buildings.isNotEmpty()) {
                FilterDropdown(
                    label = "教学楼",
                    options = withAll(options.buildings),
                    selectedCode = form.jxlh,
                    onSelect = { code -> vm.updateForm { it.copy(jxlh = code) } },
                )
            }
            if (options.categories.isNotEmpty()) {
                FilterDropdown(
                    label = "课程类别",
                    options = withAll(options.categories),
                    selectedCode = form.kclb,
                    onSelect = { code -> vm.updateForm { it.copy(kclb = code) } },
                )
            }
        }

        RibbonSectionTitle("上课时间")
        FilterDropdown(
            label = "上课星期",
            options = WEEKDAY_OPTIONS,
            selectedCode = form.skxq?.toString().orEmpty(),
            onSelect = { code -> vm.updateForm { it.copy(skxq = code.toIntOrNull()) } },
        )
        FilterDropdown(
            label = "开始节次",
            options = SESSION_OPTIONS,
            selectedCode = form.skjc?.toString().orEmpty(),
            onSelect = { code -> vm.updateForm { it.copy(skjc = code.toIntOrNull()) } },
        )

        Spacer(Modifier.height(8.dp))
        Button(
            onClick = vm::search,
            enabled = form.termCode.isNotEmpty(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = MaterialTheme.shapes.large,
        ) {
            Text("查询", style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = vm::resetFilters, modifier = Modifier.fillMaxWidth()) {
            Text("重置条件")
        }
        Spacer(Modifier.height(16.dp))
    }
}

/**
 * 结果页：首页加载、整页错误、空结果、分片列表。
 * 列表滚动接近末尾时由 [ResultList] 调用 vm.loadMore()，不一次性拉取全部。
 */
@Composable
internal fun CourseResultsPane(
    state: CourseScheduleUiState,
    vm: CourseScheduleViewModel,
    modifier: Modifier = Modifier,
) {
    when {
        !state.showResults -> RibbonState(
            kind = RibbonStateKind.EMPTY,
            title = "选择条件后查询",
            description = "在左侧设置学期与筛选条件",
            modifier = modifier,
        )
        state.isLoading -> Box(modifier, contentAlignment = Alignment.Center) {
            LoadingScreen("正在查询…")
        }
        state.error != null && state.records.isEmpty() -> RibbonState(
            kind = RibbonStateKind.ERROR,
            title = "查询失败",
            description = state.error,
            actionText = "重试",
            onAction = vm::search,
            modifier = modifier,
        )
        state.records.isEmpty() -> RibbonState(
            kind = RibbonStateKind.EMPTY,
            title = "没有符合条件的开课",
            modifier = modifier,
        )
        else -> ResultList(state, vm, modifier)
    }
}

@Composable
private fun ResultList(
    state: CourseScheduleUiState,
    vm: CourseScheduleViewModel,
    modifier: Modifier,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
            .collect { last ->
                if (last >= vm.uiState.value.records.size - LOAD_MORE_THRESHOLD) vm.loadMore()
            }
    }

    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item(key = "summary") {
            Text(
                "共 ${state.totalCount} 条开课记录",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
        items(state.records, key = { courseRecordKey(it) }) { record ->
            CourseRecordCard(record = record, onClick = { vm.select(record) })
        }
        item(key = "footer") {
            ResultFooter(state, vm)
        }
    }
}

@Composable
private fun ResultFooter(state: CourseScheduleUiState, vm: CourseScheduleViewModel) {
    Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
        val loadMoreError = state.loadMoreError
        when {
            state.isLoadingMore -> AppCircularProgressIndicator(modifier = Modifier.size(32.dp))
            loadMoreError != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    loadMoreError,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
                TextButton(onClick = vm::loadMore) { Text("重试加载") }
            }
            state.hasMore -> Spacer(Modifier.height(1.dp))
            else -> Text(
                "已显示全部 ${state.records.size} 条",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** 列表项：课程名 + 学分；教师与课序；上课时间；余量与校区 */
@Composable
internal fun CourseRecordCard(record: CourseScheduleRecord, onClick: () -> Unit) {
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 24.dp,
        padding = PaddingValues(16.dp),
        interactive = true,
        onClick = onClick,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                record.kcm ?: "未知课程",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            record.xf?.let { RibbonChip(text = "$it 学分", tone = RibbonTone.PRIMARY) }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "${record.skjs ?: "教师待定"} · 课序 ${record.kxh ?: "-"}",
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            record.scheduleDescription.ifEmpty { "时间待定" },
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(Modifier.height(4.dp))
        val capacity = "余量 ${record.bkskyl ?: "-"} / 容量 ${record.bkskrl ?: "-"}"
        val campus = record.xqm ?: record.kkxqm
        Text(
            listOfNotNull(capacity, campus).joinToString(" · "),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** 第二层：点击列表项弹出的详情，数据已在列表项中，不再请求 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CourseDetailSheet(record: CourseScheduleRecord, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                record.kcm ?: "未知课程",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "课程号 ${record.kch ?: "-"} · 课序 ${record.kxh ?: "-"} · ${record.xf ?: "-"} 学分 · ${record.xs ?: "-"} 学时",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            DetailRow("授课教师", record.skjs)
            DetailRow("上课星期", record.weekdayStr)
            DetailRow("上课节次", record.classTimeStr?.let { "第${it}节" })
            DetailRow("上课周次", record.zcsm ?: record.skzc)
            DetailRow("校区", record.xqm ?: record.kkxqm)
            DetailRow("教学楼", record.jxlm)
            DetailRow("教室", record.jasm)
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            DetailRow("课程类别", record.kclbmc)
            DetailRow("开课院系", record.kkxsjc)
            DetailRow("考试类型", record.kslxmc)
            DetailRow("课容量 / 余量", "${record.bkskrl ?: "-"} / ${record.bkskyl ?: "-"}")
            DetailRow("选课模式", record.xkmssm)
            DetailRow("面向班级", record.mxbj)
            DetailRow("学生数", record.xss?.toString())
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String?) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(96.dp),
        )
        Text(
            value?.takeIf { it.isNotBlank() } ?: "—",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun FormTextField(label: String, value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterDropdown(
    label: String,
    options: List<Pair<String, String>>,
    selectedCode: String,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = options.firstOrNull { it.first == selectedCode }?.second
        ?: options.firstOrNull()?.second.orEmpty()
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selectedName,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(),
            singleLine = true,
            shape = MaterialTheme.shapes.large,
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
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

/** 页面下拉选项前追加“全部”（空代码 = 不限） */
private fun withAll(options: List<CourseScheduleOption>): List<Pair<String, String>> =
    listOf("" to "全部") + options.map { it.code to it.name }
