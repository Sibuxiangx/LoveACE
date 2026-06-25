package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.AcademicInfo
import tech.loveace.appv3.ui.components.*
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
                    Text("彩带小工具", fontWeight = FontWeight.Bold)
                    Text(
                        "$displayName 同学，你好",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            })
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // ── 学期信息 ──
            val semStatus = semesterState.status
            if (semStatus is SemesterStatus.Vacation || semStatus is SemesterStatus.InSession) {
                item {
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        SectionTitle("学期")
                        Spacer(Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        ) {
                            when (semStatus) {
                                is SemesterStatus.Vacation -> {
                                    ListItem(
                                        headlineContent = {
                                            Text("假期中", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                        },
                                        supportingContent = {
                                            if (semStatus.nextSemesterName != null) {
                                                Text("即将到来：${semStatus.nextSemesterName}\n${semStatus.nextStartDate} 开学（还有 ${semStatus.daysUntilStart} 天）")
                                            }
                                        },
                                        leadingContent = {
                                            Box(
                                                Modifier.size(44.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
                                                contentAlignment = Alignment.Center,
                                            ) {
                                                Icon(Icons.Default.BeachAccess, null, modifier = Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onTertiaryContainer)
                                            }
                                        },
                                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                    )
                                }
                                is SemesterStatus.InSession -> {
                                    Column(Modifier.padding(20.dp)) {
                                        Row(
                                            Modifier.fillMaxWidth(),
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            Box(
                                                Modifier.size(44.dp).background(
                                                    if (semStatus.isEnding) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.primaryContainer,
                                                    CircleShape,
                                                ),
                                                contentAlignment = Alignment.Center,
                                            ) {
                                                Icon(
                                                    if (semStatus.isEnding) Icons.Default.Timer else Icons.Default.School,
                                                    null, modifier = Modifier.size(22.dp),
                                                    tint = if (semStatus.isEnding) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer,
                                                )
                                            }
                                            Spacer(Modifier.width(14.dp))
                                            Column(Modifier.weight(1f)) {
                                                Text(semStatus.semesterName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                                Text(
                                                    if (semStatus.isEnding) "第${semStatus.currentWeek}周 · 学期即将结束" else "第${semStatus.currentWeek}周",
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                            }
                                            Text(
                                                "${semStatus.currentWeek}/${semStatus.totalWeeks}",
                                                style = MaterialTheme.typography.headlineSmall,
                                                fontWeight = FontWeight.Bold,
                                                color = MaterialTheme.colorScheme.primary,
                                            )
                                        }
                                        Spacer(Modifier.height(12.dp))
                                        AppLinearProgressIndicator(
                                            progress = { (semStatus.currentWeek.toFloat() / semStatus.totalWeeks).coerceIn(0f, 1f) },
                                            modifier = Modifier.fillMaxWidth().height(6.dp),
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
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        SectionTitle("学期")
                        Spacer(Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        ) {
                            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                                AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
                            }
                        }
                    }
                }
            }

            // ── 学业数据 ──
            val info = academicState.academicInfo
            if (info != null) {
                // GPA / 均分排名主卡片
                item {
                    AcademicOverviewCard(info, Modifier.padding(horizontal = 20.dp))
                }

                // 学业指标网格：本学期课程总数（突出）+ 已修 + 不及格
                item {
                    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        // 本学期课程总数 — 突出显示
                        Card(
                            Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.secondaryContainer,
                            ),
                        ) {
                            Row(
                                Modifier.padding(horizontal = 20.dp, vertical = 16.dp).fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Box(
                                    Modifier.size(44.dp).background(
                                        MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.12f), CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Default.MenuBook, null, modifier = Modifier.size(22.dp),
                                        tint = MaterialTheme.colorScheme.onSecondaryContainer)
                                }
                                Spacer(Modifier.width(14.dp))
                                Column(Modifier.weight(1f)) {
                                    Text("本学期课程总数", style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer)
                                    Text("待修课程", style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f))
                                }
                                Text("${info.pendingCourses}",
                                    style = MaterialTheme.typography.headlineMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer)
                            }
                        }

                        // 已修 + 不及格 并排
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            // 已修
                            Card(
                                Modifier.weight(1f),
                                shape = MaterialTheme.shapes.large,
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                                ),
                            ) {
                                Column(Modifier.padding(16.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(Icons.Default.CheckCircle, null, modifier = Modifier.size(16.dp),
                                            tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                        Spacer(Modifier.width(6.dp))
                                        Text("已修课程", style = MaterialTheme.typography.labelMedium,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer)
                                    }
                                    Spacer(Modifier.height(6.dp))
                                    Text("${info.completedCourses}",
                                        style = MaterialTheme.typography.headlineSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer)
                                }
                            }
                            // 不及格
                            val hasFailures = info.failedCourses > 0
                            Card(
                                Modifier.weight(1f),
                                shape = MaterialTheme.shapes.large,
                                colors = CardDefaults.cardColors(
                                    containerColor = if (hasFailures) MaterialTheme.colorScheme.errorContainer
                                        else MaterialTheme.colorScheme.tertiaryContainer,
                                ),
                            ) {
                                Column(Modifier.padding(16.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(
                                            if (hasFailures) Icons.Default.Error else Icons.Default.Verified,
                                            null, modifier = Modifier.size(16.dp),
                                            tint = if (hasFailures) MaterialTheme.colorScheme.onErrorContainer
                                                else MaterialTheme.colorScheme.onTertiaryContainer,
                                        )
                                        Spacer(Modifier.width(6.dp))
                                        Text("不及格", style = MaterialTheme.typography.labelMedium,
                                            color = if (hasFailures) MaterialTheme.colorScheme.onErrorContainer
                                                else MaterialTheme.colorScheme.onTertiaryContainer)
                                    }
                                    Spacer(Modifier.height(6.dp))
                                    Text("${info.failedCourses}",
                                        style = MaterialTheme.typography.headlineSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = if (hasFailures) MaterialTheme.colorScheme.onErrorContainer
                                            else MaterialTheme.colorScheme.onTertiaryContainer)
                                }
                            }
                        }
                    }
                }
            } else if (academicState.isLoading) {
                item {
                    Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                        AppCircularProgressIndicator()
                    }
                }
            }

            // ── 一卡通余额 ──
            val balance = yktState.balance
            if (balance != null) {
                item {
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        SectionTitle("一卡通")
                        Spacer(Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth().clickable { onNavigateToDetail(YKTRoute) },
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        ) {
                            ListItem(
                                headlineContent = {
                                    Text("¥${"%.2f".format(balance.balance)}",
                                        style = MaterialTheme.typography.headlineSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary)
                                },
                                supportingContent = { Text("卡片余额") },
                                leadingContent = {
                                    Box(
                                        Modifier.size(44.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(Icons.Default.CreditCard, null, modifier = Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                    }
                                },
                                trailingContent = {
                                    Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            )
                        }
                    }
                }
            } else if (yktState.isLoading) {
                item {
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        SectionTitle("一卡通")
                        Spacer(Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        ) {
                            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                                AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
                            }
                        }
                    }
                }
            }

            // ── 爱安财 ──
            val aacInfo = aacState.creditInfo
            if (aacInfo != null) {
                item {
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        SectionTitle("爱安财")
                        Spacer(Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        ) {
                            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(
                                        Modifier.size(44.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(Icons.Default.VolunteerActivism, null, modifier = Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onTertiaryContainer)
                                    }
                                    Spacer(Modifier.width(12.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text("${"%.1f".format(aacInfo.totalScore)} / 10 分",
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.Bold)
                                        Text("毕业要求总分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    val adoptColor = if (aacInfo.isTypeAdopt) Color(0xFF2E7D32) else Color(0xFFE65100)
                                    val adoptBg = adoptColor.copy(alpha = 0.12f)
                                    AssistChip(
                                        onClick = {},
                                        label = { Text(if (aacInfo.isTypeAdopt) "已达标" else "未达标", style = MaterialTheme.typography.labelSmall) },
                                        leadingIcon = {
                                            Icon(
                                                if (aacInfo.isTypeAdopt) Icons.Default.CheckCircle else Icons.Default.Cancel,
                                                null, modifier = Modifier.size(14.dp),
                                            )
                                        },
                                        colors = AssistChipDefaults.assistChipColors(
                                            containerColor = adoptBg, labelColor = adoptColor, leadingIconContentColor = adoptColor,
                                        ),
                                        border = null,
                                    )
                                }
                                // 进度条
                                AppLinearProgressIndicator(
                                    progress = { (aacInfo.totalScore / 10.0).toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier.fillMaxWidth().height(8.dp),
                                    color = if (aacInfo.isTypeAdopt) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.primary,
                                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                )
                            }
                        }
                    }
                }
            } else if (aacState.isLoading) {
                item {
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        SectionTitle("爱安财")
                        Spacer(Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = MaterialTheme.shapes.extraLarge,
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        ) {
                            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                                AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}


@Composable
private fun AcademicOverviewCard(info: AcademicInfo, modifier: Modifier = Modifier) {
    ElevatedCard(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
    ) {
        Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(contentAlignment = Alignment.Center) {
                    AppCircularProgressIndicator(
                        progress = { (info.gpa / 5.0).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.size(78.dp),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                    Text(
                        "%.2f".format(info.gpa),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                Spacer(Modifier.width(18.dp))
                Column(Modifier.weight(1f)) {
                    Text("绩点 / 5.0", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(2.dp))
                    Text(
                        info.currentTerm.ifEmpty { "当前学期" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (info.hasAverageRank) {
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ) {
                        Column(
                            Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text("均分排名", style = MaterialTheme.typography.labelSmall)
                            Text("#${info.averageRank}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
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
                        modifier = Modifier.fillMaxWidth().height(5.dp),
                        color = MaterialTheme.colorScheme.secondary,
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                    Text(
                        if (info.hasAverageRank) "均分排名越靠前，进度条越接近满格" else "均分进度",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

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
        color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.7f),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(supporting, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
