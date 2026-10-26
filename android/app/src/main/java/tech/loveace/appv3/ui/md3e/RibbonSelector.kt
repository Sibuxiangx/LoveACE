package tech.loveace.appv3.ui.md3e

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** 教学周范围（教务系统最多 24 周）。 */
private val WEEKS = (1..24).toList()

/**
 * 选项格：节次（多选）、星期（单选）、上课节次（单选）共用。
 * 选中时圆角从 14dp spring 变形为胶囊，颜色即时切换；columns 决定每行格数，末行不足时留白对齐。
 * onToggle 的语义由调用方决定（多选切换、单选可再点取消）。
 */
@Composable
fun <T> RibbonSlotGrid(
    options: List<Pair<T, String>>,
    selected: Set<T>,
    columns: Int,
    onToggle: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.chunked(columns).forEach { rowOptions ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                rowOptions.forEach { (value, label) ->
                    RibbonSlotTile(
                        label = label,
                        selected = value in selected,
                        onClick = { onToggle(value) },
                        modifier = Modifier.weight(1f),
                    )
                }
                repeat(columns - rowOptions.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun RibbonSlotTile(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier,
) {
    val corner by animateDpAsState(
        targetValue = if (selected) 26.dp else 14.dp,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "slotCorner",
    )
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = modifier
            .height(52.dp)
            .clip(RoundedCornerShape(corner))
            .background(if (selected) scheme.primaryContainer else scheme.surfaceContainerHigh)
            .selectable(selected = selected, onClick = onClick, role = Role.Checkbox),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) scheme.onPrimaryContainer else scheme.onSurfaceVariant,
        )
    }
}

/**
 * 教学周横向条（1–24 周）：选中周为实心圆，本周（未选中时）描边。
 * 选中变化时自动滚动，让选中周靠左露出前几周。
 */
@Composable
fun RibbonWeekStrip(
    selected: Int,
    currentWeek: Int?,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(selected) {
        listState.animateScrollToItem((selected - 4).coerceAtLeast(0))
    }
    LazyRow(
        modifier = modifier,
        state = listState,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(WEEKS, key = { it }) { week ->
            RibbonWeekTile(
                week = week,
                selected = week == selected,
                isCurrent = week == currentWeek,
                onClick = { onSelect(week) },
            )
        }
    }
}

@Composable
private fun RibbonWeekTile(
    week: Int,
    selected: Boolean,
    isCurrent: Boolean,
    onClick: () -> Unit,
) {
    val corner by animateDpAsState(
        targetValue = if (selected) 22.dp else 14.dp,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "weekCorner",
    )
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(corner)
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(shape)
            .background(if (selected) scheme.primary else scheme.surfaceContainerHigh)
            .then(if (isCurrent && !selected) Modifier.border(1.dp, scheme.primary, shape) else Modifier)
            .selectable(selected = selected, onClick = onClick, role = Role.RadioButton),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "$week",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
            color = if (selected) scheme.onPrimary else scheme.onSurfaceVariant,
        )
    }
}
