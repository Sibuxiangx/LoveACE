package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.UnifiedExamInfo
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ExamViewModel

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
            !state.hasLoaded || state.isLoading -> LoadingScreen()
            state.error != null -> ErrorScreen(state.error!!) { vm.loadExams() }
            state.exams.isEmpty() -> EmptyScreen("暂无考试安排")
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(state.exams, key = { "${it.courseName}_${it.examDate}_${it.examTime}" }) { exam -> ExamCard(exam) }
            }
        }
    }
}

@Composable
fun ExamCard(exam: UnifiedExamInfo) {
    Card(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Text(exam.courseName, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                SuggestionChip(onClick = {}, label = { Text(exam.examType) })
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
