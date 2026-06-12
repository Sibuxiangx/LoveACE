package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.R
import tech.loveace.appv3.data.model.UserCredentials
import tech.loveace.appv3.ui.viewmodel.AuthState
import tech.loveace.appv3.ui.viewmodel.AuthUiState

/**
 * 横屏登录页：左侧品牌区 + 右侧表单/快速登录区
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun LandscapeLoginScreen(
    uiState: AuthUiState,
    rememberedCredentials: UserCredentials?,
    onLogin: (userId: String, ecPassword: String, password: String) -> Unit,
    onQuickLogin: () -> Unit,
    onSwitchUser: () -> Unit,
) {
    var showManualLogin by remember { mutableStateOf(rememberedCredentials == null) }
    val isLoading = uiState.state == AuthState.Loading

    LaunchedEffect(uiState.state) {
        if (uiState.state == AuthState.Error && !showManualLogin) {
            showManualLogin = true
        }
    }

    val enterTransition = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        enterTransition.animateTo(1f, animationSpec = tween(600, easing = EaseOutCubic))
    }

    Surface(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxSize()) {
            // ── 左侧品牌区 ──
            Box(
                modifier = Modifier.weight(0.4f).fillMaxHeight().padding(32.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Image(
                        painter = painterResource(R.drawable.logo),
                        contentDescription = "Logo",
                        modifier = Modifier.size(120.dp).clip(CircleShape).scale(enterTransition.value),
                        contentScale = ContentScale.Crop,
                    )
                    Spacer(Modifier.height(24.dp))
                    Text("彩带小工具", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text("安徽财经大学学生工具", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(32.dp))
                    Text("❤ Created By LoveACE Team", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                }
            }

            // ── 右侧区域 ──
            Box(
                modifier = Modifier.weight(0.6f).fillMaxHeight().padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (!showManualLogin && rememberedCredentials != null) {
                    // 快速登录
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("欢迎回来", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(8.dp))
                        Text(rememberedCredentials.userId, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(48.dp))
                        LandscapeTelemetryNotice()
                        Spacer(Modifier.height(16.dp))

                        if (isLoading) {
                            CircularWavyProgressIndicator(modifier = Modifier.size(64.dp))
                            Spacer(Modifier.height(20.dp))
                            Text("快速登录中...", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } else {
                            Button(
                                onClick = onQuickLogin,
                                modifier = Modifier.widthIn(max = 300.dp).fillMaxWidth().height(52.dp),
                                shape = MaterialTheme.shapes.extraLarge,
                            ) {
                                Icon(Icons.Default.Login, null, modifier = Modifier.size(20.dp))
                                Spacer(Modifier.width(8.dp))
                                Text("快速登录", style = MaterialTheme.typography.titleMedium)
                            }
                        }

                        Spacer(Modifier.height(16.dp))
                        TextButton(onClick = { onSwitchUser(); showManualLogin = true }, enabled = !isLoading) {
                            Icon(Icons.Default.SwitchAccount, null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("切换用户")
                        }
                    }
                } else {
                    // 手动登录表单
                    LandscapeManualLoginForm(
                        uiState = uiState,
                        initialUserId = rememberedCredentials?.userId ?: "",
                        initialEcPassword = rememberedCredentials?.ecPassword ?: "",
                        initialPassword = rememberedCredentials?.password ?: "",
                        isLoading = isLoading,
                        onLogin = onLogin,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun LandscapeManualLoginForm(
    uiState: AuthUiState,
    initialUserId: String,
    initialEcPassword: String,
    initialPassword: String,
    isLoading: Boolean,
    onLogin: (userId: String, ecPassword: String, password: String) -> Unit,
) {
    var userId by remember { mutableStateOf(initialUserId) }
    var ecPassword by remember { mutableStateOf(initialEcPassword) }
    var password by remember { mutableStateOf(initialPassword) }
    var showEcPwd by remember { mutableStateOf(false) }
    var showPwd by remember { mutableStateOf(false) }
    var showPasswordHelp by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current

    Column(
        modifier = Modifier.widthIn(max = 420.dp).verticalScroll(rememberScrollState()).imePadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("登录", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(24.dp))

        ElevatedCard(modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge) {
            Column(Modifier.padding(horizontal = 24.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedTextField(
                    value = userId, onValueChange = { userId = it },
                    label = { Text("学号") }, leadingIcon = { Icon(Icons.Default.Person, null) },
                    singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
                    enabled = !isLoading,
                )
                OutlinedTextField(
                    value = ecPassword, onValueChange = { ecPassword = it },
                    label = { Text("VPN密码") }, leadingIcon = { Icon(Icons.Default.VpnKey, null) },
                    trailingIcon = { IconButton(onClick = { showEcPwd = !showEcPwd }) { Icon(if (showEcPwd) Icons.Default.VisibilityOff else Icons.Default.Visibility, "切换可见") } },
                    visualTransformation = if (showEcPwd) VisualTransformation.None else PasswordVisualTransformation(),
                    singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
                    enabled = !isLoading,
                )
                OutlinedTextField(
                    value = password, onValueChange = { password = it },
                    label = { Text("教务密码") }, leadingIcon = { Icon(Icons.Default.Lock, null) },
                    trailingIcon = { IconButton(onClick = { showPwd = !showPwd }) { Icon(if (showPwd) Icons.Default.VisibilityOff else Icons.Default.Visibility, "切换可见") } },
                    visualTransformation = if (showPwd) VisualTransformation.None else PasswordVisualTransformation(),
                    singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = {
                        focusManager.clearFocus()
                        if (userId.isNotBlank() && ecPassword.isNotBlank() && password.isNotBlank())
                            onLogin(userId, ecPassword, password)
                    }),
                    enabled = !isLoading,
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        LandscapeTelemetryNotice()

        Spacer(Modifier.height(12.dp))

        val canLogin = !isLoading && userId.isNotBlank() && ecPassword.isNotBlank() && password.isNotBlank()
        Button(
            onClick = { onLogin(userId, ecPassword, password) },
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = MaterialTheme.shapes.extraLarge, enabled = canLogin,
        ) {
            if (isLoading) {
                CircularWavyProgressIndicator(modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text("登录中...")
            } else {
                Text("登录", style = MaterialTheme.typography.titleMedium)
            }
        }

        AnimatedVisibility(
            visible = uiState.errorMessage != null,
            enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically(),
        ) {
            Card(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            ) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Warning, null, tint = MaterialTheme.colorScheme.onErrorContainer)
                    Spacer(Modifier.width(12.dp))
                    Text(uiState.errorMessage ?: "", color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        TextButton(onClick = { showPasswordHelp = true }) {
            Icon(Icons.Default.HelpOutline, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("不知道密码是什么？")
        }
    }

    if (showPasswordHelp) {
        LandscapePasswordHelpDialog(onDismiss = { showPasswordHelp = false })
    }
}

@Composable
private fun LandscapeTelemetryNotice() {
    Text(
        "登录即表示同意上传匿名使用统计（本地随机 ID、学号前四位与加盐哈希、版本和基础设备信息），不会上传密码、完整学号或业务内容。",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun LandscapePasswordHelpDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Default.HelpOutline, null) },
        title = { Text("密码说明") },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.VpnKey, null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text("VPN密码（EasyConnect）", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Text("用于连接校园VPN的密码", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Lock, null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text("教务密码（UAAP）", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Text("用于登录教务系统等校内服务的密码", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)),
                    shape = MaterialTheme.shapes.large,
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
                        Icon(Icons.Default.Info, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("如果没有修改过密码，默认密码通常是身份证后六位。", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("我知道了") } },
    )
}
