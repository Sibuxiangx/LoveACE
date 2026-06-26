package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.YKTUiState
import tech.loveace.appv3.ui.viewmodel.YKTViewModel

/**
 * 横屏一卡通：左栏余额+充值 | 右栏消费记录
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeYKTScreen(authViewModel: AuthViewModel, vm: YKTViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.yktService) {
        authViewModel.yktService?.let { vm.init(it); vm.loadAll() }
    }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.paymentResult) {
        state.paymentResult?.let {
            snackbarHostState.showSnackbar(if (it.success) "充值成功: ${it.message}" else "充值失败: ${it.message}")
            vm.clearPaymentResult()
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("一卡通") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading && state.balance == null -> LoadingScreen()
            state.error != null && state.balance == null -> ErrorScreen(state.error!!) { vm.loadAll() }
            else -> Row(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // 左栏：余额 + 充值
                Column(
                    Modifier.weight(0.45f).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    state.balance?.let { balance ->
                        ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
                            Column(Modifier.padding(24.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                                        Icon(Icons.Default.CreditCard, null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                    }
                                    Spacer(Modifier.width(12.dp))
                                    Text("校园卡余额", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                }
                                Spacer(Modifier.height(16.dp))
                                Row(verticalAlignment = Alignment.Bottom) {
                                    Text("%.2f".format(balance.balance), style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                                    Spacer(Modifier.width(4.dp))
                                    Text("元", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 4.dp))
                                }
                            }
                        }
                    }
                    LandscapePaymentCard(state, vm, authViewModel)
                }

                // 右栏：消费记录
                Column(Modifier.weight(0.55f)) {
                    when {
                        state.isTransactionsLoading -> {
                            // 加载中
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    AppCircularProgressIndicator(modifier = Modifier.size(40.dp))
                                    Spacer(Modifier.height(16.dp))
                                    Text("消费记录加载中，请稍候...", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("一卡通消费记录加载较慢，请耐心等待", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                                }
                            }
                        }
                        state.transactionsError != null -> {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Icon(Icons.Default.ErrorOutline, null, modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.error.copy(alpha = 0.6f))
                                    Spacer(Modifier.height(12.dp))
                                    Text("消费记录加载失败", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(state.transactionsError!!, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                                }
                            }
                        }
                        state.transactions.isNotEmpty() -> {
                            LazyColumn(
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                                contentPadding = PaddingValues(bottom = 16.dp),
                            ) {
                                item {
                                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
                                        Box(Modifier.size(40.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                                            Icon(Icons.Default.Receipt, null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onTertiaryContainer)
                                        }
                                        Spacer(Modifier.width(12.dp))
                                        Column {
                                            Text("近期交易", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                            Text("共 ${state.transactions.size} 条记录", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }
                                items(state.transactions.take(20), key = { "${it.transactionTime}_${it.accountingTime}_${it.balance}" }) { tx ->
                                    ListItem(
                                        headlineContent = { Text(tx.area.ifEmpty { tx.operationType }, style = MaterialTheme.typography.bodyMedium) },
                                        supportingContent = { Text(tx.transactionTime.ifEmpty { tx.accountingTime }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                                        leadingContent = {
                                            Box(Modifier.size(36.dp).background(if (tx.isIncome) Color(0xFF2E7D32).copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape), contentAlignment = Alignment.Center) {
                                                Icon(if (tx.isIncome) Icons.Default.Add else Icons.Default.Remove, null, modifier = Modifier.size(16.dp), tint = if (tx.isIncome) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurfaceVariant)
                                            }
                                        },
                                        trailingContent = { Text(tx.amountText, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = if (tx.isIncome) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurface) },
                                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                    )
                                }
                            }
                        }
                        else -> {
                            // 余额已加载但消费记录还没开始加载
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Icon(Icons.Default.ReceiptLong, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f))
                                    Spacer(Modifier.height(12.dp))
                                    Text("暂无消费记录", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LandscapePaymentCard(state: YKTUiState, vm: YKTViewModel, authViewModel: AuthViewModel) {
    var showPasswordDialog by remember { mutableStateOf(false) }

    Card(
        Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.ElectricBolt, null, modifier = Modifier.size(20.dp), tint = if (state.isPaymentUnlocked) Color(0xFFE65100) else MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(12.dp))
                Text("电费充值", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                if (!state.isPaymentUnlocked) {
                    Surface(color = Color(0xFFE65100).copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Lock, null, modifier = Modifier.size(12.dp), tint = Color(0xFFE65100))
                            Spacer(Modifier.width(4.dp))
                            Text("已锁定", style = MaterialTheme.typography.labelSmall, color = Color(0xFFE65100))
                        }
                    }
                }
            }

            if (state.isPaymentUnlocked) {
                LandscapeUnlockedPayment(state, vm)
            } else {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("点击解锁充值功能", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    FilledTonalButton(onClick = { showPasswordDialog = true }, shape = RoundedCornerShape(50)) {
                        Icon(Icons.Default.Lock, null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("验证密码解锁")
                    }
                }
            }
        }
    }

    if (showPasswordDialog) {
        LandscapePasswordVerifyDialog(
            onVerify = { password ->
                if (authViewModel.verifyPassword(password)) { showPasswordDialog = false; vm.unlockPayment(); true } else false
            },
            onDismiss = { showPasswordDialog = false },
        )
    }
}

@Composable
private fun LandscapeUnlockedPayment(state: YKTUiState, vm: YKTViewModel) {
    var amountText by remember { mutableStateOf("") }
    val canPay = state.selectedRoom != null && !state.isPaying && amountText.toIntOrNull()?.let { it > 0 } == true

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LandscapeOptionDropdown("校区", state.dorms, state.selectedDorm, state.dorms.isNotEmpty(), Modifier.weight(1f)) { vm.selectDorm(it) }
            LandscapeOptionDropdown("楼栋", state.buildings, state.selectedBuilding, state.buildings.isNotEmpty(), Modifier.weight(1f)) { vm.selectBuilding(it) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LandscapeOptionDropdown("楼层", state.floors, state.selectedFloor, state.floors.isNotEmpty(), Modifier.weight(1f)) { vm.selectFloor(it) }
            LandscapeOptionDropdown("房间", state.rooms, state.selectedRoom, state.rooms.isNotEmpty(), Modifier.weight(1f)) { vm.selectRoom(it) }
        }
        OutlinedTextField(
            value = amountText, onValueChange = { amountText = it.filter { c -> c.isDigit() } },
            label = { Text("充值金额（元）") }, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(10, 50, 100).forEach { amount ->
                OutlinedButton(onClick = { amountText = amount.toString() }, shape = RoundedCornerShape(50), modifier = Modifier.weight(1f)) { Text("$amount 元") }
            }
        }
        Button(onClick = { amountText.toIntOrNull()?.let { vm.payElectricity(it) } }, enabled = canPay, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(50)) {
            if (state.isPaying) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
            else Icon(Icons.Default.ElectricBolt, null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (state.isPaying) "充值中..." else "确认充值")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LandscapeOptionDropdown(label: String, options: List<SelectOption>, selected: SelectOption?, enabled: Boolean, modifier: Modifier, onSelect: (SelectOption) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded && enabled, onExpandedChange = { if (enabled) expanded = it }, modifier = modifier) {
        OutlinedTextField(
            value = selected?.name ?: "", onValueChange = {}, readOnly = true, label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(), enabled = enabled, singleLine = true,
        )
        ExposedDropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false }) {
            options.forEach { option -> DropdownMenuItem(text = { Text(option.name) }, onClick = { onSelect(option); expanded = false }) }
        }
    }
}

@Composable
private fun LandscapePasswordVerifyDialog(onVerify: (String) -> Boolean, onDismiss: () -> Unit) {
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Box(
                Modifier.size(48.dp).background(Color(0xFFE65100).copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Default.Lock, null, modifier = Modifier.size(24.dp), tint = Color(0xFFE65100))
            }
        },
        title = { Text("解锁充值功能") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.5f)),
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Info, null, modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onTertiaryContainer)
                        Spacer(Modifier.width(8.dp))
                        Text("为保护账户安全，请输入登录时使用的 UAAP 密码或 VPN 密码进行验证。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onTertiaryContainer)
                    }
                }
                OutlinedTextField(
                    value = password, onValueChange = { password = it; error = null },
                    label = { Text("密码") },
                    placeholder = { Text("请输入 UAAP 密码或 VPN 密码") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    singleLine = true, isError = error != null,
                    supportingText = error?.let { { Text(it, color = MaterialTheme.colorScheme.error) } },
                )
            }
        },
        confirmButton = {
            Button(onClick = {
                if (password.isEmpty()) { error = "请输入密码"; return@Button }
                if (!onVerify(password)) error = "密码错误，请输入登录时使用的 UAAP 密码或 VPN 密码"
            }, shape = RoundedCornerShape(50)) { Text("验证") }
        },
        dismissButton = { OutlinedButton(onClick = onDismiss, shape = RoundedCornerShape(50)) { Text("取消") } },
    )
}
