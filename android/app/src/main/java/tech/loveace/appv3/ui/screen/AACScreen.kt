package tech.loveace.appv3.ui.screen

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.CutCornerShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.AACCreditCategory
import tech.loveace.appv3.data.model.AACCreditItem
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AACViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.util.CsvExporter

private const val GRADUATION_TOTAL = 10.0
private const val PRACTICE_MIN = 1.0
private const val LABOR_REQUIRED = 4.0

/** 从分类列表中提取社会实践分数（三下乡/社会实践 项目在劳动教育/让逸竞劳分类下） */
private fun calcPracticeScore(categories: List<AACCreditCategory>): Double {
    var score = 0.0
    for (cat in categories) {
        if (cat.typeName.contains("劳动教育") || cat.typeName.contains("让逸竞劳")) {
            for (item in cat.children) {
                if (item.typeName.contains("三下乡") || item.title.contains("三下乡") || item.title.contains("社会实践")) {
                    score += item.score
                }
            }
        }
    }
    return score
}

/** 提取劳动教育分数 */
private fun calcLaborScore(categories: List<AACCreditCategory>): Double {
    return categories.filter { it.typeName.contains("劳动教育") || it.typeName.contains("让逸竞劳") }
        .sumOf { it.totalScore }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AACScreen(authViewModel: AuthViewModel, vm: AACViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.aacService) {
        authViewModel.aacService?.let { vm.init(it); vm.loadAll() }
    }

    val context = LocalContext.current
    var showExportDialog by remember { mutableStateOf(false) }

    if (showExportDialog) {
        ExportDialog(
            title = "导出爱安财数据",
            description = "将导出所有爱安财分类及明细数据为 CSV 文件，保存到下载目录。",
            onExport = { CsvExporter.exportAACScores(context, state.categories) },
            onDismiss = { showExportDialog = false },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("爱安财") },
                actions = {
                    if (state.categories.isNotEmpty()) {
                        IconButton(onClick = { showExportDialog = true }) {
                            Icon(Icons.Default.FileDownload, "导出CSV")
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> LoadingScreen()
            state.error != null -> ErrorScreen(state.error!!) { vm.loadAll() }
            else -> {
                val info = state.creditInfo
                val categories = state.categories
                val practiceScore = remember(categories) { calcPracticeScore(categories) }
                val laborScore = remember(categories) { calcLaborScore(categories) }
                val effectiveTotal = (info?.totalScore ?: 0.0) + practiceScore
                val isOverflow = effectiveTotal >= GRADUATION_TOTAL

                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    if (info != null) {
                        item { GraduationProgressCard(info.totalScore, practiceScore, laborScore, effectiveTotal, isOverflow, info.isTypeAdopt, info.typeAdoptResult) }
                    }
                    // 分类卡片
                    items(categories, key = { it.id }) { category ->
                        val index = categories.indexOf(category)
                        CategoryCard(category, index)
                    }
                }
            }
        }
    }
}



@Composable
private fun GraduationProgressCard(
    totalScore: Double,
    practiceScore: Double,
    laborScore: Double,
    effectiveTotal: Double,
    isOverflow: Boolean,
    isTypeAdopt: Boolean,
    typeAdoptResult: String,
) {
    ElevatedCard(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
    ) {
        Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // 标题行 + 达标状态
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("毕业要求", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("毕业需 ${GRADUATION_TOTAL.toInt()} 分",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                val adoptColor = if (isTypeAdopt) Color(0xFF2E7D32) else Color(0xFFE65100)
                val adoptBg = if (isTypeAdopt) Color(0xFF2E7D32).copy(alpha = 0.12f) else Color(0xFFE65100).copy(alpha = 0.12f)
                AssistChip(
                    onClick = {},
                    label = { Text(if (isTypeAdopt) "已达标" else "未达标", fontWeight = FontWeight.SemiBold) },
                    leadingIcon = {
                        Icon(
                            if (isTypeAdopt) Icons.Default.CheckCircle else Icons.Default.Cancel,
                            null, modifier = Modifier.size(16.dp)
                        )
                    },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = adoptBg,
                        labelColor = adoptColor,
                        leadingIconContentColor = adoptColor,
                    ),
                    border = null,
                )
            }

            // 总分显示
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    "%.1f".format(totalScore),
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (practiceScore > 0) {
                    Text(
                        " + %.1f".format(practiceScore),
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f),
                    )
                }
                Text(
                    " / ${GRADUATION_TOTAL.toInt()} 分",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // 进度条：溢出用 indeterminate 波浪动画，未满用确定进度
            if (isOverflow) {
                AppLinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth().height(12.dp),
                    color = MaterialTheme.colorScheme.tertiary,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                )
            } else {
                AppLinearProgressIndicator(
                    progress = { (effectiveTotal / GRADUATION_TOTAL).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(12.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                )
            }

            // 两项指标明细（带 wavy ring）
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                RequirementWavyCard(
                    label = "社会实践",
                    current = practiceScore,
                    required = PRACTICE_MIN,
                    modifier = Modifier.weight(1f),
                )
                RequirementWavyCard(
                    label = "劳动教育",
                    current = laborScore,
                    required = LABOR_REQUIRED,
                    modifier = Modifier.weight(1f),
                )
            }

            // 未达标原因
            if (!isTypeAdopt && typeAdoptResult.isNotEmpty()) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = Color(0xFFE65100).copy(alpha = 0.08f),
                    ),
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Info, null, modifier = Modifier.size(16.dp), tint = Color(0xFFE65100))
                        Spacer(Modifier.width(8.dp))
                        Text(typeAdoptResult, style = MaterialTheme.typography.bodySmall, color = Color(0xFFE65100))
                    }
                }
            }
        }
    }
}


/** 带 wavy ring 的指标卡片 */

@Composable
private fun RequirementWavyCard(label: String, current: Double, required: Double, modifier: Modifier = Modifier) {
    val met = current >= required
    val progress = (current / required).toFloat().coerceIn(0f, 1f)
    val color = if (met) Color(0xFF2E7D32) else MaterialTheme.colorScheme.primary
    val bg = if (met) Color(0xFF2E7D32).copy(alpha = 0.08f) else MaterialTheme.colorScheme.surfaceContainerHigh

    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = bg),
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(
            Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Wavy ring
            Box(contentAlignment = Alignment.Center) {
                if (met) {
                    AppCircularProgressIndicator(
                        modifier = Modifier.size(40.dp),
                        color = color,
                        trackColor = color.copy(alpha = 0.3f),
                    )
                } else {
                    AppCircularProgressIndicator(
                        progress = { progress },
                        modifier = Modifier.size(40.dp),
                        color = color,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                }
            }
            Column(Modifier.weight(1f)) {
                Text(label, style = MaterialTheme.typography.labelMedium, color = color)
                Text(
                    "${"%.1f".format(current)}/${required.let { if (it == it.toLong().toDouble()) it.toInt().toString() else "%.1f".format(it) }}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = color,
                )
            }
            if (met) {
                Icon(Icons.Default.CheckCircle, null, tint = color, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/** 分类卡片 - M3E 风格 */

@Composable
private fun CategoryCard(category: AACCreditCategory, index: Int = 0) {
    var expanded by remember { mutableStateOf(false) }
    
    // 根据索引选择不同的形状、颜色和图标
    val (shape, containerColor, icon) = remember(index) {
        val shapes = listOf(
            Triple(CircleShape, Color(0xFF1976D2), Icons.Default.School),
            Triple(RoundedCornerShape(12.dp), Color(0xFF7B1FA2), Icons.Default.EmojiEvents),
            Triple(CutCornerShape(topStart = 12.dp, bottomEnd = 12.dp), Color(0xFF00796B), Icons.Default.VolunteerActivism),
            Triple(RoundedCornerShape(topStart = 16.dp, topEnd = 4.dp, bottomStart = 4.dp, bottomEnd = 16.dp), Color(0xFFE64A19), Icons.Default.Groups),
            Triple(RoundedCornerShape(8.dp), Color(0xFF5D4037), Icons.Default.WorkspacePremium),
            Triple(CircleShape, Color(0xFF0288D1), Icons.Default.AutoAwesome),
        )
        shapes[index % shapes.size]
    }

    Card(
        modifier = Modifier.fillMaxWidth().animateContentSize(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column {
            // 标题行 - 可点击展开
            ListItem(
                modifier = Modifier.clip(MaterialTheme.shapes.extraLarge).clickable(enabled = category.children.isNotEmpty()) { expanded = !expanded },
                headlineContent = {
                    Text(category.typeName, fontWeight = FontWeight.SemiBold)
                },
                supportingContent = {
                    Text("${category.children.size} 项记录")
                },
                leadingContent = {
                    Box(
                        Modifier.size(48.dp).background(containerColor.copy(alpha = 0.15f), shape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "%.0f".format(category.totalScore),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = containerColor,
                            )
                            Text(
                                "分",
                                style = MaterialTheme.typography.labelSmall,
                                color = containerColor.copy(alpha = 0.8f),
                            )
                        }
                    }
                },
                trailingContent = {
                    if (category.children.isNotEmpty()) {
                        Icon(
                            if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                            "展开",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )

            // 展开的详情列表
            if (expanded && category.children.isNotEmpty()) {
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                    category.children.forEach { item ->
                        CreditItemRow(item)
                    }
                }
            }
        }
    }
}

/** 单条学分记录 - 使用 ListItem */
@Composable
private fun CreditItemRow(item: AACCreditItem) {
    val isPractice = item.typeName.contains("三下乡") || item.title.contains("三下乡") || item.title.contains("社会实践")
    val scoreColor = when {
        item.score >= 10 -> Color(0xFFC62828)
        item.score >= 5 -> Color(0xFFE65100)
        item.score >= 2 -> Color(0xFF1565C0)
        else -> Color(0xFF2E7D32)
    }

    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isPractice) {
                    Icon(
                        Icons.Default.VolunteerActivism, null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(4.dp))
                }
                Text(item.title, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
            }
        },
        supportingContent = {
            Column {
                if (item.typeName.isNotEmpty()) {
                    Text(item.typeName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (item.addTime.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Schedule, null, modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(4.dp))
                        Text(item.addTime, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        },
        trailingContent = {
            Surface(
                color = scoreColor.copy(alpha = 0.12f),
                shape = MaterialTheme.shapes.small,
            ) {
                Text(
                    "+${"%.1f".format(item.score)}",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = scoreColor,
                )
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
