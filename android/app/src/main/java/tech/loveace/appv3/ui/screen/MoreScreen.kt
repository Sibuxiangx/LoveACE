package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonShape
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.md3e.ShapeBadge
import tech.loveace.appv3.ui.md3e.ribbonToneColors
import tech.loveace.appv3.ui.navigation.*
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.ui.Alignment

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoreScreen(onNavigateToDetail: (Any) -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text("更多功能") }) }) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // 教务服务
            RibbonSectionTitle("教务服务", modifier = Modifier.padding(top = 14.dp))
            FeatureGrid(ACADEMIC_TILES, onNavigateToDetail)

            // 校园生活
            RibbonSectionTitle("校园生活", modifier = Modifier.padding(top = 14.dp))
            FeatureGrid(CAMPUS_TILES, onNavigateToDetail)

            // 素质拓展
            RibbonSectionTitle("素质拓展", modifier = Modifier.padding(top = 14.dp))
            FeatureGrid(QUALITY_TILES, onNavigateToDetail)

            Spacer(Modifier.height(12.dp))
        }
    }
}

private fun navigateFeature(feature: String, route: Any, onNavigateToDetail: (Any) -> Unit) {
    Analytics.trackFeature(feature)
    onNavigateToDetail(route)
}

private data class FeatureTile(
    val feature: String,
    val icon: ImageVector,
    val title: String,
    val subtitle: String,
    val tone: RibbonTone,
    val shape: RibbonShape,
    val route: Any,
)

// 教务服务：成绩(主) / 考试(次) / 课表(次) / 培养(三) / 评教(主)；相邻 tile 花形不同
private val ACADEMIC_TILES = listOf(
    FeatureTile("成绩查询", Icons.Default.Grade, "成绩查询", "各学期成绩与绩点", RibbonTone.PRIMARY, RibbonShape.COOKIE_8, ScoresRoute),
    FeatureTile("考试安排", Icons.Default.EventNote, "考试安排", "时间、地点和倒计时", RibbonTone.SECONDARY, RibbonShape.CLOVER_4, ExamRoute),
    FeatureTile("课表查询", Icons.Default.CalendarMonth, "我的课表", "按天查看课程", RibbonTone.SECONDARY, RibbonShape.PEBBLE_3, ScheduleRoute),
    FeatureTile("培养方案", Icons.AutoMirrored.Filled.MenuBook, "培养方案", "学分与课程完成度", RibbonTone.TERTIARY, RibbonShape.COOKIE_6, PlanRoute),
    FeatureTile("自动教师评价", Icons.Default.RateReview, "自动评教", "批量完成教务系统教师评价", RibbonTone.PRIMARY, RibbonShape.FLOWER_5, TeacherEvaluationRoute),
)

// 校园生活
private val CAMPUS_TILES = listOf(
    FeatureTile("零星维修", Icons.Default.Build, "零星维修", "报修和查看维修进度", RibbonTone.TERTIARY, RibbonShape.COOKIE_8, RepairRoute),
    FeatureTile("一卡通", Icons.Default.CreditCard, "一卡通", "余额查询和消费记录", RibbonTone.PRIMARY, RibbonShape.CLOVER_4, YKTRoute),
    FeatureTile("电费查询", Icons.Default.ElectricBolt, "电费查询", "宿舍电费余额和用电记录", RibbonTone.SECONDARY, RibbonShape.COOKIE_6, ElectricityRoute),
)

// 素质拓展
private val QUALITY_TILES = listOf(
    FeatureTile("竞赛信息", Icons.Default.EmojiEvents, "竞赛获奖", "获奖记录与学分", RibbonTone.TERTIARY, RibbonShape.COOKIE_8, CompetitionRoute),
    FeatureTile("劳动俱乐部", Icons.Default.Handshake, "劳动俱乐部", "劳动教育进度", RibbonTone.PRIMARY, RibbonShape.PEBBLE_3, LaborClubRoute),
)

/** 两列交错网格（对齐小程序 tab-menu）：左右两列各自纵向排列 */
@Composable
private fun FeatureGrid(tiles: List<FeatureTile>, onNavigateToDetail: (Any) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            tiles.filterIndexed { index, _ -> index % 2 == 0 }
                .forEach { FeatureTileCell(it, onNavigateToDetail) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            tiles.filterIndexed { index, _ -> index % 2 == 1 }
                .forEach { FeatureTileCell(it, onNavigateToDetail) }
        }
    }
}

/** 菜单 tile：花形徽章 + 标题 + 两行副标题，紧凑 24dp 圆角，按压 morph */
@Composable
private fun FeatureTileCell(tile: FeatureTile, onNavigateToDetail: (Any) -> Unit) {
    val (badgeBg, badgeFg) = ribbonToneColors(tile.tone)
    RibbonCard(
        modifier = Modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 24.dp,
        padding = PaddingValues(16.dp),
        interactive = true,
        onClick = { navigateFeature(tile.feature, tile.route, onNavigateToDetail) },
    ) {
        ShapeBadge(
            shape = tile.shape,
            size = 46.dp,
            color = badgeBg,
            icon = tile.icon,
            iconTint = badgeFg,
            iconSizeFraction = 0.5f,
        )
        Spacer(Modifier.height(10.dp))
        Text(tile.title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(2.dp))
        Text(
            tile.subtitle,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            minLines = 1,
        )
    }
}
