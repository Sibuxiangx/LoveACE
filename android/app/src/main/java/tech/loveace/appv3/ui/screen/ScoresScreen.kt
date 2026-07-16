package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.ScoreRecord
import tech.loveace.appv3.data.model.ScoreDetail
import tech.loveace.appv3.data.model.hasPublishedScore
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AcademicViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.util.CsvExporter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScoresScreen(authViewModel: AuthViewModel, onBack: (() -> Unit)? = null, vm: AcademicViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.jwcService) {
        authViewModel.jwcService?.let { vm.init(it); vm.loadTerms() }
    }

    val context = LocalContext.current
    var showExportDialog by remember { mutableStateOf(false) }

    if (state.selectedScore != null) {
        ModalBottomSheet(onDismissRequest = vm::dismissScoreDetail) {
            ScoreDetailSheet(
                record = state.selectedScore!!,
                detail = state.scoreDetail,
                isLoading = state.scoreDetailLoading,
                error = state.scoreDetailError,
            )
        }
    }

    if (showExportDialog && state.scores != null && state.selectedTerm != null) {
        val records = state.scores!!.records
        val termId = state.selectedTerm!!.termCode
        val termName = state.selectedTerm!!.termName
        ExportDialog(
            title = "导出学期成绩",
            description = "将导出 $termName 的成绩数据为 CSV 文件，保存到下载目录。",
            onExport = { CsvExporter.exportTermScores(context, records, termId) },
            onDismiss = { showExportDialog = false },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("学期成绩") },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") }
                    }
                },
                actions = {
                    if (!state.scores?.records.isNullOrEmpty()) {
                        IconButton(onClick = { showExportDialog = true }) {
                            Icon(Icons.Default.FileDownload, "导出CSV")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (state.terms.isNotEmpty()) {
                PrimaryScrollableTabRow(
                    selectedTabIndex = state.terms.indexOf(state.selectedTerm).coerceAtLeast(0),
                    modifier = Modifier.fillMaxWidth(),
                    edgePadding = 16.dp,
                ) {
                    state.terms.forEach { term ->
                        Tab(
                            selected = term == state.selectedTerm,
                            onClick = { vm.selectTerm(term) },
                            text = { Text(term.termName, maxLines = 1) },
                        )
                    }
                }
            }

            when {
                state.scoresLoading -> LoadingScreen()
                state.scores?.records.isNullOrEmpty() -> EmptyScreen("该学期暂无成绩")
                else -> LazyColumn(
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(state.scores!!.records, key = { "${it.termId}_${it.courseCode}_${it.courseClass}_${it.sequence}" }) { record ->
                        ScoreCard(record, onClick = if (state.selectedTerm?.isCurrent == true && record.hasPublishedScore) {
                            { vm.loadScoreDetail(record) }
                        } else {
                            null
                        })
                    }
                }
            }
        }
    }
}

@Composable
fun ScoreCard(record: ScoreRecord, onClick: (() -> Unit)? = null) {
    val scoreNum = record.score.toDoubleOrNull()
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    record.courseNameCn,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("${record.credits} 学分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    record.courseType?.takeIf { it.isNotBlank() }?.let { type -> ScoreMetaBadge(type, MaterialTheme.colorScheme.secondaryContainer) }
                    record.examType?.takeIf { it.isNotBlank() }?.let { type -> ScoreMetaBadge(type, MaterialTheme.colorScheme.tertiaryContainer) }
                }
                if (record.courseNameEn.isNotBlank()) {
                    Text(
                        record.courseNameEn,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        record.score.ifBlank { "暂无成绩" },
                        style = if (record.hasPublishedScore) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = if (record.hasPublishedScore) scoreGradientColor(scoreNum) else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (record.hasPublishedScore) {
                        Text("分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (onClick != null) {
                    Icon(Icons.Default.KeyboardArrowRight, contentDescription = "查看成绩明细")
                }
            }
        }
    }
}

@Composable
private fun ScoreMetaBadge(text: String, color: Color) {
    Surface(
        color = color,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        shape = MaterialTheme.shapes.small,
    ) {
        Text(text, style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp))
    }
}

@Composable
fun ScoreDetailSheet(record: ScoreRecord, detail: ScoreDetail?, isLoading: Boolean, error: String?) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(record.courseNameCn, style = MaterialTheme.typography.titleLarge)
        Text("成绩明细", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        when {
            isLoading -> LinearProgressIndicator(Modifier.fillMaxWidth())
            error != null -> Text(error, color = MaterialTheme.colorScheme.error)
            detail == null || detail.items.isEmpty() -> Text("暂无成绩明细", color = MaterialTheme.colorScheme.onSurfaceVariant)
            else -> detail.items.forEach { item ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(item.scoreType, style = MaterialTheme.typography.titleSmall)
                    DetailScoreRow("平时", item.usualScore)
                    DetailScoreRow("期中", item.midtermScore)
                    DetailScoreRow("期末", item.finalScore)
                    DetailScoreRow("分类总成绩", item.categoryScore)
                    if (item.remark.isNotBlank()) DetailScoreRow("备注", item.remark)
                }
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun DetailScoreRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value.ifBlank { "-" }, fontWeight = FontWeight.Medium)
    }
}

/** 红→绿渐变：<60 红色，60-100 每5分渐变一档 */
private fun scoreGradientColor(score: Double?): Color {
    if (score == null) return Color(0xFF757575) // 非数字成绩（优/良/合格等）
    if (score < 60) return Color(0xFFD32F2F) // 不及格：红色
    // 60→100 映射到 0→1，每5分一档
    val t = ((score - 60.0) / 40.0).coerceIn(0.0, 1.0).toFloat()
    // 红(0°) → 橙(30°) → 黄(55°) → 黄绿(80°) → 绿(130°) 的 HSV 插值
    // 用几个关键色做分段线性插值，视觉更自然
    return when {
        t < 0.25f -> lerpColor(Color(0xFFE53935), Color(0xFFF57C00), t / 0.25f)       // 60-70: 红→橙
        t < 0.50f -> lerpColor(Color(0xFFF57C00), Color(0xFFFBC02D), (t - 0.25f) / 0.25f) // 70-80: 橙→黄
        t < 0.75f -> lerpColor(Color(0xFFFBC02D), Color(0xFF7CB342), (t - 0.50f) / 0.25f) // 80-90: 黄→黄绿
        else -> lerpColor(Color(0xFF7CB342), Color(0xFF2E7D32), (t - 0.75f) / 0.25f)      // 90-100: 黄绿→绿
    }
}

private fun lerpColor(a: Color, b: Color, fraction: Float): Color {
    val f = fraction.coerceIn(0f, 1f)
    return Color(
        red = a.red + (b.red - a.red) * f,
        green = a.green + (b.green - a.green) * f,
        blue = a.blue + (b.blue - a.blue) * f,
    )
}
