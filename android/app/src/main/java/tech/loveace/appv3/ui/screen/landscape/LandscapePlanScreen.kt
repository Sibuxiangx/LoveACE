package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.PlanViewModel
import tech.loveace.appv3.util.CsvExporter

/**
 * 横屏培养方案：左侧总览 + 右侧分类详情列表
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapePlanScreen(authViewModel: AuthViewModel, vm: PlanViewModel = viewModel()) {
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

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("培养方案") },
            actions = {
                if (state.planInfo != null) {
                    IconButton(onClick = { showExportDialog = true }) {
                        Icon(Icons.Default.FileDownload, "导出CSV")
                    }
                }
            },
        )

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
            state.error != null -> RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "加载失败",
                description = state.error,
                actionText = "重试",
                onAction = { vm.loadPlan() },
            )
            state.planInfo == null -> RibbonState(kind = RibbonStateKind.EMPTY, title = "暂无数据")
            else -> {
                val plan = state.planInfo!!
                Row(
                    Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    // 左栏：总览
                    Column(
                        Modifier.weight(0.4f).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        val extended = LocalExtendedColors.current
                        val totalPassedCredits = plan.categories.sumOf { it.completedCredits }
                        val creditProgress = if (plan.estimatedGraduationCredits > 0)
                            (totalPassedCredits / plan.estimatedGraduationCredits).toFloat().coerceIn(0f, 1f) else 0f
                        val creditColor = if (creditProgress >= 1f) extended.success else MaterialTheme.colorScheme.primary

                        RibbonCard(
                            modifier = Modifier.fillMaxWidth(),
                            variant = if (plan.failedCourses > 0) RibbonCardVariant.ERROR_CONTAINER else RibbonCardVariant.PRIMARY_CONTAINER,
                            radius = 32.dp,
                            padding = PaddingValues(22.dp),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Text(
                                    plan.planName,
                                    style = MaterialTheme.typography.titleLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = ribbonContainerColor(if (plan.failedCourses > 0) RibbonCardVariant.ERROR_CONTAINER else RibbonCardVariant.PRIMARY_CONTAINER),
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(50)) {
                                        Text("专业: ${plan.major}", modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSecondaryContainer)
                                    }
                                    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(50)) {
                                        Text("年级: ${plan.grade}", modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSecondaryContainer)
                                    }
                                }
                                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))

                                // 学分进度 — 环形
                                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                                    Box(contentAlignment = Alignment.Center) {
                                        AppCircularProgressIndicator(
                                            progress = { creditProgress },
                                            modifier = Modifier.size(100.dp),
                                            color = creditColor,
                                            trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                        )
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            Text("${"%.1f".format(totalPassedCredits)}",
                                                style = RibbonNumeric.Large, color = creditColor)
                                            Text("/ ${"%.0f".format(plan.estimatedGraduationCredits)}",
                                                style = RibbonNumeric.Caption,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                    Spacer(Modifier.height(4.dp))
                                    Text("学分进度 ${"%.0f".format(creditProgress * 100)}%",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }

                                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))

                                // 统计信息 — 每行一个，环形指示器
                                CircularStatRow("总分类", plan.totalCategories, plan.totalCategories, "个")
                                CircularStatRow("已修课程", plan.totalCourses, plan.totalCourses, "门")
                                CircularStatRow("已过", plan.passedCourses, plan.totalCourses, "门",
                                    valueColor = extended.success, ringColor = extended.success)
                                CircularStatRow("尚不及格", plan.failedCourses, plan.totalCourses, "门",
                                    valueColor = if (plan.failedCourses > 0) MaterialTheme.colorScheme.error else null,
                                    ringColor = if (plan.failedCourses > 0) MaterialTheme.colorScheme.error else null)
                                if (plan.missingRequiredCourses > 0) {
                                    CircularStatRow("必修缺修", plan.missingRequiredCourses, plan.totalCourses, "门",
                                        valueColor = extended.warning, ringColor = extended.warning)
                                    Text("* 必修缺修数据来源于教务处标记",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
                                }
                            }
                        }
                    }

                    // 右栏：分类列表
                    LazyColumn(
                        Modifier.weight(0.6f),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(bottom = 16.dp),
                    ) {
                        items(plan.categories, key = { it.categoryId }) { category ->
                            LandscapePlanCategoryCard(category)
                        }
                    }
                }
            }
        }
    }
}


@Composable
private fun CircularStatRow(
    label: String, value: Int, total: Int, unit: String,
    valueColor: Color? = null, ringColor: Color? = null,
) {
    val color = valueColor ?: MaterialTheme.colorScheme.onSurface
    val ring = ringColor ?: MaterialTheme.colorScheme.primary
    val progress = if (total > 0) (value.toFloat() / total).coerceIn(0f, 1f) else 0f

    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator(
                progress = { progress },
                modifier = Modifier.size(40.dp),
                color = ring,
                trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            )
        }
        Text(label, style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            modifier = Modifier.widthIn(min = 48.dp))
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.Bottom) {
            Text("$value", style = RibbonNumeric.Medium, color = color)
            Text(unit, style = RibbonNumeric.Caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}


@Composable
private fun LandscapePlanCategoryCard(category: PlanCategory) {
    var expanded by remember { mutableStateOf(false) }
    val hasChildren = category.courses.isNotEmpty() || category.subcategories.isNotEmpty()

    RibbonCard(
        modifier = Modifier.fillMaxWidth().animateContentSize(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(0.dp),
    ) {
        Column {
            Column(
                Modifier.clip(MaterialTheme.shapes.extraLarge).clickable(enabled = hasChildren) { expanded = !expanded }.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(category.categoryName, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    if (category.isCompleted) {
                        RibbonChip("已达标", tone = RibbonTone.SUCCESS, icon = Icons.Default.CheckCircle)
                    }
                    if (hasChildren) Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, "展开", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (category.minCredits > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("最低 ${"%.1f".format(category.minCredits)} 学分 · 通过 ${"%.1f".format(category.completedCredits)} 学分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    val pColor = progressColor(category.completionPercentage)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        AppLinearProgressIndicator(
                            progress = { (category.completionPercentage / 100.0).toFloat().coerceIn(0f, 1f) },
                            modifier = Modifier.weight(1f).height(8.dp), color = pColor, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("${"%.0f".format(category.completionPercentage)}%", style = RibbonNumeric.Caption, color = pColor)
                    }
                }

                // 统计 chips
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    RibbonChip("已修 ${category.totalCourses}门", tone = RibbonTone.NEUTRAL)
                    RibbonChip("已过 ${category.passedCourses}门", tone = RibbonTone.SUCCESS)
                    if (category.failedCourses > 0) {
                        RibbonChip("尚不及格 ${category.failedCourses}门", tone = RibbonTone.ERROR)
                    }
                    if (category.missingRequiredCourses > 0) {
                        RibbonChip("必修缺修 ${category.missingRequiredCourses}门", tone = RibbonTone.WARNING)
                    }
                }
            }
            if (expanded && hasChildren) {
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    category.courses.forEach { course -> LandscapePlanCourseRow(course) }
                }
                if (category.subcategories.isNotEmpty()) {
                    Column(Modifier.padding(start = 16.dp, end = 8.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        category.subcategories.forEach { sub -> LandscapePlanCategoryCard(sub) }
                    }
                }
            }
        }
    }
}

@Composable
private fun progressColor(percentage: Double): Color = when {
    percentage >= 100 -> LocalExtendedColors.current.success
    percentage >= 80 -> MaterialTheme.colorScheme.primary
    else -> LocalExtendedColors.current.warning
}

@Composable
private fun LandscapePlanCourseRow(course: PlanCourse) {
    val statusTone = when (course.statusDescription) {
        "已通过" -> RibbonTone.SUCCESS
        "未通过" -> RibbonTone.ERROR
        else -> RibbonTone.NEUTRAL
    }
    val statusColor = when (statusTone) {
        RibbonTone.SUCCESS -> LocalExtendedColors.current.success
        RibbonTone.ERROR -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.outline
    }
    val statusIcon = when (course.statusDescription) { "已通过" -> Icons.Default.CheckCircle; "未通过" -> Icons.Default.Cancel; else -> Icons.Default.RadioButtonUnchecked }
    ListItem(
        headlineContent = { Text(buildString { if (course.courseCode.isNotEmpty()) append("[${course.courseCode}] "); append(course.courseName.ifEmpty { course.courseCode }) }, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                course.credits?.let { Text("${it}学分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                course.score?.let { Text("成绩: $it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        },
        leadingContent = { Icon(statusIcon, course.statusDescription, modifier = Modifier.size(20.dp), tint = statusColor) },
        trailingContent = {
            RibbonChip(course.statusDescription, tone = statusTone)
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}


