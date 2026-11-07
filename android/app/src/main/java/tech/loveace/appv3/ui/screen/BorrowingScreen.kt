package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.BorrowRecord
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonListCard
import tech.loveace.appv3.ui.md3e.RibbonSectionTitle
import tech.loveace.appv3.ui.md3e.RibbonShape
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.md3e.RibbonTone
import tech.loveace.appv3.ui.md3e.ShapeBadge
import tech.loveace.appv3.ui.md3e.ribbonContentColor
import tech.loveace.appv3.ui.md3e.ribbonToneColors
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.BorrowingViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BorrowingScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
    vm: BorrowingViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.portalService) {
        vm.bind(authViewModel.portalService)
        vm.load()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("我的借阅") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                    }
                },
            )
        },
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 96.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                when {
                    state.needsLogin -> item {
                        RibbonState(kind = RibbonStateKind.LOGIN, title = "请先登录")
                    }
                    !state.loaded && state.error != null -> item {
                        RibbonState(
                            kind = RibbonStateKind.ERROR,
                            title = "无法加载借阅记录",
                            description = state.error,
                            actionText = "重试",
                            onAction = vm::retry,
                        )
                    }
                    !state.loaded -> item {
                        Box(
                            Modifier.fillMaxWidth().padding(vertical = 48.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            AppCircularProgressIndicator(modifier = Modifier.size(48.dp))
                        }
                    }
                    else -> {
                        state.refreshError?.let { message ->
                            item { RefreshErrorCard(message, onRetry = vm::retry) }
                        }
                        item {
                            BorrowSection(
                                title = "正在借阅",
                                footer = "共 ${state.current.size} 本",
                                icon = Icons.AutoMirrored.Filled.MenuBook,
                                tone = RibbonTone.SUCCESS,
                                accessibilityLabel = "借阅中",
                                emptyText = "暂无在借图书",
                                records = state.current,
                            )
                        }
                        item {
                            BorrowSection(
                                title = "借阅历史",
                                footer = "共 ${state.history.size} 条",
                                icon = Icons.Filled.History,
                                tone = RibbonTone.WARNING,
                                accessibilityLabel = "已还",
                                emptyText = "暂无借阅历史",
                                records = state.history,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RefreshErrorCard(message: String, onRetry: () -> Unit) {
    val contentColor = ribbonContentColor(RibbonCardVariant.ERROR_CONTAINER)
    RibbonCard(
        variant = RibbonCardVariant.ERROR_CONTAINER,
        radius = 28.dp,
        padding = PaddingValues(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                message,
                style = MaterialTheme.typography.bodyMedium,
                color = contentColor,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onRetry) { Text("重试") }
        }
    }
}

@Composable
private fun BorrowSection(
    title: String,
    footer: String,
    icon: ImageVector,
    tone: RibbonTone,
    accessibilityLabel: String,
    emptyText: String,
    records: List<BorrowRecord>,
) {
    val (bg, fg) = ribbonToneColors(tone, filled = true)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        RibbonSectionTitle(
            title,
            trailing = {
                ShapeBadge(
                    shape = RibbonShape.COOKIE_8,
                    size = 28.dp,
                    color = bg,
                    icon = icon,
                    iconTint = fg,
                    iconSizeFraction = 0.6f,
                    modifier = Modifier.semantics { contentDescription = accessibilityLabel },
                )
            },
        )
        RibbonListCard {
            if (records.isEmpty()) {
                Text(
                    emptyText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp),
                )
            } else {
                records.forEach { record -> BorrowRecordRow(record) }
            }
        }
        Text(
            footer,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 6.dp),
        )
    }
}

@Composable
private fun BorrowRecordRow(record: BorrowRecord) {
    val title = record.title.takeIf { it.isNotBlank() } ?: "未知书名"
    val returned = record.returnedAt?.takeIf { it.isNotBlank() }
    val detail = buildString {
        append("借 ")
        append(record.borrowedAt)
        if (returned != null) {
            append(" · 还 ")
            append(returned)
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
