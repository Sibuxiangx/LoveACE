package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YKTScreen(authViewModel: AuthViewModel, onBack: () -> Unit, vm: YKTViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.yktService) {
        authViewModel.yktService?.let { vm.init(it); vm.loadAll() }
    }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.paymentResult) {
        state.paymentResult?.let {
            snackbarHostState.showSnackbar(
                if (it.success) "充值成功: ${it.message}" else "充值失败: ${it.message}"
            )
            vm.clearPaymentResult()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("一卡通") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading && state.balance == null -> LoadingScreen()
            state.error != null && state.balance == null -> ErrorScreen(state.error!!) { vm.loadAll() }
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 96.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                state.balance?.let { balance -> item { BalanceCard(balance) } }
                item { PaymentCard(state, vm, authViewModel) }
                if (state.isTransactionsLoading) {
                    item { TransactionLoadingIndicator() }
                } else if (state.transactions.isNotEmpty()) {
                    item { TransactionHeader(state.transactions) }
                    items(state.transactions.take(20), key = { "${it.transactionTime}_${it.accountingTime}_${it.balance}" }) { tx -> TransactionItem(tx) }
                    if (state.transactions.size > 20) {
                        item {
                            Text("仅显示最近 20 条记录", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp))
                        }
                    }
                } else if (state.transactionsError != null) {
                    item { TransactionErrorHint(state.transactionsError!!) }
                }
            }
        }
    }
}

// ── 余额卡片 ──

@Composable
private fun BalanceCard(balance: CardBalance) {
    ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
        Column(Modifier.padding(24.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.CreditCard, null, modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer)
                }
                Spacer(Modifier.width(12.dp))
                Text("校园卡余额", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(20.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text("%.2f".format(balance.balance),
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(4.dp))
                Text("元", style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 4.dp))
            }
        }
    }
}

// ── 电费充值卡片 ──

@Composable
private fun PaymentCard(state: YKTUiState, vm: YKTViewModel, authViewModel: AuthViewModel) {
    var showPasswordDialog by remember { mutableStateOf(false) }

    Card(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // 标题行
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(40.dp).background(
                        if (state.isPaymentUnlocked) Color(0xFFE65100).copy(alpha = 0.12f)
                        else MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape
                    ), contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.ElectricBolt, null, modifier = Modifier.size(20.dp),
                        tint = if (state.isPaymentUnlocked) Color(0xFFE65100) else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.width(12.dp))
                Text("电费充值", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                if (!state.isPaymentUnlocked) {
                    Surface(color = Color(0xFFE65100).copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Lock, null, modifier = Modifier.size(12.dp), tint = Color(0xFFE65100))
                            Spacer(Modifier.width(4.dp))
                            Text("已锁定", style = MaterialTheme.typography.labelSmall, color = Color(0xFFE65100))
                        }
                    }
                }
            }

            if (state.isPaymentUnlocked) {
                UnlockedPaymentContent(state, vm)
            } else {
                // 锁定状态 — 提示验证密码
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.LockOpen, null, modifier = Modifier.size(48.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f))
                    Text("充值功能已锁定", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("点击下方按钮验证密码后解锁",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
                    Spacer(Modifier.height(4.dp))
                    FilledTonalButton(
                        onClick = { showPasswordDialog = true },
                        shape = RoundedCornerShape(50),
                    ) {
                        Icon(Icons.Default.Lock, null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("验证密码解锁")
                    }
                }
            }
        }
    }

    // 密码验证对话框
    if (showPasswordDialog) {
        PasswordVerifyDialog(
            onVerify = { password ->
                if (authViewModel.verifyPassword(password)) {
                    showPasswordDialog = false
                    vm.unlockPayment()
                    true
                } else false
            },
            onDismiss = { showPasswordDialog = false },
        )
    }
}


// ── 密码验证对话框 ──

@Composable
private fun PasswordVerifyDialog(onVerify: (String) -> Boolean, onDismiss: () -> Unit) {
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var isVerifying by remember { mutableStateOf(false) }

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
                    value = password,
                    onValueChange = { password = it; error = null },
                    label = { Text("密码") },
                    placeholder = { Text("请输入 UAAP 密码或 VPN 密码") },
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    singleLine = true,
                    isError = error != null,
                    supportingText = error?.let { { Text(it, color = MaterialTheme.colorScheme.error) } },
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (password.isEmpty()) {
                        error = "请输入密码"
                        return@Button
                    }
                    isVerifying = true
                    if (!onVerify(password)) {
                        error = "密码错误，请输入登录时使用的 UAAP 密码或 VPN 密码"
                        isVerifying = false
                    }
                },
                shape = RoundedCornerShape(50),
                enabled = !isVerifying,
            ) {
                Text("验证")
            }
        },
        dismissButton = {
            OutlinedButton(onClick = onDismiss, shape = RoundedCornerShape(50)) { Text("取消") }
        },
    )
}

// ── 已解锁的充值内容 ──

@Composable
private fun UnlockedPaymentContent(state: YKTUiState, vm: YKTViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        state.studentInfo?.let { info ->
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)),
                shape = MaterialTheme.shapes.medium,
            ) {
                ListItem(
                    headlineContent = { Text(info.name, fontWeight = FontWeight.SemiBold) },
                    supportingContent = { Text("学号: ${info.studentId}") },
                    leadingContent = {
                        Icon(Icons.Default.Person, null, modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.primary)
                    },
                    trailingContent = {
                        Text("余额: ${"%.2f".format(info.balance)}元",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary)
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        PaymentSelectors(state, vm)
        PaymentAmountInput(state, vm)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilledTonalButton(
                onClick = { vm.loadPurchaseHistory() },
                modifier = Modifier.weight(1f), shape = RoundedCornerShape(50),
            ) {
                Icon(Icons.Default.History, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("充值记录")
            }
            TextButton(onClick = { vm.lockPayment() }) {
                Icon(Icons.Default.Lock, null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("锁定")
            }
        }
        state.purchaseHistory?.let { PurchaseHistorySection(it) }
    }
}


// ── 级联选择器 ──

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PaymentSelectors(state: YKTUiState, vm: YKTViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OptionDropdown("校区", state.dorms, state.selectedDorm, state.dorms.isNotEmpty()) { vm.selectDorm(it) }
        OptionDropdown("楼栋", state.buildings, state.selectedBuilding, state.buildings.isNotEmpty()) { vm.selectBuilding(it) }
        OptionDropdown("楼层", state.floors, state.selectedFloor, state.floors.isNotEmpty()) { vm.selectFloor(it) }
        OptionDropdown("房间", state.rooms, state.selectedRoom, state.rooms.isNotEmpty()) { vm.selectRoom(it) }
        if (state.loadingOptions) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text("加载中...", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OptionDropdown(
    label: String, options: List<SelectOption>, selected: SelectOption?,
    enabled: Boolean, onSelect: (SelectOption) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded && enabled, onExpandedChange = { if (enabled) expanded = it }) {
        OutlinedTextField(
            value = selected?.name ?: "", onValueChange = {}, readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(), enabled = enabled, singleLine = true,
        )
        ExposedDropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(option.name) }, onClick = { onSelect(option); expanded = false })
            }
        }
    }
}

// ── 充值金额 ──

@Composable
private fun PaymentAmountInput(state: YKTUiState, vm: YKTViewModel) {
    var amountText by remember { mutableStateOf("") }
    val canPay = state.selectedRoom != null && !state.isPaying && amountText.toIntOrNull()?.let { it > 0 } == true

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = amountText,
            onValueChange = { amountText = it.filter { c -> c.isDigit() } },
            label = { Text("充值金额（元）") },
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(10, 50, 100).forEach { amount ->
                OutlinedButton(
                    onClick = { amountText = amount.toString() },
                    shape = RoundedCornerShape(50), modifier = Modifier.weight(1f),
                ) { Text("$amount 元") }
            }
        }
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f)),
            shape = MaterialTheme.shapes.medium,
        ) {
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Info, null, modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer)
                Spacer(Modifier.width(8.dp))
                Text("充值金额必须为正整数，将从校园卡余额中扣除",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer)
            }
        }
        Button(
            onClick = { amountText.toIntOrNull()?.let { vm.payElectricity(it) } },
            enabled = canPay, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(50),
        ) {
            if (state.isPaying) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary)
            } else {
                Icon(Icons.Default.ElectricBolt, null, modifier = Modifier.size(18.dp))
            }
            Spacer(Modifier.width(6.dp))
            Text(if (state.isPaying) "充值中..." else "确认充值")
        }
    }
}

// ── 购电记录 ──

@Composable
private fun PurchaseHistorySection(history: ElectricPurchaseQueryResult) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("购电记录", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text("${history.startDate} ~ ${history.endDate}", style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (history.records.isEmpty()) {
            Text("暂无购电记录", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            Text("共 ${history.records.size} 条，合计 ${"%.2f".format(history.totalAmount)} 元",
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            history.records.forEach { record ->
                ListItem(
                    headlineContent = { Text(record.roomInfo, style = MaterialTheme.typography.bodyMedium) },
                    supportingContent = { Text(record.purchaseDate) },
                    trailingContent = {
                        Text("${"%.2f".format(record.amount)} 元", style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold, color = Color(0xFF2E7D32))
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
    }
}

// ── 交易记录加载中 ──


@Composable
private fun TransactionLoadingIndicator() {
    Card(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Row(
            Modifier.padding(20.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            AppCircularProgressIndicator(modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(12.dp))
            Text("消费记录加载中，请稍候...", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ── 交易记录加载失败 ──

@Composable
private fun TransactionErrorHint(error: String) {
    Card(
        Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)),
    ) {
        Row(
            Modifier.padding(16.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.ErrorOutline, null, modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.width(8.dp))
            Text("消费记录加载失败: $error", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer)
        }
    }
}

// ── 交易记录标题 ──

@Composable
private fun TransactionHeader(transactions: List<TransactionRecord>) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(40.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Default.Receipt, null, modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onTertiaryContainer)
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text("近期交易", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text("共 ${transactions.size} 条记录", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ── 交易记录项 ──

@Composable
private fun TransactionItem(tx: TransactionRecord) {
    ListItem(
        headlineContent = {
            Text(tx.area.ifEmpty { tx.operationType }, style = MaterialTheme.typography.bodyMedium)
        },
        supportingContent = {
            Text(tx.transactionTime.ifEmpty { tx.accountingTime },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        },
        leadingContent = {
            Box(
                Modifier.size(36.dp).background(
                    if (tx.isIncome) Color(0xFF2E7D32).copy(alpha = 0.12f)
                    else MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape
                ), contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (tx.isIncome) Icons.Default.Add else Icons.Default.Remove,
                    null, modifier = Modifier.size(16.dp),
                    tint = if (tx.isIncome) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        trailingContent = {
            Text(tx.amountText, style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = if (tx.isIncome) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurface)
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
