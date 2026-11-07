package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.screen.YKTErrorCard
import tech.loveace.appv3.ui.screen.consumptionSection
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
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

    LaunchedEffect(authViewModel.yktService, authViewModel.portalService) {
        authViewModel.yktService?.let { vm.init(it, authViewModel.portalService); vm.loadAll() }
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
        if (state.isLoading && state.balance == null) {
            LoadingScreen()
        } else {
            Row(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // 左栏：余额 + 充值
                Column(
                    Modifier.weight(0.45f).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    val balance = state.balance
                    if (balance != null) {
                        RibbonCard(Modifier.fillMaxWidth(), variant = RibbonCardVariant.PRIMARY_CONTAINER, radius = 32.dp, padding = PaddingValues(22.dp)) {
                            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    ShapeBadge(shape = RibbonShape.COOKIE_8, size = 44.dp, color = MaterialTheme.colorScheme.primary, icon = Icons.Default.CreditCard, iconTint = MaterialTheme.colorScheme.onPrimary)
                                    Spacer(Modifier.width(12.dp))
                                    Text("校园卡余额", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                }
                                Spacer(Modifier.height(16.dp))
                                Row(verticalAlignment = Alignment.Bottom) {
                                    Text("%.2f".format(balance.balance), style = RibbonNumeric.Large, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                    Spacer(Modifier.width(4.dp))
                                    Text("元", style = RibbonNumeric.Caption, color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f), modifier = Modifier.padding(bottom = 4.dp))
                                }
                            }
                        }
                    } else {
                        state.error?.let { message -> YKTErrorCard(message) { vm.loadBalance() } }
                    }
                    LandscapePaymentCard(state, vm, authViewModel)
                }

                // 右栏：本月消费
                LazyColumn(
                    Modifier.weight(0.55f),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    contentPadding = PaddingValues(bottom = 16.dp),
                ) {
                    consumptionSection(state, vm)
                }
            }
        }
    }
}

@Composable
private fun LandscapePaymentCard(state: YKTUiState, vm: YKTViewModel, authViewModel: AuthViewModel) {
    var showPasswordDialog by remember { mutableStateOf(false) }

    RibbonCard(Modifier.fillMaxWidth(), variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.ElectricBolt, null, modifier = Modifier.size(20.dp), tint = if (state.isPaymentUnlocked) LocalExtendedColors.current.warning else MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(12.dp))
                Text("电费充值", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                if (!state.isPaymentUnlocked) {
                    RibbonChip("已锁定", tone = RibbonTone.WARNING, filled = true, icon = Icons.Default.Lock)
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
            ShapeBadge(
                shape = RibbonShape.COOKIE_8,
                size = 48.dp,
                color = LocalExtendedColors.current.warningContainer,
                icon = Icons.Default.Lock,
                iconTint = LocalExtendedColors.current.onWarningContainer,
            )
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
