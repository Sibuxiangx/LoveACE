package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel

/**
 * 开课查询（更多 → 教务服务）。单页：右上角“筛选”打开条件 sheet，查询后分页列出结果，
 * 点击结果项弹出详情。
 */
@Composable
fun CourseScheduleScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: CourseScheduleViewModel = viewModel(),
) {
    CourseScheduleScaffold(authViewModel = authViewModel, vm = vm, onBack = onBack)
}

/** 竖屏与横屏共用的页面骨架；横屏没有返回键（由横屏导航负责）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CourseScheduleScaffold(
    authViewModel: AuthViewModel,
    vm: CourseScheduleViewModel,
    onBack: (() -> Unit)?,
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var filtersOpen by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(authViewModel.courseScheduleService) {
        authViewModel.courseScheduleService?.let { vm.init(it); vm.loadIndex() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("开课查询") },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { filtersOpen = true }) {
                        Icon(Icons.Default.FilterList, "筛选")
                    }
                },
            )
        },
    ) { padding ->
        Box(
            Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.TopCenter,
        ) {
            CourseResultsPane(
                state = state,
                vm = vm,
                modifier = Modifier.fillMaxSize().widthIn(max = 720.dp),
            )
        }
    }

    if (filtersOpen) {
        CourseFilterSheet(
            state = state,
            vm = vm,
            onDismiss = { filtersOpen = false },
            onSearch = {
                vm.search()
                filtersOpen = false
            },
        )
    }

    state.selected?.let { record ->
        CourseDetailSheet(record = record, onDismiss = vm::dismissDetail)
    }
}
