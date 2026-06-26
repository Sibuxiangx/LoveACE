package tech.loveace.appv3.ui.screen

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.PlanCategory
import tech.loveace.appv3.data.model.PlanCourse
import tech.loveace.appv3.data.model.PlanCompletionInfo
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.PlanViewModel
import tech.loveace.appv3.util.CsvExporter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanScreen(authViewModel: AuthViewModel, onBack: () -> Unit, vm: PlanViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.planService) {
        authViewModel.planService?.let { vm.init(it); vm.loadPlan() }
    }

    val context = LocalContext.current
    var showExportDialog by remember { mutableStateOf(false) }

    if (showExportDialog && state.planInfo != null) {
        val plan = state.planInfo!!
        ExportDialog(
            title = "导出培养方案",
            description = "将导出培养方案完成情况为 CSV 文件，保存到下载目录。",
            onExport = { CsvExporter.exportPlanCompletion(context, plan) },
            onDismiss = { showExportDialog = false },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("培养方案") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = {
                    if (state.planInfo != null) {
                        IconButton(onClick = { showExportDialog = true }) {
                            Icon(Icons.Default.FileDownload, "导出CSV")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            // 多培养方案 tab 栏
            if (state.planOptions.size > 1 && state.planInfo != null) {
                PrimaryScrollableTabRow(
                    selectedTabIndex = state.selectedTabIndex,
                    modifier = Modifier.fillMaxWidth(),
                    edgePadding = 16.dp,
                ) {
                    state.planOptions.forEachIndexed { index, option ->
                        Tab(
                            selected = index == state.selectedTabIndex,
                            onClick = { vm.selectTab(index) },
                            text = { Text(option.planName, maxLines = 1) },
                        )
                    }
                }
            }

            when {
                state.isLoading -> LoadingScreen()
                state.error != null -> ErrorScreen(state.error!!) { vm.loadPlan() }
                state.planInfo == null -> EmptyScreen()
                else -> {
                    val plan = state.planInfo!!
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        item { PlanSummaryCard(plan) }
                        items(plan.categories, key = { it.categoryId }) { category ->
                            PlanCategoryCard(category, depth = 0)
                        }
                    }
                }
            }
        }
    }
}

// ── 总览卡片 ──


@Composable
private fun PlanSummaryCard(plan: PlanCompletionInfo) {
    val totalPassedCredits = plan.categories.sumOf { it.completedCredits }
    val creditProgress = if (plan.estimatedGraduationCredits > 0)
        (totalPassedCredits / plan.estimatedGraduationCredits).toFloat().coerceIn(0f, 1f) else 0f
    val creditColor = when {
        creditProgress >= 1f -> Color(0xFF2E7D32)
        creditProgress >= 0.8f -> Color(0xFF1565C0)
        else -> MaterialTheme.colorScheme.primary
    }

    ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
        Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // 方案名称
            Text(plan.planName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)

            // 专业 + 年级 chips
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoChip("专业", plan.major)
                InfoChip("年级", plan.grade)
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))

            // 学分进度：已通过 / 预估毕业
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
                    Column {
                        Text("学分进度", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text("${"%.1f".format(totalPassedCredits)}",
                                style = MaterialTheme.typography.headlineMedium,
                                fontWeight = FontWeight.Bold, color = creditColor)
                            Text(" / ${"%.1f".format(plan.estimatedGraduationCredits)} 学分",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Text("${"%.0f".format(creditProgress * 100)}%",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold, color = creditColor)
                }
                AppLinearProgressIndicator(
                    progress = { creditProgress },
                    modifier = Modifier.fillMaxWidth().height(10.dp),
                    color = creditColor,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                )
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))

            // 统计信息 — 每行一个，横向线性进度
            LinearStatRow("总分类", plan.totalCategories, plan.totalCategories, "个")
            LinearStatRow("已修课程", plan.totalCourses, plan.totalCourses, "门")
            LinearStatRow("已过", plan.passedCourses, plan.totalCourses, "门",
                valueColor = Color(0xFF2E7D32), barColor = Color(0xFF2E7D32))
            LinearStatRow("尚不及格", plan.failedCourses, plan.totalCourses, "门",
                valueColor = if (plan.failedCourses > 0) Color(0xFFD32F2F) else null,
                barColor = if (plan.failedCourses > 0) Color(0xFFD32F2F) else null)
            if (plan.missingRequiredCourses > 0) {
                LinearStatRow("必修缺修", plan.missingRequiredCourses, plan.totalCourses, "门",
                    valueColor = Color(0xFFE65100), barColor = Color(0xFFE65100))
                Text("* 必修缺修数据来源于教务处标记",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
            }
        }
    }
}

@Composable
private fun InfoChip(label: String, value: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = RoundedCornerShape(50),
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text("$label: ", style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSecondaryContainer)
            Text(value, style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSecondaryContainer)
        }
    }
}


@Composable
private fun LinearStatRow(
    label: String, value: Int, total: Int, unit: String,
    valueColor: Color? = null, barColor: Color? = null,
) {
    val color = valueColor ?: MaterialTheme.colorScheme.onSurface
    val bar = barColor ?: MaterialTheme.colorScheme.primary
    val progress = if (total > 0) (value.toFloat() / total).coerceIn(0f, 1f) else 0f

    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            modifier = Modifier.widthIn(min = 48.dp))
        AppLinearProgressIndicator(
            progress = { progress },
            modifier = Modifier.weight(1f).height(6.dp),
            color = bar,
            trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
        )
        Row(verticalAlignment = Alignment.Bottom) {
            Text("$value", style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold, color = color)
            Text(unit, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ── 分类卡片 ──


@Composable
private fun PlanCategoryCard(category: PlanCategory, depth: Int) {
    var expanded by remember { mutableStateOf(false) }
    val hasChildren = category.courses.isNotEmpty() || category.subcategories.isNotEmpty()

    Card(
        modifier = Modifier.fillMaxWidth().padding(start = (depth * 12).dp).animateContentSize(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(
            containerColor = if (depth == 0) MaterialTheme.colorScheme.surfaceContainerLow
            else MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column {
            // 标题区域
            Column(
                Modifier
                    .clip(MaterialTheme.shapes.extraLarge)
                    .clickable(enabled = hasChildren) { expanded = !expanded }
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // 名称 + 达标状态
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(category.categoryName, Modifier.weight(1f),
                        style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    if (category.isCompleted) {
                        Surface(color = Color(0xFF2E7D32).copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                            Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(Icons.Default.CheckCircle, null, modifier = Modifier.size(14.dp), tint = Color(0xFF2E7D32))
                                Text("已达标", style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold, color = Color(0xFF2E7D32))
                            }
                        }
                    }
                    if (hasChildren) {
                        Icon(
                            if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                            "展开", tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                // 学分信息
                if (category.minCredits > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("最低 ", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("${"%.1f".format(category.minCredits)}", style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold)
                        Text(" 学分  ·  通过 ", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("${"%.1f".format(category.completedCredits)}", style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold, color = progressColor(category.completionPercentage))
                        Text(" 学分", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }

                    // 进度条 + 百分比
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        AppLinearProgressIndicator(
                            progress = { (category.completionPercentage / 100.0).toFloat().coerceIn(0f, 1f) },
                            modifier = Modifier.weight(1f).height(8.dp),
                            color = progressColor(category.completionPercentage),
                            trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("${"%.0f".format(category.completionPercentage)}%",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = progressColor(category.completionPercentage))
                    }
                }

                // 统计 chips
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StatChip("已修", "${category.totalCourses}门")
                    StatChip("已过", "${category.passedCourses}门", Color(0xFF2E7D32))
                    if (category.failedCourses > 0) {
                        StatChip("尚不及格", "${category.failedCourses}门", Color(0xFFD32F2F))
                    }
                    if (category.missingRequiredCourses > 0) {
                        StatChip("必修缺修", "${category.missingRequiredCourses}门", Color(0xFFE65100))
                    }
                }
            }

            // 展开内容
            if (expanded && hasChildren) {
                HorizontalDivider(Modifier.padding(horizontal = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    category.courses.forEach { course -> PlanCourseRow(course) }
                }
                // 子分类递归
                if (category.subcategories.isNotEmpty()) {
                    Column(Modifier.padding(start = 8.dp, end = 8.dp, bottom = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        category.subcategories.forEach { sub -> PlanCategoryCard(sub, depth + 1) }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatChip(label: String, value: String, color: Color? = null) {
    val chipColor = color ?: MaterialTheme.colorScheme.onSurfaceVariant
    val bg = color?.copy(alpha = 0.10f) ?: MaterialTheme.colorScheme.surfaceContainerHigh
    Surface(color = bg, shape = RoundedCornerShape(50)) {
        Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp)) {
            Text("$label ", style = MaterialTheme.typography.labelSmall, color = chipColor)
            Text(value, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = chipColor)
        }
    }
}

private fun progressColor(percentage: Double): Color = when {
    percentage >= 100 -> Color(0xFF2E7D32)
    percentage >= 80 -> Color(0xFF1565C0)
    else -> Color(0xFFE65100)
}

// ── 课程行 ──

@Composable
private fun PlanCourseRow(course: PlanCourse) {
    val statusColor = when (course.statusDescription) {
        "已通过" -> Color(0xFF2E7D32)
        "未通过" -> Color(0xFFD32F2F)
        else -> MaterialTheme.colorScheme.outline
    }
    val statusIcon = when (course.statusDescription) {
        "已通过" -> Icons.Default.CheckCircle
        "未通过" -> Icons.Default.Cancel
        else -> Icons.Default.RadioButtonUnchecked
    }

    ListItem(
        headlineContent = {
            Text(
                buildString {
                    if (course.courseCode.isNotEmpty()) append("[${course.courseCode}] ")
                    append(course.courseName.ifEmpty { course.courseCode })
                },
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (course.credits != null) {
                    Text("${course.credits}学分", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (!course.courseType.isNullOrEmpty()) {
                    Text(course.courseType, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (course.score != null) {
                    Text("成绩: ${course.score}", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        },
        leadingContent = {
            Icon(statusIcon, course.statusDescription, modifier = Modifier.size(20.dp), tint = statusColor)
        },
        trailingContent = {
            Surface(color = statusColor.copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                Text(course.statusDescription, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = statusColor)
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
