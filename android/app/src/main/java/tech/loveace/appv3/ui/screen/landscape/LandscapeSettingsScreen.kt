package tech.loveace.appv3.ui.screen.landscape

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import tech.loveace.appv3.R
import tech.loveace.appv3.ui.components.SectionTitle
import tech.loveace.appv3.ui.theme.*
import tech.loveace.appv3.service.CourseNotificationService
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.OtaViewModel
import tech.loveace.appv3.ui.viewmodel.ProfileViewModel
import tech.loveace.appv3.util.AppLogger

/**
 * 横屏设置：左栏用户资料 | 右栏主题+外观+关于
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandscapeSettingsScreen(
    authViewModel: AuthViewModel,
    themeViewModel: ThemeViewModel,
    profileViewModel: ProfileViewModel,
    otaViewModel: OtaViewModel = androidx.lifecycle.viewmodel.compose.viewModel(),
) {
    val authState by authViewModel.uiState.collectAsStateWithLifecycle()
    val themeConfig by themeViewModel.themeConfig.collectAsStateWithLifecycle()
    val profile by profileViewModel.state.collectAsStateWithLifecycle()
    val otaState by otaViewModel.state.collectAsStateWithLifecycle()
    var showNicknameDialog by remember { mutableStateOf(false) }

    val context = LocalContext.current
    var pendingCropUri by remember { mutableStateOf<Uri?>(null) }
    val avatarPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri != null) {
            try { context.contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
            pendingCropUri = uri
        }
    }

    // 头像裁切对话框
    if (pendingCropUri != null) {
        tech.loveace.appv3.ui.components.ImageCropDialog(
            imageUri = pendingCropUri!!,
            cropShape = tech.loveace.appv3.ui.components.CropShape.Circle,
            onCropped = { croppedUri ->
                profileViewModel.setAvatarUri(croppedUri.toString())
                pendingCropUri = null
            },
            onDismiss = { pendingCropUri = null },
        )
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = { Text("我的") })

        Row(
            Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // 左栏：用户资料
            Column(
                Modifier.weight(0.4f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                ElevatedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
                    Column(
                        Modifier.padding(24.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(Modifier.size(102.dp)) {
                            // 大头像
                            Box(
                                Modifier.size(96.dp).clip(CircleShape).clickable { avatarPicker.launch("image/*") },
                                contentAlignment = Alignment.Center,
                            ) {
                                if (profile.avatarUri != null) {
                                    AsyncImage(model = profile.avatarUri, contentDescription = "头像", modifier = Modifier.fillMaxSize().clip(CircleShape), contentScale = ContentScale.Crop)
                                } else {
                                    Image(painter = painterResource(R.drawable.logo), contentDescription = "头像", modifier = Modifier.fillMaxSize().clip(CircleShape), contentScale = ContentScale.Crop)
                                }
                            }
                            // 相机图标 - 置于头像右下外侧
                            Box(Modifier.align(Alignment.BottomEnd).size(28.dp).background(MaterialTheme.colorScheme.primary, CircleShape).clickable { avatarPicker.launch("image/*") }, contentAlignment = Alignment.Center) {
                                Icon(Icons.Default.CameraAlt, null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onPrimary)
                            }
                        }
                        Spacer(Modifier.height(16.dp))
                        Text(
                            profile.nickname.ifEmpty { authState.userId.ifEmpty { "未设置昵称" } },
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(authState.userId, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(12.dp))
                        OutlinedButton(onClick = { showNicknameDialog = true }, shape = MaterialTheme.shapes.large) {
                            Icon(Icons.Default.Edit, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("修改昵称")
                        }
                    }
                }

                // 关于
                Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column(Modifier.padding(20.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Info, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text("彩带小工具 v3", style = MaterialTheme.typography.bodyLarge)
                                Text("v${tech.loveace.appv3.service.OtaService.getCurrentVersion(context)} · Material 3 Expressive", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            FilledTonalButton(
                                onClick = { otaViewModel.checkForUpdate(silent = false) },
                                enabled = !otaState.checking,
                                shape = MaterialTheme.shapes.large,
                            ) {
                                if (otaState.checking) {
                                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                                    Spacer(Modifier.width(6.dp))
                                }
                                Text(if (otaState.checking) "检查中" else "检查更新")
                            }
                        }
                        otaState.noUpdateMessage?.let { msg ->
                            Spacer(Modifier.height(8.dp))
                            Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                            LaunchedEffect(msg) {
                                kotlinx.coroutines.delay(3000)
                                otaViewModel.clearMessage()
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                        Text("❤️ Created By LoveACE Team", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.height(16.dp))
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                        Spacer(Modifier.height(16.dp))
                        Text("赞赏开发者", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.height(4.dp))
                        Text("如果觉得好用，可以请我喝杯咖啡 ☕", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(12.dp))
                        Image(
                            painter = painterResource(R.drawable.mm_reward_qrcode),
                            contentDescription = "赞赏码",
                            modifier = Modifier.fillMaxWidth().aspectRatio(1f).clip(MaterialTheme.shapes.large),
                            contentScale = ContentScale.Fit,
                        )
                    }
                }

                // 日志
                Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Row(Modifier.padding(20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { AppLogger.shareLogFile(context) }, shape = MaterialTheme.shapes.large) {
                            Icon(Icons.Default.Share, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("导出日志")
                        }
                        OutlinedButton(onClick = { AppLogger.clearLogs() }, shape = MaterialTheme.shapes.large) {
                            Icon(Icons.Default.Delete, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("清除日志")
                        }
                    }
                }

                // 退出登录
                FilledTonalButton(
                    onClick = { authViewModel.logout() },
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    colors = ButtonDefaults.filledTonalButtonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Logout, null)
                    Spacer(Modifier.width(8.dp))
                    Text("退出登录")
                }
            }

            // 右栏：主题 + 外观
            Column(
                Modifier.weight(0.6f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // 主题色选择
                SectionTitle("主题颜色")
                Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column(Modifier.padding(20.dp)) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SeedColors.ALL.forEach { option ->
                                val isSelected = themeConfig.seedColorArgb == option.argb
                                Box(
                                    modifier = Modifier.size(48.dp).clip(CircleShape).background(option.color, CircleShape)
                                        .then(if (isSelected) Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape) else Modifier)
                                        .clickable { themeViewModel.setSeedColor(option.argb) },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (isSelected) Icon(Icons.Default.Check, null, tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(22.dp))
                                }
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        val selectedName = SeedColors.ALL.find { it.argb == themeConfig.seedColorArgb }?.name ?: ""
                        Text(selectedName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }

                // 深色模式
                SectionTitle("外观")
                Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("深色模式", style = MaterialTheme.typography.titleSmall)
                        Spacer(Modifier.height(8.dp))
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            val modes = listOf(DarkMode.SYSTEM to "跟随系统", DarkMode.LIGHT to "浅色", DarkMode.DARK to "深色")
                            modes.forEachIndexed { index, (mode, label) ->
                                SegmentedButton(selected = themeConfig.darkMode == mode, onClick = { themeViewModel.setDarkMode(mode) }, shape = SegmentedButtonDefaults.itemShape(index, modes.size)) { Text(label) }
                            }
                        }
                    }
                }

                // 动态取色
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                        Row(Modifier.padding(20.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("壁纸动态取色", style = MaterialTheme.typography.titleSmall)
                                Text("使用系统壁纸颜色（部分ROM不支持）", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Switch(checked = themeConfig.useDynamicColor, onCheckedChange = { themeViewModel.setDynamicColor(it) })
                        }
                    }
                }

                // 常驻通知
                SectionTitle("功能")
                val notifPermissionLauncher = rememberLauncherForActivityResult(
                    ActivityResultContracts.RequestPermission(),
                ) { granted ->
                    if (granted) {
                        themeViewModel.setCourseNotification(true)
                        CourseNotificationService.start(context)
                    }
                }
                Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Row(Modifier.padding(20.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("常驻通知栏课程提示", style = MaterialTheme.typography.titleSmall)
                            Text("在通知栏显示下一节课信息，上课时显示进度", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(
                            checked = themeConfig.courseNotificationEnabled,
                            onCheckedChange = { enabled ->
                                if (enabled) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                                        != PackageManager.PERMISSION_GRANTED
                                    ) {
                                        notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                    } else {
                                        themeViewModel.setCourseNotification(true)
                                        CourseNotificationService.start(context)
                                    }
                                } else {
                                    themeViewModel.setCourseNotification(false)
                                    CourseNotificationService.stop(context)
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    if (showNicknameDialog) {
        var text by remember { mutableStateOf(profile.nickname) }
        AlertDialog(
            onDismissRequest = { showNicknameDialog = false },
            title = { Text("修改昵称") },
            text = { OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("昵称") }, singleLine = true, modifier = Modifier.fillMaxWidth()) },
            confirmButton = { TextButton(onClick = { profileViewModel.setNickname(text); showNicknameDialog = false }) { Text("确定") } },
            dismissButton = { TextButton(onClick = { showNicknameDialog = false }) { Text("取消") } },
        )
    }

    if (otaState.showDialog && otaState.updateInfo != null) {
        tech.loveace.appv3.ui.screen.UpdateDialog(otaState.updateInfo!!, otaViewModel)
    }
}
