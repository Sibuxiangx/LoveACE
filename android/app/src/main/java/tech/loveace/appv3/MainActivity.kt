package tech.loveace.appv3

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.launch
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.ui.navigation.*
import tech.loveace.appv3.ui.screen.*
import tech.loveace.appv3.ui.screen.landscape.LandscapeLoginScreen
import tech.loveace.appv3.ui.theme.RibbonTheme
import tech.loveace.appv3.ui.theme.ThemeViewModel
import tech.loveace.appv3.ui.viewmodel.AuthState
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.service.CourseNotificationService
import tech.loveace.appv3.ui.screen.UpdateDialog
import tech.loveace.appv3.ui.viewmodel.OtaViewModel
import tech.loveace.appv3.util.AppLogger
import tech.loveace.appv3.widget.WidgetSyncHelper

class MainActivity : FragmentActivity() {
    val pendingWidgetNav = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        AppLogger.init(this)
        Analytics.init(this)
        Analytics.trackAppStart(if (intent?.getStringExtra("navigate_to") != null) "widget" else "launcher")
        handleWidgetIntent(intent)

        // 请求设备支持的最高刷新率（120Hz / 90Hz 等）
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            display?.supportedModes
                ?.maxByOrNull { it.refreshRate }
                ?.let { preferredMode ->
                    window.attributes = window.attributes.also {
                        it.preferredDisplayModeId = preferredMode.modeId
                    }
                }
        } else {
            window.attributes = window.attributes.also {
                it.preferredRefreshRate = 120f
            }
        }

        setContent {
            val themeViewModel: ThemeViewModel = viewModel()
            RibbonTheme(themeViewModel) {
                RibbonApp(themeViewModel = themeViewModel)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        intent?.getStringExtra("navigate_to")?.let {
            pendingWidgetNav.value = it
        }
    }
}

@Composable
fun RibbonApp(
    authViewModel: AuthViewModel = viewModel(),
    themeViewModel: ThemeViewModel = viewModel(),
    otaViewModel: OtaViewModel = viewModel(),
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val otaState by otaViewModel.state.collectAsStateWithLifecycle()
    val navController = rememberNavController()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val activity = context as? MainActivity
    val widgetNavTarget by (activity?.pendingWidgetNav ?: remember { mutableStateOf(null) })
    var widgetScheduleNav by remember { mutableStateOf(false) }

    // Silent OTA check on launch
    LaunchedEffect(Unit) { otaViewModel.checkForUpdate(silent = true) }

    if (!otaState.startupCheckComplete) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator()
        }
        return
    }

    LaunchedEffect(Unit) { authViewModel.restoreSession() }

    // Global announcement/update host. The ViewModel enforces force OTA -> announcement -> optional OTA.
    if (otaState.showAnnouncementDialog && otaState.announcement != null) {
        AnnouncementDialog(otaState.announcement!!, otaViewModel)
    } else if (otaState.showUpdateDialog && otaState.updateInfo != null) {
        UpdateDialog(otaState.updateInfo!!, otaViewModel)
    }

    // 登录成功后立即同步 widget 数据
    LaunchedEffect(authState.state) {
        when (authState.state) {
            AuthState.Authenticated -> {
                val navTarget = widgetNavTarget
                navController.navigate(MainRoute) {
                    popUpTo(0) { inclusive = true }
                }
                if (navTarget == "schedule") {
                    activity?.pendingWidgetNav?.value = null
                    activity?.intent?.removeExtra("navigate_to")
                    widgetScheduleNav = true
                }
                scope.launch {
                    WidgetSyncHelper.syncWidgetDataIfNeeded(
                        context = context,
                        jwcService = authViewModel.jwcService,
                        scheduleService = authViewModel.studentScheduleService,
                    )
                }
            }
            AuthState.Unauthenticated, AuthState.Error -> {
                navController.navigate(LoginRoute) {
                    popUpTo(0) { inclusive = true }
                }
            }
            else -> {}
        }
    }

    // 处理 onNewIntent：App 已在前台且已登录时，点击小组件直接跳转
    LaunchedEffect(widgetNavTarget) {
        if (widgetNavTarget == "schedule" && authState.state == AuthState.Authenticated) {
            activity?.pendingWidgetNav?.value = null
            activity?.intent?.removeExtra("navigate_to")
            widgetScheduleNav = true
        }
    }

    // 每次 App 进入前台时刷新 widget
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            Log.d("MainActivity", "App resumed, refreshing widgets")
            if (authState.state == AuthState.Authenticated) {
                WidgetSyncHelper.syncWidgetDataIfNeeded(
                    context = context,
                    jwcService = authViewModel.jwcService,
                    scheduleService = authViewModel.studentScheduleService,
                )
            }
        }
    }

    // 常驻通知服务：根据设置项启停
    val themeConfig by themeViewModel.themeConfig.collectAsStateWithLifecycle()
    LaunchedEffect(themeConfig.courseNotificationEnabled) {
        if (themeConfig.courseNotificationEnabled) {
            CourseNotificationService.start(context)
        } else {
            CourseNotificationService.stop(context)
        }
    }

    // 初始显示 Splash（加载中），根据认证结果导航
    val startDest: Any = SplashRoute

    NavHost(navController = navController, startDestination = startDest) {
        composable<SplashRoute> {
            // 简单的启动加载页
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Image(
                        painter = painterResource(R.drawable.logo),
                        contentDescription = null,
                        modifier = Modifier.size(80.dp),
                    )
                    Spacer(Modifier.height(24.dp))
                    AppCircularProgressIndicator(
                        modifier = Modifier.size(48.dp),
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "正在连接...",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        composable<LoginRoute> {
            val remembered = authViewModel.getRememberedCredentials()
            val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
            
            if (isLandscape) {
                LandscapeLoginScreen(
                    uiState = authState,
                    rememberedCredentials = remembered,
                    onLogin = { uid, ec, pwd -> authViewModel.login(uid, ec, pwd) },
                    onQuickLogin = { authViewModel.restoreSession() },
                    onSwitchUser = { authViewModel.clearSavedCredentials() },
                )
            } else {
                LoginScreen(
                    uiState = authState,
                    rememberedCredentials = remembered,
                    onLogin = { uid, ec, pwd -> authViewModel.login(uid, ec, pwd) },
                    onQuickLogin = { authViewModel.restoreSession() },
                    onSwitchUser = { authViewModel.clearSavedCredentials() },
                )
            }
        }

        composable<MainRoute> {
            MainShell(
                authViewModel = authViewModel,
                themeViewModel = themeViewModel,
                otaViewModel = otaViewModel,
                onNavigateToDetail = { route -> navController.navigate(route) },
                navigateToSchedule = widgetScheduleNav,
                onScheduleNavigated = { widgetScheduleNav = false },
            )
        }

        composable<ScoresRoute> {
            ScoresScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<ExamRoute> {
            ExamScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<YKTRoute> {
            YKTScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<ElectricityRoute> {
            ElectricityScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<CompetitionRoute> {
            CompetitionScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<LaborClubRoute> {
            LaborClubScreen(
                authViewModel,
                onBack = { navController.popBackStack() },
                onNavigateToScan = { navController.navigate(QRScanRoute) },
            )
        }
        composable<ScheduleRoute> {
            ScheduleScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<PlanRoute> {
            PlanScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<RepairRoute> {
            RepairScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<DoorCardRoute> {
            DoorCardScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<TeacherEvaluationRoute> {
            TeacherEvaluationScreen(authViewModel, onBack = { navController.popBackStack() })
        }
        composable<QRScanRoute> {
            val parentEntry = remember(it) { navController.getBackStackEntry(LaborClubRoute) }
            val laborVm: tech.loveace.appv3.ui.viewmodel.LaborClubViewModel = viewModel(parentEntry)
            QRScanScreen(
                onBack = { navController.popBackStack() },
                onScanned = { qrData ->
                    laborVm.scanSignIn(qrData)
                    navController.popBackStack()
                },
            )
        }
    }
}
