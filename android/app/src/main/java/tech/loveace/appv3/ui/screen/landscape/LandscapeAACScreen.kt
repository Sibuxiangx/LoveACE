package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.CutCornerShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
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

private fun calcPracticeScore(categories: List<AACCreditCategory>): Double {
    var score = 0.0
    for (cat in categories) {
        if (cat.typeName.contains("劳动教育") || cat.typeName.contains("让逸竞劳")) {
            for (item in cat.children) {
                if (item.typeName.contains("三下乡") || item.title.contains("三下乡") || item.title.contains("社会实践")) score += item.score
            }
        }
    }
    return score
}

private fun calcLaborScore(categories: List<AACCreditCategory>): Double =
    categories.filter { it.typeName.contains("劳动教育") || it.typeName.contains("让逸竞劳") }.sumOf { it.totalScore }

/**
 * 横屏爱安财：左侧毕业进度 + 分类选择器，右侧分类明细
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeAACScreen(authViewModel: AuthViewModel, vm: AACViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.aacService) {
        authViewModel.aacService?.let { vm.init(it); vm.loadAll() }
    }

    val context = LocalContext.current
    var showExportDialog by remember { mutableStateOf(false) }

    if (showExportDialog && state.categories.isNotEmpty()) {
        ExportDialog(
            title = "导出爱安财数据",
            description = "将导出所有爱安财分类及明细数据为 CSV 文件，保存到下载目录。",
            onExport = { CsvExporter.exportAACScores(context, state.categories) },
            onDismiss = { showExportDialog = false },
        )
    }

    Column(Modifier.fillMaxSize()) {
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

        when {
            state.isLoading -> LoadingScreen()
            state.error != null -> ErrorScreen(state.error!!) { vm.loadAll() }
            else -> {
                val info = state.creditInfo
                val categories = state.categories
                val practiceScore = remember(categories) { calcPracticeScore(categories) }
                val laborScore = remember(categories) { calcLaborScore(categories) }
                val effectiveTotal = (info?.totalScore ?: 0.0) + practiceScore
                var selectedCategory by remember { mutableStateOf<AACCreditCategory?>(null) }

                Row(
                    Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    // 左栏：毕业进度 + 分类选择器
                    Column(
                        Modifier.weight(0.4f),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        if (info != null) {
                            // 总分卡片
                            ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
                                Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                        Text("毕业要求", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                        val adoptColor = if (info.isTypeAdopt) Color(0xFF2E7D32) else Color(0xFFE65100)
                                        AssistChip(
                                            onClick = {},
                                            label = { Text(if (info.isTypeAdopt) "已达标" else "未达标", fontWeight = FontWeight.SemiBold) },
                                            leadingIcon = { Icon(if (info.isTypeAdopt) Icons.Default.CheckCircle else Icons.Default.Cancel, null, modifier = Modifier.size(16.dp)) },
                                            colors = AssistChipDefaults.assistChipColors(containerColor = adoptColor.copy(alpha = 0.12f), labelColor = adoptColor, leadingIconContentColor = adoptColor),
                                            border = null,
                                        )
                                    }
                                    Row(verticalAlignment = Alignment.Bottom) {
                                        Text("%.1f".format(info.totalScore), style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                                        if (practiceScore > 0) Text(" + %.1f".format(practiceScore), style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f))
                                        Text(" / ${GRADUATION_TOTAL.toInt()} 分", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    if (effectiveTotal >= GRADUATION_TOTAL) {
                                        AppLinearProgressIndicator(modifier = Modifier.fillMaxWidth().height(12.dp), color = MaterialTheme.colorScheme.tertiary)
                                    } else {
                                        AppLinearProgressIndicator(
                                            progress = { (effectiveTotal / GRADUATION_TOTAL).toFloat().coerceIn(0f, 1f) },
                                            modifier = Modifier.fillMaxWidth().height(12.dp),
                                            color = MaterialTheme.colorScheme.primary,
                                            trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                        )
                                    }
                                }
                            }

                            // 两项指标（wavy ring）
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                LandscapeRequirementWavyCard("社会实践", practiceScore, PRACTICE_MIN, Modifier.weight(1f))
                                LandscapeRequirementWavyCard("劳动教育", laborScore, LABOR_REQUIRED, Modifier.weight(1f))
                            }
                        }

                        // 分类选择器
                        LazyColumn(
                            Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            contentPadding = PaddingValues(bottom = 16.dp),
                        ) {
                            itemsIndexed(categories, key = { _, cat -> cat.id }) { index, category ->
                                val isSelected = selectedCategory?.id == category.id
                                LandscapeCategorySelectorItem(category, index, isSelected) {
                                    selectedCategory = if (isSelected) null else category
                                }
                            }
                        }
                    }

                    // 右栏：分类明细
                    Column(Modifier.weight(0.6f)) {
                        val cat = selectedCategory
                        if (cat != null && cat.children.isNotEmpty()) {
                            Text("${cat.typeName}（${cat.children.size} 项）",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(bottom = 12.dp))
                            LazyColumn(
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                                contentPadding = PaddingValues(bottom = 16.dp),
                            ) {
                                items(cat.children, key = { it.id }) { item ->
                                    LandscapeCreditItemRow(item)
                                }
                            }
                        } else {
                            // 空状态提示
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Icon(Icons.Default.TouchApp, null,
                                        modifier = Modifier.size(48.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f))
                                    Text("点击左侧分类查看明细",
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// 分类样式配置
private data class CategoryStyle(val shape: Shape, val color: Color)

private val CATEGORY_STYLES = listOf(
    CategoryStyle(CircleShape, Color(0xFF1976D2)),
    CategoryStyle(RoundedCornerShape(12.dp), Color(0xFF7B1FA2)),
    CategoryStyle(CutCornerShape(topStart = 12.dp, bottomEnd = 12.dp), Color(0xFF00796B)),
    CategoryStyle(RoundedCornerShape(topStart = 16.dp, topEnd = 4.dp, bottomStart = 4.dp, bottomEnd = 16.dp), Color(0xFFE64A19)),
    CategoryStyle(RoundedCornerShape(8.dp), Color(0xFF5D4037)),
    CategoryStyle(CircleShape, Color(0xFF0288D1)),
)

/** 左侧分类选择器项 */
@Composable
private fun LandscapeCategorySelectorItem(category: AACCreditCategory, index: Int, isSelected: Boolean, onClick: () -> Unit) {
    val style = CATEGORY_STYLES[index % CATEGORY_STYLES.size]
    val containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer
        else MaterialTheme.colorScheme.surfaceContainerLow
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        ListItem(
            modifier = Modifier.clickable(onClick = onClick),
            headlineContent = { Text(category.typeName, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            supportingContent = { Text("${category.children.size} 项", style = MaterialTheme.typography.bodySmall) },
            leadingContent = {
                Box(
                    Modifier.size(44.dp).background(
                        if (isSelected) style.color else style.color.copy(alpha = 0.15f),
                        style.shape,
                    ), contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("%.0f".format(category.totalScore),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            color = if (isSelected) Color.White else style.color)
                        Text("分",
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isSelected) Color.White.copy(alpha = 0.8f) else style.color.copy(alpha = 0.8f))
                    }
                }
            },
            trailingContent = {
                if (isSelected) Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.primary)
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}


@Composable
private fun LandscapeRequirementWavyCard(label: String, current: Double, required: Double, modifier: Modifier) {
    val met = current >= required
    val progress = (current / required).toFloat().coerceIn(0f, 1f)
    val color = if (met) Color(0xFF2E7D32) else MaterialTheme.colorScheme.primary
    val bg = if (met) Color(0xFF2E7D32).copy(alpha = 0.08f) else MaterialTheme.colorScheme.surfaceContainerHigh
    
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = bg), shape = MaterialTheme.shapes.medium) {
        Row(
            Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                if (met) {
                    AppCircularProgressIndicator(
                        modifier = Modifier.size(36.dp),
                        color = color,
                        trackColor = color.copy(alpha = 0.3f),
                    )
                } else {
                    AppCircularProgressIndicator(
                        progress = { progress },
                        modifier = Modifier.size(36.dp),
                        color = color,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                }
            }
            Column(Modifier.weight(1f)) {
                Text(label, style = MaterialTheme.typography.labelSmall, color = color)
                Text(
                    "${"%.1f".format(current)}/${required.let { if (it == it.toLong().toDouble()) it.toInt().toString() else "%.1f".format(it) }}",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = color,
                )
            }
            if (met) {
                Icon(Icons.Default.CheckCircle, null, tint = color, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun LandscapeCreditItemRow(item: AACCreditItem) {
    val scoreColor = when {
        item.score >= 10 -> Color(0xFFC62828)
        item.score >= 5 -> Color(0xFFE65100)
        item.score >= 2 -> Color(0xFF1565C0)
        else -> Color(0xFF2E7D32)
    }
    ListItem(
        headlineContent = { Text(item.title, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium) },
        supportingContent = {
            Column {
                if (item.typeName.isNotEmpty()) Text(item.typeName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (item.addTime.isNotEmpty()) Text(item.addTime, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        trailingContent = {
            Surface(color = scoreColor.copy(alpha = 0.12f), shape = MaterialTheme.shapes.small) {
                Text("+${"%.1f".format(item.score)}", modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = scoreColor)
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
