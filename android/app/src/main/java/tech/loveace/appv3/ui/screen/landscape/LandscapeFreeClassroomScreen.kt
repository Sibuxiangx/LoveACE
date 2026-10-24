package tech.loveace.appv3.ui.screen.landscape

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
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
import tech.loveace.appv3.ui.screen.BuildingList
import tech.loveace.appv3.ui.screen.FcModeSwitch
import tech.loveace.appv3.ui.screen.PREFS_NAME
import tech.loveace.appv3.ui.screen.RoomDetailSheet
import tech.loveace.appv3.ui.screen.RoomExplorer
import tech.loveace.appv3.ui.screen.SettingsSheet
import tech.loveace.appv3.ui.screen.queryControlItems
import tech.loveace.appv3.ui.screen.queryResultItems
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.FcMode
import tech.loveace.appv3.ui.viewmodel.FreeClassroomViewModel

/**
 * 横屏空闲教室：左侧是时段筛选（按时间找）或楼列表（逐楼探索），右侧是结果或教室。
 * 状态与竖屏共用 [FreeClassroomViewModel]；面板组件复用竖屏实现。
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
                IconButton(onClick = { vm.setSettingsOpen(true) }) {
                    Icon(Icons.Default.Settings, "设置")
                }
            },
        )
        FcModeSwitch(mode = state.mode, onChange = vm::setMode)
        val initError = state.initError
        when {
            state.initLoading && state.buildings.isEmpty() -> Box(
                Modifier.fillMaxWidth().weight(1f),
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
            )
            state.mode == FcMode.QUERY -> Row(Modifier.fillMaxWidth().weight(1f)) {
                LazyColumn(
                    modifier = Modifier.width(360.dp).fillMaxHeight(),
                    contentPadding = PaddingValues(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    queryControlItems(state, vm)
                }
                Spacer(Modifier.width(8.dp))
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    contentPadding = PaddingValues(start = 8.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    queryResultItems(state, vm)
                }
            }
            else -> Row(Modifier.fillMaxWidth().weight(1f)) {
                BuildingList(state = state, vm = vm, modifier = Modifier.width(360.dp).fillMaxHeight())
                Spacer(Modifier.width(8.dp))
                val building = state.exploreBuilding
                if (building == null) {
                    Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                        Text(
                            "点左侧一栋楼，逐层看每间教室。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    RoomExplorer(state = state, vm = vm, building = building, modifier = Modifier.weight(1f))
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
