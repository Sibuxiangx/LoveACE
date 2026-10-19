package tech.loveace.appv3.ui.md3e

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 语义色调（对齐小程序 m3-chip tone）：neutral=中性、primary= headline/要做的事、
 * secondary/tertiary=平静信息、success=已完成、warning=将到期/部分、error=失败/紧急。
 */
enum class RibbonTone { NEUTRAL, PRIMARY, SECONDARY, TERTIARY, SUCCESS, WARNING, ERROR, INVERSE }

/** tone → (容器, 内容) 颜色对；filled 取实底主色对，否则取 container 对 */
@Composable
fun ribbonToneColors(tone: RibbonTone, filled: Boolean = false): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    val extended = LocalExtendedColors.current
    return when (tone) {
        RibbonTone.NEUTRAL ->
            if (filled) scheme.surfaceContainerHighest to scheme.onSurface
            else scheme.surfaceContainerHigh to scheme.onSurfaceVariant
        RibbonTone.PRIMARY ->
            if (filled) scheme.primary to scheme.onPrimary
            else scheme.primaryContainer to scheme.onPrimaryContainer
        RibbonTone.SECONDARY ->
            if (filled) scheme.secondary to scheme.onSecondary
            else scheme.secondaryContainer to scheme.onSecondaryContainer
        RibbonTone.TERTIARY ->
            if (filled) scheme.tertiary to scheme.onTertiary
            else scheme.tertiaryContainer to scheme.onTertiaryContainer
        RibbonTone.SUCCESS ->
            if (filled) extended.success to extended.onSuccess
            else extended.successContainer to extended.onSuccessContainer
        RibbonTone.WARNING ->
            if (filled) extended.warning to extended.onWarning
            else extended.warningContainer to extended.onWarningContainer
        RibbonTone.ERROR ->
            if (filled) scheme.error to scheme.onError
            else scheme.errorContainer to scheme.onErrorContainer
        RibbonTone.INVERSE ->
            scheme.inverseSurface to scheme.inverseOnSurface
    }
}

/** 状态小标签（对齐 m3-chip）：28dp 高、radius 10、12sp/600 */
@Composable
fun RibbonChip(
    text: String,
    modifier: Modifier = Modifier,
    tone: RibbonTone = RibbonTone.NEUTRAL,
    filled: Boolean = false,
    icon: ImageVector? = null,
) {
    val (bg, fg) = ribbonToneColors(tone, filled)
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, modifier = Modifier.size(14.dp), tint = fg)
            Spacer(Modifier.width(4.dp))
        }
        Text(text, style = MaterialTheme.typography.labelMedium, color = fg, maxLines = 1)
    }
}

/** 区块标题（对齐 .sec-title）：14sp / 700 / primary / 宽字距 */
@Composable
fun RibbonSectionTitle(
    text: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            letterSpacing = 0.5.sp,
        )
        if (trailing != null) {
            Spacer(Modifier.weight(1f))
            trailing()
        }
    }
}

/** 列表行（对齐 m3-list-item）：44-46dp 花形徽章 + 双行文本 + trailing，min 64dp 高 */
@Composable
fun RibbonListItem(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    badgeShape: RibbonShape = RibbonShape.COOKIE_8,
    badgeTone: RibbonTone = RibbonTone.PRIMARY,
    trailing: (@Composable () -> Unit)? = null,
    chevron: Boolean = false,
    dimmed: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val (badgeBg, badgeFg) = ribbonToneColors(badgeTone)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .graphicsLayer { alpha = if (dimmed) 0.55f else 1f }
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            ShapeBadge(
                shape = badgeShape,
                size = 44.dp,
                color = badgeBg,
                icon = icon,
                iconTint = badgeFg,
            )
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            trailing()
        }
        if (chevron) {
            Spacer(Modifier.width(4.dp))
            Icon(
                Icons.Rounded.ChevronRight,
                null,
                modifier = Modifier.size(22.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
