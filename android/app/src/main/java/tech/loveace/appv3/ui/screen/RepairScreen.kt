package tech.loveace.appv3.ui.screen

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.service.RepairService
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.RepairViewModel
import java.io.ByteArrayOutputStream

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RepairScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: RepairViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var selectedTab by remember { mutableIntStateOf(0) }
    var showDetail by remember { mutableStateOf<String?>(null) }
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

    when {
        showSubmitForm -> RepairSubmitView(
            vm = vm, authViewModel = authViewModel,
            onBack = { showSubmitForm = false },
        )
        else -> Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("零星维修") },
                    navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                    actions = { IconButton(onClick = { showSubmitForm = true }) { Icon(Icons.Default.Add, "报修") } },
                )
            },
        ) { padding ->
            when {
                state.isLoading -> LoadingScreen()
                state.error != null -> ErrorScreen(state.error!!) { vm.loadOrders() }
                else -> Column(Modifier.fillMaxSize().padding(padding)) {
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
                        EmptyScreen("暂无${if (selectedTab == 0) "待完成" else "已完成"}的工单")
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(orders, key = { it.taskId }) { order ->
                                RepairOrderCard(order) { showDetail = order.taskId }
                            }
                        }
                    }
                }
            }

            // 工单详情 BottomSheet
            if (showDetail != null) {
                RepairDetailSheet(
                    vm = vm,
                    taskId = showDetail!!,
                    onDismiss = { showDetail = null; vm.clearDetail() },
                )
            }
        }
    }
}

// ==================== 永久警告横幅 ====================

@Composable
internal fun RepairWarningBanner() {
    RibbonCard(
        variant = RibbonCardVariant.ERROR_CONTAINER,
        radius = 28.dp,
        padding = PaddingValues(16.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.Warning, contentDescription = null, modifier = Modifier.size(20.dp),
                tint = ribbonContentColor(RibbonCardVariant.ERROR_CONTAINER))
            Spacer(Modifier.width(12.dp))
            Text(
                "⚠️ 部分接口未经完整测试，功能不一定可用。如果提交报修后没有反应，请前往学校零星维修平台提交报修。",
                style = MaterialTheme.typography.bodySmall,
                color = ribbonContentColor(RibbonCardVariant.ERROR_CONTAINER),
            )
        }
    }
}

@Composable
internal fun RepairOrderCard(order: RepairOrder, onClick: () -> Unit) {
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(20.dp),
        interactive = true,
        onClick = onClick,
    ) {
        Column {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(order.title, style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.width(8.dp))
                RibbonChip(
                    order.statusText,
                    tone = if (order.isPending) RibbonTone.TERTIARY else RibbonTone.SECONDARY,
                )
            }
            Spacer(Modifier.height(8.dp))
            if (order.location.isNotEmpty()) {
                Text("📍 ${order.location}", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
            }
            if (order.createTime.isNotEmpty()) {
                Text("🕐 ${order.createTime}", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (order.orderNumber.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text("📋 ${order.orderNumber}", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

// ==================== 工单详情 BottomSheet ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RepairDetailSheet(vm: RepairViewModel, taskId: String, onDismiss: () -> Unit) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(taskId) { vm.loadDetail(taskId) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(bottom = 32.dp),
        ) {
            Text("维修详情", style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))

            when {
                state.isDetailLoading -> Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.detailError != null -> Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.detailError!!, style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.height(12.dp))
                        FilledTonalButton(onClick = { vm.loadDetail(taskId) }) { Text("重试") }
                    }
                }
                state.detail != null -> {
                    val detail = state.detail!!
                    Column(
                        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        RibbonSectionTitle("报修信息")
                        RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                RepairDetailRow("故障区域", detail.faultArea)
                                RepairDetailRow("维修项目", detail.repairProject)
                                RepairDetailRow("联系电话", detail.phone)
                                RepairDetailRow("故障地址", detail.faultAddress)
                            }
                        }
                        if (detail.description.isNotEmpty()) {
                            RibbonSectionTitle("故障详情")
                            Card(shape = MaterialTheme.shapes.extraLarge,
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                                Text(detail.description, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                        if (detail.progress.isNotEmpty()) {
                            RibbonSectionTitle("维修进度")
                            Card(shape = MaterialTheme.shapes.extraLarge,
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
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
                        if (detail.settlements.isNotEmpty()) {
                            RibbonSectionTitle("决算单")
                            Card(shape = MaterialTheme.shapes.extraLarge,
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
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
                        Spacer(Modifier.height(16.dp))
                    }
                }
            }
        }
    }
}

@Composable
internal fun RepairDetailRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(80.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
    }
}

// ==================== 图片压缩工具 ====================

internal fun compressAndEncodeImage(context: android.content.Context, uri: Uri, maxWidth: Int = 640): String? {
    return try {
        val inputStream = context.contentResolver.openInputStream(uri) ?: return null
        val original = BitmapFactory.decodeStream(inputStream)
        inputStream.close()
        val ratio = if (original.width > maxWidth) maxWidth.toFloat() / original.width else 1f
        val scaled = if (ratio < 1f) {
            Bitmap.createScaledBitmap(original, (original.width * ratio).toInt(), (original.height * ratio).toInt(), true)
        } else original
        val baos = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 85, baos)
        val bytes = baos.toByteArray()
        Base64.encodeToString(bytes, Base64.NO_WRAP)
    } catch (e: Exception) { null }
}

// ==================== 报修提交 ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RepairSubmitView(
    vm: RepairViewModel,
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
) {
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

    Scaffold(topBar = {
        TopAppBar(title = { Text("快速报修") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } })
    }) { padding ->
        when {
            state.isFormLoading -> LoadingScreen("加载报修信息...")
            state.formError != null -> ErrorScreen(state.formError!!) { vm.loadFormData() }
            state.formData != null -> {
                val formData = state.formData!!
                Column(
                    Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    // 故障区域
                    RibbonSectionTitle("故障区域")
                    OutlinedCard(onClick = { showAreaPicker = true }, shape = MaterialTheme.shapes.large) {
                        ListItem(
                            headlineContent = {
                                Text(if (selectedArea != null) "$selectedAreaGroupName/${selectedArea!!.name}" else "请选择故障区域和楼宇",
                                    color = if (selectedArea != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                            },
                            trailingContent = { Icon(Icons.Rounded.ChevronRight, null) })
                    }

                    // 维修项目
                    RibbonSectionTitle("维修项目")
                    OutlinedCard(onClick = { showProjectPicker = true }, shape = MaterialTheme.shapes.large) {
                        ListItem(
                            headlineContent = {
                                Text(if (selectedProject != null) "$selectedProjectGroupName/${selectedProject!!.name}" else "请选择维修项目",
                                    color = if (selectedProject != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                            },
                            trailingContent = { Icon(Icons.Rounded.ChevronRight, null) })
                    }

                    // 联系电话
                    RibbonSectionTitle("联系电话")
                    OutlinedTextField(value = phone, onValueChange = { phone = it.take(11) },
                        modifier = Modifier.fillMaxWidth(), placeholder = { Text("请填写您的联系电话") },
                        singleLine = true, shape = MaterialTheme.shapes.large)

                    // 故障地址
                    RibbonSectionTitle("故障地址")
                    OutlinedTextField(value = address, onValueChange = { address = it },
                        modifier = Modifier.fillMaxWidth(), placeholder = { Text("请填写故障的详细地址") },
                        singleLine = true, shape = MaterialTheme.shapes.large)

                    // 故障详情
                    RibbonSectionTitle("故障详情")
                    OutlinedTextField(value = description, onValueChange = { description = it.take(200) },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 100.dp),
                        placeholder = { Text("请详细描述故障信息") },
                        supportingText = { Text("${description.length}/200") },
                        shape = MaterialTheme.shapes.large)

                    // 故障图片
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

                    // 提交错误
                    AnimatedVisibility(state.submitError != null) {
                        Text(state.submitError ?: "", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    // 提交按钮
                    Button(
                        onClick = { showConfirmDialog = true },
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        enabled = !state.isSubmitting && !state.isUploading && selectedArea != null && selectedProject != null
                                && phone.isNotEmpty() && address.isNotEmpty() && description.isNotEmpty(),
                        shape = MaterialTheme.shapes.large,
                    ) {
                        if (state.isSubmitting) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)) }
                        Text("提交报修")
                    }
                    Spacer(Modifier.height(32.dp))

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
}

// ==================== 图片选择器组件 ====================

@Composable
internal fun RepairImagePicker(
    imageUrls: List<String>,
    isUploading: Boolean,
    onAddImage: () -> Unit,
    onRemoveImage: (String) -> Unit,
) {
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(vertical = 4.dp),
    ) {
        items(imageUrls) { url ->
            Box(Modifier.size(80.dp).clip(MaterialTheme.shapes.medium)) {
                AsyncImage(
                    model = "${RepairService.BASE_URL}$url",
                    contentDescription = "故障图片",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
                Box(
                    modifier = Modifier.align(Alignment.TopEnd).padding(4.dp).size(18.dp)
                        .background(MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.85f), CircleShape)
                        .clip(CircleShape).clickable { onRemoveImage(url) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.Close, "删除", modifier = Modifier.size(10.dp),
                        tint = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        }
        item {
            OutlinedCard(
                onClick = onAddImage,
                modifier = Modifier.size(80.dp),
                shape = MaterialTheme.shapes.medium,
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (isUploading) {
                        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    } else {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Default.AddAPhoto, "添加图片", modifier = Modifier.size(24.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text("添加", style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

// ==================== 分组选择弹窗 ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PickerDialog(
    title: String,
    groups: List<String>,
    items: (Int) -> List<String>,
    onSelect: (groupIndex: Int, itemIndex: Int) -> Unit,
    onDismiss: () -> Unit,
) {
    if (groups.isEmpty()) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(title) },
            text = { Text("暂无可选数据，请稍后重试") },
            confirmButton = { TextButton(onClick = onDismiss) { Text("确定") } },
        )
        return
    }
    var selectedGroupIndex by remember { mutableIntStateOf(0) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(bottom = 32.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))
            ScrollableTabRow(selectedTabIndex = selectedGroupIndex, edgePadding = 16.dp) {
                groups.forEachIndexed { index, name ->
                    Tab(selected = selectedGroupIndex == index, onClick = { selectedGroupIndex = index }, text = { Text(name) })
                }
            }
            val currentItems = items(selectedGroupIndex.coerceIn(0, (groups.size - 1).coerceAtLeast(0)))
            if (currentItems.isEmpty()) {
                Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("该分类下暂无选项", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(modifier = Modifier.heightIn(max = 400.dp), contentPadding = PaddingValues(horizontal = 8.dp)) {
                    items(currentItems.size) { index ->
                        ListItem(headlineContent = { Text(currentItems[index]) },
                            modifier = Modifier.clickable { onSelect(selectedGroupIndex, index) })
                    }
                }
            }
        }
    }
}
