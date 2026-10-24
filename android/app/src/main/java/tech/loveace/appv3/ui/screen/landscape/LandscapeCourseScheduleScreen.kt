package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.screen.CourseDetailSheet
import tech.loveace.appv3.ui.screen.CourseFormPane
import tech.loveace.appv3.ui.screen.CourseResultsPane
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel

/**
 * 横屏开课查询：左侧查询条件，右侧结果列表；点击结果项弹出详情。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeCourseScheduleScreen(
    authViewModel: AuthViewModel,
    vm: CourseScheduleViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.courseScheduleService) {
        authViewModel.courseScheduleService?.let { vm.init(it); vm.loadIndex() }
    }

    Row(Modifier.fillMaxSize()) {
        Column(Modifier.width(360.dp).fillMaxHeight()) {
            TopAppBar(title = { Text("开课查询") })
            CourseFormPane(state, vm, Modifier.weight(1f))
        }
        VerticalDivider()
        Column(Modifier.weight(1f).fillMaxHeight()) {
            TopAppBar(title = { Text("开课结果") })
            CourseResultsPane(state, vm, Modifier.weight(1f))
        }
    }

    state.selected?.let { record ->
        CourseDetailSheet(record = record, onDismiss = vm::dismissDetail)
    }
}
