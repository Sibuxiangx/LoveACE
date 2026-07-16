package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.screen.ScoreCard
import tech.loveace.appv3.ui.screen.ScoreDetailSheet
import tech.loveace.appv3.ui.viewmodel.AcademicViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.util.CsvExporter
import tech.loveace.appv3.data.model.hasPublishedScore

/**
 * 横屏成绩：左侧学期选择列表 + 右侧成绩双列网格
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeScoresScreen(authViewModel: AuthViewModel, vm: AcademicViewModel = viewModel()) {
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

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("学期成绩") },
            actions = {
                if (!state.scores?.records.isNullOrEmpty()) {
                    IconButton(onClick = { showExportDialog = true }) {
                        Icon(Icons.Default.FileDownload, "导出CSV")
                    }
                }
            },
        )

        // 学期 Tab 分页
        if (state.terms.isNotEmpty()) {
            PrimaryScrollableTabRow(
                selectedTabIndex = state.terms.indexOf(state.selectedTerm).coerceAtLeast(0),
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

        // 成绩双列网格
        when {
            state.scoresLoading -> LoadingScreen()
            state.scores?.records.isNullOrEmpty() -> EmptyScreen("该学期暂无成绩")
            else -> {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
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
