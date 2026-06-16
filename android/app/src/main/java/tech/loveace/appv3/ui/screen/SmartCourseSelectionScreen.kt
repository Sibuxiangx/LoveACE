package tech.loveace.appv3.ui.screen

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.SmartCourseSelectionViewModel

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun SmartCourseSelectionScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    viewModel: SmartCourseSelectionViewModel = viewModel(),
    showBackButton: Boolean = true,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var termMenuExpanded by remember { mutableStateOf(false) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        scope.launch {
            snackbarHostState.showSnackbar(if (granted) "已允许通知状态显示" else "未授权通知，仍可在页面查看状态")
        }
    }

    LaunchedEffect(Unit) {
        viewModel.loadTargetTerms(authViewModel.courseScheduleService, authViewModel.jwcService)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    if (state.isScanning) {
        QRScanScreen(
            title = "扫描智能选课二维码",
            hint = "请扫描电脑网页上的智能选课二维码",
            onBack = { viewModel.cancelScanning() },
            onScanned = { qrData ->
                viewModel.connectAndUpload(
                    qrData = qrData,
                    userId = authViewModel.uiState.value.userId,
                    jwcService = authViewModel.jwcService,
                    studentScheduleService = authViewModel.studentScheduleService,
                    courseScheduleService = authViewModel.courseScheduleService,
                    planService = authViewModel.planService,
                )
            },
        )
        return
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("智能选课") },
                navigationIcon = {
                    if (showBackButton) {
                        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(
                            imageVector = when {
                                state.error != null -> Icons.Default.Error
                                state.isWorking -> Icons.Default.Sync
                                state.isConnected -> Icons.Default.CheckCircle
                                else -> Icons.Default.Link
                            },
                            contentDescription = null,
                            tint = when {
                                state.error != null -> MaterialTheme.colorScheme.error
                                state.isConnected -> MaterialTheme.colorScheme.primary
                                else -> MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                        Text(state.status, style = MaterialTheme.typography.titleMedium)
                    }
                    Text(state.detail, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    state.sessionId?.let {
                        AssistChip(onClick = {}, label = { Text("会话：$it") })
                    }
                    if (state.isWorking) {
                        LinearWavyProgressIndicator(Modifier.fillMaxWidth())
                    }
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("电脑端页面", style = MaterialTheme.typography.titleMedium)
                    Text(state.webUrl, color = MaterialTheme.colorScheme.primary)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilledTonalButton(
                            onClick = {
                                copyToClipboard(context, state.webUrl)
                                scope.launch { snackbarHostState.showSnackbar("已复制网页链接") }
                            },
                        ) {
                            Icon(Icons.Default.ContentCopy, null)
                            Spacer(Modifier.width(8.dp))
                            Text("复制链接")
                        }
                    }
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("排课学期", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "请选择要排课的学期。学校通常会在本学期末开放下学期开课数据。",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Box {
                        FilledTonalButton(
                            onClick = { termMenuExpanded = true },
                            enabled = !state.isLoadingTerms && state.targetTerms.isNotEmpty() && !state.isWorking,
                        ) {
                            Text(
                                when {
                                    state.isLoadingTerms -> "正在加载学期..."
                                    state.selectedTerm != null -> state.selectedTerm!!.termName
                                    else -> "选择学期"
                                },
                            )
                        }
                        DropdownMenu(
                            expanded = termMenuExpanded,
                            onDismissRequest = { termMenuExpanded = false },
                        ) {
                            state.targetTerms.forEach { term ->
                                DropdownMenuItem(
                                    text = { Text(term.termName) },
                                    onClick = {
                                        viewModel.selectTerm(term.termCode)
                                        termMenuExpanded = false
                                    },
                                )
                            }
                        }
                    }
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("连接步骤", style = MaterialTheme.typography.titleMedium)
                    Text("1. 在电脑打开上方链接。\n2. 点击网页生成二维码。\n3. 用这里的扫码按钮扫描二维码。\n4. 保持本页打开，等待课表、培养方案和开课数据上传完成。")
                    Spacer(Modifier.height(4.dp))
                    FilledTonalButton(
                        onClick = { viewModel.startScanning() },
                        enabled = !state.isWorking && state.selectedTermCode != null,
                    ) {
                        Icon(Icons.Default.QrCodeScanner, null)
                        Spacer(Modifier.width(8.dp))
                        Text("扫码连接")
                    }
                    if (state.isConnected || state.isWorking) {
                        OutlinedButton(onClick = { viewModel.closeSocket() }) {
                            Text("断开连接")
                        }
                    }
                }
            }
        }
    }
}

private fun copyToClipboard(context: Context, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("智能选课网页", text))
}
