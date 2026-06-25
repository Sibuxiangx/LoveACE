package tech.loveace.appv3.ui.screen.landscape

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.BluetoothSearching
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.screen.ICCardView
import tech.loveace.appv3.ui.screen.buildBlePermissions
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.DoorCardUiState
import tech.loveace.appv3.ui.viewmodel.DoorCardViewModel

/**
 * 横屏宿舍门卡：左栏 IC 卡 + 连接 | 右栏操作面板
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeDoorCardScreen(
    authViewModel: AuthViewModel,
    vm: DoorCardViewModel = viewModel(),
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val state by vm.uiState.collectAsStateWithLifecycle()
    var showUnbindDialog by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { grants ->
        val allGranted = grants.values.all { it }
        if (allGranted) vm.connectBle()
    }

    LaunchedEffect(authState.userId) {
        if (authState.userId.isNotEmpty()) vm.init(authState.userId)
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("宿舍门卡") },
            actions = {
                if (state.isBound) {
                    IconButton(onClick = { showUnbindDialog = true }) {
                        Icon(Icons.Default.LinkOff, "解绑")
                    }
                }
            },
        )
    }) { padding ->
        if (!state.isBound) {
            LandscapeBindView(
                isBinding = state.isBinding,
                bindError = state.bindError,
                onBind = { userno, username, password -> vm.bind(userno, username, password) },
                modifier = Modifier.padding(padding),
            )
        } else {
            LandscapePassContent(
                state = state,
                onConnect = {
                    permissionLauncher.launch(buildBlePermissions())
                },
                onDisconnect = { vm.disconnectBle() },
                onOpenDoor = { vm.openDoor() },
                onAddCard = { vm.addCard() },
                onFreezeCard = { vm.freezeCard() },
                onCheckTime = { vm.checkTime() },
                onAlwaysOpen = { vm.alwaysOpen() },
                onAlwaysOff = { vm.alwaysOff() },
                onCheckDaily = { vm.checkDaily() },
                onClearMessage = { vm.clearMessage() },
                modifier = Modifier.padding(padding),
            )
        }
    }

    // 解绑确认
    if (showUnbindDialog) {
        AlertDialog(
            onDismissRequest = { showUnbindDialog = false },
            icon = { Icon(Icons.Default.Warning, null) },
            title = { Text("确认解绑") },
            text = { Text("解绑后需要重新输入门卡系统账号密码。确认解绑？") },
            confirmButton = {
                Button(onClick = { showUnbindDialog = false; vm.unbind() }) { Text("确认") }
            },
            dismissButton = {
                OutlinedButton(onClick = { showUnbindDialog = false }) { Text("取消") }
            },
        )
    }
}

// ==================== 横屏绑定 ====================

@Composable
private fun LandscapeBindView(
    isBinding: Boolean,
    bindError: String?,
    onBind: (String, String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var userno by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Row(
        modifier.fillMaxSize().padding(24.dp),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 左侧：图标 + 说明
        Column(
            Modifier.weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier.size(96.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Default.Key, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
            }
            Spacer(Modifier.height(20.dp))
            Text("宿舍门卡绑定", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text(
                "绑定后可使用手机蓝牙开门",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // 右侧：表单
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = userno, onValueChange = { userno = it },
                modifier = Modifier.fillMaxWidth(), label = { Text("学号") },
                singleLine = true, shape = MaterialTheme.shapes.large,
                leadingIcon = { Icon(Icons.Default.Badge, null) },
            )
            OutlinedTextField(
                value = username, onValueChange = { username = it },
                modifier = Modifier.fillMaxWidth(), label = { Text("姓名") },
                singleLine = true, shape = MaterialTheme.shapes.large,
                leadingIcon = { Icon(Icons.Default.Person, null) },
            )
            OutlinedTextField(
                value = password, onValueChange = { password = it },
                modifier = Modifier.fillMaxWidth(), label = { Text("密码") },
                singleLine = true, visualTransformation = PasswordVisualTransformation(),
                shape = MaterialTheme.shapes.large,
                leadingIcon = { Icon(Icons.Default.Lock, null) },
            )
            AnimatedVisibility(bindError != null) {
                Card(
                    shape = MaterialTheme.shapes.large,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                ) {
                    Row(Modifier.padding(12.dp)) {
                        Icon(Icons.Default.Error, null, tint = MaterialTheme.colorScheme.onErrorContainer)
                        Spacer(Modifier.width(8.dp))
                        Text(bindError ?: "", color = MaterialTheme.colorScheme.onErrorContainer)
                    }
                }
            }
            Button(
                onClick = { onBind(userno, username, password) },
                modifier = Modifier.fillMaxWidth().height(48.dp),
                enabled = !isBinding && userno.isNotEmpty() && username.isNotEmpty() && password.isNotEmpty(),
                shape = MaterialTheme.shapes.large,
            ) {
                if (isBinding) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)) }
                Text("绑定")
            }
        }
    }
}


// ==================== 横屏 IC 卡 + 操作面板 ====================


@Composable
private fun LandscapePassContent(
    state: DoorCardUiState,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onOpenDoor: () -> Unit,
    onAddCard: () -> Unit,
    onFreezeCard: () -> Unit,
    onCheckTime: () -> Unit,
    onAlwaysOpen: () -> Unit,
    onAlwaysOff: () -> Unit,
    onCheckDaily: () -> Unit,
    onClearMessage: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val room = state.rooms.firstOrNull()
    val isConnected = state.bleState == BleConnectionState.Connected
    val isConnecting = state.bleState == BleConnectionState.Scanning || state.bleState == BleConnectionState.Connecting

    when {
        state.isLoadingRooms -> LoadingScreen("加载门卡信息...")
        state.roomsError != null -> ErrorScreen(state.roomsError!!) {}
        room == null -> EmptyScreen("暂无可用房间")
        else -> Row(
            modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // 左栏：IC 卡 + 连接状态
            Column(
                Modifier.weight(0.45f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                ICCardView(
                    personName = state.userInfo?.personName ?: "",
                    roomName = room.roomName,
                    buildName = room.buildName,
                    power = room.power,
                    bleState = state.bleState,
                )

                // BLE 连接按钮
                if (!isConnected && !isConnecting) {
                    Button(
                        onClick = onConnect,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = MaterialTheme.shapes.extraLarge,
                    ) {
                        Icon(Icons.Default.Bluetooth, null, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("连接门锁", style = MaterialTheme.typography.titleSmall)
                    }
                } else if (isConnecting) {
                    OutlinedCard(
                        shape = MaterialTheme.shapes.extraLarge,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            Modifier.padding(16.dp).fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(12.dp))
                            Text("请将手机靠近门锁感应区...", style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                } else {
                    // 已连接 — 开门大按钮
                    Button(
                        onClick = onOpenDoor,
                        modifier = Modifier.fillMaxWidth().height(64.dp),
                        enabled = !state.isOperating,
                        shape = MaterialTheme.shapes.extraLarge,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                        ),
                    ) {
                        Icon(Icons.Default.LockOpen, null, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("手机开门", style = MaterialTheme.typography.titleMedium)
                    }

                    TextButton(
                        onClick = onDisconnect,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Default.BluetoothDisabled, null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("断开连接")
                    }
                }

                // 提示信息
                Card(
                    shape = MaterialTheme.shapes.large,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                ) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                        Icon(Icons.Default.Info, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(12.dp))
                        Text(
                            "请确保蓝牙已开启，并将手机靠近门锁感应区域。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            // 右栏：操作消息 + 更多操作
            Column(
                Modifier.weight(0.55f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // 操作消息
                AnimatedVisibility(state.operationMessage != null) {
                    Card(
                        shape = MaterialTheme.shapes.large,
                        colors = CardDefaults.cardColors(
                            containerColor = when {
                                state.operationMessage?.contains("成功") == true -> MaterialTheme.colorScheme.primaryContainer
                                state.operationMessage?.contains("失败") == true -> MaterialTheme.colorScheme.errorContainer
                                else -> MaterialTheme.colorScheme.surfaceContainerLow
                            },
                        ),
                    ) {
                        Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            if (state.isOperating) {
                                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            } else {
                                Icon(
                                    when {
                                        state.operationMessage?.contains("成功") == true -> Icons.Default.CheckCircle
                                        state.operationMessage?.contains("失败") == true -> Icons.Default.Error
                                        else -> Icons.Default.Info
                                    }, null, modifier = Modifier.size(18.dp),
                                )
                            }
                            Spacer(Modifier.width(12.dp))
                            Text(state.operationMessage ?: "", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                            if (!state.isOperating) {
                                IconButton(onClick = onClearMessage, modifier = Modifier.size(24.dp)) {
                                    Icon(Icons.Default.Close, null, modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                }

                // 更多操作
                if (isConnected) {
                    SectionTitle("更多操作")
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        LandscapeActionBtn(Icons.Default.CreditCard, "发卡", !state.isOperating, onAddCard, Modifier.weight(1f))
                        LandscapeActionBtn(Icons.Default.AcUnit, "冻结卡", !state.isOperating, onFreezeCard, Modifier.weight(1f))
                        LandscapeActionBtn(Icons.Default.AccessTime, "校时", !state.isOperating, onCheckTime, Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        LandscapeActionBtn(Icons.Default.LockOpen, "常开", !state.isOperating, onAlwaysOpen, Modifier.weight(1f))
                        LandscapeActionBtn(Icons.Default.Lock, "常闭", !state.isOperating, onAlwaysOff, Modifier.weight(1f))
                        LandscapeActionBtn(
                            Icons.Default.Checklist,
                            if (state.userInfo?.personKind == 1) "巡更" else "考勤",
                            !state.isOperating, onCheckDaily, Modifier.weight(1f),
                        )
                    }
                } else {
                    // 未连接时显示占位
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.AutoMirrored.Filled.BluetoothSearching, null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                            )
                            Spacer(Modifier.height(12.dp))
                            Text(
                                "连接门锁后可使用更多操作",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LandscapeActionBtn(
    icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier,
) {
    FilledTonalButton(
        onClick = onClick, modifier = modifier.height(52.dp),
        enabled = enabled, shape = MaterialTheme.shapes.large,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null, modifier = Modifier.size(18.dp))
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
    }
}
