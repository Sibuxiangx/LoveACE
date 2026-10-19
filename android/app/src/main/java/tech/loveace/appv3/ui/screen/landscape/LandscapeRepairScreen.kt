package tech.loveace.appv3.ui.screen.landscape

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.screen.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.RepairViewModel

/**
 * 横屏零星维修：左栏工单列表 | 右栏详情/报修表单
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeRepairScreen(
    authViewModel: AuthViewModel,
    vm: RepairViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var selectedTab by remember { mutableIntStateOf(0) }
    var selectedTaskId by remember { mutableStateOf<String?>(null) }
    var showSubmitForm by remember { mutableStateOf(false) }

    LaunchedEffect(authViewModel.repairService) {
        authViewModel.repairService?.let { vm.init(it); vm.loadOrders() }
    }

    LaunchedEffect(state.submitSuccess) {
        if (state.submitSuccess) {
            showSubmitForm = false
            vm.clearSubmitState()
            vm.clearImages()
            vm.loadOrders()
        }
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("零星维修") },
            actions = {
                IconButton(onClick = { showSubmitForm = !showSubmitForm; selectedTaskId = null }) {
                    Icon(if (showSubmitForm) Icons.Default.Close else Icons.Default.Add,
                        if (showSubmitForm) "关闭" else "报修")
                }
            },
        )
    }) { padding ->
        when {
            state.isLoading && state.pending.isEmpty() && state.completed.isEmpty() -> LoadingScreen()
            state.error != null && state.pending.isEmpty() && state.completed.isEmpty() ->
                ErrorScreen(state.error!!) { vm.loadOrders() }
            else -> Row(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // 左栏：工单列表
                Column(Modifier.weight(0.4f)) {
                    // 永久警告横幅
                    RepairWarningBanner()

                    TabRow(selectedTabIndex = selectedTab) {
                        Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 },
                            text = { Text("待完成 (${state.pending.size})") })
                        Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 },
                            text = { Text("已完成 (${state.completed.size})") })
                    }
                    val orders = if (selectedTab == 0) state.pending else state.completed
                    if (orders.isEmpty()) {
                        EmptyScreen("暂无工单")
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(orders, key = { it.taskId }) { order ->
                                RepairOrderCard(order) {
                                    selectedTaskId = order.taskId
                                    showSubmitForm = false
                                    vm.loadDetail(order.taskId)
                                }
                            }
                        }
                    }
                }

                // 右栏：详情或报修表单
                Column(Modifier.weight(0.6f)) {
                    when {
                        showSubmitForm -> LandscapeSubmitForm(vm, authViewModel)
                        selectedTaskId != null -> LandscapeDetailPanel(vm, selectedTaskId!!)
                        else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Default.Build, null, modifier = Modifier.size(48.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f))
                                Spacer(Modifier.height(12.dp))
                                Text("选择工单查看详情，或点击 + 发起报修",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                            }
                        }
                    }
                }
            }
        }
    }
}

// ==================== 横屏详情面板 ====================

@Composable
private fun LandscapeDetailPanel(vm: RepairViewModel, taskId: String) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    when {
        state.isDetailLoading -> LoadingScreen()
        state.detailError != null -> ErrorScreen(state.detailError!!) { vm.loadDetail(taskId) }
        state.detail != null -> {
            val detail = state.detail!!
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = PaddingValues(bottom = 16.dp),
            ) {
                item {
                    RibbonSectionTitle("报修信息")
                    RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            RepairDetailRow("故障区域", detail.faultArea)
                            RepairDetailRow("维修项目", detail.repairProject)
                            RepairDetailRow("联系电话", detail.phone)
                            RepairDetailRow("故障地址", detail.faultAddress)
                        }
                    }
                }
                if (detail.description.isNotEmpty()) {
                    item {
                        RibbonSectionTitle("故障详情")
                        RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
                            Text(detail.description, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                if (detail.progress.isNotEmpty()) {
                    item {
                        RibbonSectionTitle("维修进度")
                        RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
                            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                detail.progress.forEachIndexed { index, item ->
                                    Row {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(60.dp)) {
                                            Icon(
                                                if (index == 0) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked, null,
                                                tint = if (index == 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                                                modifier = Modifier.size(20.dp))
                                            Text(item.stage, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                        Column(Modifier.weight(1f)) {
                                            if (item.time.isNotEmpty()) Text(item.time, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            if (item.description.isNotEmpty()) Text(item.description, style = MaterialTheme.typography.bodyMedium)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (detail.settlements.isNotEmpty()) {
                    item {
                        RibbonSectionTitle("决算单")
                        RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
                            Column {
                                Row(Modifier.fillMaxWidth()) {
                                    Text("服务内容", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium)
                                    Text("材料", Modifier.width(80.dp), style = MaterialTheme.typography.labelMedium)
                                    Text("工分", Modifier.width(60.dp), style = MaterialTheme.typography.labelMedium)
                                }
                                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                                detail.settlements.forEach { item ->
                                    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                                        Text(item.serviceName, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                                        Text(item.material, Modifier.width(80.dp), style = MaterialTheme.typography.bodySmall)
                                        Text(item.workPoints, Modifier.width(60.dp), style = MaterialTheme.typography.bodySmall)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ==================== 横屏报修表单 ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LandscapeSubmitForm(vm: RepairViewModel, authViewModel: AuthViewModel) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    var selectedAreaGroupName by remember { mutableStateOf("") }
    var selectedArea by remember { mutableStateOf<RepairAreaItem?>(null) }
    var selectedProjectGroupName by remember { mutableStateOf("") }
    var selectedProject by remember { mutableStateOf<RepairProjectItem?>(null) }
    var phone by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var showAreaPicker by remember { mutableStateOf(false) }
    var showProjectPicker by remember { mutableStateOf(false) }
    var showConfirmDialog by remember { mutableStateOf(false) }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let {
            val base64 = compressAndEncodeImage(context, it)
            if (base64 != null) vm.uploadImage(base64)
        }
    }

    LaunchedEffect(authViewModel.repairService) {
        authViewModel.repairService?.let { vm.init(it); vm.loadFormData() }
    }

    when {
        state.isFormLoading -> LoadingScreen("加载报修信息...")
        state.formError != null -> ErrorScreen(state.formError!!) { vm.loadFormData() }
        state.formData != null -> {
            val formData = state.formData!!
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("快速报修", style = MaterialTheme.typography.titleMedium)

                // 横屏两列布局
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        RibbonSectionTitle("故障区域")
                        RibbonCard(interactive = true, onClick = { showAreaPicker = true }, radius = 28.dp, padding = PaddingValues(vertical = 6.dp)) {
                            ListItem(
                                headlineContent = {
                                    Text(if (selectedArea != null) "$selectedAreaGroupName/${selectedArea!!.name}" else "请选择",
                                        color = if (selectedArea != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                                },
                                trailingContent = { Icon(Icons.Rounded.ChevronRight, null) },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
                        RibbonSectionTitle("联系电话")
                        OutlinedTextField(value = phone, onValueChange = { phone = it.take(11) },
                            modifier = Modifier.fillMaxWidth(), placeholder = { Text("联系电话") },
                            singleLine = true, shape = MaterialTheme.shapes.large)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        RibbonSectionTitle("维修项目")
                        RibbonCard(interactive = true, onClick = { showProjectPicker = true }, radius = 28.dp, padding = PaddingValues(vertical = 6.dp)) {
                            ListItem(
                                headlineContent = {
                                    Text(if (selectedProject != null) "$selectedProjectGroupName/${selectedProject!!.name}" else "请选择",
                                        color = if (selectedProject != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                                },
                                trailingContent = { Icon(Icons.Rounded.ChevronRight, null) },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
                        RibbonSectionTitle("故障地址")
                        OutlinedTextField(value = address, onValueChange = { address = it },
                            modifier = Modifier.fillMaxWidth(), placeholder = { Text("详细地址") },
                            singleLine = true, shape = MaterialTheme.shapes.large)
                    }
                }

                RibbonSectionTitle("故障详情")
                OutlinedTextField(value = description, onValueChange = { description = it.take(200) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp),
                    placeholder = { Text("请详细描述故障信息") },
                    supportingText = { Text("${description.length}/200") },
                    shape = MaterialTheme.shapes.large)

                RibbonSectionTitle("故障图片")
                RepairImagePicker(
                    imageUrls = state.uploadedImageUrls,
                    isUploading = state.isUploading,
                    onAddImage = { imagePicker.launch("image/*") },
                    onRemoveImage = { vm.removeImage(it) },
                )
                if (state.uploadError != null) {
                    Text(state.uploadError!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }

                AnimatedVisibility(state.submitError != null) {
                    Text(state.submitError ?: "", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }

                Button(
                    onClick = { showConfirmDialog = true },
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                    enabled = !state.isSubmitting && !state.isUploading && selectedArea != null && selectedProject != null
                            && phone.isNotEmpty() && address.isNotEmpty() && description.isNotEmpty(),
                    shape = MaterialTheme.shapes.large,
                ) {
                    if (state.isSubmitting) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)) }
                    Text("提交报修")
                }
                Spacer(Modifier.height(16.dp))

                // 提交确认弹窗
                if (showConfirmDialog) {
                    AlertDialog(
                        onDismissRequest = { showConfirmDialog = false },
                        icon = { Icon(Icons.Default.Warning, contentDescription = null) },
                        title = { Text("确认提交") },
                        text = { Text("请勿随意提交报修，请仔细检查您填写的信息是否正确。确认提交？") },
                        confirmButton = {
                            Button(onClick = {
                                showConfirmDialog = false
                                val picUrls = state.uploadedImageUrls.joinToString(",").let { if (it.isNotEmpty()) ",$it" else "" }
                                vm.submitRepair(RepairSubmitRequest(
                                    areaId = selectedArea!!.id,
                                    areaName = "$selectedAreaGroupName/${selectedArea!!.name}",
                                    projectId = selectedProject!!.id,
                                    projectName = "$selectedProjectGroupName/${selectedProject!!.name}",
                                    phone = phone, address = address, description = description,
                                    picUrls = picUrls,
                                ))
                            }) { Text("确认提交") }
                        },
                        dismissButton = {
                            OutlinedButton(onClick = { showConfirmDialog = false }) { Text("取消") }
                        },
                    )
                }
            }

            if (showAreaPicker) {
                PickerDialog(title = "选择故障区域",
                    groups = formData.areas.map { it.groupName },
                    items = { gi -> formData.areas[gi].items.map { it.name } },
                    onSelect = { gi, ii -> selectedAreaGroupName = formData.areas[gi].groupName; selectedArea = formData.areas[gi].items[ii]; showAreaPicker = false },
                    onDismiss = { showAreaPicker = false })
            }
            if (showProjectPicker) {
                PickerDialog(title = "选择维修项目",
                    groups = formData.projects.map { it.groupName },
                    items = { gi -> formData.projects[gi].items.map { it.name } },
                    onSelect = { gi, ii -> selectedProjectGroupName = formData.projects[gi].groupName; selectedProject = formData.projects[gi].items[ii]; showProjectPicker = false },
                    onDismiss = { showProjectPicker = false })
            }
        }
    }
}
