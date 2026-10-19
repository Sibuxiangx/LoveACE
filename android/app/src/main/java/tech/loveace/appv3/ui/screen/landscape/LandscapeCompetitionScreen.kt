package tech.loveace.appv3.ui.screen.landscape

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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.AwardProject
import tech.loveace.appv3.data.model.CreditsSummary
import tech.loveace.appv3.ui.components.*
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.CompetitionViewModel

/**
 * 横屏竞赛信息：左栏学分汇总 | 右栏获奖项目列表
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeCompetitionScreen(
    authViewModel: AuthViewModel,
    vm: CompetitionViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.competitionService) {
        authViewModel.competitionService?.let { vm.init(it); vm.loadCompetitionInfo() }
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = { Text("竞赛信息") })

        when {
            state.isLoading -> LoadingScreen()
            state.error != null -> ErrorScreen(state.error!!) { vm.loadCompetitionInfo() }
            state.data == null -> EmptyScreen("暂无竞赛数据")
            else -> {
                val data = state.data!!
                Row(
                    Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    // 左栏：学分汇总
                    Column(
                        Modifier.weight(0.4f).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        data.creditsSummary?.let { summary ->
                            RibbonCard(Modifier.fillMaxWidth(), variant = RibbonCardVariant.PRIMARY_CONTAINER, radius = 32.dp, padding = PaddingValues(22.dp)) {
                                Column {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        ShapeBadge(shape = RibbonShape.FLOWER_5, size = 44.dp, color = MaterialTheme.colorScheme.primary, icon = Icons.Default.School, iconTint = MaterialTheme.colorScheme.onPrimary)
                                        Spacer(Modifier.width(12.dp))
                                        Text("创新学分汇总", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                    }
                                    Spacer(Modifier.height(20.dp))
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.Bottom) {
                                        Text("${"%.1f".format(summary.totalCredits)}", style = RibbonNumeric.Large, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                        Spacer(Modifier.width(4.dp))
                                        Text("学分", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f), modifier = Modifier.padding(bottom = 4.dp))
                                    }
                                    Spacer(Modifier.height(20.dp))
                                    val categories = listOfNotNull(
                                        summary.disciplineCompetitionCredits?.let { "学科竞赛" to it },
                                        summary.scientificResearchCredits?.let { "科学研究" to it },
                                        summary.transferableCompetitionCredits?.let { "可转竞赛" to it },
                                        summary.innovationPracticeCredits?.let { "创新实践" to it },
                                        summary.abilityCertificationCredits?.let { "能力认证" to it },
                                        summary.otherProjectCredits?.let { "其他项目" to it },
                                    )
                                    if (categories.isNotEmpty()) {
                                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            categories.chunked(2).forEach { row ->
                                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    row.forEach { (label, value) ->
                                                        RibbonCard(modifier = Modifier.weight(1f), variant = RibbonCardVariant.SURFACE_CONTAINER, radius = 24.dp, padding = PaddingValues(horizontal = 12.dp, vertical = 10.dp)) {
                                                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                                                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                                                Text("${"%.1f".format(value)}", style = RibbonNumeric.Medium, color = MaterialTheme.colorScheme.primary)
                                                            }
                                                        }
                                                    }
                                                    if (row.size == 1) Spacer(Modifier.weight(1f))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 右栏：获奖项目
                    LazyColumn(
                        Modifier.weight(0.6f),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(bottom = 16.dp),
                    ) {
                        if (data.awards.isNotEmpty()) {
                            item {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    ShapeBadge(shape = RibbonShape.COOKIE_8, size = 44.dp, color = MaterialTheme.colorScheme.tertiaryContainer, icon = Icons.Default.EmojiEvents, iconTint = MaterialTheme.colorScheme.onTertiaryContainer)
                                    Spacer(Modifier.width(12.dp))
                                    Column {
                                        Text("获奖项目", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                        Text("共 ${data.awards.size} 项", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                            items(data.awards, key = { it.projectId }) { award -> LandscapeAwardCard(award) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LandscapeAwardCard(award: AwardProject) {
    var expanded by remember { mutableStateOf(false) }
    val extended = LocalExtendedColors.current
    val statusTone = when {
        award.status.contains("通过") || award.status.contains("认定") -> RibbonTone.SUCCESS
        award.status.contains("审核") || award.status.contains("待") -> RibbonTone.WARNING
        award.status.contains("驳回") || award.status.contains("拒") -> RibbonTone.ERROR
        else -> RibbonTone.NEUTRAL
    }
    RibbonCard(Modifier.fillMaxWidth().animateContentSize(), variant = RibbonCardVariant.SURFACE_LOW, radius = 28.dp, padding = PaddingValues(16.dp)) {
        Column(Modifier.clickable { expanded = !expanded }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(award.projectName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                if (award.status.isNotEmpty()) {
                    RibbonChip(award.status, tone = statusTone)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (award.level.isNotEmpty()) RibbonChip(award.level, tone = RibbonTone.PRIMARY)
                if (award.grade.isNotEmpty()) RibbonChip(award.grade, tone = RibbonTone.SECONDARY)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (award.credits > 0) Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Star, null, modifier = Modifier.size(14.dp), tint = extended.warning); Spacer(Modifier.width(2.dp)); Text("${award.credits} 学分", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (award.awardDate.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.CalendarMonth, null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(2.dp)); Text(award.awardDate, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            if (expanded) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (award.applicantName.isNotEmpty()) Row { Text("申请人", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(72.dp)); Text("${award.applicantName}（${award.applicantId}）", style = MaterialTheme.typography.bodySmall) }
                    if (award.order > 0) Row { Text("排名", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(72.dp)); Text("第 ${award.order} 名", style = MaterialTheme.typography.bodySmall) }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
            }
        }
    }
}
