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
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.viewmodel.CourseScheduleUiState
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel
import tech.loveace.appv3.ui.viewmodel.courseRecordKey

/** 上课星期：值 1..7，显示单字 */
private val WEEKDAY_CHIPS = listOf(
    "1" to "一", "2" to "二", "3" to "三", "4" to "四", "5" to "五", "6" to "六", "7" to "日",
)

/** 开始节次：教务系统固定 10 节（11–12 节不排课），与桌面时间网格一致 */
private val SESSION_CHIPS = (1..10).map { "$it" to "$it" }

/** 距离列表末尾还剩几条时开始加载下一页 */
private const val LOAD_MORE_THRESHOLD = 3

/**
 * 查询表单：常用条件在上（学期、课程名、课程号/教师、星期、节次），
 * 院系/校区/教学楼/类别收进“更多条件”折叠区；查询与重置固定在底部。
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
    val hasScope = options.departments.isNotEmpty() || options.campuses.isNotEmpty() ||
        options.buildings.isNotEmpty() || options.categories.isNotEmpty()

    Column(modifier) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RibbonSectionTitle("学期与课程")
            FilterDropdown(
                label = "学期",
                options = state.terms.map { it.termCode to it.termName },
                selectedCode = form.termCode,
                onSelect = { code -> vm.updateForm { it.copy(termCode = code) } },
            )
            FormTextField(label = "课程名", value = form.kcm) { value ->
                vm.updateForm { it.copy(kcm = value) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FormTextField(label = "课程号", value = form.kch, modifier = Modifier.weight(1f)) { value ->
                    vm.updateForm { it.copy(kch = value) }
                }
                FormTextField(label = "授课教师", value = form.skjs, modifier = Modifier.weight(1f)) { value ->
                    vm.updateForm { it.copy(skjs = value) }
                }
            }

            if (hasScope) {
                MoreFilters(state, vm)
            }

            RibbonSectionTitle("上课时间")
            FormSubLabel("上课星期")
            ChoiceChips(
                options = WEEKDAY_CHIPS,
                selectedCode = form.skxq?.toString().orEmpty(),
                onSelect = { code -> vm.updateForm { it.copy(skxq = code.toIntOrNull()) } },
            )
            FormSubLabel("开始节次")
            ChoiceChips(
                options = SESSION_CHIPS,
                selectedCode = form.skjc?.toString().orEmpty(),
                onSelect = { code -> vm.updateForm { it.copy(skjc = code.toIntOrNull()) } },
            )
            Text(
                "这里选的是课程开始的节次。比如 1-2 节的课，要选 1 才能查到。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        CourseFormActions(
            enabled = form.termCode.isNotEmpty(),
            onReset = vm::resetFilters,
            onSearch = vm::search,
        )
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

/** 底部固定操作栏：重置 + 查询 */
@Composable
private fun CourseFormActions(
    enabled: Boolean,
    onReset: () -> Unit,
    onSearch: () -> Unit,
) {
    Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 3.dp) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedButton(
                onClick = onReset,
                modifier = Modifier.height(52.dp),
                shape = MaterialTheme.shapes.large,
            ) {
                Text("重置")
            }
            Button(
                onClick = onSearch,
                enabled = enabled,
                modifier = Modifier.weight(1f).height(52.dp),
                shape = MaterialTheme.shapes.large,
            ) {
                Text("查询", style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

/** 单选芯片：再点一次取消选择（= 不限） */
@Composable
private fun ChoiceChips(
    options: List<Pair<String, String>>,
    selectedCode: String,
    onSelect: (String) -> Unit,
) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { (code, label) ->
            FilterChip(
                selected = code == selectedCode,
                onClick = { onSelect(if (code == selectedCode) "" else code) },
                label = { Text(label) },
            )
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
            Column(Modifier.padding(horizontal = 4.dp)) {
                Text(
                    "共 ${state.totalCount} 条开课记录",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "点击卡片可查看详细信息",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
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
