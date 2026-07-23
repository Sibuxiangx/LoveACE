package tech.loveace.appv3.ui.screen.landscape

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import tech.loveace.appv3.R
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.ui.theme.ThemeViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.OtaViewModel
import tech.loveace.appv3.ui.viewmodel.ProfileViewModel

/** 横屏导航项 */
data class LandscapeNavItem(
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    val section: String = "", // 分组标题
    val trackFeature: Boolean = false,
)

/** 横屏主 Shell：左侧固定导航栏 + 右侧内容区 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeShell(
    authViewModel: AuthViewModel,
    themeViewModel: ThemeViewModel,
    otaViewModel: OtaViewModel,
    profileViewModel: ProfileViewModel = viewModel(),
    navigateToSchedule: Boolean = false,
    onScheduleNavigated: () -> Unit = {},
) {
    val profileState by profileViewModel.state.collectAsStateWithLifecycle()
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    var selectedIndex by remember { mutableIntStateOf(if (navigateToSchedule) 4 else 0) }

    LaunchedEffect(navigateToSchedule) {
        if (navigateToSchedule) {
            selectedIndex = 4
            onScheduleNavigated()
        }
    }

    val navItems = listOf(
        LandscapeNavItem("首页", Icons.Filled.School, Icons.Outlined.School, "主要"),
        LandscapeNavItem("爱安财", Icons.Filled.VolunteerActivism, Icons.Outlined.VolunteerActivism),
        LandscapeNavItem("成绩查询", Icons.Filled.Grade, Icons.Outlined.Grade, "教务服务", trackFeature = true),
        LandscapeNavItem("考试安排", Icons.Filled.EventNote, Icons.Outlined.EventNote, trackFeature = true),
        LandscapeNavItem("课程表", Icons.Filled.CalendarMonth, Icons.Outlined.CalendarMonth, trackFeature = true),
        LandscapeNavItem("培养方案", Icons.Filled.MenuBook, Icons.Outlined.MenuBook, trackFeature = true),
        LandscapeNavItem("自动评教", Icons.Filled.RateReview, Icons.Outlined.RateReview, trackFeature = true),
        LandscapeNavItem("一卡通", Icons.Filled.CreditCard, Icons.Outlined.CreditCard, "校园生活", trackFeature = true),
        LandscapeNavItem("电费查询", Icons.Filled.ElectricBolt, Icons.Outlined.ElectricBolt, trackFeature = true),
        LandscapeNavItem("零星维修", Icons.Filled.Build, Icons.Outlined.Build, trackFeature = true),
        LandscapeNavItem("宿舍门卡", Icons.Filled.Key, Icons.Outlined.Key, trackFeature = true),
        LandscapeNavItem("竞赛信息", Icons.Filled.EmojiEvents, Icons.Outlined.EmojiEvents, "素质拓展", trackFeature = true),
        LandscapeNavItem("劳动俱乐部", Icons.Filled.Handshake, Icons.Outlined.Handshake, trackFeature = true),
        LandscapeNavItem("我的", Icons.Filled.Person, Icons.Outlined.Person, "设置"),
    )

    LaunchedEffect(selectedIndex) {
        Analytics.trackScreen(navItems.getOrNull(selectedIndex)?.label ?: "unknown")
    }

    // 设置用户隔离存储
    LaunchedEffect(authState.userId) {
        if (authState.userId.isNotEmpty()) {
            profileViewModel.setActiveUserId(authState.userId)
        }
    }

    PermanentNavigationDrawer(
        drawerContent = {
            PermanentDrawerSheet(
                modifier = Modifier.width(240.dp),
                drawerContainerColor = MaterialTheme.colorScheme.surfaceContainerLow,
            ) {
                // 顶部 Logo + 用户信息
                Column(
                    Modifier.padding(horizontal = 16.dp, vertical = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    // 头像
                    Box(Modifier.size(56.dp).clip(CircleShape)) {
                        if (profileState.avatarUri != null) {
                            AsyncImage(
                                model = profileState.avatarUri,
                                contentDescription = "头像",
                                modifier = Modifier.fillMaxSize().clip(CircleShape),
                                contentScale = ContentScale.Crop,
                            )
                        } else {
                            Image(
                                painter = painterResource(R.drawable.logo),
                                contentDescription = "Logo",
                                modifier = Modifier.fillMaxSize().clip(CircleShape),
                                contentScale = ContentScale.Crop,
                            )
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "彩带小工具",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                    )
                }

                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                Spacer(Modifier.height(8.dp))

                // 导航项列表
                Column(
                    Modifier.verticalScroll(rememberScrollState()).weight(1f),
                ) {
                    navItems.forEachIndexed { index, item ->
                        // 分组标题
                        if (item.section.isNotEmpty()) {
                            if (index > 0) Spacer(Modifier.height(8.dp))
                            Text(
                                item.section,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 28.dp, vertical = 4.dp),
                            )
                        }
                        NavigationDrawerItem(
                            label = { Text(item.label) },
                            icon = {
                                Icon(
                                    if (selectedIndex == index) item.selectedIcon else item.unselectedIcon,
                                    contentDescription = item.label,
                                )
                            },
                            selected = selectedIndex == index,
                            onClick = {
                                if (item.trackFeature) Analytics.trackFeature(item.label)
                                selectedIndex = index
                            },
                            modifier = Modifier.padding(horizontal = 12.dp),
                        )
                    }
                }
            }
        },
    ) {
        // 右侧内容区
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.surface,
        ) {
            when (selectedIndex) {
                0 -> LandscapeHomeScreen(authViewModel, profileViewModel)
                1 -> LandscapeAACScreen(authViewModel)
                2 -> LandscapeScoresScreen(authViewModel)
                3 -> LandscapeExamScreen(authViewModel)
                4 -> LandscapeScheduleScreen(authViewModel)
                5 -> LandscapePlanScreen(authViewModel)
                6 -> LandscapeTeacherEvaluationScreen(authViewModel)
                7 -> LandscapeYKTScreen(authViewModel)
                8 -> LandscapeElectricityScreen(authViewModel)
                9 -> LandscapeRepairScreen(authViewModel)
                10 -> LandscapeDoorCardScreen(authViewModel)
                11 -> LandscapeCompetitionScreen(authViewModel)
                12 -> LandscapeLaborClubScreen(authViewModel, profileViewModel)
                13 -> LandscapeSettingsScreen(
                    authViewModel,
                    themeViewModel,
                    profileViewModel,
                    otaViewModel,
                )
            }
        }
    }
}
