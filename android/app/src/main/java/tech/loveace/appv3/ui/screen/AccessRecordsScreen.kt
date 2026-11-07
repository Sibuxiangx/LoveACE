package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.AccessDirection
import tech.loveace.appv3.data.model.AccessKind
import tech.loveace.appv3.data.model.AccessRange
import tech.loveace.appv3.data.model.AccessRecord
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonListCard
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonShape
import tech.loveace.appv3.ui.md3e.RibbonSlotGrid
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.md3e.ShapeBadge
import tech.loveace.appv3.ui.md3e.ribbonContentColor
import tech.loveace.appv3.ui.md3e.ribbonToneColors
import tech.loveace.appv3.ui.viewmodel.AccessRecordsViewModel
import tech.loveace.appv3.ui.viewmodel.AuthViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccessRecordsScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: AccessRecordsViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.portalService) {
        vm.bind(authViewModel.portalService)
        vm.load()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("门禁查询") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    val kinds = AccessKind.entries
                    kinds.forEachIndexed { index, kind ->
                        SegmentedButton(
                            selected = state.kind == kind,
                            onClick = { vm.selectKind(kind) },
                            shape = SegmentedButtonDefaults.itemShape(index, kinds.size),
                        ) {
                            Text(kind.title)
                        }
                    }
                }
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    RibbonSlotGrid(
                        options = AccessRange.entries.map { it to it.title },
                        selected = setOf(state.range),
                        columns = AccessRange.entries.size,
                        onToggle = { vm.selectRange(it) },
                    )
                    Text(
                        "默认只查本周。需要更早的记录，可以在这里调整查询时间。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 6.dp),
                    )
                }
            }

            if (state.kind == AccessKind.DORMITORY) {
                item { DormDelayBanner() }
            }

            when {
                state.needsLogin -> item {
                    RibbonState(kind = RibbonStateKind.LOGIN, title = "请先登录")
                }
                !state.loaded && state.isLoading -> item {
                    Box(Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                        AppCircularProgressIndicator(modifier = Modifier.size(48.dp))
                    }
                }
                !state.loaded && state.error != null -> item {
                    RibbonState(
                        kind = RibbonStateKind.ERROR,
                        title = "无法加载门禁记录",
                        description = state.error,
                        actionText = "重试",
                        onAction = vm::retry,
                    )
                }
                state.loaded && state.records.isEmpty() -> item {
                    RibbonState(
                        kind = RibbonStateKind.EMPTY,
                        title = "暂无门禁记录",
                        description = "${state.range.title}没有刷卡记录。",
                    )
                }
                state.loaded -> {
                    item {
                        RibbonSectionTitle("${state.kind.title}门禁")
                    }
                    item {
                        RibbonListCard {
                            state.records.forEach { record -> AccessRecordRow(record) }
                        }
                    }
                    item {
                        LoadMoreFooter(
                            shownCount = state.records.size,
                            total = state.total,
                            isLoadingMore = state.isLoadingMore,
                            loadMoreError = state.loadMoreError,
                            onLoadMore = vm::loadMore,
                            onRetry = vm::retry,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DormDelayBanner() {
    RibbonCard(
        variant = RibbonCardVariant.WARNING_CONTAINER,
        radius = 28.dp,
        padding = PaddingValues(16.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Icon(
                Icons.Filled.AccessTime,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = ribbonContentColor(RibbonCardVariant.WARNING_CONTAINER),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                "宿舍门禁数据有延迟同步，刚刷的记录可能过一段时间才会出现，结果以学校系统为准。",
                style = MaterialTheme.typography.bodyMedium,
                color = ribbonContentColor(RibbonCardVariant.WARNING_CONTAINER),
            )
        }
    }
}

@Composable
private fun AccessRecordRow(record: AccessRecord) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                record.time,
                style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                record.detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        record.direction?.let { DirectionBadge(it) }
    }
}

@Composable
private fun DirectionBadge(direction: AccessDirection) {
    val (label, icon, tone) = when (direction) {
        AccessDirection.ENTRY -> Triple("进", Icons.AutoMirrored.Filled.Login, RibbonTone.SUCCESS)
        AccessDirection.EXIT -> Triple("出", Icons.AutoMirrored.Filled.Logout, RibbonTone.WARNING)
    }
    val (bg, fg) = ribbonToneColors(tone, filled = true)
    ShapeBadge(
        shape = RibbonShape.CLOVER_4,
        size = 36.dp,
        color = bg,
        icon = icon,
        iconTint = fg,
        modifier = Modifier.semantics { contentDescription = label },
    )
}

@Composable
private fun LoadMoreFooter(
    shownCount: Int,
    total: Int,
    isLoadingMore: Boolean,
    loadMoreError: String?,
    onLoadMore: () -> Unit,
    onRetry: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (shownCount < total) {
            Button(onClick = onLoadMore, enabled = !isLoadingMore) {
                Text("加载更多", fontWeight = FontWeight.SemiBold)
            }
        }
        if (loadMoreError != null) {
            Text(
                loadMoreError,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
            TextButton(onClick = onRetry) { Text("重试") }
        }
        Text(
            "已显示 $shownCount 条，共 $total 条",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
