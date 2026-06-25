package tech.loveace.appv3.ui.screen

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.R
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.theme.LocalIsDarkTheme
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.DoorCardUiState
import tech.loveace.appv3.ui.viewmodel.DoorCardViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DoorCardScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("宿舍门卡") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                    }
                },
                actions = {
                    if (state.isBound) {
                        IconButton(onClick = { showUnbindDialog = true }) {
                            Icon(Icons.Default.LinkOff, "解绑")
                        }
                    }
                },
            )
        },
    ) { padding ->
        if (!state.isBound) {
            DoorCardBindView(
                isBinding = state.isBinding,
                bindError = state.bindError,
                onBind = { userno, username, password -> vm.bind(userno, username, password) },
                modifier = Modifier.padding(padding),
            )
        } else {
            DoorCardPassView(
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

// ==================== 绑定视图 ====================

@Composable
private fun DoorCardBindView(
    isBinding: Boolean,
    bindError: String?,
    onBind: (String, String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var userno by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // IC 卡风格头部
        Card(
            shape = MaterialTheme.shapes.extraLarge,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
        ) {
            Column(
                Modifier.fillMaxWidth().padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    Modifier.size(72.dp).background(MaterialTheme.colorScheme.primary, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.Key, null, modifier = Modifier.size(36.dp), tint = MaterialTheme.colorScheme.onPrimary)
                }
                Spacer(Modifier.height(16.dp))
                Text("宿舍门卡绑定", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Text(
                    "绑定后可使用手机蓝牙开门",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                )
            }
        }

        SectionTitle("账号信息")

        OutlinedTextField(
            value = userno, onValueChange = { userno = it },
            modifier = Modifier.fillMaxWidth(), label = { Text("学号") },
            placeholder = { Text("请输入学号") }, singleLine = true,
            shape = MaterialTheme.shapes.large,
            leadingIcon = { Icon(Icons.Default.Badge, null) },
        )
        OutlinedTextField(
            value = username, onValueChange = { username = it },
            modifier = Modifier.fillMaxWidth(), label = { Text("姓名") },
            placeholder = { Text("请输入姓名") }, singleLine = true,
            shape = MaterialTheme.shapes.large,
            leadingIcon = { Icon(Icons.Default.Person, null) },
        )
        OutlinedTextField(
            value = password, onValueChange = { password = it },
            modifier = Modifier.fillMaxWidth(), label = { Text("密码") },
            placeholder = { Text("请输入门卡系统密码") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            shape = MaterialTheme.shapes.large,
            leadingIcon = { Icon(Icons.Default.Lock, null) },
        )

        AnimatedVisibility(bindError != null) {
            Card(
                shape = MaterialTheme.shapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            ) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Error, null, tint = MaterialTheme.colorScheme.onErrorContainer)
                    Spacer(Modifier.width(12.dp))
                    Text(bindError ?: "", color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        }

        Button(
            onClick = { onBind(userno, username, password) },
            modifier = Modifier.fillMaxWidth().height(52.dp),
            enabled = !isBinding && userno.isNotEmpty() && username.isNotEmpty() && password.isNotEmpty(),
            shape = MaterialTheme.shapes.large,
        ) {
            if (isBinding) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text("绑定")
        }

        Card(
            shape = MaterialTheme.shapes.large,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        ) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Default.Info, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(12.dp))
                Text(
                    "此功能使用宿舍门卡管理系统账号，与校园 VPN 账号不同。如不清楚密码请联系宿管。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ==================== IC 卡通行证视图 ====================


@Composable
private fun DoorCardPassView(
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
        else -> Column(
            modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── IC 卡主卡片 ──
            ICCardView(
                personName = state.userInfo?.personName ?: "",
                roomName = room.roomName,
                buildName = room.buildName,
                power = room.power,
                bleState = state.bleState,
            )

            // ── BLE 连接按钮 ──
            if (!isConnected && !isConnecting) {
                Button(
                    onClick = onConnect,
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = MaterialTheme.shapes.extraLarge,
                ) {
                    Icon(Icons.Default.Bluetooth, null, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("连接门锁", style = MaterialTheme.typography.titleSmall)
                }
            } else if (isConnecting) {
                OutlinedCard(
                    shape = MaterialTheme.shapes.extraLarge,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        Modifier.padding(20.dp).fillMaxWidth(),
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
                    modifier = Modifier.fillMaxWidth().height(72.dp),
                    enabled = !state.isOperating,
                    shape = MaterialTheme.shapes.extraLarge,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                    ),
                ) {
                    Icon(Icons.Default.LockOpen, null, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("手机开门", style = MaterialTheme.typography.titleMedium)
                }

                // 断开连接
                TextButton(
                    onClick = onDisconnect,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.BluetoothDisabled, null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("断开连接")
                }
            }

            // ── 操作消息 ──
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

            // ── 更多操作（折叠区域） ──
            if (isConnected) {
                SectionTitle("更多操作")
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DoorActionChip(Icons.Default.CreditCard, "发卡", !state.isOperating, onAddCard, Modifier.weight(1f))
                    DoorActionChip(Icons.Default.AcUnit, "冻结卡", !state.isOperating, onFreezeCard, Modifier.weight(1f))
                    DoorActionChip(Icons.Default.AccessTime, "校时", !state.isOperating, onCheckTime, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    DoorActionChip(Icons.Default.LockOpen, "常开", !state.isOperating, onAlwaysOpen, Modifier.weight(1f))
                    DoorActionChip(Icons.Default.Lock, "常闭", !state.isOperating, onAlwaysOff, Modifier.weight(1f))
                    DoorActionChip(
                        Icons.Default.Checklist,
                        if (state.userInfo?.personKind == 1) "巡更" else "考勤",
                        !state.isOperating, onCheckDaily, Modifier.weight(1f),
                    )
                }
            }

            Spacer(Modifier.height(32.dp))
        }
    }
}

// ==================== 莫兰迪色系 IC 卡 — 艺术插画风（亮/暗双模式） ====================

/** 卡面配色数据类 */
private data class CardPalette(
    val cardBackground: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val borderColor: Color,
    val chipGold: Color,
    val chipGoldLine: Color,
    val bleGreen: Color,
    val bleYellow: Color,
    val bleRed: Color,
    val illustrationTint: Color,
    val shimmerHighlight: Color,
    val illustrationAlpha: Float,
)

/** 亮色莫兰迪 — 哑光米白 */
private val LightCardPalette = CardPalette(
    cardBackground = Color(0xFFF5F5F3),
    textPrimary = Color(0xFF2D3436),
    textSecondary = Color(0xFF636E72),
    textTertiary = Color(0xFFB2BEC3),
    borderColor = Color(0xFFD5D8DC),
    chipGold = Color(0xFFCBB682),
    chipGoldLine = Color(0xFFB8A06E),
    bleGreen = Color(0xFF7EAE8B),
    bleYellow = Color(0xFFD4B96A),
    bleRed = Color(0xFFC97B7B),
    illustrationTint = Color(0xFF8FA7B3),
    shimmerHighlight = Color.White.copy(alpha = 0.2f),
    illustrationAlpha = 0.12f,
)

/** 暗色莫兰迪 — 深岩灰 */
private val DarkCardPalette = CardPalette(
    cardBackground = Color(0xFF1E2328),
    textPrimary = Color(0xFFE8EAED),
    textSecondary = Color(0xFFA0A8B0),
    textTertiary = Color(0xFF5C6670),
    borderColor = Color(0xFF353B42),
    chipGold = Color(0xFF9A8A5E),
    chipGoldLine = Color(0xFF7D7048),
    bleGreen = Color(0xFF6B9E7A),
    bleYellow = Color(0xFFC4A85A),
    bleRed = Color(0xFFB86B6B),
    illustrationTint = Color(0xFF6B8290),
    shimmerHighlight = Color.White.copy(alpha = 0.08f),
    illustrationAlpha = 0.10f,
)

@Composable
private fun cardPalette(): CardPalette =
    if (LocalIsDarkTheme.current) DarkCardPalette else LightCardPalette

@Composable
internal fun ICCardView(
    personName: String,
    roomName: String,
    buildName: String,
    power: Int,
    bleState: BleConnectionState,
) {
    val isDark = LocalIsDarkTheme.current
    val palette = cardPalette()

    // Shimmer 扫光动画
    val shimmerTransition = rememberInfiniteTransition(label = "shimmer")
    val shimmerOffset by shimmerTransition.animateFloat(
        initialValue = -1f,
        targetValue = 2f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmerOffset",
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1.586f) // 标准 IC 卡比例
            .border(
                width = 1.dp,
                color = palette.borderColor.copy(alpha = 0.6f),
                shape = RoundedCornerShape(28.dp),
            ),
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = palette.cardBackground),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .drawWithContent {
                    drawContent()
                    // Shimmer 扫光层
                    val shimmerWidth = size.width * 0.4f
                    val startX = shimmerOffset * size.width
                    drawRect(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                Color.Transparent,
                                palette.shimmerHighlight.copy(alpha = palette.shimmerHighlight.alpha * 0.6f),
                                palette.shimmerHighlight,
                                palette.shimmerHighlight.copy(alpha = palette.shimmerHighlight.alpha * 0.6f),
                                Color.Transparent,
                            ),
                            start = Offset(startX, 0f),
                            end = Offset(startX + shimmerWidth, size.height),
                        ),
                    )
                },
        ) {
            // 底层：校园建筑线条插画（若隐若现）— 亮/暗使用不同矢量图
            val skylineRes = if (isDark) R.drawable.ic_campus_skyline_night else R.drawable.ic_campus_skyline
            Image(
                painter = painterResource(skylineRes),
                contentDescription = null,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .fillMaxWidth(0.7f)
                    .fillMaxHeight(0.55f)
                    .offset(x = 16.dp, y = 8.dp)
                    .alpha(palette.illustrationAlpha),
                contentScale = ContentScale.FillWidth,
                // 亮色模式用 tint 统一线条色；暗色模式夜景图自带配色，不再 tint
                colorFilter = if (isDark) null else ColorFilter.tint(
                    palette.illustrationTint,
                    blendMode = BlendMode.SrcIn,
                ),
            )

            // 信息层
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(24.dp),
            ) {
                // ── 顶部：校徽区 + NFC 标识 ──
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // 左上：校徽占位 + 标题
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        // IC 芯片图案
                        Box(
                            Modifier
                                .size(width = 36.dp, height = 26.dp)
                                .clip(RoundedCornerShape(5.dp))
                                .background(palette.chipGold)
                                .border(0.5.dp, palette.chipGoldLine, RoundedCornerShape(5.dp)),
                        )
                        Column {
                            Text(
                                "CAMPUS CARD",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Medium,
                                color = palette.textTertiary,
                                letterSpacing = 2.sp,
                            )
                            Text(
                                "宿舍门卡",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = palette.textSecondary,
                            )
                        }
                    }

                    // 右上：NFC + BLE 状态
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        // BLE 状态
                        val bleColor = when (bleState) {
                            BleConnectionState.Connected -> palette.bleGreen
                            BleConnectionState.Scanning, BleConnectionState.Connecting -> palette.bleYellow
                            BleConnectionState.Error -> palette.bleRed
                            else -> palette.textTertiary
                        }
                        Box(
                            Modifier
                                .size(7.dp)
                                .background(bleColor, CircleShape),
                        )
                        Text(
                            when (bleState) {
                                BleConnectionState.Connected -> "已连接"
                                BleConnectionState.Scanning -> "搜索中"
                                BleConnectionState.Connecting -> "连接中"
                                BleConnectionState.Error -> "连接失败"
                                else -> "未连接"
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = palette.textTertiary,
                        )
                        Icon(
                            Icons.Default.Nfc, null,
                            modifier = Modifier.size(18.dp),
                            tint = palette.textTertiary.copy(alpha = 0.6f),
                        )
                    }
                }

                Spacer(Modifier.weight(1f))

                // ── 中部：房间号（核心视觉） ──
                Text(
                    roomName,
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Light,
                    color = palette.textPrimary,
                    letterSpacing = 2.sp,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    buildName,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Normal,
                    color = palette.textSecondary,
                    letterSpacing = 0.5.sp,
                )

                Spacer(Modifier.weight(1f))

                // ── 底部：姓名 + 电量 ──
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Bottom,
                ) {
                    Text(
                        personName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Medium,
                        color = palette.textPrimary,
                        letterSpacing = 3.sp,
                    )

                    // 电量
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        val batteryIcon = when {
                            power >= 80 -> Icons.Default.BatteryFull
                            power >= 50 -> Icons.Default.Battery5Bar
                            power >= 20 -> Icons.Default.Battery3Bar
                            else -> Icons.Default.Battery1Bar
                        }
                        val batteryColor = when {
                            power < 20 -> palette.bleRed
                            power < 50 -> palette.bleYellow
                            else -> palette.textTertiary
                        }
                        Icon(
                            batteryIcon, null,
                            modifier = Modifier.size(16.dp),
                            tint = batteryColor,
                        )
                        Spacer(Modifier.width(3.dp))
                        Text(
                            "${power}%",
                            style = MaterialTheme.typography.labelSmall,
                            color = batteryColor,
                        )
                    }
                }
            }
        }
    }
}

// ==================== 操作 Chip ====================

@Composable
private fun DoorActionChip(
    icon: ImageVector,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier.height(52.dp),
        enabled = enabled,
        shape = MaterialTheme.shapes.large,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null, modifier = Modifier.size(18.dp))
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
    }
}

// ==================== 工具函数 ====================

internal fun buildBlePermissions(): Array<String> {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
    } else {
        arrayOf(
            Manifest.permission.BLUETOOTH,
            Manifest.permission.BLUETOOTH_ADMIN,
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
    }
}
