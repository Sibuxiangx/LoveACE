package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.screen.TeacherEvaluationContent
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.TeacherEvaluationViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeTeacherEvaluationScreen(
    authViewModel: AuthViewModel,
    vm: TeacherEvaluationViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(authViewModel.teacherEvaluationService) {
        authViewModel.teacherEvaluationService?.let {
            vm.init(it)
            vm.load()
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("确认开始自动评教？") },
            text = { Text("任务会每 6 秒启动一门课程，准备表单后等待 140 秒再提交。期间请保持 App 在前台，不要锁屏或切到后台。") },
            confirmButton = { Button(onClick = { showConfirm = false; vm.startBatch() }) { Text("开始") } },
            dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("取消") } },
        )
    }

    Scaffold(topBar = { TopAppBar(title = { Text("自动教师评价") }) }) { padding ->
        TeacherEvaluationContent(
            state = state,
            onStart = { showConfirm = true },
            onStop = { vm.stop() },
            onRetry = { vm.load() },
            onStrategyChange = { vm.setStrategy(it) },
            modifier = Modifier.fillMaxSize().padding(padding),
        )
    }
}
