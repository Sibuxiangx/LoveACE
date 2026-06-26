package tech.loveace.appv3.ui.screen.landscape

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import tech.loveace.appv3.data.model.LaborClubActivity
import tech.loveace.appv3.data.model.SignItem
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.LaborClubUiState
import tech.loveace.appv3.ui.viewmodel.LaborClubViewModel
import tech.loveace.appv3.ui.viewmodel.ProfileViewModel

/**
 * 横屏劳动俱乐部：左栏进度+俱乐部+相框 | 右栏活动列表（可点击弹出详情）
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeLaborClubScreen(
    authViewModel: AuthViewModel,
    profileViewModel: ProfileViewModel = viewModel(),
    vm: LaborClubViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val profileState by profileViewModel.state.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }
    var showDetailActivity by remember { mutableStateOf<LaborClubActivity?>(null) }

    val context = LocalContext.current
    var pendingCropUri by remember { mutableStateOf<Uri?>(null) }
    var imageAreaSize by remember { mutableStateOf(IntSize.Zero) }
    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri != null) {
            try { context.contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
            pendingCropUri = uri
        }
    }

    // 图片裁切对话框
    if (pendingCropUri != null) {
        val ratio = if (imageAreaSize.width > 0 && imageAreaSize.height > 0)
            imageAreaSize.width.toFloat() / imageAreaSize.height.toFloat()
        else 1f
        tech.loveace.appv3.ui.components.ImageCropDialog(
            imageUri = pendingCropUri!!,
            cropShape = tech.loveace.appv3.ui.components.CropShape.Custom(ratio),
            onCropped = { croppedUri ->
                profileViewModel.setLaborImageUri(croppedUri.toString())
                pendingCropUri = null
            },
            onDismiss = { pendingCropUri = null },
        )
    }

    LaunchedEffect(authViewModel.laborClubService) {
        authViewModel.laborClubService?.let { vm.init(it); vm.loadAll() }
    }
    LaunchedEffect(state.signInResult) {
        state.signInResult?.let { snackbarHostState.showSnackbar(if (it.isSuccess) "✅ ${it.msg}" else "❌ ${it.msg}"); vm.clearSignInResult() }
    }
    LaunchedEffect(state.applyResult) {
        state.applyResult?.let { snackbarHostState.showSnackbar(it); vm.clearApplyResult() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("劳动俱乐部") },
                actions = { IconButton(onClick = { vm.loadAll() }) { Icon(Icons.Default.Sync, "刷新") } },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading && state.progress == null -> LoadingScreen()
            state.error != null && state.progress == null -> ErrorScreen(state.error!!) { vm.loadAll() }
            else -> Row(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // 左栏：进度 + 俱乐部 + 相框
                Column(
                    Modifier.weight(0.4f),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    // 进度 + 俱乐部（可滚动）
                    Column(
                        Modifier.verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        // 进度卡片
                        state.progress?.let { progress ->
                            val isCompleted = progress.isCompleted
                            ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
                                Column(Modifier.padding(24.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("劳动修课进度", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                        Spacer(Modifier.weight(1f))
                                        Surface(color = (if (isCompleted) Color(0xFF2E7D32) else Color(0xFFE65100)).copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                                            Row(Modifier.padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                                Icon(if (isCompleted) Icons.Default.CheckCircle else Icons.Default.Cancel, null, modifier = Modifier.size(14.dp), tint = if (isCompleted) Color(0xFF2E7D32) else Color(0xFFE65100))
                                                Spacer(Modifier.width(4.dp))
                                                Text(if (isCompleted) "已达标" else "未达标", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = if (isCompleted) Color(0xFF2E7D32) else Color(0xFFE65100))
                                            }
                                        }
                                    }
                                    Spacer(Modifier.height(16.dp))
                                    Row(verticalAlignment = Alignment.Bottom) {
                                        Text("${progress.finishCount}", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                                        Text(" / 10 次", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Spacer(Modifier.height(12.dp))
                                    AppLinearProgressIndicator(progress = { (progress.progress / 100.0).coerceIn(0.0, 1.0).toFloat() }, modifier = Modifier.fillMaxWidth().height(8.dp))
                                    Spacer(Modifier.height(4.dp))
                                    Text("${"%.0f".format(progress.progress)}%", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }

                        // 俱乐部列表
                        if (state.clubs.isNotEmpty()) {
                            Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("已加入俱乐部 (${state.clubs.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                    state.clubs.forEach { club ->
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Icon(Icons.Default.Groups, null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                            Spacer(Modifier.width(8.dp))
                                            Text(club.name, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                                            Text("${club.memberNum} 人", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 相框 — 填充剩余空间
                    Box(modifier = Modifier.fillMaxWidth().weight(1f)
                        .onSizeChanged { imageAreaSize = it }) {
                        if (profileState.laborImageUri != null) {
                            ElevatedCard(modifier = Modifier.fillMaxSize(), shape = MaterialTheme.shapes.extraLarge) {
                                Box(Modifier.fillMaxSize()) {
                                    AsyncImage(
                                        model = profileState.laborImageUri, contentDescription = "自选图片",
                                        modifier = Modifier.fillMaxSize().clip(MaterialTheme.shapes.extraLarge),
                                        contentScale = ContentScale.Crop,
                                    )
                                    Row(
                                        modifier = Modifier.align(Alignment.TopEnd).padding(8.dp),
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        FilledIconButton(
                                            onClick = { profileViewModel.setLaborImageUri(null) },
                                            modifier = Modifier.size(28.dp),
                                            colors = IconButtonDefaults.filledIconButtonColors(
                                                containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.85f),
                                                contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                            ),
                                        ) { Icon(Icons.Default.Close, "清除", modifier = Modifier.size(14.dp)) }
                                        FilledIconButton(
                                            onClick = { imagePicker.launch("image/*") },
                                            modifier = Modifier.size(28.dp),
                                            colors = IconButtonDefaults.filledIconButtonColors(
                                                containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.8f),
                                                contentColor = MaterialTheme.colorScheme.onSurface,
                                            ),
                                        ) { Icon(Icons.Default.Edit, "更换", modifier = Modifier.size(14.dp)) }
                                    }
                                }
                            }
                        } else {
                            OutlinedCard(
                                modifier = Modifier.fillMaxSize().clickable { imagePicker.launch("image/*") },
                                shape = MaterialTheme.shapes.extraLarge,
                                colors = CardDefaults.outlinedCardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.5f)),
                            ) {
                                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        Icon(Icons.Default.Image, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f))
                                        Spacer(Modifier.height(8.dp))
                                        Text("我的画框", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                                        Spacer(Modifier.height(2.dp))
                                        Text("点击选择图片", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f))
                                    }
                                }
                            }
                        }
                    }
                }

                // 右栏：活动列表
                Column(Modifier.weight(0.6f)) {
                    val tabs = listOf("我的活动" to state.joinedActivities.size, "添加活动" to state.addActivitiesTotalCount)
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
                        tabs.forEachIndexed { index, (label, count) ->
                            SegmentedButton(selected = selectedTab == index, onClick = { selectedTab = index }, shape = SegmentedButtonDefaults.itemShape(index, tabs.size)) { Text("$label ($count)") }
                        }
                    }

                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 16.dp),
                    ) {
                        when (selectedTab) {
                            0 -> {
                                val ongoing = state.ongoingActivities
                                val finished = state.finishedActivities
                                if (ongoing.isEmpty() && finished.isEmpty()) {
                                    item { EmptyScreen("暂无活动记录") }
                                } else {
                                    if (ongoing.isNotEmpty()) {
                                        item { Text("待开始 (${ongoing.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold) }
                                        items(ongoing, key = { it.id }) { a -> LandscapeActivityCard(a, showSignStatus = true, onClick = { showDetailActivity = a }) }
                                    }
                                    if (finished.isNotEmpty()) {
                                        item { Spacer(Modifier.height(8.dp)); Text("已开始 (${finished.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold) }
                                        items(finished, key = { it.id }) { a -> LandscapeActivityCard(a, showSignStatus = true, onClick = { showDetailActivity = a }) }
                                    }
                                }
                            }
                            1 -> {
                                val available = state.availableActivities
                                if (available.isEmpty() && state.fullActivities.isEmpty() && state.notStartedActivities.isEmpty() && state.expiredActivities.isEmpty()) {
                                    item { EmptyScreen("当前没有可报名的活动") }
                                } else {
                                    if (available.isNotEmpty()) {
                                        item { Text("可报名 (${available.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold) }
                                        items(available, key = { it.id }) { a -> LandscapeActivityCard(a, showApplyButton = true, isJoined = state.isActivityJoined(a.id), onApply = { vm.applyActivity(a.id) }, onClick = { showDetailActivity = a }) }
                                    }
                                    val full = state.fullActivities
                                    if (full.isNotEmpty()) {
                                        item { Spacer(Modifier.height(8.dp)); Text("已满员 (${full.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold) }
                                        items(full, key = { it.id }) { a -> LandscapeActivityCard(a, onClick = { showDetailActivity = a }) }
                                    }
                                    val notStarted = state.notStartedActivities
                                    if (notStarted.isNotEmpty()) {
                                        item { Spacer(Modifier.height(8.dp)); Text("未开始报名 (${notStarted.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold) }
                                        items(notStarted, key = { it.id }) { a -> LandscapeActivityCard(a, onClick = { showDetailActivity = a }) }
                                    }
                                    val expired = state.expiredActivities
                                    if (expired.isNotEmpty()) {
                                        item { Spacer(Modifier.height(8.dp)); Text("已过期 (${expired.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold) }
                                        items(expired, key = { it.id }) { a -> LandscapeActivityCard(a, onClick = { showDetailActivity = a }) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 活动详情对话框
    showDetailActivity?.let { activity ->
        LandscapeActivityDetailDialog(activity, state, vm) { showDetailActivity = null }
    }
}

@Composable
private fun LandscapeActivityCard(
    activity: LaborClubActivity,
    showSignStatus: Boolean = false,
    showApplyButton: Boolean = false,
    isJoined: Boolean = false,
    onApply: () -> Unit = {},
    onClick: () -> Unit = {},
) {
    var showConfirm by remember { mutableStateOf(false) }
    val (statusColor, statusLabel) = remember(activity.startTime, activity.endTime, activity.stateName) {
        val now = java.time.LocalDateTime.now()
        try {
            val start = java.time.LocalDateTime.parse(activity.startTime.replace(" ", "T"))
            val end = java.time.LocalDateTime.parse(activity.endTime.replace(" ", "T"))
            when {
                now.isBefore(start) -> Color(0xFF00897B) to "待开始"
                now.isAfter(end) -> Color(0xFF757575) to "已结束"
                else -> Color(0xFF2E7D32) to "进行中"
            }
        } catch (_: Exception) { Color(0xFF757575) to activity.stateName.ifEmpty { "未知" } }
    }

    OutlinedCard(Modifier.fillMaxWidth().clickable(onClick = onClick), shape = MaterialTheme.shapes.large) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(activity.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.width(8.dp))
                    Surface(color = statusColor.copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                        Text(statusLabel, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = statusColor)
                    }
                }
                val info = "${activity.clubName} · ${activity.memberNum}/${activity.peopleNum} 人"
                Text(info, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (showSignStatus) {
                    val signColor = when { activity.isAllSigned -> Color(0xFF2E7D32); activity.signList?.isNotEmpty() == true -> Color(0xFFE65100); else -> MaterialTheme.colorScheme.primary }
                    Text(activity.signInStatus, style = MaterialTheme.typography.labelSmall, color = signColor)
                }
            }
            if (showApplyButton && !isJoined) {
                Spacer(Modifier.width(12.dp))
                FilledTonalButton(onClick = { showConfirm = true }, shape = RoundedCornerShape(50)) { Text("报名") }
            }
            if (isJoined && showApplyButton) {
                Spacer(Modifier.width(12.dp))
                Surface(color = Color(0xFF2E7D32).copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                    Text("已加入", modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp), style = MaterialTheme.typography.labelSmall, color = Color(0xFF2E7D32), fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("确认报名") },
            text = { Text("确认报名活动「${activity.title}」？") },
            confirmButton = { TextButton(onClick = { showConfirm = false; onApply() }) { Text("确认") } },
            dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("取消") } },
        )
    }
}

@Composable
private fun LandscapeActivityDetailDialog(
    activity: LaborClubActivity,
    state: LaborClubUiState,
    vm: LaborClubViewModel,
    onDismiss: () -> Unit,
) {
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(activity.id) { vm.loadActivityDetail(activity.id) }
    DisposableEffect(Unit) { onDispose { vm.clearActivityDetail() } }

    val detail = state.activityDetail

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Column {
                Text(activity.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(activity.clubName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Card(
                    Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        DetailRow(Icons.Default.Schedule, "活动时间", formatTimeRange(activity.startTime, activity.endTime))
                        DetailRow(Icons.Default.People, "报名人数", "${activity.memberNum}/${activity.peopleNum}")
                        if (detail != null) {
                            if (detail.teacherNames.isNotEmpty())
                                DetailRow(Icons.Default.Person, "教师", detail.teacherNames)
                            if (detail.location.isNotEmpty())
                                DetailRow(Icons.Default.LocationOn, "上课地点", detail.location)
                        } else if (activity.chargeUserName.isNotEmpty()) {
                            DetailRow(Icons.Default.Person, "负责人", activity.chargeUserName)
                        }
                        if (state.detailLoading) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                                Text("加载详情...", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        if (activity.signUpStartTime.isNotEmpty())
                            DetailRow(Icons.Default.DateRange, "报名时间", formatTimeRange(activity.signUpStartTime, activity.signUpEndTime))
                    }
                }

                val signList = detail?.signList?.takeIf { it.isNotEmpty() } ?: activity.signList
                if (signList != null && signList.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("签到记录", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.weight(1f))
                        val allSigned = signList.all { it.isSign }
                        Surface(color = (if (allSigned) Color(0xFF2E7D32) else Color(0xFFE65100)).copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                            Row(Modifier.padding(horizontal = 8.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(if (allSigned) Icons.Default.CheckCircle else Icons.Default.Pending, null, modifier = Modifier.size(12.dp), tint = if (allSigned) Color(0xFF2E7D32) else Color(0xFFE65100))
                                Spacer(Modifier.width(4.dp))
                                Text(if (allSigned) "全部完成" else "${signList.count { it.isSign }}/${signList.size}", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = if (allSigned) Color(0xFF2E7D32) else Color(0xFFE65100))
                            }
                        }
                    }
                    signList.forEach { sign ->
                        val color = if (sign.isSign) Color(0xFF2E7D32) else Color(0xFFE65100)
                        OutlinedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(if (sign.isSign) Icons.Default.CheckCircle else Icons.Default.Pending, null, modifier = Modifier.size(18.dp), tint = color)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(sign.typeName.ifEmpty { "签到" }, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                    Text("${sign.startTime} - ${sign.endTime}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Surface(color = color.copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                                    Text(sign.statusText, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = color)
                                }
                            }
                        }
                    }
                }

                if (!state.isActivityJoined(activity.id) && activity.memberNum < activity.peopleNum) {
                    Button(onClick = { showConfirm = true }, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large) {
                        Text("立即报名")
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
    )

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("确认报名") },
            text = { Text("确认报名活动「${activity.title}」？") },
            confirmButton = { TextButton(onClick = { showConfirm = false; vm.applyActivity(activity.id); onDismiss() }) { Text("确认") } },
            dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("取消") } },
        )
    }
}

@Composable
private fun DetailRow(icon: ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

private fun formatTimeRange(start: String, end: String): String {
    fun fmt(s: String): String = try {
        val dt = java.time.LocalDateTime.parse(s.replace(" ", "T"))
        java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm").format(dt)
    } catch (_: Exception) { s }
    return "${fmt(start)} ~ ${fmt(end)}"
}
