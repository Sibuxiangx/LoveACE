package tech.loveace.appv3.ui.screen.landscape

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import tech.loveace.appv3.data.model.AcademicInfo
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
import tech.loveace.appv3.ui.viewmodel.*
import tech.loveace.appv3.ui.screen.AacTile
import tech.loveace.appv3.ui.screen.AcademicCounts
import tech.loveace.appv3.ui.screen.AcademicHero
import tech.loveace.appv3.ui.screen.HomeTile
import tech.loveace.appv3.ui.screen.LoadingTile
import tech.loveace.appv3.ui.screen.SemesterStatusRow
import tech.loveace.appv3.ui.screen.YktTile

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
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val academicState by academicVm.uiState.collectAsStateWithLifecycle()
    val aacState by aacVm.uiState.collectAsStateWithLifecycle()
    val yktState by yktVm.uiState.collectAsStateWithLifecycle()
    val profileState by profileViewModel.state.collectAsStateWithLifecycle()
    val semesterState by semesterVm.uiState.collectAsStateWithLifecycle()

    val displayName = profileState.nickname.ifEmpty { authState.userId }

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
        authViewModel.jwcService?.let { academicVm.init(it); academicVm.loadAcademicInfo() }
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
            // ── 左栏：学业 + 一卡通/爱安财 + 学期与日历（与竖屏共用卡片） ──
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                val info = academicState.academicInfo
                if (info != null) {
                    AcademicHero(info)
                    AcademicCounts(info)
                } else if (academicState.isLoading) {
                    LoadingTile()
                }

                // 一卡通 + 爱安财：等高双卡
                val balance = yktState.balance
                val aacInfo = aacState.creditInfo
                if (balance != null || yktState.isLoading || aacInfo != null || aacState.isLoading) {
                    Row(
                        Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        when {
                            balance != null -> YktTile(
                                balanceText = "¥${"%.2f".format(balance.balance)}",
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                            yktState.isLoading -> LoadingTile(Modifier.weight(1f).fillMaxHeight())
                            else -> Spacer(Modifier.weight(1f))
                        }
                        when {
                            aacInfo != null -> AacTile(
                                info = aacInfo,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                            aacState.isLoading -> LoadingTile(Modifier.weight(1f).fillMaxHeight())
                            else -> Spacer(Modifier.weight(1f))
                        }
                    }
                }

                // 学期 + 小日历
                val semStatus = semesterState.status
                HomeTile(color = MaterialTheme.colorScheme.surfaceContainerLow) {
                    SemesterStatusRow(semStatus)
                    Spacer(Modifier.height(12.dp))
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    Spacer(Modifier.height(12.dp))
                    MiniCalendar()
                }
            }

            // ── 右栏：用户自选图片展示器（整栏） ──
            Box(
                modifier = Modifier.weight(1f).fillMaxHeight()
                    .onSizeChanged { imageAreaSize = it },
            ) {
                if (profileState.homeImageUri != null) {
                    // 已选图片 — 填满右栏
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(RoundedCornerShape(28.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerLow),
                    ) {
                        Box(Modifier.fillMaxSize()) {
                            AsyncImage(
                                model = profileState.homeImageUri,
                                contentDescription = "自选图片",
                                modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp)),
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
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(RoundedCornerShape(28.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.5f))
                            .clickable { imagePicker.launch("image/*") },
                        contentAlignment = Alignment.Center,
                    ) {
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
