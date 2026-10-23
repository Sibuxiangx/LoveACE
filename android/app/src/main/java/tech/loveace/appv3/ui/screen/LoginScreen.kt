package tech.loveace.appv3.ui.screen

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import tech.loveace.appv3.ui.components.*
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
import androidx.compose.ui.unit.sp
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.input.KeyboardCapitalization
import kotlinx.coroutines.delay
import tech.loveace.appv3.R
import tech.loveace.appv3.data.model.UserCredentials
import tech.loveace.appv3.util.describeFullWidthChars
import tech.loveace.appv3.util.hasFullWidthChars
import tech.loveace.appv3.ui.md3e.*
import tech.loveace.appv3.ui.viewmodel.AuthState
import tech.loveace.appv3.ui.viewmodel.AuthUiState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    uiState: AuthUiState,
    rememberedCredentials: UserCredentials?,
    onLogin: (userId: String, ecPassword: String, password: String, captchaCode: String?) -> Unit,
    onUserIdChanged: (userId: String) -> Unit,
    onQuickLogin: () -> Unit,
    onSwitchUser: () -> Unit,
    onDismissPasswordChange: () -> Unit = {},
) {
    // 是否有已保存的凭证（可快速登录）
    var showManualLogin by remember { mutableStateOf(rememberedCredentials == null || uiState.errorMessage != null) }
    val isLoading = uiState.state == AuthState.Loading

    // 如果有保存凭证且出错了（含需要重新登录的提示），自动切到手动登录
    LaunchedEffect(uiState.state, uiState.errorMessage) {
        if ((uiState.state == AuthState.Error || uiState.errorMessage != null) && !showManualLogin) {
            showManualLogin = true
        }
    }

    val enterTransition = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        enterTransition.animateTo(1f, animationSpec = tween(600, easing = EaseOutCubic))
    }

    Surface(Modifier.fillMaxSize()) {
        if (!showManualLogin && rememberedCredentials != null) {
            // ── 快速登录界面 ──
            QuickLoginView(
                userId = rememberedCredentials.userId,
                isLoading = isLoading,
                enterScale = enterTransition.value,
                onQuickLogin = onQuickLogin,
                onSwitchUser = {
                    onSwitchUser()
                    showManualLogin = true
                },
            )
        } else {
            // ── 手动登录表单 ──
            ManualLoginView(
                uiState = uiState,
                initialUserId = rememberedCredentials?.userId ?: "",
                initialEcPassword = rememberedCredentials?.ecPassword ?: "",
                initialPassword = rememberedCredentials?.password ?: "",
                isLoading = isLoading,
                enterScale = enterTransition.value,
                onLogin = onLogin,
                onUserIdChanged = onUserIdChanged,
            )
        }
    }

    // 学校强制改密拦截提示（不是密码错误）
    if (uiState.passwordChangeRequired) {
        PasswordChangeRequiredDialog(onDismiss = onDismissPasswordChange)
    }
}


@Composable
private fun QuickLoginView(
    userId: String,
    isLoading: Boolean,
    enterScale: Float,
    onQuickLogin: () -> Unit,
    onSwitchUser: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        ShapeBadge(
            shape = RibbonShape.COOKIE_8,
            size = 100.dp,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier.scale(enterScale),
        ) {
            Image(
                painter = painterResource(R.drawable.logo),
                contentDescription = "Logo",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        }
        Spacer(Modifier.height(24.dp))
        Text("彩带小工具", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text(
            "欢迎回来，$userId",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))
        PreloginNoticeCard()
        Spacer(Modifier.height(28.dp))
        TelemetryNotice()
        Spacer(Modifier.height(16.dp))

        if (isLoading) {
            AppCircularProgressIndicator(modifier = Modifier.size(64.dp))
            Spacer(Modifier.height(20.dp))
            Text("快速登录中...", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            Button(
                onClick = onQuickLogin,
                modifier = Modifier.fillMaxWidth(0.7f).height(56.dp),
                shape = MaterialTheme.shapes.extraLarge,
            ) {
                Icon(Icons.Default.Login, null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("快速登录", style = MaterialTheme.typography.titleMedium)
            }
        }

        Spacer(Modifier.height(16.dp))
        TextButton(onClick = onSwitchUser, enabled = !isLoading) {
            Icon(Icons.Default.SwitchAccount, null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("切换用户")
        }

        Spacer(Modifier.height(48.dp))
        Text(
            "❤ Created By LoveACE Team",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ManualLoginView(
    uiState: AuthUiState,
    initialUserId: String,
    initialEcPassword: String,
    initialPassword: String,
    isLoading: Boolean,
    enterScale: Float,
    onLogin: (userId: String, ecPassword: String, password: String, captchaCode: String?) -> Unit,
    onUserIdChanged: (userId: String) -> Unit,
) {
    var userId by remember { mutableStateOf(initialUserId) }
    var ecPassword by remember { mutableStateOf(initialEcPassword) }
    var password by remember { mutableStateOf(initialPassword) }
    var captchaInput by remember { mutableStateOf("") }
    var showEcPwd by remember { mutableStateOf(false) }
    var showPwd by remember { mutableStateOf(false) }
    var showPasswordHelp by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    // VPN密码默认与教务密码相同：仅当保存过的密码确实不同时，才默认展开高级选项
    val savedSeparatePwd = initialEcPassword.isNotEmpty() && initialEcPassword != initialPassword
    var useSeparatePwd by remember { mutableStateOf(savedSeparatePwd) }
    var showAdvanced by remember { mutableStateOf(savedSeparatePwd) }
    val effectiveEcPassword = if (useSeparatePwd) ecPassword else password
    // 全角字符校验：中文输入法容易混入全角数字/字母/标点，教务系统只认半角
    val fullWidthHint = when {
        hasFullWidthChars(userId) -> "学号含全角字符 ${describeFullWidthChars(userId)}，请切换为英文半角输入"
        hasFullWidthChars(password) -> "教务密码含全角字符 ${describeFullWidthChars(password)}，请切换为英文半角输入"
        useSeparatePwd && hasFullWidthChars(ecPassword) -> "VPN密码含全角字符 ${describeFullWidthChars(ecPassword)}，请切换为英文半角输入"
        else -> null
    }
    // 验证码：仅当学校要求（已有图片）时生效；去掉首尾空白后必须非空且不含全角字符
    val captchaCode = if (uiState.captchaImage != null) captchaInput.trim() else null
    val captchaOk = captchaCode == null || (captchaCode.isNotEmpty() && !hasFullWidthChars(captchaCode))
    // 冷却期内禁用登录按钮（不触网），剩余秒数每秒刷新
    val cooldownSec = rememberLoginCooldownSeconds(uiState.cooldownUntil)
    val canLogin = !isLoading && cooldownSec == 0L && fullWidthHint == null && userId.isNotBlank() && password.isNotBlank() && (!useSeparatePwd || ecPassword.isNotBlank()) && captchaOk

    // 学号变化：清除验证码状态，并载入该学号的冷却
    LaunchedEffect(userId) { onUserIdChanged(userId) }
    // 每张新图片（首次获取、点击刷新、验证码错误后重取）都清空已输入的验证码
    LaunchedEffect(uiState.captchaImage) { captchaInput = "" }

    fun tryLogin() {
        focusManager.clearFocus()
        if (canLogin) onLogin(userId, effectiveEcPassword, password, captchaCode)
    }

    Column(
        modifier = Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(72.dp))

        ShapeBadge(
            shape = RibbonShape.COOKIE_8,
            size = 88.dp,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier.scale(enterScale),
        ) {
            Image(
                painter = painterResource(R.drawable.logo),
                contentDescription = "Logo",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        }
        Spacer(Modifier.height(16.dp))
        Text("彩带小工具", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        Text("安徽财经大学学生工具", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))
        PreloginNoticeCard()
        Spacer(Modifier.height(20.dp))

        ElevatedCard(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(32.dp)) {
            Column(Modifier.padding(horizontal = 20.dp, vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedTextField(
                    value = userId, onValueChange = { userId = it },
                    label = { Text("学号") }, leadingIcon = { Icon(Icons.Default.Person, null) },
                    singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
                    enabled = !isLoading,
                    isError = hasFullWidthChars(userId),
                    supportingText = {
                        if (hasFullWidthChars(userId)) Text("含全角字符 ${describeFullWidthChars(userId)}，请用英文半角", fontSize = 12.sp)
                    },
                )
                OutlinedTextField(
                    value = password, onValueChange = { password = it },
                    label = { Text("教务密码") }, leadingIcon = { Icon(Icons.Default.Lock, null) },
                    trailingIcon = { IconButton(onClick = { showPwd = !showPwd }) { Icon(if (showPwd) Icons.Default.VisibilityOff else Icons.Default.Visibility, "切换可见") } },
                    visualTransformation = if (showPwd) VisualTransformation.None else PasswordVisualTransformation(),
                    singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { tryLogin() }),
                    enabled = !isLoading,
                    isError = hasFullWidthChars(password),
                    supportingText = {
                        if (hasFullWidthChars(password)) Text("含全角字符 ${describeFullWidthChars(password)}，请用英文半角", fontSize = 12.sp)
                    },
                )
                uiState.captchaImage?.let { image ->
                    CaptchaField(
                        image = image,
                        value = captchaInput,
                        onValueChange = { captchaInput = it },
                        onRefresh = { onLogin(userId, effectiveEcPassword, password, null) },
                        enabled = !isLoading,
                        refreshEnabled = !isLoading && cooldownSec == 0L,
                    )
                }
                // ── 高级选项：VPN密码默认与教务密码相同，默认折叠 ──
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(MaterialTheme.shapes.large)
                        .clickable { showAdvanced = !showAdvanced }
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Default.Tune, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "高级选项",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        if (showAdvanced) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        contentDescription = if (showAdvanced) "收起高级选项" else "展开高级选项",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                AnimatedVisibility(
                    visible = showAdvanced,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut(),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "我的网关密码和教务密码不一样",
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.weight(1f),
                            )
                            Switch(checked = useSeparatePwd, onCheckedChange = { useSeparatePwd = it }, enabled = !isLoading)
                        }
                        if (useSeparatePwd) {
                            OutlinedTextField(
                                value = ecPassword, onValueChange = { ecPassword = it },
                                label = { Text("VPN密码") }, leadingIcon = { Icon(Icons.Default.VpnKey, null) },
                                trailingIcon = { IconButton(onClick = { showEcPwd = !showEcPwd }) { Icon(if (showEcPwd) Icons.Default.VisibilityOff else Icons.Default.Visibility, "切换可见") } },
                                visualTransformation = if (showEcPwd) VisualTransformation.None else PasswordVisualTransformation(),
                                singleLine = true, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                                keyboardActions = KeyboardActions(onDone = { tryLogin() }),
                                enabled = !isLoading,
                                isError = hasFullWidthChars(ecPassword),
                                supportingText = {
                                    if (hasFullWidthChars(ecPassword)) Text("含全角字符 ${describeFullWidthChars(ecPassword)}，请用英文半角", fontSize = 12.sp)
                                },
                            )
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        TelemetryNotice()

        Spacer(Modifier.height(16.dp))

        Button(
            onClick = { onLogin(userId, effectiveEcPassword, password, captchaCode) },
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = MaterialTheme.shapes.extraLarge, enabled = canLogin,
        ) {
            if (isLoading) {
                AppCircularProgressIndicator(modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text("登录中...")
            } else {
                Text("登录", style = MaterialTheme.typography.titleMedium)
            }
        }
        if (cooldownSec > 0L) {
            Spacer(Modifier.height(8.dp))
            Text(
                "请 $cooldownSec 秒后再试",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }

        AnimatedVisibility(
            visible = uiState.errorMessage != null,
            enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically(),
        ) {
            Card(
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
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

        Spacer(Modifier.height(16.dp))
        TextButton(onClick = { showPasswordHelp = true }) {
            Icon(Icons.Default.HelpOutline, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("不知道密码是什么？")
        }

        Spacer(Modifier.weight(1f))
        Text("❤ Created By LoveACE Team", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(24.dp))
    }

    if (showPasswordHelp) { PasswordHelpDialog(onDismiss = { showPasswordHelp = false }) }
}

@Composable
private fun TelemetryNotice() {
    Text(
        "登录即表示同意上传匿名使用统计（本地随机 ID、学号前四位与加盐哈希、版本和基础设备信息），不会上传密码、完整学号或业务内容。",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
}

/**
 * 学校强制改密拦截提示。
 * 这不是密码错误：不清凭据、不计失败次数、不自动重试；由用户自行前往教务系统完成改密。
 */
@Composable
private fun PasswordChangeRequiredDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Default.Lock, null) },
        title = { Text("学校要求修改密码") },
        text = {
            Text("你的账号被学校要求修改密码（通常是密码到期强制更换），这不是密码错误。\n\n请用浏览器登录学校教务系统（智慧校园/教务处），登录时会自动弹出“修改密码”页面，按提示完成修改。完成后回到本 App，用新密码重新登录即可。")
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("我知道了") }
        },
    )
}

@Composable
private fun PasswordHelpDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Default.HelpOutline, null) },
        title = { Text("密码说明") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                PasswordHelpSection(Icons.Default.Lock, "教务密码（UAAP）", "通常只需填写教务密码，彩带小工具会使用同一密码建立校内访问并登录教务系统，登录界面如下图所示：")
                Image(
                    painter = painterResource(R.drawable.uaap), contentDescription = "UAAP 登录界面",
                    modifier = Modifier.fillMaxWidth().clip(MaterialTheme.shapes.large), contentScale = ContentScale.FillWidth,
                )
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f)),
                    shape = MaterialTheme.shapes.large,
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
                        Icon(Icons.Default.Tune, null, tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("只有在你确认网关密码与教务密码不同时，才需要在登录页的高级选项中单独填写 VPN 密码。", style = MaterialTheme.typography.bodySmall)
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
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f)),
                    shape = MaterialTheme.shapes.large,
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
                        Icon(Icons.Default.Lightbulb, null, tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("忘记密码时，请通过学校官方教务系统确认或重置。", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("我知道了") } },
    )
}

@Composable
private fun PasswordHelpSection(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    desc: String,
) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(2.dp))
            Text(desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * 学校网关验证码行：图片固定 44dp 高（保持宽高比），点击刷新；输入框只接受半角 ASCII。
 * 图片为 GIF 原始字节，由 BitmapFactory 解码首帧。
 */
@Composable
internal fun CaptchaField(
    image: ByteArray,
    value: String,
    onValueChange: (String) -> Unit,
    onRefresh: () -> Unit,
    enabled: Boolean,
    refreshEnabled: Boolean,
) {
    val bitmap = remember(image) { BitmapFactory.decodeByteArray(image, 0, image.size)?.asImageBitmap() }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        OutlinedTextField(
            value = value, onValueChange = onValueChange,
            label = { Text("验证码") },
            singleLine = true, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.large,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Ascii,
                capitalization = KeyboardCapitalization.None,
                autoCorrect = false,
                imeAction = ImeAction.Done,
            ),
            enabled = enabled,
            isError = hasFullWidthChars(value),
            supportingText = {
                if (hasFullWidthChars(value)) Text("验证码含全角字符，请用英文半角", fontSize = 12.sp)
            },
        )
        if (bitmap != null) {
            Image(
                bitmap = bitmap,
                contentDescription = "验证码，点击刷新",
                modifier = Modifier
                    .height(44.dp)
                    .clip(MaterialTheme.shapes.small)
                    .clickable(enabled = refreshEnabled, onClick = onRefresh),
                contentScale = ContentScale.FillHeight,
            )
        }
    }
}

/** 登录冷却剩余秒数（向上取整），每秒刷新一次，归零后自动恢复 */
@Composable
internal fun rememberLoginCooldownSeconds(cooldownUntil: Long): Long {
    val remainingSec by produceState(initialValue = 0L, cooldownUntil) {
        while (true) {
            val leftMs = cooldownUntil - System.currentTimeMillis()
            value = if (leftMs > 0L) (leftMs + 999L) / 1000L else 0L
            if (leftMs <= 0L) break
            delay(1000L)
        }
    }
    return remainingSec
}
