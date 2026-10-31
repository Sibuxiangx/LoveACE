package tech.loveace.appv3.ui.screen

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import tech.loveace.appv3.data.model.AACCreditInfo
import tech.loveace.appv3.data.model.AcademicInfo
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.components.AppLinearProgressIndicator
import tech.loveace.appv3.ui.md3e.RibbonChip
import tech.loveace.appv3.ui.md3e.RibbonShape
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.md3e.ShapeBadge
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import tech.loveace.appv3.ui.theme.RibbonNumeric
import tech.loveace.appv3.ui.viewmodel.SemesterStatus

/** 首页主数字（绩点）。 */
private val HeroNumeric = TextStyle(
    fontSize = 40.sp,
    fontWeight = FontWeight(800),
    lineHeight = 44.sp,
    letterSpacing = (-0.5).sp,
)

/** hero 卡的形状：左上、左下、右下 28dp，右上 64dp（参考 Kazumi 规则卡）。 */
internal val HeroShape: Shape = RoundedCornerShape(
    topStart = 28.dp,
    topEnd = 64.dp,
    bottomStart = 28.dp,
    bottomEnd = 28.dp,
)

/**
 * 通用卡片：纯色容器 + 圆角 + 按压缩放（弹簧回弹）。
 * 只有传了 onClick 才有按压反馈。竖屏与横屏共用。
 */
@Composable
internal fun HomeTile(
    color: Color,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(28.dp),
    padding: PaddingValues = PaddingValues(20.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && onClick != null) 0.97f else 1f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "homeTileScale",
    )
    val clickModifier = if (onClick != null) {
        Modifier.clickable(interactionSource = interaction, indication = null, onClick = onClick)
    } else {
        Modifier
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(shape)
            .background(color)
            .then(clickModifier)
            .padding(padding),
        content = content,
    )
}

/** 加载占位：与卡片同样的容器，中间转圈。 */
@Composable
internal fun LoadingTile(modifier: Modifier = Modifier) {
    HomeTile(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = modifier,
        padding = PaddingValues(24.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator(modifier = Modifier.size(28.dp))
        }
    }
}

/** 学期状态行：假期 / 在读 / 加载中。卡片容器由调用方决定，这里只放内容。 */
@Composable
internal fun SemesterStatusRow(status: SemesterStatus, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    when (status) {
        is SemesterStatus.Loading -> Box(
            modifier.fillMaxWidth().height(48.dp),
            contentAlignment = Alignment.Center,
        ) {
            AppCircularProgressIndicator(modifier = Modifier.size(24.dp))
        }
        is SemesterStatus.Vacation -> Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            ShapeBadge(
                shape = RibbonShape.COOKIE_12,
                size = 48.dp,
                color = colors.tertiaryContainer,
                icon = Icons.Default.BeachAccess,
                iconTint = colors.onTertiaryContainer,
            )
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text("假期中", style = MaterialTheme.typography.titleMedium)
                if (status.nextSemesterName != null) {
                    Text(
                        "即将到来：${status.nextSemesterName}\n${status.nextStartDate} 开学（还有 ${status.daysUntilStart} 天）",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.onSurfaceVariant,
                    )
                }
            }
        }
        is SemesterStatus.InSession -> {
            val ending = status.isEnding
            val accent = if (ending) colors.error else colors.primary
            Column(modifier) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    ShapeBadge(
                        shape = RibbonShape.COOKIE_8,
                        size = 48.dp,
                        color = if (ending) colors.errorContainer else colors.primaryContainer,
                        icon = if (ending) Icons.Default.Timer else Icons.Default.School,
                        iconTint = if (ending) colors.onErrorContainer else colors.onPrimaryContainer,
                    )
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(status.semesterName, style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (ending) "第${status.currentWeek}周 · 学期即将结束"
                            else "第${status.currentWeek}周 · 共${status.totalWeeks}周",
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.onSurfaceVariant,
                        )
                    }
                    Text(
                        "${status.currentWeek}/${status.totalWeeks}",
                        style = RibbonNumeric.Large,
                        color = accent,
                    )
                }
                Spacer(Modifier.height(12.dp))
                AppLinearProgressIndicator(
                    progress = { (status.currentWeek.toFloat() / status.totalWeeks).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(8.dp),
                    color = accent,
                    trackColor = colors.surfaceContainerHighest,
                )
            }
        }
        else -> Unit
    }
}

/** 学业 hero：primary 底色的大卡，绩点为主数字，右侧是绩点环，下面是均分与排名人数。 */
@Composable
internal fun AcademicHero(info: AcademicInfo, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    HomeTile(color = colors.primary, modifier = modifier, shape = HeroShape, padding = PaddingValues(22.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    "绩点 / 5.0",
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.onPrimary,
                )
                Text(
                    info.currentTerm.ifEmpty { "当前学期" },
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onPrimary.copy(alpha = 0.8f),
                )
                Spacer(Modifier.height(8.dp))
                Text("%.2f".format(info.gpa), style = HeroNumeric, color = colors.onPrimary)
                if (info.hasAverageRank) {
                    Spacer(Modifier.height(8.dp))
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = colors.onPrimary,
                        contentColor = colors.primary,
                    ) {
                        Text(
                            "均分排名 #${info.averageRank}",
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        )
                    }
                }
            }
            Spacer(Modifier.width(12.dp))
            Box(contentAlignment = Alignment.Center) {
                AppCircularProgressIndicator(
                    progress = { (info.gpa / 5.0).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.size(96.dp),
                    color = colors.onPrimary,
                    trackColor = colors.primaryContainer,
                )
            }
        }

        Spacer(Modifier.height(18.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            HeroMetric(
                label = "均分",
                value = if (info.averageScore > 0.0) "%.2f".format(info.averageScore) else "--",
                supporting = "百分制",
                modifier = Modifier.weight(1f),
            )
            HeroMetric(
                label = "排名人数",
                value = if (info.averageRankTotal > 0) "${info.averageRankTotal}" else "--",
                supporting = if (info.hasAverageRank) "第 ${info.averageRank} / ${info.averageRankTotal}" else "暂无排名",
                modifier = Modifier.weight(1f),
            )
        }

        if (info.averageScore > 0.0 || info.hasAverageRank) {
            Spacer(Modifier.height(14.dp))
            AppLinearProgressIndicator(
                progress = {
                    if (info.hasAverageRank) info.averageRankProgress
                    else (info.averageScore / 100.0).toFloat().coerceIn(0f, 1f)
                },
                modifier = Modifier.fillMaxWidth().height(6.dp),
                color = colors.onPrimary,
                trackColor = colors.primaryContainer,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                if (info.hasAverageRank) "均分排名越靠前，进度条越接近满格" else "均分进度",
                style = MaterialTheme.typography.bodySmall,
                color = colors.onPrimary.copy(alpha = 0.8f),
            )
        }
    }
}

/** hero 内的半宽指标：primaryContainer 底色嵌在 primary 卡里。 */
@Composable
private fun HeroMetric(
    label: String,
    value: String,
    supporting: String,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.large,
        color = colors.primaryContainer,
        contentColor = colors.onPrimaryContainer,
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = RibbonNumeric.Caption, color = colors.onPrimaryContainer.copy(alpha = 0.8f))
            Text(value, style = RibbonNumeric.Medium, color = colors.onPrimaryContainer)
            Text(
                supporting,
                style = MaterialTheme.typography.bodySmall,
                color = colors.onPrimaryContainer.copy(alpha = 0.8f),
            )
        }
    }
}

/** 课程计数 bento：本学期课程总数为宽卡，已修与不及格并排等高。 */
@Composable
internal fun AcademicCounts(info: AcademicInfo, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    val hasFailures = info.failedCourses > 0
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HomeTile(color = colors.secondaryContainer, padding = PaddingValues(horizontal = 20.dp, vertical = 18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.MenuBook,
                    null,
                    modifier = Modifier.size(28.dp),
                    tint = colors.onSecondaryContainer,
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "本学期课程总数",
                        style = MaterialTheme.typography.titleSmall,
                        color = colors.onSecondaryContainer,
                    )
                    Text(
                        "待修课程",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.onSecondaryContainer.copy(alpha = 0.8f),
                    )
                }
                Text(
                    "${info.pendingCourses}",
                    style = RibbonNumeric.Large,
                    color = colors.onSecondaryContainer,
                )
            }
        }
        Row(
            Modifier.fillMaxWidth().height(IntrinsicSize.Min),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            MetricTile(
                label = "已修课程",
                value = "${info.completedCourses}",
                icon = Icons.Default.CheckCircle,
                color = colors.tertiaryContainer,
                contentColor = colors.onTertiaryContainer,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
            MetricTile(
                label = "不及格",
                value = "${info.failedCourses}",
                icon = if (hasFailures) Icons.Default.Error else Icons.Default.Verified,
                color = if (hasFailures) colors.errorContainer else colors.surfaceContainerHigh,
                contentColor = if (hasFailures) colors.onErrorContainer else colors.onSurface,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
        }
    }
}

/** 单个数字指标：左上图标，中间大数字，底部标签。 */
@Composable
internal fun MetricTile(
    label: String,
    value: String,
    icon: ImageVector,
    color: Color,
    contentColor: Color,
    modifier: Modifier = Modifier,
) {
    HomeTile(color = color, modifier = modifier, padding = PaddingValues(18.dp)) {
        Icon(icon, null, modifier = Modifier.size(24.dp), tint = contentColor)
        Spacer(Modifier.height(18.dp))
        Text(value, style = RibbonNumeric.Large, color = contentColor)
        Spacer(Modifier.height(2.dp))
        Text(label, style = MaterialTheme.typography.labelLarge, color = contentColor)
    }
}

/**
 * 一卡通卡：左上图标，余额为主数字。
 * onClick 为空时不显示箭头（横屏没有详情导航）。
 */
@Composable
internal fun YktTile(
    balanceText: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    val colors = MaterialTheme.colorScheme
    HomeTile(
        color = colors.surfaceContainerHigh,
        modifier = modifier,
        padding = PaddingValues(18.dp),
        onClick = onClick,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CreditCard, null, modifier = Modifier.size(24.dp), tint = colors.primary)
            Spacer(Modifier.weight(1f))
            if (onClick != null) {
                Icon(Icons.Rounded.ChevronRight, null, tint = colors.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(18.dp))
        Text("一卡通", style = MaterialTheme.typography.titleMedium, color = colors.onSurface)
        Text(balanceText, style = RibbonNumeric.Large, color = colors.primary)
        Text("卡片余额", style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
    }
}

/** 爱安财卡：毕业要求总分与达标状态，底部是进度条。 */
@Composable
internal fun AacTile(info: AACCreditInfo, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    val success = LocalExtendedColors.current.success
    HomeTile(color = colors.tertiaryContainer, modifier = modifier, padding = PaddingValues(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Default.VolunteerActivism,
                null,
                modifier = Modifier.size(24.dp),
                tint = colors.onTertiaryContainer,
            )
            Spacer(Modifier.weight(1f))
            RibbonChip(
                if (info.isTypeAdopt) "已达标" else "未达标",
                tone = if (info.isTypeAdopt) RibbonTone.SUCCESS else RibbonTone.WARNING,
                icon = if (info.isTypeAdopt) Icons.Default.CheckCircle else Icons.Default.Cancel,
            )
        }
        Spacer(Modifier.height(18.dp))
        Text("爱安财", style = MaterialTheme.typography.titleMedium, color = colors.onTertiaryContainer)
        Text(
            "${"%.1f".format(info.totalScore)} / 10 分",
            style = RibbonNumeric.Medium,
            color = colors.onTertiaryContainer,
        )
        Text(
            "毕业要求总分",
            style = MaterialTheme.typography.bodySmall,
            color = colors.onTertiaryContainer.copy(alpha = 0.8f),
        )
        Spacer(Modifier.height(12.dp))
        AppLinearProgressIndicator(
            progress = { (info.totalScore / 10.0).toFloat().coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().height(8.dp),
            color = if (info.isTypeAdopt) success else colors.onTertiaryContainer,
            trackColor = colors.onTertiaryContainer.copy(alpha = 0.16f),
        )
    }
}
