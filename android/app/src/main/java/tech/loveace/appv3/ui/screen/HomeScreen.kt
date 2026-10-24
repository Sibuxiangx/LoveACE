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

            // ── 学业数据：2 列网格，与下方卡片列对齐 ──
            val info = academicState.academicInfo
            if (info != null) {
                item {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        RibbonSectionTitle("学业", modifier = Modifier.padding(top = 12.dp, bottom = 10.dp))
                    }
                }
                item {
                    Row(
                        Modifier.padding(horizontal = 16.dp).height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        GpaHeroCard(info, Modifier.weight(1f))
                        CourseHeroCard(info, Modifier.weight(1f))
                    }
                }
                item {
                    Row(
                        Modifier.padding(horizontal = 16.dp).height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        StatCard(
                            label = "已修课程",
                            value = "${info.completedCourses}",
                            icon = Icons.Default.CheckCircle,
                            variant = RibbonCardVariant.PRIMARY_CONTAINER,
                            modifier = Modifier.weight(1f),
                        )
                        val hasFailures = info.failedCourses > 0
                        StatCard(
                            label = "不及格",
                            value = "${info.failedCourses}",
                            icon = if (hasFailures) Icons.Default.Error else Icons.Default.Verified,
                            variant = if (hasFailures) RibbonCardVariant.ERROR_CONTAINER else RibbonCardVariant.TERTIARY_CONTAINER,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            } else if (academicState.isLoading) {
                item {
                    BentoLoadingCard(Modifier.padding(horizontal = 16.dp).fillMaxWidth())
                }
            }

            // ── 一卡通 + 爱安财：与上方同一网格 ──
            val balance = yktState.balance
            val aacInfo = aacState.creditInfo
            if (balance != null || aacInfo != null || yktState.isLoading || aacState.isLoading) {
                item {
                    Row(
                        Modifier.padding(horizontal = 16.dp).height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        when {
                            balance != null -> StatCard(
                                label = "一卡通",
                                value = "¥ ${"%.2f".format(balance.balance)}",
                                icon = Icons.Default.CreditCard,
                                variant = RibbonCardVariant.SECONDARY_CONTAINER,
                                modifier = Modifier.weight(1f),
                                compact = true,
                                interactive = true,
                                onClick = { onNavigateToDetail(YKTRoute) },
                                footer = {
                                    Text("卡片余额", style = MaterialTheme.typography.bodySmall)
                                },
                            )
                            yktState.isLoading -> BentoLoadingCard(Modifier.weight(1f))
                            else -> Spacer(Modifier.weight(1f))
                        }
                        when {
                            aacInfo != null -> {
                                val passed = aacInfo.isTypeAdopt
                                val variant = if (passed) RibbonCardVariant.SUCCESS_CONTAINER else RibbonCardVariant.WARNING_CONTAINER
                                StatCard(
                                    label = "爱安财",
                                    value = "%.1f".format(aacInfo.totalScore),
                                    icon = Icons.Default.VolunteerActivism,
                                    variant = variant,
                                    modifier = Modifier.weight(1f),
                                    compact = true,
                                    footer = {
                                        Text("毕业要求 / 10 分", style = MaterialTheme.typography.bodySmall)
                                        RibbonChip(
                                            if (passed) "已达标" else "未达标",
                                            tone = if (passed) RibbonTone.SUCCESS else RibbonTone.WARNING,
                                            icon = if (passed) Icons.Default.CheckCircle else Icons.Default.Cancel,
                                        )
                                        AppLinearProgressIndicator(
                                            progress = { (aacInfo.totalScore / 10.0).toFloat().coerceIn(0f, 1f) },
                                            modifier = Modifier.fillMaxWidth().height(6.dp),
                                            color = ribbonContentColor(variant),
                                            trackColor = ribbonContentColor(variant).copy(alpha = 0.2f),
                                        )
                                    },
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

/** 绩点大卡：环形进度 + 绩点，下方排名标签与均分（MD bento 大卡）。 */
@Composable
private fun GpaHeroCard(info: AcademicInfo, modifier: Modifier = Modifier) {
    RibbonCard(
        modifier = modifier.fillMaxHeight(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 32.dp,
        padding = PaddingValues(20.dp),
    ) {
        Column(
            Modifier.fillMaxHeight(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Box(contentAlignment = Alignment.Center) {
                AppCircularProgressIndicator(
                    progress = { (info.gpa / 5.0).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.size(112.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                )
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("%.2f".format(info.gpa), style = RibbonNumeric.Large, color = MaterialTheme.colorScheme.primary)
                    Text(
                        "绩点 / 5.0",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RibbonChip(
                    if (info.hasAverageRank) "排名 ${info.averageRank}/${info.averageRankTotal}" else "暂无排名",
                    tone = RibbonTone.PRIMARY,
                )
                val averageText = if (info.averageScore > 0.0) "%.2f".format(info.averageScore) else "--"
                Text(
                    "均分 $averageText",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** 本学期课程大卡：左上图标徽章，底部大数字与说明。 */
@Composable
private fun CourseHeroCard(info: AcademicInfo, modifier: Modifier = Modifier) {
    val variant = RibbonCardVariant.SECONDARY_CONTAINER
    val content = ribbonContentColor(variant)
    RibbonCard(
        modifier = modifier.fillMaxHeight(),
        variant = variant,
        radius = 32.dp,
        padding = PaddingValues(20.dp),
    ) {
        Column(Modifier.fillMaxHeight(), verticalArrangement = Arrangement.SpaceBetween) {
            ShapeBadge(
                shape = RibbonShape.COOKIE_6,
                size = 48.dp,
                color = content.copy(alpha = 0.12f),
                icon = Icons.Default.MenuBook,
                iconTint = content,
            )
            Column {
                Text("${info.pendingCourses}", style = RibbonNumeric.XL, color = content)
                Text("本学期课程", style = MaterialTheme.typography.titleMedium, color = content)
                Text(
                    "本学期已选课程总数",
                    style = MaterialTheme.typography.bodySmall,
                    color = content.copy(alpha = 0.78f),
                )
            }
        }
    }
}

/** 统计小卡：左上图标 + 标题，下方大数字与说明（MD bento 小卡）。 */
@Composable
private fun StatCard(
    label: String,
    value: String,
    icon: ImageVector,
    variant: RibbonCardVariant,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    interactive: Boolean = false,
    onClick: () -> Unit = {},
    footer: @Composable ColumnScope.() -> Unit = {},
) {
    val content = ribbonContentColor(variant)
    RibbonCard(
        modifier = modifier.fillMaxHeight(),
        variant = variant,
        radius = 32.dp,
        padding = PaddingValues(20.dp),
        interactive = interactive,
        onClick = onClick,
    ) {
        Column(Modifier.fillMaxHeight(), verticalArrangement = Arrangement.SpaceBetween) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp), tint = content)
                Spacer(Modifier.width(8.dp))
                Text(label, style = MaterialTheme.typography.labelLarge, color = content)
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(value, style = if (compact) RibbonNumeric.Large else RibbonNumeric.XL, color = content)
                footer()
            }
        }
    }
}

@Composable
private fun BentoLoadingCard(modifier: Modifier = Modifier) {
    RibbonCard(
        modifier = modifier,
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 32.dp,
        padding = PaddingValues(16.dp),
    ) {
        Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 120.dp), contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
        }
    }
}
