package tech.loveace.appv3.ui.screen

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ElectricityScreen(authViewModel: AuthViewModel, onBack: () -> Unit, vm: ElectricityViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var showRoomSheet by remember { mutableStateOf(false) }
    var usageExpanded by remember { mutableStateOf(false) }
    var paymentExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(authViewModel.isimService) {
        authViewModel.isimService?.let {
            vm.init(it)
            vm.autoLoad()
        }
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("电费查询") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
            actions = {
                if (state.boundRoomCode != null) {
                    IconButton(onClick = { showRoomSheet = true }) {
                        Icon(Icons.Default.Edit, "更换房间")
                    }
                    IconButton(onClick = { vm.autoLoad() }) {
                        Icon(Icons.Default.Sync, "刷新")
                    }
                }
            },
        )
    }) { padding ->
        when {
            // 未绑定房间
            state.boundRoomCode == null && state.electricityInfo == null && !state.isLoading -> {
                UnboundRoomContent(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    onBind = { showRoomSheet = true },
                )
            }
            // 加载中且无数据
            state.isLoading && state.electricityInfo == null -> LoadingScreen()
            // 错误
            state.error != null && state.electricityInfo == null -> {
                ErrorScreen(state.error!!) { vm.autoLoad() }
            }
            // 有数据
            else -> {
                val info = state.electricityInfo
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    // 房间信息
                    state.boundRoomDisplay?.let { display ->
                        item {
                            Surface(
                                color = MaterialTheme.colorScheme.primaryContainer,
                                shape = RoundedCornerShape(50),
                                modifier = Modifier.clickable { showRoomSheet = true },
                            ) {
                                Row(
                                    Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(Icons.Default.Home, null, modifier = Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                    Spacer(Modifier.width(6.dp))
                                    Text(display, style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer)
                                }
                            }
                        }
                    }

                    if (info != null) {
                        // 余额卡片
                        item { BalanceCard(info.balance) }

                        // 用电记录
                        if (info.usageRecords.isNotEmpty()) {
                            item {
                                UsageSection(
                                    records = info.usageRecords,
                                    expanded = usageExpanded,
                                    onToggle = { usageExpanded = !usageExpanded },
                                )
                            }
                        }

                        // 充值记录
                        if (info.payments.isNotEmpty()) {
                            item {
                                PaymentSection(
                                    records = info.payments,
                                    expanded = paymentExpanded,
                                    onToggle = { paymentExpanded = !paymentExpanded },
                                )
                            }
                        }
                    }

                    if (state.isLoading) {
                        item {
                            Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                                AppCircularProgressIndicator()
                            }
                        }
                    }
                }
            }
        }
    }

    // 房间选择 Bottom Sheet
    if (showRoomSheet) {
        RoomSelectionSheet(
            vm = vm,
            onDismiss = { showRoomSheet = false },
            onConfirm = {
                vm.confirmBinding()
                showRoomSheet = false
            },
        )
    }
}


// ── 未绑定房间提示 ──


@Composable
private fun UnboundRoomContent(modifier: Modifier, onBind: () -> Unit) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            Box(
                Modifier.size(80.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Default.Home, null, modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer)
            }
            Spacer(Modifier.height(24.dp))
            Text("未绑定房间", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text("请先绑定您的宿舍房间\n以便查询电费信息",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
            Spacer(Modifier.height(32.dp))
            Button(onClick = onBind) {
                Icon(Icons.Default.AddLocation, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("绑定房间")
            }
        }
    }
}

// ── 余额卡片 ──


@Composable
private fun BalanceCard(balance: ElectricityBalance) {
    ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
        Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("剩余电量", style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${"%.1f".format(balance.total)}",
                    style = MaterialTheme.typography.displayMedium,
                    fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(4.dp))
                Text("度", style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 6.dp))
            }
            Spacer(Modifier.height(20.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                BalanceChip("购电", balance.remainingPurchased, Color(0xFF1565C0), Modifier.weight(1f))
                BalanceChip("补助", balance.remainingSubsidy, Color(0xFF2E7D32), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun BalanceChip(label: String, value: Double, color: Color, modifier: Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${"%.1f".format(value)}", style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold, color = color)
                Spacer(Modifier.width(2.dp))
                Text("度", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 2.dp))
            }
        }
    }
}


// ── 用电记录 ──

@Composable
private fun UsageSection(records: List<ElectricityUsageRecord>, expanded: Boolean, onToggle: () -> Unit) {
    val displayRecords = if (expanded) records else records.take(6)
    val hasMore = records.size > 6

    ElevatedCard(Modifier.fillMaxWidth().animateContentSize(), shape = MaterialTheme.shapes.extraLarge) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(36.dp).background(Color(0xFFFFF3E0), CircleShape),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Default.Bolt, null, modifier = Modifier.size(18.dp), tint = Color(0xFFE65100)) }
                Spacer(Modifier.width(10.dp))
                Text("用电记录", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f))
                Text("共 ${records.size} 条", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            displayRecords.forEach { record ->
                UsageItem(record)
                Spacer(Modifier.height(8.dp))
            }
            if (hasMore) {
                TextButton(onClick = onToggle, modifier = Modifier.fillMaxWidth()) {
                    Text(if (expanded) "收起" else "展开全部 (${records.size}条)")
                    Spacer(Modifier.width(4.dp))
                    Icon(
                        if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        null, modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun UsageItem(record: ElectricityUsageRecord) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(record.recordTime, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                if (record.meterName.isNotEmpty()) {
                    Text(record.meterName, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Surface(color = Color(0xFFFFF3E0), shape = RoundedCornerShape(50)) {
                Text("-${"%.1f".format(record.usageAmount)} 度",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold, color = Color(0xFFE65100))
            }
        }
    }
}

// ── 充值记录 ──

@Composable
private fun PaymentSection(records: List<PaymentRecord>, expanded: Boolean, onToggle: () -> Unit) {
    val displayRecords = if (expanded) records else records.take(6)
    val hasMore = records.size > 6

    ElevatedCard(Modifier.fillMaxWidth().animateContentSize(), shape = MaterialTheme.shapes.extraLarge) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(36.dp).background(Color(0xFFE8F5E9), CircleShape),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Default.Paid, null, modifier = Modifier.size(18.dp), tint = Color(0xFF2E7D32)) }
                Spacer(Modifier.width(10.dp))
                Text("充值记录", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f))
                Text("共 ${records.size} 条", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(12.dp))
            displayRecords.forEach { record ->
                PaymentItem(record)
                Spacer(Modifier.height(8.dp))
            }
            if (hasMore) {
                TextButton(onClick = onToggle, modifier = Modifier.fillMaxWidth()) {
                    Text(if (expanded) "收起" else "展开全部 (${records.size}条)")
                    Spacer(Modifier.width(4.dp))
                    Icon(
                        if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        null, modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun PaymentItem(record: PaymentRecord) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(record.paymentTime, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                if (record.paymentType.isNotEmpty()) {
                    Text(record.paymentType, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Surface(color = Color(0xFFE8F5E9), shape = RoundedCornerShape(50)) {
                Text("+${"%.2f".format(record.amount)} 元",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold, color = Color(0xFF2E7D32))
            }
        }
    }
}


// ── 房间选择 Bottom Sheet ──

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RoomSelectionSheet(
    vm: ElectricityViewModel,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // 首次打开时加载楼栋
    LaunchedEffect(Unit) { vm.loadBuildings() }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp)) {
            // 标题
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.MeetingRoom, null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(12.dp))
                Text("选择房间", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(8.dp))
            Text("请依次选择楼栋、楼层和房间", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))

            // 楼栋
            SelectorDropdown(
                label = "楼栋",
                items = state.buildings,
                selected = state.selectedBuilding?.let { mapOf("code" to it.code, "name" to it.name) },
                enabled = state.buildings.isNotEmpty(),
                onSelect = { vm.selectBuilding(it["code"]!!, it["name"]!!) },
            )
            Spacer(Modifier.height(16.dp))

            // 楼层
            SelectorDropdown(
                label = "楼层",
                items = state.floors,
                selected = state.selectedFloor?.let { mapOf("code" to it.code, "name" to it.name) },
                enabled = state.selectedBuilding != null && state.floors.isNotEmpty(),
                onSelect = { vm.selectFloor(it["code"]!!, it["name"]!!) },
            )
            Spacer(Modifier.height(16.dp))

            // 房间
            SelectorDropdown(
                label = "房间",
                items = state.rooms,
                selected = state.selectedRoom?.let { mapOf("code" to it.code, "name" to it.name) },
                enabled = state.selectedFloor != null && state.rooms.isNotEmpty(),
                onSelect = { vm.selectRoom(it["code"]!!, it["name"]!!) },
            )

            // 加载指示器
            if (state.isLoading) {
                Spacer(Modifier.height(16.dp))
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    AppCircularProgressIndicator(modifier = Modifier.size(32.dp))
                }
            }

            Spacer(Modifier.height(24.dp))

            // 按钮
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("取消") }
                Spacer(Modifier.width(12.dp))
                Button(
                    onClick = onConfirm,
                    enabled = state.selectedRoom != null && !state.isLoading,
                ) { Text("确认绑定") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SelectorDropdown(
    label: String,
    items: List<Map<String, String>>,
    selected: Map<String, String>?,
    enabled: Boolean,
    onSelect: (Map<String, String>) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Column {
        Text(label, style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(6.dp))
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { if (enabled) expanded = it }) {
            OutlinedTextField(
                value = selected?.get("name") ?: "",
                onValueChange = {},
                readOnly = true,
                enabled = enabled,
                placeholder = { Text("请选择$label") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier.fillMaxWidth().menuAnchor(),
                shape = MaterialTheme.shapes.medium,
                singleLine = true,
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                items.forEach { item ->
                    DropdownMenuItem(
                        text = { Text(item["name"] ?: "") },
                        onClick = {
                            onSelect(item)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}
