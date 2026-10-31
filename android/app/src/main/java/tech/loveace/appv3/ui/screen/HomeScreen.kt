package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.AcademicInfo
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
import tech.loveace.appv3.ui.navigation.*
import tech.loveace.appv3.ui.viewmodel.AACViewModel
import tech.loveace.appv3.ui.viewmodel.AcademicViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ProfileViewModel
import tech.loveace.appv3.ui.viewmodel.SemesterViewModel
import tech.loveace.appv3.ui.viewmodel.SemesterStatus
import tech.loveace.appv3.ui.viewmodel.YKTViewModel

/** 首页主数字（GPA）：比 RibbonNumeric.Large 更大，只在首页 hero 使用。 */
private val HeroNumeric = TextStyle(
    fontSize = 34.sp,
    fontWeight = FontWeight(800),
    lineHeight = 38.sp,
    letterSpacing = (-0.5).sp,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    authViewModel: AuthViewModel,
    onNavigateToDetail: (Any) -> Unit,
    academicVm: AcademicViewModel = viewModel(),
    aacVm: AACViewModel = viewModel(),
    yktVm: YKTViewModel = viewModel(),
    semesterVm: SemesterViewModel = viewModel(),
    profileVm: ProfileViewModel = viewModel(),
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val academicState by academicVm.uiState.collectAsStateWithLifecycle()
    val aacState by aacVm.uiState.collectAsStateWithLifecycle()
    val yktState by yktVm.uiState.collectAsStateWithLifecycle()
    val semesterState by semesterVm.uiState.collectAsStateWithLifecycle()
    val profileState by profileVm.state.collectAsStateWithLifecycle()

    val displayName = profileState.nickname.ifEmpty { authState.userId }

    LaunchedEffect(authViewModel.jwcService) {
        authViewModel.jwcService?.let {
            academicVm.init(it)
            academicVm.loadAcademicInfo()
        }
    }
    LaunchedEffect(authViewModel.aacService) {
        authViewModel.aacService?.let { aacVm.init(it); aacVm.loadAll() }
    }
    LaunchedEffect(authViewModel.yktService) {
        authViewModel.yktService?.let { yktVm.init(it); yktVm.loadAll() }
    }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("彩带小工具", fontWeight = FontWeight.Bold) })
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── 问候 ──
            item(key = "greeting") {
                Greeting(displayName = displayName)
            }

            // ── 学期 ──
            val semStatus = semesterState.status
            item(key = "semester") {
                when (semStatus) {
                    is SemesterStatus.Vacation -> HomeSection(title = "学期") {
                        RibbonCard(variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(20.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                ShapeBadge(
                                    shape = RibbonShape.COOKIE_12,
                                    size = 48.dp,
                                    color = MaterialTheme.colorScheme.tertiaryContainer,
                                    icon = Icons.Default.BeachAccess,
                                    iconTint = MaterialTheme.colorScheme.onTertiaryContainer,
                                )
                                Spacer(Modifier.width(14.dp))
                                Column {
                                    Text("假期中", style = MaterialTheme.typography.titleMedium)
                                    if (semStatus.nextSemesterName != null) {
                                        Text(
                                            "即将到来：${semStatus.nextSemesterName}\n${semStatus.nextStartDate} 开学（还有 ${semStatus.daysUntilStart} 天）",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
                    is SemesterStatus.InSession -> HomeSection(title = "学期") {
                        RibbonCard(
                            variant = if (semStatus.isEnding) RibbonCardVariant.ERROR_CONTAINER else RibbonCardVariant.PRIMARY_CONTAINER,
                            radius = 28.dp,
                            padding = PaddingValues(20.dp),
                        ) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                ShapeBadge(
                                    shape = RibbonShape.COOKIE_8,
                                    size = 48.dp,
                                    color = if (semStatus.isEnding) MaterialTheme.colorScheme.error
                                        else MaterialTheme.colorScheme.primary,
                                    icon = if (semStatus.isEnding) Icons.Default.Timer else Icons.Default.School,
                                    iconTint = MaterialTheme.colorScheme.onPrimary,
                                )
                                Spacer(Modifier.width(14.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(semStatus.semesterName, style = MaterialTheme.typography.titleMedium)
                                    Text(
                                        if (semStatus.isEnding) "第${semStatus.currentWeek}周 · 学期即将结束" else "第${semStatus.currentWeek}周",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Text(
                                    "${semStatus.currentWeek}/${semStatus.totalWeeks}",
                                    style = RibbonNumeric.Large,
                                    color = if (semStatus.isEnding) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                                )
                            }
                            Spacer(Modifier.height(12.dp))
                            AppLinearProgressIndicator(
                                progress = { (semStatus.currentWeek.toFloat() / semStatus.totalWeeks).coerceIn(0f, 1f) },
                                modifier = Modifier.fillMaxWidth().height(8.dp),
                                color = if (semStatus.isEnding) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                                trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                            )
                        }
                    }
                    is SemesterStatus.Loading -> HomeSection(title = "学期") { LoadingCard() }
                    else -> Unit
                }
            }

            // ── 学业 ──
            val info = academicState.academicInfo
            if (info != null) {
                item(key = "academic-hero") {
                    HomeSection(title = "学业") {
                        AcademicOverviewCard(info)
                    }
                }
                item(key = "academic-counts") {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        // 本学期课程总数：宽卡，突出显示
                        RibbonCard(
                            modifier = Modifier.fillMaxWidth(),
                            variant = RibbonCardVariant.SECONDARY_CONTAINER,
                            radius = 28.dp,
                            padding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                ShapeBadge(
                                    shape = RibbonShape.COOKIE_6,
                                    size = 44.dp,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.12f),
                                    icon = Icons.Default.MenuBook,
                                    iconTint = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                                Spacer(Modifier.width(14.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        "本学期课程总数",
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                    )
                                    Text(
                                        "待修课程",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f),
                                    )
                                }
                                Text(
                                    "${info.pendingCourses}",
                                    style = RibbonNumeric.Large,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                            }
                        }

                        // 已修 + 不及格：并排；已修 = tertiary，不及格有挂科时 error，否则 primary
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            StatTile(
                                label = "已修课程",
                                value = "${info.completedCourses}",
                                icon = Icons.Default.CheckCircle,
                                variant = RibbonCardVariant.TERTIARY_CONTAINER,
                                modifier = Modifier.weight(1f),
                            )
                            val hasFailures = info.failedCourses > 0
                            StatTile(
                                label = "不及格",
                                value = "${info.failedCourses}",
                                icon = if (hasFailures) Icons.Default.Error else Icons.Default.Verified,
                                variant = if (hasFailures) RibbonCardVariant.ERROR_CONTAINER else RibbonCardVariant.PRIMARY_CONTAINER,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            } else if (academicState.isLoading) {
                item(key = "academic-loading") {
                    HomeSection(title = "学业") { LoadingCard(height = 120.dp) }
                }
            }

            // ── 一卡通 ──
            val balance = yktState.balance
            if (balance != null) {
                item(key = "ykt") {
                    HomeSection(title = "一卡通") {
                        RibbonCard(
                            modifier = Modifier.fillMaxWidth(),
                            variant = RibbonCardVariant.SURFACE_LOW,
                            radius = 28.dp,
                            padding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                            interactive = true,
                            onClick = { onNavigateToDetail(YKTRoute) },
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                ShapeBadge(
                                    shape = RibbonShape.CLOVER_4,
                                    size = 44.dp,
                                    color = MaterialTheme.colorScheme.primaryContainer,
                                    icon = Icons.Default.CreditCard,
                                    iconTint = MaterialTheme.colorScheme.onPrimaryContainer,
                                )
                                Spacer(Modifier.width(14.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        "¥${"%.2f".format(balance.balance)}",
                                        style = RibbonNumeric.Large,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                    Text(
                                        "卡片余额",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Icon(
                                    Icons.Rounded.ChevronRight,
                                    null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            } else if (yktState.isLoading) {
                item(key = "ykt-loading") {
                    HomeSection(title = "一卡通") { LoadingCard() }
                }
            }

            // ── 爱安财 ──
            val aacInfo = aacState.creditInfo
            if (aacInfo != null) {
                item(key = "aac") {
                    HomeSection(title = "爱安财") {
                        RibbonCard(
                            modifier = Modifier.fillMaxWidth(),
                            variant = RibbonCardVariant.SURFACE_LOW,
                            radius = 28.dp,
                            padding = PaddingValues(20.dp),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    ShapeBadge(
                                        shape = RibbonShape.COOKIE_8,
                                        size = 44.dp,
                                        color = MaterialTheme.colorScheme.tertiaryContainer,
                                        icon = Icons.Default.VolunteerActivism,
                                        iconTint = MaterialTheme.colorScheme.onTertiaryContainer,
                                    )
                                    Spacer(Modifier.width(12.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            "${"%.1f".format(aacInfo.totalScore)} / 10 分",
                                            style = MaterialTheme.typography.titleMedium,
                                        )
                                        Text(
                                            "毕业要求总分",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    RibbonChip(
                                        if (aacInfo.isTypeAdopt) "已达标" else "未达标",
                                        tone = if (aacInfo.isTypeAdopt) RibbonTone.SUCCESS else RibbonTone.WARNING,
                                        icon = if (aacInfo.isTypeAdopt) Icons.Default.CheckCircle else Icons.Default.Cancel,
                                    )
                                }
                                AppLinearProgressIndicator(
                                    progress = { (aacInfo.totalScore / 10.0).toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(8.dp),
                                    color = if (aacInfo.isTypeAdopt) LocalExtendedColors.current.success
                                        else MaterialTheme.colorScheme.primary,
                                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                )
                            }
                        }
                    }
                }
            } else if (aacState.isLoading) {
                item(key = "aac-loading") {
                    HomeSection(title = "爱安财") { LoadingCard() }
                }
            }
        }
    }
}

/** 问候区：名字首字做花形徽章，下面是欢迎语。信息与原来相同。 */
@Composable
private fun Greeting(displayName: String) {
    Row(
        Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ShapeBadge(
            shape = RibbonShape.COOKIE_12,
            size = 56.dp,
            color = MaterialTheme.colorScheme.primaryContainer,
        ) {
            Text(
                displayName.firstOrNull()?.toString() ?: "?",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text(
                "$displayName 同学，你好",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "今天的学业、一卡通和爱安财都在这里",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** 分组标题 + 内容：所有首页分组统一用这一个结构。 */
@Composable
private fun HomeSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        RibbonSectionTitle(title, modifier = Modifier.padding(top = 8.dp))
        content()
    }
}

/** 加载占位：居中转圈，高度可调。 */
@Composable
private fun LoadingCard(height: androidx.compose.ui.unit.Dp = 88.dp) {
    RibbonCard(modifier = Modifier.fillMaxWidth(), radius = 28.dp, padding = PaddingValues(24.dp)) {
        Box(Modifier.fillMaxWidth().height(height - 48.dp), contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
        }
    }
}

/** GPA / 排名 hero 卡：绩点环 + 大数字，下面是均分与排名人数。 */
@Composable
private fun AcademicOverviewCard(info: AcademicInfo, modifier: Modifier = Modifier) {
    RibbonCard(
        modifier = modifier.fillMaxWidth(),
        variant = RibbonCardVariant.PRIMARY_CONTAINER,
        radius = 32.dp,
        padding = PaddingValues(22.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(contentAlignment = Alignment.Center) {
                    AppCircularProgressIndicator(
                        progress = { (info.gpa / 5.0).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.size(104.dp),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                    Text("%.2f".format(info.gpa), style = HeroNumeric, color = MaterialTheme.colorScheme.primary)
                }
                Spacer(Modifier.width(18.dp))
                Column(Modifier.weight(1f)) {
                    Text("绩点 / 5.0", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(2.dp))
                    Text(
                        info.currentTerm.ifEmpty { "当前学期" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.78f),
                    )
                }
                if (info.hasAverageRank) {
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ) {
                        Column(
                            Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text("均分排名", style = MaterialTheme.typography.labelSmall)
                            Text("#${info.averageRank}", style = RibbonNumeric.Medium)
                        }
                    }
                }
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AcademicMiniMetric(
                    label = "均分",
                    value = if (info.averageScore > 0.0) "%.2f".format(info.averageScore) else "--",
                    supporting = "百分制",
                    modifier = Modifier.weight(1f),
                )
                AcademicMiniMetric(
                    label = "排名人数",
                    value = if (info.averageRankTotal > 0) "${info.averageRankTotal}" else "--",
                    supporting = if (info.hasAverageRank) "第 ${info.averageRank} / ${info.averageRankTotal}" else "暂无排名",
                    modifier = Modifier.weight(1f),
                )
            }

            if (info.averageScore > 0.0 || info.hasAverageRank) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    AppLinearProgressIndicator(
                        progress = {
                            if (info.hasAverageRank) info.averageRankProgress
                            else (info.averageScore / 100.0).toFloat().coerceIn(0f, 1f)
                        },
                        modifier = Modifier.fillMaxWidth().height(6.dp),
                        color = MaterialTheme.colorScheme.secondary,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                    Text(
                        if (info.hasAverageRank) "均分排名越靠前，进度条越接近满格" else "均分进度",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.78f),
                    )
                }
            }
        }
    }
}

/** hero 内的半宽指标 tile：surface 高一层（嵌套 tile 规则） */
@Composable
private fun AcademicMiniMetric(
    label: String,
    value: String,
    supporting: String,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.6f),
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = RibbonNumeric.Caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = RibbonNumeric.Medium)
            Text(supporting, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** 半宽统计 tile：紧凑 24dp 圆角 + 大数字 */
@Composable
private fun StatTile(
    label: String,
    value: String,
    icon: ImageVector,
    variant: RibbonCardVariant,
    modifier: Modifier = Modifier,
) {
    RibbonCard(
        modifier = modifier,
        variant = variant,
        radius = 24.dp,
        padding = PaddingValues(16.dp),
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, modifier = Modifier.size(16.dp), tint = ribbonContentColor(variant))
                Spacer(Modifier.width(6.dp))
                Text(label, style = MaterialTheme.typography.labelMedium, color = ribbonContentColor(variant))
            }
            Spacer(Modifier.height(6.dp))
            Text(value, style = RibbonNumeric.Large, color = ribbonContentColor(variant))
        }
    }
}
