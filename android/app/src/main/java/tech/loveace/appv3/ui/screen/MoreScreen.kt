package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.ui.components.SectionTitle
import tech.loveace.appv3.ui.navigation.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoreScreen(onNavigateToDetail: (Any) -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text("更多功能") }) }) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 教务服务
            SectionTitle("教务服务")
            FeatureGroupCard {
                FeatureListItem(
                    icon = Icons.Default.Grade,
                    title = "成绩查询",
                    subtitle = "查看各学期课程成绩",
                    iconColor = MaterialTheme.colorScheme.primary,
                    iconBg = MaterialTheme.colorScheme.primaryContainer,
                    onClick = { navigateFeature("成绩查询", ScoresRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.EventNote,
                    title = "考试安排",
                    subtitle = "查看考试时间和地点",
                    iconColor = MaterialTheme.colorScheme.secondary,
                    iconBg = MaterialTheme.colorScheme.secondaryContainer,
                    onClick = { navigateFeature("考试安排", ExamRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.CalendarMonth,
                    title = "课表查询",
                    subtitle = "查看学期课程安排",
                    iconColor = MaterialTheme.colorScheme.secondary,
                    iconBg = MaterialTheme.colorScheme.secondaryContainer,
                    onClick = { navigateFeature("课表查询", ScheduleRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.AutoMirrored.Filled.MenuBook,
                    title = "培养方案",
                    subtitle = "查看专业培养计划完成情况",
                    iconColor = MaterialTheme.colorScheme.tertiary,
                    iconBg = MaterialTheme.colorScheme.tertiaryContainer,
                    onClick = { navigateFeature("培养方案", PlanRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.RateReview,
                    title = "自动教师评价",
                    subtitle = "批量完成教务系统教师评价",
                    iconColor = MaterialTheme.colorScheme.primary,
                    iconBg = MaterialTheme.colorScheme.primaryContainer,
                    onClick = { navigateFeature("自动教师评价", TeacherEvaluationRoute, onNavigateToDetail) },
                )
            }

            // 校园生活
            SectionTitle("校园生活")
            FeatureGroupCard {
                FeatureListItem(
                    icon = Icons.Default.Build,
                    title = "零星维修",
                    subtitle = "报修和查看维修进度",
                    iconColor = MaterialTheme.colorScheme.tertiary,
                    iconBg = MaterialTheme.colorScheme.tertiaryContainer,
                    onClick = { navigateFeature("零星维修", RepairRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.CreditCard,
                    title = "一卡通",
                    subtitle = "余额查询和消费记录",
                    iconColor = MaterialTheme.colorScheme.primary,
                    iconBg = MaterialTheme.colorScheme.primaryContainer,
                    onClick = { navigateFeature("一卡通", YKTRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.ElectricBolt,
                    title = "电费查询",
                    subtitle = "宿舍电费余额和用电记录",
                    iconColor = MaterialTheme.colorScheme.secondary,
                    iconBg = MaterialTheme.colorScheme.secondaryContainer,
                    onClick = { navigateFeature("电费查询", ElectricityRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.Key,
                    title = "宿舍门卡",
                    subtitle = "蓝牙开门和门卡管理",
                    iconColor = MaterialTheme.colorScheme.tertiary,
                    iconBg = MaterialTheme.colorScheme.tertiaryContainer,
                    onClick = { navigateFeature("宿舍门卡", DoorCardRoute, onNavigateToDetail) },
                )
            }


            // 素质拓展
            SectionTitle("素质拓展")
            FeatureGroupCard {
                FeatureListItem(
                    icon = Icons.Default.EmojiEvents,
                    title = "竞赛信息",
                    subtitle = "学科竞赛获奖和学分",
                    iconColor = MaterialTheme.colorScheme.tertiary,
                    iconBg = MaterialTheme.colorScheme.tertiaryContainer,
                    onClick = { navigateFeature("竞赛信息", CompetitionRoute, onNavigateToDetail) },
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                FeatureListItem(
                    icon = Icons.Default.Handshake,
                    title = "劳动俱乐部",
                    subtitle = "劳动教育活动和签到",
                    iconColor = MaterialTheme.colorScheme.primary,
                    iconBg = MaterialTheme.colorScheme.primaryContainer,
                    onClick = { navigateFeature("劳动俱乐部", LaborClubRoute, onNavigateToDetail) },
                )
            }
        }
    }
}

private fun navigateFeature(feature: String, route: Any, onNavigateToDetail: (Any) -> Unit) {
    Analytics.trackFeature(feature)
    onNavigateToDetail(route)
}

/** 分组卡片容器 */
@Composable
private fun FeatureGroupCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(content = content)
    }
}

/** 单个功能 ListItem */
@Composable
private fun FeatureListItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    iconColor: Color,
    iconBg: Color,
    onClick: () -> Unit,
) {
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        leadingContent = {
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(iconBg),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, null, modifier = Modifier.size(20.dp), tint = iconColor)
            }
        },
        trailingContent = {
            Icon(
                Icons.Default.ChevronRight, null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
