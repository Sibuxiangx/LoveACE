package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.navigation.YKTRoute
import tech.loveace.appv3.ui.viewmodel.AACViewModel
import tech.loveace.appv3.ui.viewmodel.AcademicViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ProfileViewModel
import tech.loveace.appv3.ui.viewmodel.SemesterStatus
import tech.loveace.appv3.ui.viewmodel.SemesterViewModel
import tech.loveace.appv3.ui.viewmodel.YKTViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    authViewModel: AuthViewModel,
    onNavigateToDetail: (Any) -> Unit,
    academicVm: AcademicViewModel = viewModel(),
    aacVm: AACViewModel = viewModel(),
    yktVm: YKTViewModel = viewModel(),
    semesterVm: SemesterViewModel = viewModel(),
    profileVm: ProfileViewModel = viewModel(),
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val academicState by academicVm.uiState.collectAsStateWithLifecycle()
    val aacState by aacVm.uiState.collectAsStateWithLifecycle()
    val yktState by yktVm.uiState.collectAsStateWithLifecycle()
    val semesterState by semesterVm.uiState.collectAsStateWithLifecycle()
    val profileState by profileVm.state.collectAsStateWithLifecycle()

    val displayName = profileState.nickname.ifEmpty { authState.userId }

    LaunchedEffect(authViewModel.jwcService) {
        authViewModel.jwcService?.let {
            academicVm.init(it)
            academicVm.loadAcademicInfo()
        }
    }
    LaunchedEffect(authViewModel.aacService) {
        authViewModel.aacService?.let { aacVm.init(it); aacVm.loadAll() }
    }
    LaunchedEffect(authViewModel.yktService) {
        authViewModel.yktService?.let { yktVm.init(it); yktVm.loadAll() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("彩带小工具", fontWeight = FontWeight.Bold)
                        Text(
                            "$displayName 同学，你好",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── 学期 ──
            val semStatus = semesterState.status
            item(key = "semester") {
                when (semStatus) {
                    is SemesterStatus.Loading -> LoadingTile()
                    is SemesterStatus.Vacation, is SemesterStatus.InSession -> HomeTile(
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                    ) {
                        SemesterStatusRow(semStatus)
                    }
                    else -> Unit
                }
            }

            // ── 学业：hero + 课程计数 ──
            val info = academicState.academicInfo
            if (info != null) {
                item(key = "academic-hero") { AcademicHero(info) }
                item(key = "academic-counts") { AcademicCounts(info) }
            } else if (academicState.isLoading) {
                item(key = "academic-loading") { LoadingTile() }
            }

            // ── 一卡通 + 爱安财：等高双卡 ──
            val balance = yktState.balance
            val aacInfo = aacState.creditInfo
            val showTools = balance != null || yktState.isLoading || aacInfo != null || aacState.isLoading
            if (showTools) {
                item(key = "tools") {
                    Row(
                        Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        when {
                            balance != null -> YktTile(
                                balanceText = "¥${"%.2f".format(balance.balance)}",
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                                onClick = { onNavigateToDetail(YKTRoute) },
                            )
                            yktState.isLoading -> LoadingTile(Modifier.weight(1f).fillMaxHeight())
                            else -> Spacer(Modifier.weight(1f))
                        }
                        when {
                            aacInfo != null -> AacTile(
                                info = aacInfo,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                            aacState.isLoading -> LoadingTile(Modifier.weight(1f).fillMaxHeight())
                            else -> Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}
