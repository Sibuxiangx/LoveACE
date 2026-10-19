package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.UnifiedExamInfo
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ExamViewModel
import java.time.LocalDate
import java.time.temporal.ChronoUnit

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExamScreen(authViewModel: AuthViewModel, onBack: () -> Unit, vm: ExamViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.jwcService) {
        authViewModel.jwcService?.let { vm.init(it); vm.loadExams() }
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("考试安排") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
        )
    }) { padding ->
        when {
            state.isLoading -> LoadingScreen()
            state.error != null -> RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "加载失败",
                description = state.error,
                actionText = "重试",
                onAction = { vm.loadExams() },
            )
            state.exams.isEmpty() -> RibbonState(kind = RibbonStateKind.EMPTY, title = "暂无考试安排")
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.exams, key = { "${it.courseName}_${it.examDate}_${it.examTime}" }) { exam -> ExamCard(exam) }
            }
        }
    }
}

@Composable
fun ExamCard(exam: UnifiedExamInfo) {
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(20.dp),
    ) {
        Column {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(exam.courseName, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                RibbonChip(exam.examType, tone = examUrgencyTone(exam.examDate))
            }
            Spacer(Modifier.height(10.dp))
            Text("📅 ${exam.examDate}  🕐 ${exam.examTime}", style = MaterialTheme.typography.bodyMedium)
            if (exam.examLocation.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text("📍 ${exam.examLocation}", style = MaterialTheme.typography.bodyMedium)
            }
            if (exam.note.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text("📝 ${exam.note}", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** 考试临近程度 → 芯片色调：3 天内 ERROR / 7 天内 WARNING / 更远 SECONDARY / 已过 NEUTRAL */
private fun examUrgencyTone(dateStr: String): RibbonTone {
    val m = Regex("(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})").find(dateStr) ?: return RibbonTone.SECONDARY
    return try {
        val date = LocalDate.of(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt())
        val days = ChronoUnit.DAYS.between(LocalDate.now(), date)
        when {
            days < 0 -> RibbonTone.NEUTRAL
            days <= 3 -> RibbonTone.ERROR
            days <= 7 -> RibbonTone.WARNING
            else -> RibbonTone.SECONDARY
        }
    } catch (e: Exception) {
        RibbonTone.SECONDARY
    }
}
