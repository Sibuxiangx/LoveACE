package tech.loveace.appv3.ui.screen

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.LaborClubActivity
import tech.loveace.appv3.data.model.LaborClubInfo
import tech.loveace.appv3.data.model.LaborClubProgressInfo
import tech.loveace.appv3.data.model.SignItem
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.LaborClubUiState
import tech.loveace.appv3.ui.viewmodel.LaborClubViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LaborClubScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    onNavigateToScan: () -> Unit,
    vm: LaborClubViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }
    var showDetailSheet by remember { mutableStateOf<LaborClubActivity?>(null) }

    LaunchedEffect(authViewModel.laborClubService) {
        authViewModel.laborClubService?.let { vm.init(it); vm.loadAll() }
    }
    LaunchedEffect(state.signInResult) {
        state.signInResult?.let {
            snackbarHostState.showSnackbar(if (it.isSuccess) "✅ ${it.msg}" else "❌ ${it.msg}")
            vm.clearSignInResult()
        }
    }
    LaunchedEffect(state.applyResult) {
        state.applyResult?.let {
            snackbarHostState.showSnackbar(it)
            vm.clearApplyResult()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("劳动俱乐部") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") } },
                actions = {
                    IconButton(onClick = onNavigateToScan) { Icon(Icons.Default.QrCodeScanner, "扫码签到") }
                    IconButton(onClick = { vm.loadAll() }) { Icon(Icons.Default.Sync, "刷新") }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading && state.progress == null -> LoadingScreen()
            state.error != null && state.progress == null -> ErrorScreen(state.error!!) { vm.loadAll() }
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 96.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // 进度卡片
                state.progress?.let { item { ProgressCard(it) } }

                // 俱乐部信息
                if (state.clubs.isNotEmpty()) {
                    item { ClubsSection(state.clubs) }
                }

                // Tab 切换
                item {
                    TabRow(selectedTab, state)
                    { selectedTab = it }
                }

                // 内容
                when (selectedTab) {
                    0 -> myActivitiesContent(state, onActivityClick = { showDetailSheet = it })
                    1 -> addActivitiesContent(state, vm, onActivityClick = { showDetailSheet = it })
                }
            }
        }
    }

    // 活动详情 BottomSheet
    showDetailSheet?.let { activity ->
        ActivityDetailSheet(activity, state, vm) { showDetailSheet = null }
    }
}

// ── Tab Row ──
@Composable
private fun TabRow(selectedTab: Int, state: LaborClubUiState, onTabSelected: (Int) -> Unit) {
    val tabs = listOf("我的活动" to state.joinedActivities.size, "添加活动" to state.addActivitiesTotalCount)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        tabs.forEachIndexed { index, (label, count) ->
            SegmentedButton(
                selected = selectedTab == index,
                onClick = { onTabSelected(index) },
                shape = SegmentedButtonDefaults.itemShape(index, tabs.size),
            ) {
                Text("$label ($count)")
            }
        }
    }
}


// ── 进度卡片 ──

@Composable
private fun ProgressCard(progress: LaborClubProgressInfo) {
    val isCompleted = progress.isCompleted
    val variant = if (isCompleted) RibbonCardVariant.SUCCESS_CONTAINER else RibbonCardVariant.WARNING_CONTAINER
    val onCard = ribbonContentColor(variant)
    val extended = LocalExtendedColors.current
    RibbonCard(
        Modifier.fillMaxWidth(),
        variant = variant,
        radius = 32.dp,
        padding = PaddingValues(22.dp),
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("劳动修课进度", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                    color = onCard)
                Spacer(Modifier.weight(1f))
                RibbonChip(
                    if (isCompleted) "已达标" else "未达标",
                    tone = if (isCompleted) RibbonTone.SUCCESS else RibbonTone.WARNING,
                    filled = true,
                    icon = if (isCompleted) Icons.Default.CheckCircle else Icons.Default.Cancel,
                )
            }
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${progress.finishCount}", style = RibbonNumeric.Large, color = onCard)
                Text(" / 10", style = MaterialTheme.typography.titleLarge,
                    color = onCard.copy(alpha = 0.78f))
                Spacer(Modifier.width(8.dp))
                Text("次", style = MaterialTheme.typography.bodyMedium,
                    color = onCard.copy(alpha = 0.78f), modifier = Modifier.padding(bottom = 4.dp))
            }
            Spacer(Modifier.height(12.dp))
            AppLinearProgressIndicator(
                progress = { (progress.progress / 100.0).coerceIn(0.0, 1.0).toFloat() },
                modifier = Modifier.fillMaxWidth().height(8.dp),
                color = onCard,
                trackColor = onCard.copy(alpha = 0.2f),
            )
            Spacer(Modifier.height(8.dp))
            Text("${"%.0f".format(progress.progress)}%", style = RibbonNumeric.Caption, color = onCard.copy(alpha = 0.78f))
            if (!isCompleted) {
                Spacer(Modifier.height(8.dp))
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Info, null, modifier = Modifier.size(14.dp), tint = extended.warning)
                        Spacer(Modifier.width(6.dp))
                        Text("还需完成 ${10 - progress.finishCount} 次活动",
                            style = MaterialTheme.typography.labelSmall, color = extended.warning)
                    }
                }
            }
        }
    }
}

// ── 俱乐部信息 ──
@Composable
private fun ClubsSection(clubs: List<LaborClubInfo>) {
    var expanded by remember { mutableStateOf(false) }
    RibbonCard(Modifier.fillMaxWidth().animateContentSize(), variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp, padding = PaddingValues(0.dp)) {
        Column {
            ListItem(
                headlineContent = { Text("已加入俱乐部", fontWeight = FontWeight.Bold) },
                supportingContent = { Text("${clubs.size} 个俱乐部") },
                leadingContent = {
                    ShapeBadge(
                        shape = RibbonShape.COOKIE_8,
                        size = 40.dp,
                        color = MaterialTheme.colorScheme.tertiaryContainer,
                        icon = Icons.Default.Groups,
                        iconTint = MaterialTheme.colorScheme.onTertiaryContainer,
                    )
                },
                trailingContent = {
                    Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null,
                        tint = MaterialTheme.colorScheme.primary)
                },
                modifier = Modifier.clickable { expanded = !expanded },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
            if (expanded) {
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    clubs.forEach { club ->
                        Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                ShapeBadge(
                                    shape = RibbonShape.COOKIE_6,
                                    size = 36.dp,
                                    color = MaterialTheme.colorScheme.secondaryContainer,
                                    icon = Icons.Default.Groups,
                                    iconTint = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(club.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                    if (!club.typeName.isNullOrEmpty()) {
                                        Text(club.typeName, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                                Text("${club.memberNum} 人", style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── 我的活动 ──
private fun LazyListScope.myActivitiesContent(state: LaborClubUiState, onActivityClick: (LaborClubActivity) -> Unit) {
    val ongoing = state.ongoingActivities
    val finished = state.finishedActivities

    if (ongoing.isEmpty() && finished.isEmpty()) {
        item { EmptyScreen("暂无活动记录，去「添加活动」报名吧") }
        return
    }
    if (ongoing.isNotEmpty()) {
        item {
            ActivityGroup("待开始", "${ongoing.size} 个活动", Icons.Default.EventAvailable,
                ribbonToneColors(RibbonTone.TERTIARY).first, ongoing, showSignStatus = true, onActivityClick = onActivityClick)
        }
    }
    if (finished.isNotEmpty()) {
        item {
            ActivityGroup("已开始", "${finished.size} 个活动", Icons.Default.History,
                ribbonToneColors(RibbonTone.NEUTRAL).first, finished, showSignStatus = true, onActivityClick = onActivityClick)
        }
    }
}

// ── 添加活动 ──
private fun LazyListScope.addActivitiesContent(state: LaborClubUiState, vm: LaborClubViewModel, onActivityClick: (LaborClubActivity) -> Unit) {
    val available = state.availableActivities
    val full = state.fullActivities
    val notStarted = state.notStartedActivities
    val expired = state.expiredActivities

    if (available.isEmpty() && full.isEmpty() && notStarted.isEmpty() && expired.isEmpty()) {
        item { EmptyScreen("当前没有可报名的活动") }
        return
    }
    if (available.isNotEmpty()) {
        item {
            ActivityGroup("可报名", "${available.size} 个活动", Icons.Default.AddCircleOutline,
                ribbonToneColors(RibbonTone.PRIMARY).first, available, showApplyButton = true, state = state, vm = vm, onActivityClick = onActivityClick)
        }
    }
    if (full.isNotEmpty()) {
        item {
            ActivityGroup("已满员", "${full.size} 个活动", Icons.Default.Block,
                ribbonToneColors(RibbonTone.WARNING).first, full, onActivityClick = onActivityClick)
        }
    }
    if (notStarted.isNotEmpty()) {
        item {
            ActivityGroup("未开始报名", "${notStarted.size} 个活动", Icons.Default.Schedule,
                ribbonToneColors(RibbonTone.SECONDARY).first, notStarted, onActivityClick = onActivityClick)
        }
    }
    if (expired.isNotEmpty()) {
        item {
            ActivityGroup("已过期", "${expired.size} 个活动", Icons.Default.EventBusy,
                ribbonToneColors(RibbonTone.NEUTRAL).first, expired, onActivityClick = onActivityClick)
        }
    }
}

// ── 活动分组 ──
@Composable
private fun ActivityGroup(
    title: String, subtitle: String, icon: ImageVector, accentColor: Color,
    activities: List<LaborClubActivity>,
    showSignStatus: Boolean = false, showApplyButton: Boolean = false,
    state: LaborClubUiState? = null, vm: LaborClubViewModel? = null,
    onActivityClick: (LaborClubActivity) -> Unit,
) {
    var expanded by remember { mutableStateOf(true) }
    RibbonCard(Modifier.fillMaxWidth().animateContentSize(), variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp, padding = PaddingValues(0.dp)) {
        Column {
            ListItem(
                headlineContent = { Text(title, fontWeight = FontWeight.Bold) },
                supportingContent = { Text(subtitle) },
                leadingContent = {
                    ShapeBadge(
                        shape = RibbonShape.PEBBLE_3,
                        size = 40.dp,
                        color = accentColor.copy(alpha = 0.15f),
                        icon = icon,
                        iconTint = accentColor,
                    )
                },
                trailingContent = {
                    Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null,
                        tint = MaterialTheme.colorScheme.primary)
                },
                modifier = Modifier.clickable { expanded = !expanded },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
            if (expanded) {
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    activities.forEach { activity ->
                        ActivityCard(activity, showSignStatus, showApplyButton,
                            isJoined = state?.isActivityJoined(activity.id) == true,
                            onApply = { vm?.applyActivity(activity.id) },
                            onClick = { onActivityClick(activity) })
                    }
                }
            }
        }
    }
}

// ── 活动卡片 ──
@Composable
private fun ActivityCard(
    activity: LaborClubActivity,
    showSignStatus: Boolean, showApplyButton: Boolean,
    isJoined: Boolean = false,
    onApply: () -> Unit = {},
    onClick: () -> Unit,
) {
    var showConfirm by remember { mutableStateOf(false) }

    RibbonCard(
        Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 24.dp,
        padding = PaddingValues(14.dp),
        interactive = true,
        onClick = onClick,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // 标题 + 状态
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(activity.title, style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f),
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.width(8.dp))
                RibbonChip(activityStatusLabel(activity), tone = activityStatusTone(activity))
            }
            // 时间
            InfoRow(Icons.Default.Schedule, formatTimeRange(activity.startTime, activity.endTime))
            // 俱乐部
            InfoRow(Icons.Default.Groups, activity.clubName)
            // 人数
            InfoRow(Icons.Default.People, "${activity.memberNum}/${activity.peopleNum} 人")
            // 签到状态
            if (showSignStatus) {
                val signList = activity.signList
                val signTone = when {
                    activity.isAllSigned -> RibbonTone.SUCCESS
                    signList != null && signList.isNotEmpty() -> RibbonTone.WARNING
                    else -> RibbonTone.PRIMARY
                }
                val signIcon = when {
                    activity.isAllSigned -> Icons.Default.CheckCircle
                    signList != null && signList.isNotEmpty() -> Icons.Default.Pending
                    else -> Icons.Default.Info
                }
                RibbonChip(activity.signInStatus, tone = signTone, icon = signIcon)
            }
            // 报名按钮
            if (showApplyButton && !isJoined) {
                Spacer(Modifier.height(2.dp))
                Button(onClick = { showConfirm = true }, modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.large) {
                    Icon(Icons.Default.Add, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("报名")
                }
            }
            if (isJoined && showApplyButton) {
                val extended = LocalExtendedColors.current
                Surface(color = extended.successContainer, shape = MaterialTheme.shapes.large,
                    modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CheckCircle, null, modifier = Modifier.size(16.dp), tint = extended.onSuccessContainer)
                        Spacer(Modifier.width(4.dp))
                        Text("已加入", style = MaterialTheme.typography.labelMedium, color = extended.onSuccessContainer, fontWeight = FontWeight.SemiBold)
                    }
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

// ── 活动详情 BottomSheet ──
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityDetailSheet(
    activity: LaborClubActivity, state: LaborClubUiState, vm: LaborClubViewModel,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(activity.id) { vm.loadActivityDetail(activity.id) }
    DisposableEffect(Unit) { onDispose { vm.clearActivityDetail() } }

    val detail = state.activityDetail

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // 标题
            item {
                Text(activity.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Text(activity.clubName, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            // 信息卡片
            item {
                RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(16.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
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
            }
            // 签到记录 — prefer detail API signList, fallback to runtime attached
            val signList = detail?.signList?.takeIf { it.isNotEmpty() } ?: activity.signList
            if (signList != null && signList.isNotEmpty()) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("签到记录", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.weight(1f))
                        val allSigned = signList.all { it.isSign }
                        RibbonChip(
                            if (allSigned) "全部完成" else "${signList.count { it.isSign }}/${signList.size}",
                            tone = if (allSigned) RibbonTone.SUCCESS else RibbonTone.WARNING,
                            icon = if (allSigned) Icons.Default.CheckCircle else Icons.Default.Pending,
                        )
                    }
                }
                items(signList) { sign -> SignItemCard(sign) }
            }
            // 报名按钮
            if (!state.isActivityJoined(activity.id) && activity.memberNum < activity.peopleNum) {
                item {
                    var showConfirm by remember { mutableStateOf(false) }
                    Spacer(Modifier.height(4.dp))
                    Button(onClick = { showConfirm = true }, modifier = Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.extraLarge) {
                        Text("立即报名")
                    }
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
            }
            item { Spacer(Modifier.height(32.dp)) }
        }
    }
}

@Composable
private fun SignItemCard(sign: SignItem) {
    val extended = LocalExtendedColors.current
    val tone = if (sign.isSign) RibbonTone.SUCCESS else RibbonTone.WARNING
    val color = if (sign.isSign) extended.success else extended.warning
    RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 24.dp,
        padding = PaddingValues(horizontal = 12.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (sign.isSign) Icons.Default.CheckCircle else Icons.Default.Pending,
                null, modifier = Modifier.size(20.dp), tint = color,
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(sign.typeName.ifEmpty { "签到" }, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text("${sign.startTime} - ${sign.endTime}", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            RibbonChip(sign.statusText, tone = tone)
        }
    }
}

// ── 通用组件 ──
@Composable
private fun InfoRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(4.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2, overflow = TextOverflow.Ellipsis)
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

private fun activityStatusTone(activity: LaborClubActivity): RibbonTone {
    val now = java.time.LocalDateTime.now()
    return try {
        val start = java.time.LocalDateTime.parse(activity.startTime.replace(" ", "T"))
        val end = java.time.LocalDateTime.parse(activity.endTime.replace(" ", "T"))
        when {
            now.isBefore(start) -> RibbonTone.TERTIARY  // 待开始
            now.isAfter(end) -> RibbonTone.NEUTRAL      // 已结束
            else -> RibbonTone.SUCCESS                  // 进行中
        }
    } catch (_: Exception) { RibbonTone.NEUTRAL }
}

private fun activityStatusLabel(activity: LaborClubActivity): String {
    val now = java.time.LocalDateTime.now()
    return try {
        val start = java.time.LocalDateTime.parse(activity.startTime.replace(" ", "T"))
        val end = java.time.LocalDateTime.parse(activity.endTime.replace(" ", "T"))
        when {
            now.isBefore(start) -> "待开始"
            now.isAfter(end) -> "已结束"
            else -> "进行中"
        }
    } catch (_: Exception) { activity.stateName.ifEmpty { "未知" } }
}

private fun formatTimeRange(start: String, end: String): String {
    fun fmt(s: String): String = try {
        val dt = java.time.LocalDateTime.parse(s.replace(" ", "T"))
        java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm").format(dt)
    } catch (_: Exception) { s }
    return "${fmt(start)} ~ ${fmt(end)}"
}

// 需要 import for LazyListScope
private typealias LazyListScope = androidx.compose.foundation.lazy.LazyListScope
