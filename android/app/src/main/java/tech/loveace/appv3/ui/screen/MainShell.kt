package tech.loveace.appv3.ui.screen

import android.content.res.Configuration
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage
import tech.loveace.appv3.R
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.ui.navigation.*
import tech.loveace.appv3.ui.screen.landscape.LandscapeShell
import tech.loveace.appv3.ui.theme.ThemeViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.ProfileViewModel

data class BottomNavItem(
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    val route: Any,
    val useAvatar: Boolean = false,
)

/** 横竖屏分流入口 */
@Composable
fun MainShell(
    authViewModel: AuthViewModel,
    themeViewModel: ThemeViewModel,
    onNavigateToDetail: (Any) -> Unit,
    profileViewModel: ProfileViewModel = viewModel(),
    navigateToSchedule: Boolean = false,
    onScheduleNavigated: () -> Unit = {},
) {
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    if (landscape) {
        LandscapeShell(
            authViewModel = authViewModel,
            themeViewModel = themeViewModel,
            profileViewModel = profileViewModel,
            navigateToSchedule = navigateToSchedule,
            onScheduleNavigated = onScheduleNavigated,
        )
    } else {
        LaunchedEffect(navigateToSchedule) {
            if (navigateToSchedule) {
                onScheduleNavigated()
                onNavigateToDetail(ScheduleRoute)
            }
        }
        PortraitShell(
            authViewModel = authViewModel,
            themeViewModel = themeViewModel,
            onNavigateToDetail = onNavigateToDetail,
            profileViewModel = profileViewModel,
        )
    }
}

/** 竖屏：浮动胶囊毛玻璃导航栏 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun PortraitShell(
    authViewModel: AuthViewModel,
    themeViewModel: ThemeViewModel,
    onNavigateToDetail: (Any) -> Unit,
    profileViewModel: ProfileViewModel,
) {
    val navController = rememberNavController()
    val profileState by profileViewModel.state.collectAsStateWithLifecycle()
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()

    // 设置用户隔离存储
    LaunchedEffect(authState.userId) {
        if (authState.userId.isNotEmpty()) {
            profileViewModel.setActiveUserId(authState.userId)
        }
    }

    val navItems = listOf(
        BottomNavItem("首页", Icons.Filled.School, Icons.Outlined.School, HomeRoute),
        BottomNavItem("爱安财", Icons.Filled.VolunteerActivism, Icons.Outlined.VolunteerActivism, AACRoute),
        BottomNavItem("更多", Icons.Filled.MoreHoriz, Icons.Outlined.MoreHoriz, MoreRoute),
        BottomNavItem("我的", Icons.Filled.Person, Icons.Outlined.Person, SettingsRoute, useAvatar = true),
    )
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val pillShape = RoundedCornerShape(50)

    LaunchedEffect(currentRoute) {
        currentRoute?.substringAfterLast('.')?.let { Analytics.trackScreen(it) }
    }

    Box(Modifier.fillMaxSize()) {
        NavHost(
            navController = navController,
            startDestination = HomeRoute,
            modifier = Modifier.fillMaxSize(),
        ) {
            composable<HomeRoute> { HomeScreen(authViewModel, onNavigateToDetail, profileVm = profileViewModel) }
            composable<AACRoute> { AACScreen(authViewModel) }
            composable<MoreRoute> { MoreScreen(onNavigateToDetail) }
            composable<SettingsRoute> {
                SettingsScreen(authViewModel, themeViewModel, profileViewModel = profileViewModel)
            }
        }

        ShortNavigationBar(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 12.dp)
                .clip(pillShape)
                .wrapContentWidth(),
            containerColor = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.92f),
            windowInsets = WindowInsets(0),
        ) {
            navItems.forEach { item ->
                val selected = currentRoute == item.route::class.qualifiedName
                ShortNavigationBarItem(
                    selected = selected,
                    onClick = {
                        navController.navigate(item.route) {
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    icon = {
                        if (item.useAvatar) {
                            AvatarIcon(avatarUri = profileState.avatarUri, size = 24)
                        } else {
                            Icon(if (selected) item.selectedIcon else item.unselectedIcon, item.label)
                        }
                    },
                    label = { Text(item.label) },
                )
            }
        }
    }
}

/** 头像图标：有自定义头像用 AsyncImage，否则用 logo */
@Composable
fun AvatarIcon(avatarUri: String?, size: Int = 24) {
    if (avatarUri != null) {
        AsyncImage(
            model = avatarUri,
            contentDescription = "头像",
            modifier = Modifier.size(size.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
    } else {
        Image(
            painter = painterResource(R.drawable.logo),
            contentDescription = "头像",
            modifier = Modifier.size(size.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
    }
}
