package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.ElectricityBalance
import tech.loveace.appv3.data.model.ElectricityUsageRecord
import tech.loveace.appv3.data.model.PaymentRecord
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ElectricityViewModel

/**
 * 横屏电费查询：左栏余额+房间信息 | 右栏用电/充值记录
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeElectricityScreen(
    authViewModel: AuthViewModel,
    vm: ElectricityViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var showRoomSheet by remember { mutableStateOf(false) }

    LaunchedEffect(authViewModel.isimService) {
        authViewModel.isimService?.let { vm.init(it); vm.autoLoad() }
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("电费查询") },
            actions = {
                if (state.boundRoomCode != null) {
                    IconButton(onClick = { showRoomSheet = true }) { Icon(Icons.Default.Edit, "更换房间") }
                    IconButton(onClick = { vm.autoLoad() }) { Icon(Icons.Default.Sync, "刷新") }
                }
            },
        )
    }) { padding ->
        when {
            state.boundRoomCode == null && state.electricityInfo == null && !state.isLoading -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(80.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                            Icon(Icons.Default.Home, null, modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                        }
                        Spacer(Modifier.height(24.dp))
                        Text("未绑定房间", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(8.dp))
                        Text("请先绑定您的宿舍房间", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(32.dp))
                        Button(onClick = { showRoomSheet = true }) {
                            Icon(Icons.Default.AddLocation, null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("绑定房间")
                        }
                    }
                }
            }
            state.isLoading && state.electricityInfo == null -> LoadingScreen()
            state.error != null && state.electricityInfo == null -> ErrorScreen(state.error!!) { vm.autoLoad() }
            else -> {
                val info = state.electricityInfo
                Row(
                    Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    // 左栏：余额 + 房间 + 充值记录
                    Column(
                        Modifier.weight(0.4f).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        state.boundRoomDisplay?.let { display ->
                            Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(50), modifier = Modifier.clickable { showRoomSheet = true }) {
                                Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.Home, null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                    Spacer(Modifier.width(6.dp))
                                    Text(display, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                }
                            }
                        }
                        if (info != null) {
                            // 余额卡片
                            ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
                                Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("剩余电量", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Spacer(Modifier.height(8.dp))
                                    Row(verticalAlignment = Alignment.Bottom) {
                                        Text("${"%.1f".format(info.balance.total)}", style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                                        Spacer(Modifier.width(4.dp))
                                        Text("度", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
                                    }
                                    Spacer(Modifier.height(16.dp))
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        LandscapeBalanceChip("购电", info.balance.remainingPurchased, Color(0xFF1565C0), Modifier.weight(1f))
                                        LandscapeBalanceChip("补助", info.balance.remainingSubsidy, Color(0xFF2E7D32), Modifier.weight(1f))
                                    }
                                }
                            }

                            // 充值记录
                            if (info.payments.isNotEmpty()) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(36.dp).background(Color(0xFFE8F5E9), CircleShape), contentAlignment = Alignment.Center) {
                                        Icon(Icons.Default.Paid, null, modifier = Modifier.size(18.dp), tint = Color(0xFF2E7D32))
                                    }
                                    Spacer(Modifier.width(10.dp))
                                    Text("充值记录", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                    Text("共 ${info.payments.size} 条", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                info.payments.take(10).forEach { record ->
                                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow), shape = MaterialTheme.shapes.medium) {
                                        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                            Column(Modifier.weight(1f)) {
                                                Text(record.paymentTime, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                                if (record.paymentType.isNotEmpty()) Text(record.paymentType, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            }
                                            Surface(color = Color(0xFFE8F5E9), shape = RoundedCornerShape(50)) {
                                                Text("+${"%.2f".format(record.amount)} 元", modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = Color(0xFF2E7D32))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 右栏：用电记录
                    if (info != null && info.usageRecords.isNotEmpty()) {
                        LazyColumn(
                            Modifier.weight(0.6f),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            contentPadding = PaddingValues(bottom = 16.dp),
                        ) {
                            item {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(36.dp).background(Color(0xFFFFF3E0), CircleShape), contentAlignment = Alignment.Center) {
                                        Icon(Icons.Default.Bolt, null, modifier = Modifier.size(18.dp), tint = Color(0xFFE65100))
                                    }
                                    Spacer(Modifier.width(10.dp))
                                    Text("用电记录", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                    Text("共 ${info.usageRecords.size} 条", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            items(info.usageRecords.take(20), key = { "${it.recordTime}_${it.meterName}" }) { record ->
                                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow), shape = MaterialTheme.shapes.medium) {
                                    Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Column(Modifier.weight(1f)) {
                                            Text(record.recordTime, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                            if (record.meterName.isNotEmpty()) Text(record.meterName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                        Surface(color = Color(0xFFFFF3E0), shape = RoundedCornerShape(50)) {
                                            Text("-${"%.1f".format(record.usageAmount)} 度", modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = Color(0xFFE65100))
                                        }
                                    }
                                }
                            }
                        }
                    } else if (info != null) {
                        Box(Modifier.weight(0.6f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Default.Bolt, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f))
                                Spacer(Modifier.height(12.dp))
                                Text("暂无用电记录", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                            }
                        }
                    }
                }
            }
        }
    }

    if (showRoomSheet) {
        LandscapeRoomSelectionSheet(vm = vm, onDismiss = { showRoomSheet = false }, onConfirm = { vm.confirmBinding(); showRoomSheet = false })
    }
}

@Composable
private fun LandscapeBalanceChip(label: String, value: Double, color: Color, modifier: Modifier) {
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh), shape = MaterialTheme.shapes.medium) {
        Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${"%.1f".format(value)}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = color)
                Spacer(Modifier.width(2.dp))
                Text("度", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LandscapeRoomSelectionSheet(vm: ElectricityViewModel, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { vm.loadBuildings() }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp)) {
            Text("选择房间", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            // 横屏用两行两列
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                LandscapeRoomDropdown("楼栋", state.buildings, state.selectedBuilding?.let { mapOf("code" to it.code, "name" to it.name) }, state.buildings.isNotEmpty(), Modifier.weight(1f)) { vm.selectBuilding(it["code"]!!, it["name"]!!) }
                LandscapeRoomDropdown("楼层", state.floors, state.selectedFloor?.let { mapOf("code" to it.code, "name" to it.name) }, state.selectedBuilding != null && state.floors.isNotEmpty(), Modifier.weight(1f)) { vm.selectFloor(it["code"]!!, it["name"]!!) }
            }
            Spacer(Modifier.height(12.dp))
            LandscapeRoomDropdown("房间", state.rooms, state.selectedRoom?.let { mapOf("code" to it.code, "name" to it.name) }, state.selectedFloor != null && state.rooms.isNotEmpty(), Modifier.fillMaxWidth()) { vm.selectRoom(it["code"]!!, it["name"]!!) }
            if (state.isLoading) { Spacer(Modifier.height(16.dp)); Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { AppCircularProgressIndicator(modifier = Modifier.size(32.dp)) } }
            Spacer(Modifier.height(24.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("取消") }
                Spacer(Modifier.width(12.dp))
                Button(onClick = onConfirm, enabled = state.selectedRoom != null && !state.isLoading) { Text("确认绑定") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LandscapeRoomDropdown(label: String, items: List<Map<String, String>>, selected: Map<String, String>?, enabled: Boolean, modifier: Modifier, onSelect: (Map<String, String>) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(modifier) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(6.dp))
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { if (enabled) expanded = it }) {
            OutlinedTextField(value = selected?.get("name") ?: "", onValueChange = {}, readOnly = true, enabled = enabled, placeholder = { Text("请选择$label") }, trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) }, modifier = Modifier.fillMaxWidth().menuAnchor(), shape = MaterialTheme.shapes.medium, singleLine = true)
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                items.forEach { item -> DropdownMenuItem(text = { Text(item["name"] ?: "") }, onClick = { onSelect(item); expanded = false }) }
            }
        }
    }
}
