package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
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
import tech.loveace.appv3.ui.viewmodel.SemesterUiState
import tech.loveace.appv3.ui.viewmodel.YKTViewModel

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
            TopAppBar(title = {
                Column {
                    Text(
                        "彩带小工具",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text("你好，$displayName", style = MaterialTheme.typography.headlineSmall)
                }
            })
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── 学期信息 ──
            val semStatus = semesterState.status
            if (semStatus is SemesterStatus.Vacation || semStatus is SemesterStatus.InSession) {
                item {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        RibbonSectionTitle("学期", modifier = Modifier.padding(top = 12.dp, bottom = 10.dp))
                        RibbonCard(
                            modifier = Modifier.fillMaxWidth(),
                            variant = RibbonCardVariant.SURFACE_LOW,
                            radius = 28.dp,
                            padding = PaddingValues(20.dp),
                        ) {
                            when (semStatus) {
                                is SemesterStatus.Vacation -> {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        ShapeBadge(
                                            shape = RibbonShape.COOKIE_12,
                                            size = 44.dp,
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
                                is SemesterStatus.InSession -> {
                                    Column {
                                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                            ShapeBadge(
                                                shape = RibbonShape.COOKIE_8,
                                                size = 44.dp,
                                                color = if (semStatus.isEnding) MaterialTheme.colorScheme.errorContainer
                                                    else MaterialTheme.colorScheme.primaryContainer,
                                                icon = if (semStatus.isEnding) Icons.Default.Timer else Icons.Default.School,
                                                iconTint = if (semStatus.isEnding) MaterialTheme.colorScheme.onErrorContainer
                                                    else MaterialTheme.colorScheme.onPrimaryContainer,
                                            )
                                            Spacer(Modifier.width(14.dp))
                                            Column(Modifier.weight(1f)) {
                                                Text(semStatus.semesterName, style = MaterialTheme.typography.titleMedium)
                                                Text(
                                                    if (semStatus.isEnding) "第 ${semStatus.currentWeek} 周 / 共 ${semStatus.totalWeeks} 周 · 学期即将结束" else "第 ${semStatus.currentWeek} 周 / 共 ${semStatus.totalWeeks} 周",
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                            }
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
                                else -> {}
                            }
                        }
                    }
                }
            } else if (semStatus is SemesterStatus.Loading) {
                item {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        RibbonSectionTitle("学期", modifier = Modifier.padding(top = 12.dp, bottom = 10.dp))
                        RibbonCard(modifier = Modifier.fillMaxWidth(), radius = 28.dp, padding = PaddingValues(24.dp)) {
                            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
                            }
                        }
                    }
                }
            }

            // ── 学业数据 ──
            val info = academicState.academicInfo
            if (info != null) {
                // 学业 hero：绩点、排名、均分、排名进度
                item {
                    AcademicOverviewCard(info, Modifier.padding(horizontal = 16.dp))
                }

                // 本学期课程 / 已修 / 不及格：一行三列
                item {
                    CourseCountsCard(info, Modifier.padding(horizontal = 16.dp))
                }
            } else if (academicState.isLoading) {
                item {
                    Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                        AppCircularProgressIndicator(modifier = Modifier.size(32.dp))
                    }
                }
            }

            // ── 一卡通 + 爱安财：并排等高 ──
            val balance = yktState.balance
            val aacInfo = aacState.creditInfo
            if (balance != null || aacInfo != null || yktState.isLoading || aacState.isLoading) {
                item {
                    Row(
                        Modifier.padding(horizontal = 16.dp).height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        when {
                            balance != null -> BentoCard(
                                title = "一卡通",
                                badgeShape = RibbonShape.CLOVER_4,
                                badgeIcon = Icons.Default.CreditCard,
                                modifier = Modifier.weight(1f),
                                interactive = true,
                                onClick = { onNavigateToDetail(YKTRoute) },
                            ) {
                                Text(
                                    "¥ ${"%.2f".format(balance.balance)}",
                                    style = RibbonNumeric.Medium,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text(
                                    "卡片余额",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            yktState.isLoading -> BentoLoadingCard(Modifier.weight(1f))
                            else -> Spacer(Modifier.weight(1f))
                        }
                        when {
                            aacInfo != null -> BentoCard(
                                title = "爱安财",
                                badgeShape = RibbonShape.COOKIE_8,
                                badgeIcon = Icons.Default.VolunteerActivism,
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(
                                    "${"%.1f".format(aacInfo.totalScore)} / 10",
                                    style = RibbonNumeric.Medium,
                                )
                                Text(
                                    "毕业要求总分",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                RibbonChip(
                                    if (aacInfo.isTypeAdopt) "已达标" else "未达标",
                                    tone = if (aacInfo.isTypeAdopt) RibbonTone.SUCCESS else RibbonTone.WARNING,
                                    icon = if (aacInfo.isTypeAdopt) Icons.Default.CheckCircle else Icons.Default.Cancel,
                                )
                                AppLinearProgressIndicator(
                                    progress = { (aacInfo.totalScore / 10.0).toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(6.dp),
                                    color = if (aacInfo.isTypeAdopt) LocalExtendedColors.current.success else MaterialTheme.colorScheme.primary,
                                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                )
                            }
                            aacState.isLoading -> BentoLoadingCard(Modifier.weight(1f))
                            else -> Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

/** 学业 hero：绩点、排名标签、均分一行、排名进度；排名只在标签里出现一次 */
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
                        modifier = Modifier.size(78.dp),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                    Text("%.2f".format(info.gpa), style = RibbonNumeric.Large, color = MaterialTheme.colorScheme.primary)
                }
                Spacer(Modifier.width(18.dp))
                Text("绩点 / 5.0", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
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
                            Text("排名", style = MaterialTheme.typography.labelSmall)
                            Text("${info.averageRank} / ${info.averageRankTotal}", style = RibbonNumeric.Medium)
                        }
                    }
                }
            }
            val averageText = if (info.averageScore > 0.0) "%.2f".format(info.averageScore) else "--"
            val rankNote = if (info.hasAverageRank) "" else " · 暂无排名"
            Text(
                "均分 $averageText（百分制）$rankNote",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.78f),
            )
            if (info.averageScore > 0.0 || info.hasAverageRank) {
                AppLinearProgressIndicator(
                    progress = {
                        if (info.hasAverageRank) info.averageRankProgress
                        else (info.averageScore / 100.0).toFloat().coerceIn(0f, 1f)
                    },
                    modifier = Modifier.fillMaxWidth().height(6.dp),
                    color = MaterialTheme.colorScheme.secondary,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                )
            }
        }
    }
}

/** 本学期课程 / 已修 / 不及格：一行三列；不及格非零时标红 */
@Composable
private fun CourseCountsCard(info: AcademicInfo, modifier: Modifier = Modifier) {
    RibbonCard(
        modifier = modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(horizontal = 12.dp, vertical = 16.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            CourseCount(label = "本学期课程", value = info.pendingCourses, modifier = Modifier.weight(1f))
            CourseCount(label = "已修课程", value = info.completedCourses, modifier = Modifier.weight(1f))
            CourseCount(
                label = "不及格",
                value = info.failedCourses,
                modifier = Modifier.weight(1f),
                alert = info.failedCourses > 0,
            )
        }
    }
}

@Composable
private fun CourseCount(label: String, value: Int, modifier: Modifier = Modifier, alert: Boolean = false) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            "$value",
            style = RibbonNumeric.Large,
            color = if (alert) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
        )
    }
}

/** 并排小卡：图标 + 标题在上，主数字与说明在下。 */
@Composable
private fun BentoCard(
    title: String,
    badgeShape: RibbonShape,
    badgeIcon: ImageVector,
    modifier: Modifier = Modifier,
    interactive: Boolean = false,
    onClick: () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    RibbonCard(
        modifier = modifier,
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(16.dp),
        interactive = interactive,
        onClick = onClick,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ShapeBadge(
                    shape = badgeShape,
                    size = 32.dp,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    icon = badgeIcon,
                    iconTint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Spacer(Modifier.width(8.dp))
                Text(title, style = MaterialTheme.typography.labelLarge)
            }
            content()
        }
    }
}

@Composable
private fun BentoLoadingCard(modifier: Modifier = Modifier) {
    RibbonCard(
        modifier = modifier,
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(16.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
        }
    }
}
