package tech.loveace.appv3.ui.screen.landscape

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.screen.PREFS_NAME
import tech.loveace.appv3.ui.screen.RoomDetailSheet
import tech.loveace.appv3.ui.screen.SettingsSheet
import tech.loveace.appv3.ui.screen.freeClassroomControlItems
import tech.loveace.appv3.ui.screen.freeClassroomResultItems
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.FreeClassroomViewModel

/**
 * 横屏空闲教室：左侧是时段与范围条件，右侧是按楼、楼层分组的结果。
 * 状态与竖屏共用 [FreeClassroomViewModel]；面板内容复用竖屏的 LazyListScope 实现。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeFreeClassroomScreen(authViewModel: AuthViewModel, vm: FreeClassroomViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    LaunchedEffect(authViewModel.freeClassroomService) {
        authViewModel.freeClassroomService?.let { service ->
            vm.init(service, context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("空闲教室") },
            actions = {
                IconButton(onClick = vm::useNow) { Icon(Icons.Default.AccessTime, "现在有空") }
                IconButton(onClick = { vm.setSettingsOpen(true) }) { Icon(Icons.Default.Settings, "设置") }
            },
        )
        val initError = state.initError
        when {
            state.initLoading && state.buildings.isEmpty() -> Box(
                Modifier.fillMaxSize().weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                LoadingScreen("正在加载教学楼…")
            }
            initError != null && state.buildings.isEmpty() -> RibbonState(
                kind = RibbonStateKind.ERROR,
                title = "加载失败",
                description = initError,
                actionText = "重试",
                onAction = vm::retryInit,
                modifier = Modifier.fillMaxSize().weight(1f),
            )
            else -> Row(Modifier.fillMaxSize().weight(1f)) {
                LazyColumn(
                    modifier = Modifier.width(380.dp).fillMaxHeight(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    freeClassroomControlItems(state, vm)
                }
                VerticalDivider()
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    freeClassroomResultItems(state, vm)
                }
            }
        }
    }

    if (state.settingsOpen) {
        SettingsSheet(
            showStopped = state.showStopped,
            onShowStopped = vm::setShowStopped,
            onDismiss = { vm.setSettingsOpen(false) },
        )
    }

    state.selectedRoom?.let { room ->
        RoomDetailSheet(room = room, state = state, vm = vm)
    }
}
