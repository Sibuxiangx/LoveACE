package tech.loveace.appv3.ui.screen.landscape

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle as JavaTextStyle
import java.util.Locale
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import tech.loveace.appv3.data.model.AcademicInfo
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.screen.HomeExamSummary
import tech.loveace.appv3.ui.viewmodel.*
import tech.loveace.appv3.util.buildHomeExamOverview
import java.time.LocalDateTime

/**
 * 横屏首页：双栏布局
 * 左栏：学业数据 + 一卡通/爱安财
 * 右栏：用户自选图片展示器（整栏）
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeHomeScreen(
    authViewModel: AuthViewModel,
    profileViewModel: ProfileViewModel = viewModel(),
    academicVm: AcademicViewModel = viewModel(),
    aacVm: AACViewModel = viewModel(),
    yktVm: YKTViewModel = viewModel(),
    semesterVm: SemesterViewModel = viewModel(),
    examVm: ExamViewModel = viewModel(),
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val academicState by academicVm.uiState.collectAsStateWithLifecycle()
    val aacState by aacVm.uiState.collectAsStateWithLifecycle()
    val yktState by yktVm.uiState.collectAsStateWithLifecycle()
    val profileState by profileViewModel.state.collectAsStateWithLifecycle()
    val semesterState by semesterVm.uiState.collectAsStateWithLifecycle()
    val examState by examVm.uiState.collectAsStateWithLifecycle()

    val displayName = profileState.nickname.ifEmpty { authState.userId }
    val now by produceState(initialValue = LocalDateTime.now()) {
        while (true) {
            delay(60_000)
            value = LocalDateTime.now()
        }
    }
    val examOverview = remember(examState.exams, now) {
        buildHomeExamOverview(examState.exams, now)
    }

    LaunchedEffect(
        examState.hasLoaded,
        examState.isLoading,
        examOverview != null,
        now.toLocalDate(),
    ) {
        if (examState.hasLoaded && !examState.isLoading) {
            semesterVm.updatePendingExamStatus(
                hasPendingExams = examOverview != null,
                today = now.toLocalDate(),
            )
        }
    }

    val context = LocalContext.current
    var pendingCropUri by remember { mutableStateOf<Uri?>(null) }
    var imageAreaSize by remember { mutableStateOf(IntSize.Zero) }
    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) {}
            pendingCropUri = uri
        }
    }

    // 图片裁切对话框
    if (pendingCropUri != null) {
        val ratio = if (imageAreaSize.width > 0 && imageAreaSize.height > 0)
            imageAreaSize.width.toFloat() / imageAreaSize.height.toFloat()
        else 9f / 16f
        tech.loveace.appv3.ui.components.ImageCropDialog(
            imageUri = pendingCropUri!!,
            cropShape = tech.loveace.appv3.ui.components.CropShape.Custom(ratio),
            onCropped = { croppedUri ->
                profileViewModel.setHomeImageUri(croppedUri.toString())
                pendingCropUri = null
            },
            onDismiss = { pendingCropUri = null },
        )
    }

    LaunchedEffect(authViewModel.jwcService) {
        authViewModel.jwcService?.let {
            academicVm.init(it)
            academicVm.loadAcademicInfo()
            examVm.init(it)
            examVm.loadExams()
        }
    }
    LaunchedEffect(authViewModel.aacService) {
        authViewModel.aacService?.let { aacVm.init(it); aacVm.loadAll() }
    }
    LaunchedEffect(authViewModel.yktService) {
        authViewModel.yktService?.let { yktVm.init(it); yktVm.loadAll() }
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                Column {
                    Text("彩带小工具", fontWeight = FontWeight.Bold)
                    Text(
                        "$displayName 同学，你好",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
        )

        Row(
            Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // ── 左栏：学业数据 + 一卡通/爱安财 ──
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                val info = academicState.academicInfo
                if (info != null) {
                    LandscapeAcademicOverviewCard(info)

                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        LandscapeStatCard(
                            label = "本学期课程", value = "${info.pendingCourses}",
                            icon = Icons.Default.MenuBook,
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                            modifier = Modifier.weight(1f),
                        )
                        LandscapeStatCard(
                            label = "已修课程", value = "${info.completedCourses}",
                            icon = Icons.Default.CheckCircle,
                            containerColor = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            modifier = Modifier.weight(1f),
                        )
                        val hasFailures = info.failedCourses > 0
                        LandscapeStatCard(
                            label = "不及格", value = "${info.failedCourses}",
                            icon = if (hasFailures) Icons.Default.Error else Icons.Default.Verified,
                            containerColor = if (hasFailures) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.tertiaryContainer,
                            contentColor = if (hasFailures) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onTertiaryContainer,
                            modifier = Modifier.weight(1f),
                        )
                    }
                } else if (academicState.isLoading) {
                    Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
                        AppCircularProgressIndicator()
                    }
                }

                // 一卡通 + 爱安财 并排
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    val balance = yktState.balance
                    Card(
                        modifier = Modifier.weight(1f),
                        shape = MaterialTheme.shapes.extraLarge,
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    Modifier.size(36.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Default.CreditCard, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                }
                                Spacer(Modifier.width(8.dp))
                                Text("一卡通", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.height(8.dp))
                            if (balance != null) {
                                Text(
                                    "¥${"%.2f".format(balance.balance)}",
                                    style = MaterialTheme.typography.titleLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            } else if (yktState.isLoading) {
                                AppCircularProgressIndicator(modifier = Modifier.size(24.dp))
                            } else {
                                Text("--", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }

                    val aacInfo = aacState.creditInfo
                    Card(
                        modifier = Modifier.weight(1f),
                        shape = MaterialTheme.shapes.extraLarge,
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    Modifier.size(36.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Default.VolunteerActivism, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onTertiaryContainer)
                                }
                                Spacer(Modifier.width(8.dp))
                                Text("爱安财", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.height(8.dp))
                            if (aacInfo != null) {
                                Row(verticalAlignment = Alignment.Bottom) {
                                    Text(
                                        "${"%.1f".format(aacInfo.totalScore)}",
                                        style = MaterialTheme.typography.titleLarge,
                                        fontWeight = FontWeight.Bold,
                                        color = if (aacInfo.isTypeAdopt) Color(0xFF2E7D32) else MaterialTheme.colorScheme.primary,
                                    )
                                    Text(" / 10", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Spacer(Modifier.height(4.dp))
                                AppLinearProgressIndicator(
                                    progress = { (aacInfo.totalScore / 10.0).toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(6.dp),
                                    color = if (aacInfo.isTypeAdopt) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.primary,
                                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                )
                            } else if (aacState.isLoading) {
                                AppCircularProgressIndicator(modifier = Modifier.size(24.dp))
                            } else {
                                Text("--", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }

                // ── 学期 + 小日历 ──
                val semStatus = semesterState.status
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        // 学期状态行
                        when (semStatus) {
                            is SemesterStatus.Loading -> {
                                Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                                    AppCircularProgressIndicator(modifier = Modifier.size(24.dp))
                                }
                            }
                            is SemesterStatus.Vacation -> {
                                when {
                                    authViewModel.jwcService != null &&
                                        (!examState.hasLoaded || examState.isLoading) -> {
                                        Box(
                                            Modifier.fillMaxWidth().padding(8.dp),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            AppCircularProgressIndicator(modifier = Modifier.size(24.dp))
                                        }
                                    }
                                    else -> Row(verticalAlignment = Alignment.CenterVertically) {
                                        Box(
                                            Modifier.size(36.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Icon(Icons.Default.BeachAccess, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onTertiaryContainer)
                                        }
                                        Spacer(Modifier.width(10.dp))
                                        Column(Modifier.weight(1f)) {
                                            Text("假期中", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                            if (semStatus.nextSemesterName != null) {
                                                Text(
                                                    "${semStatus.nextSemesterName} · ${semStatus.nextStartDate} 开学（${semStatus.daysUntilStart}天后）",
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            is SemesterStatus.FinalExamWeek -> {
                                if (examOverview != null) {
                                    HomeExamSummary(overview = examOverview, maxItems = 2)
                                } else {
                                    Text(
                                        "期末周",
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.Bold,
                                    )
                                }
                            }
                            is SemesterStatus.InSession -> {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(
                                        Modifier.size(36.dp).background(
                                            if (semStatus.isEnding) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.primaryContainer,
                                            CircleShape,
                                        ),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(
                                            if (semStatus.isEnding) Icons.Default.Timer else Icons.Default.School,
                                            null, modifier = Modifier.size(18.dp),
                                            tint = if (semStatus.isEnding) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer,
                                        )
                                    }
                                    Spacer(Modifier.width(10.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(semStatus.semesterName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                        Text(
                                            if (semStatus.isEnding) "第${semStatus.currentWeek}周 · 学期即将结束" else "第${semStatus.currentWeek}周 · 共${semStatus.totalWeeks}周",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    Text(
                                        "${semStatus.currentWeek}/${semStatus.totalWeeks}",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                                AppLinearProgressIndicator(
                                    progress = { (semStatus.currentWeek.toFloat() / semStatus.totalWeeks).coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(4.dp),
                                    color = if (semStatus.isEnding) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                )
                            }
                            is SemesterStatus.Error -> {}
                        }

                        // 小日历
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                        MiniCalendar()
                    }
                }
            }

            // ── 右栏：用户自选图片展示器（整栏） ──
            Box(
                modifier = Modifier.weight(1f).fillMaxHeight()
                    .onSizeChanged { imageAreaSize = it },
            ) {
                if (profileState.homeImageUri != null) {
                    // 已选图片 — 填满右栏
                    ElevatedCard(
                        modifier = Modifier.fillMaxSize(),
                        shape = MaterialTheme.shapes.extraLarge,
                    ) {
                        Box(Modifier.fillMaxSize()) {
                            AsyncImage(
                                model = profileState.homeImageUri,
                                contentDescription = "自选图片",
                                modifier = Modifier.fillMaxSize().clip(MaterialTheme.shapes.extraLarge),
                                contentScale = ContentScale.Crop,
                            )
                            Row(
                                modifier = Modifier.align(Alignment.TopEnd).padding(12.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                FilledIconButton(
                                    onClick = { profileViewModel.setHomeImageUri(null) },
                                    modifier = Modifier.size(36.dp),
                                    colors = IconButtonDefaults.filledIconButtonColors(
                                        containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.85f),
                                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                    ),
                                ) {
                                    Icon(Icons.Default.Close, "清除图片", modifier = Modifier.size(18.dp))
                                }
                                FilledIconButton(
                                    onClick = { imagePicker.launch("image/*") },
                                    modifier = Modifier.size(36.dp),
                                    colors = IconButtonDefaults.filledIconButtonColors(
                                        containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.8f),
                                        contentColor = MaterialTheme.colorScheme.onSurface,
                                    ),
                                ) {
                                    Icon(Icons.Default.Edit, "更换图片", modifier = Modifier.size(18.dp))
                                }
                            }
                        }
                    }
                } else {
                    // 空状态 — 大型画框占位
                    OutlinedCard(
                        modifier = Modifier.fillMaxSize().clickable { imagePicker.launch("image/*") },
                        shape = MaterialTheme.shapes.extraLarge,
                        border = CardDefaults.outlinedCardBorder().copy(
                            brush = androidx.compose.ui.graphics.SolidColor(
                                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                            ),
                        ),
                        colors = CardDefaults.outlinedCardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.5f),
                        ),
                    ) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    Icons.Default.Image,
                                    contentDescription = null,
                                    modifier = Modifier.size(72.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                )
                                Spacer(Modifier.height(16.dp))
                                Text(
                                    "我的画框",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Medium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                )
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    "点击选择一张喜欢的图片",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}


@Composable
private fun LandscapeAcademicOverviewCard(info: AcademicInfo) {
    ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
        Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(contentAlignment = Alignment.Center) {
                    AppCircularProgressIndicator(
                        progress = { (info.gpa / 5.0).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.size(82.dp),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                    Text(
                        "%.2f".format(info.gpa),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                Spacer(Modifier.width(22.dp))
                Column(Modifier.weight(1f)) {
                    Text("绩点 / 5.0", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    Text(info.currentTerm.ifEmpty { "当前学期" }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                LandscapeAcademicNumber(
                    label = "均分",
                    value = if (info.averageScore > 0.0) "%.2f".format(info.averageScore) else "--",
                    supporting = "百分制",
                )
                Spacer(Modifier.width(10.dp))
                LandscapeAcademicNumber(
                    label = "均分排名",
                    value = if (info.hasAverageRank) "#${info.averageRank}" else "--",
                    supporting = if (info.hasAverageRank) "共 ${info.averageRankTotal} 人" else "暂无",
                    highlighted = info.hasAverageRank,
                )
            }

            AppLinearProgressIndicator(
                progress = {
                    if (info.hasAverageRank) info.averageRankProgress
                    else (info.averageScore / 100.0).toFloat().coerceIn(0f, 1f)
                },
                modifier = Modifier.fillMaxWidth().height(5.dp),
                color = MaterialTheme.colorScheme.secondary,
                trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            )
        }
    }
}

@Composable
private fun LandscapeAcademicNumber(
    label: String,
    value: String,
    supporting: String,
    highlighted: Boolean = false,
) {
    Surface(
        shape = MaterialTheme.shapes.large,
        color = if (highlighted) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.72f),
        contentColor = if (highlighted) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
    ) {
        Column(
            Modifier.widthIn(min = 96.dp).padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(label, style = MaterialTheme.typography.labelSmall)
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(supporting, style = MaterialTheme.typography.bodySmall, color = LocalContentColor.current.copy(alpha = 0.72f))
        }
    }
}

@Composable
private fun LandscapeStatCard(
    label: String,
    value: String,
    icon: ImageVector,
    containerColor: Color,
    contentColor: Color,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null, modifier = Modifier.size(24.dp), tint = contentColor)
            Spacer(Modifier.height(8.dp))
            Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = contentColor)
            Text(label, style = MaterialTheme.typography.labelMedium, color = contentColor)
        }
    }
}



/**
 * M3E 风格小日历 — 显示当月，高亮今天
 */
@Composable
private fun MiniCalendar() {
    val today = remember { LocalDate.now() }
    val yearMonth = remember { YearMonth.from(today) }
    val firstDay = yearMonth.atDay(1)
    val daysInMonth = yearMonth.lengthOfMonth()
    // 周一 = 0
    val startOffset = (firstDay.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7

    val weekdays = remember {
        DayOfWeek.entries.map { it.getDisplayName(JavaTextStyle.SHORT, Locale.CHINESE) }
    }

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        // 月份标题
        Text(
            "${yearMonth.year}年${yearMonth.monthValue}月",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))

        // 星期头
        Row(Modifier.fillMaxWidth()) {
            weekdays.forEach { day ->
                Text(
                    day,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                )
            }
        }
        Spacer(Modifier.height(2.dp))

        // 日期网格
        val totalCells = startOffset + daysInMonth
        val rows = (totalCells + 6) / 7
        for (row in 0 until rows) {
            Row(Modifier.fillMaxWidth()) {
                for (col in 0..6) {
                    val cellIndex = row * 7 + col
                    val dayNum = cellIndex - startOffset + 1
                    Box(
                        modifier = Modifier.weight(1f).aspectRatio(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (dayNum in 1..daysInMonth) {
                            val isToday = dayNum == today.dayOfMonth
                            if (isToday) {
                                Box(
                                    modifier = Modifier
                                        .size(28.dp)
                                        .background(MaterialTheme.colorScheme.primary, CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        "$dayNum",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onPrimary,
                                        fontWeight = FontWeight.Bold,
                                    )
                                }
                            } else {
                                Text(
                                    "$dayNum",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
