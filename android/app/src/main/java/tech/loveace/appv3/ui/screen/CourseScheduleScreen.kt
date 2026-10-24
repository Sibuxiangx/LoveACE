package tech.loveace.appv3.ui.screen

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel

/**
 * 开课查询（更多 → 教务服务）。两层：查询页 → 结果页（分片列表），点击结果项弹出详情。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseScheduleScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: CourseScheduleViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.courseScheduleService) {
        authViewModel.courseScheduleService?.let { vm.init(it); vm.loadIndex() }
    }

    BackHandler(enabled = state.showResults) { vm.backToForm() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (state.showResults) "开课结果" else "开课查询") },
                navigationIcon = {
                    IconButton(onClick = { if (state.showResults) vm.backToForm() else onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                    }
                },
            )
        },
    ) { padding ->
        val modifier = Modifier.fillMaxSize().padding(padding)
        if (state.showResults) {
            CourseResultsPane(state, vm, modifier)
        } else {
            CourseFormPane(state, vm, modifier)
        }
    }

    state.selected?.let { record ->
        CourseDetailSheet(record = record, onDismiss = vm::dismissDetail)
    }
}
