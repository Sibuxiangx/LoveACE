package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.screen.ExamCard
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ExamViewModel

/**
 * 横屏考试安排：双列网格展示考试卡片，充分利用横向空间
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeExamScreen(authViewModel: AuthViewModel, vm: ExamViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.jwcService) {
        authViewModel.jwcService?.let { vm.init(it); vm.loadExams() }
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = { Text("考试安排") })

        when {
            !state.hasLoaded || state.isLoading -> LoadingScreen()
            state.error != null -> ErrorScreen(state.error!!) { vm.loadExams() }
            state.exams.isEmpty() -> EmptyScreen("暂无考试安排")
            else -> LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(20.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(state.exams, key = { "${it.courseName}_${it.examDate}_${it.examTime}" }) { exam -> ExamCard(exam) }
            }
        }
    }
}
