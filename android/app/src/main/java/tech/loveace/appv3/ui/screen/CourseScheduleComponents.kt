package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import kotlinx.coroutines.flow.collect
import tech.loveace.appv3.data.model.CourseScheduleRecord
import tech.loveace.appv3.data.service.CourseScheduleService.CourseScheduleOption
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonSlotGrid
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.CourseScheduleUiState
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel
import tech.loveace.appv3.ui.viewmodel.courseRecordKey

/** 上课星期：值 1..7，显示单字 */
private val WEEKDAY_OPTIONS = listOf(
    1 to "一", 2 to "二", 3 to "三", 4 to "四", 5 to "五", 6 to "六", 7 to "日",
)

/** 开始节次：教务系统固定 10 节（11–12 节不排课），与桌面时间网格一致 */
private val SESSION_OPTIONS = (1..10).map { it to "$it" }

/** 距离列表末尾还剩几条时开始加载下一页 */
private const val LOAD_MORE_THRESHOLD = 3

/**
 * 筛选 sheet：学期、课程名称、课程号、教师、星期、开始节次；
 * 院系/校区/教学楼/类别收进“更多条件”。草稿在 sheet 里编辑，点“查询”才生效。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CourseFilterSheet(
    state: CourseScheduleUiState,
    vm: CourseScheduleViewModel,
    onDismiss: () -> Unit,
    onSearch: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val form = state.form
    val options = state.options
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "筛选",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = vm::resetFilters) { Text("重置") }
            }
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (state.terms.isNotEmpty()) {
                    RibbonSectionTitle("学期")
                    FilterDropdown(
                        label = "学期",
                        options = state.terms.map { it.termCode to it.termName },
                        selectedCode = form.termCode,
                        onSelect = { code -> vm.updateForm { it.copy(termCode = code) } },
                    )
                }
                RibbonSectionTitle("课程与教师")
                FormTextField(label = "课程名称", value = form.kcm) { value ->
                    vm.updateForm { it.copy(kcm = value) }
                }
                FormTextField(label = "课程号", value = form.kch) { value ->
                    vm.updateForm { it.copy(kch = value) }
                }
                FormTextField(label = "授课教师", value = form.skjs) { value ->
                    vm.updateForm { it.copy(skjs = value) }
                }
                RibbonSectionTitle("上课时间")
                FormSubLabel("上课星期")
                RibbonSlotGrid(
                    options = WEEKDAY_OPTIONS,
                    selected = setOfNotNull(form.skxq),
                    columns = 7,
                    onToggle = { day ->
                        vm.updateForm { it.copy(skxq = if (it.skxq == day) null else day) }
                    },
                )
                FormSubLabel("开始节次")
                RibbonSlotGrid(
                    options = SESSION_OPTIONS,
                    selected = setOfNotNull(form.skjc),
                    columns = 5,
                    onToggle = { section ->
                        vm.updateForm { it.copy(skjc = if (it.skjc == section) null else section) }
                    },
                )
                Text(
                    "开始节次是单选，只匹配课程从该节开始的记录。例如 1–2 节的课，要选 1 才能查到。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val hasScope = options.departments.isNotEmpty() || options.campuses.isNotEmpty() ||
                    options.buildings.isNotEmpty() || options.categories.isNotEmpty()
                if (hasScope) {
                    MoreFilters(state, vm)
                }
            }
            Button(
                onClick = onSearch,
                enabled = form.termCode.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = MaterialTheme.shapes.large,
            ) {
                Text("查询", style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

/** 低频条件折叠区：标题行显示已选数量，展开后才渲染下拉 */
@Composable
private fun MoreFilters(state: CourseScheduleUiState, vm: CourseScheduleViewModel) {
    val form = state.form
    val options = state.options
    var expanded by rememberSaveable { mutableStateOf(false) }
    val activeCount = listOf(form.kkxsh, form.kkxqh, form.jxlh, form.kclb).count { it.isNotEmpty() }

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
                "更多条件",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            if (activeCount > 0) {
                RibbonChip(text = "已选 $activeCount", tone = RibbonTone.PRIMARY)
            }
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = if (expanded) "收起更多条件" else "展开更多条件",
            )
        }

        if (expanded) {
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
    }
}

@Composable
private fun FormSubLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/**
 * 结果区：未查询时引导点右上角“筛选”；学期加载失败给重试；查询中、失败、空结果、分页列表。
 */
@Composable
internal fun CourseResultsPane(
    state: CourseScheduleUiState,
    vm: CourseScheduleViewModel,
    modifier: Modifier = Modifier,
) {
    val applied = state.applied
    when {
        applied == null && state.indexError != null -> RibbonState(
            kind = RibbonStateKind.ERROR,
            title = "无法加载学期",
            description = state.indexError,
            actionText = "重试",
            onAction = vm::retryIndex,
            modifier = modifier,
        )
        applied == null && state.indexLoading -> Box(modifier, contentAlignment = Alignment.Center) {
            LoadingScreen("正在加载学期…")
        }
        applied == null -> RibbonState(
            kind = RibbonStateKind.EMPTY,
            title = "开课查询",
            description = "点击右上角的「筛选」，选择学期和条件，再点「查询」。",
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
            description = "换个学期或放宽筛选条件试试。",
            modifier = modifier,
        )
        else -> CourseResultList(state, vm, modifier)
    }
}

/** 结果列表：顶部摘要 → 记录卡片 → 底部分页状态；接近末尾时加载下一页，不一次性拉取全部。 */
@Composable
private fun CourseResultList(
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
                courseSummary(state),
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

/** 摘要：学期 · 星期 · 第 N 节开始 · 共 X 条（与 iOS 同序） */
private fun courseSummary(state: CourseScheduleUiState): String {
    val applied = state.applied ?: return ""
    val parts = mutableListOf<String>()
    state.terms.firstOrNull { it.termCode == applied.termCode }?.let { parts.add(it.termName) }
    applied.skxq?.let { day ->
        WEEKDAY_OPTIONS.firstOrNull { it.first == day }?.let { parts.add("周${it.second}") }
    }
    applied.skjc?.let { parts.add("第 $it 节开始") }
    parts.add("共 ${state.totalCount} 条")
    return parts.joinToString(" · ")
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
private fun FormTextField(
    label: String,
    value: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onValueChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        modifier = modifier,
        shape = MaterialTheme.shapes.large,
    )
}

/** 下拉：未选时字段为空、只显示标签；菜单首项“不限”清空选择 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterDropdown(
    label: String,
    options: List<Pair<String, String>>,
    selectedCode: String,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = if (selectedCode.isEmpty()) {
        ""
    } else {
        options.firstOrNull { it.first == selectedCode }?.second.orEmpty()
    }
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

/** 下拉选项前追加“不限”（空代码 = 不限） */
private fun withAll(options: List<CourseScheduleOption>): List<Pair<String, String>> =
    listOf("" to "不限") + options.map { it.code to it.name }
