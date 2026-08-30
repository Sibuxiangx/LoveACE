package tech.loveace.appv3.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.data.model.LaborClubDirectoryItem
import tech.loveace.appv3.data.model.LaborClubMembershipState
import tech.loveace.appv3.data.model.LaborClubMembershipStatus
import tech.loveace.appv3.data.service.LaborClubService

@Composable
fun LaborClubApplicationStatusCard(
    membership: LaborClubMembershipState,
    statusError: String?,
    submittedStatusSyncing: Boolean,
    onApply: () -> Unit,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (membership.status == LaborClubMembershipStatus.JOINED) return

    val application = membership.latestApplication
    val presentation = when {
        statusError != null -> ClubStatusPresentation(
            title = "俱乐部状态加载失败",
            supporting = statusError,
            icon = Icons.Default.ErrorOutline,
            color = MaterialTheme.colorScheme.error,
            refreshable = true,
        )
        submittedStatusSyncing -> ClubStatusPresentation(
            title = "申请已提交，状态同步中",
            supporting = "服务器状态尚未同步",
            icon = Icons.Default.Sync,
            color = MaterialTheme.colorScheme.primary,
            refreshable = true,
        )
        membership.status == LaborClubMembershipStatus.PENDING -> ClubStatusPresentation(
            title = "俱乐部正在审批",
            supporting = applicationSummary(application?.clubName, application?.addTime, application?.replyComment),
            icon = Icons.Default.HourglassTop,
            color = Color(0xFFE65100),
            refreshable = true,
        )
        membership.status == LaborClubMembershipStatus.APPROVED_SYNCING -> ClubStatusPresentation(
            title = "审核已通过，正在同步俱乐部信息",
            supporting = applicationSummary(application?.clubName, application?.addTime, application?.replyComment),
            icon = Icons.Default.Sync,
            color = Color(0xFF2E7D32),
            refreshable = true,
        )
        membership.status == LaborClubMembershipStatus.SUBMITTING -> ClubStatusPresentation(
            title = "正在提交申请",
            supporting = application?.clubName.orEmpty(),
            icon = Icons.Default.HourglassTop,
            color = MaterialTheme.colorScheme.primary,
        )
        membership.status == LaborClubMembershipStatus.REJECTED -> ClubStatusPresentation(
            title = "上次申请未通过",
            supporting = applicationSummary(application?.clubName, application?.addTime, application?.replyComment),
            icon = Icons.Default.Block,
            color = MaterialTheme.colorScheme.error,
            clickable = true,
        )
        else -> ClubStatusPresentation(
            title = "申请加入劳动俱乐部",
            supporting = "当前尚未加入俱乐部",
            icon = Icons.Default.GroupAdd,
            color = MaterialTheme.colorScheme.primary,
            clickable = true,
        )
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .then(if (presentation.clickable) Modifier.clickable(onClick = onApply) else Modifier),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        ListItem(
            headlineContent = {
                Text(presentation.title, fontWeight = FontWeight.SemiBold)
            },
            supportingContent = {
                if (presentation.supporting.isNotBlank()) {
                    Text(
                        presentation.supporting,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            },
            leadingContent = {
                Box(
                    Modifier
                        .size(42.dp)
                        .clip(CircleShape)
                        .background(presentation.color.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    if (membership.status == LaborClubMembershipStatus.SUBMITTING) {
                        AppCircularProgressIndicator(Modifier.size(22.dp), color = presentation.color)
                    } else {
                        Icon(presentation.icon, null, tint = presentation.color)
                    }
                }
            },
            trailingContent = {
                when {
                    presentation.clickable -> Icon(Icons.Default.ChevronRight, "进入申请")
                    presentation.refreshable -> IconButton(onClick = onRefresh) {
                        Icon(Icons.Default.Refresh, "刷新俱乐部状态")
                    }
                }
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LaborClubApplicationSheet(
    directory: List<LaborClubDirectoryItem>,
    isLoading: Boolean,
    error: String?,
    isSubmitting: Boolean,
    submissionSucceeded: Boolean,
    submissionMessage: String?,
    onLoadDirectory: (Boolean) -> Unit,
    onSubmit: (String, String) -> Unit,
    onConsumeSuccess: () -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var selectedClubId by rememberSaveable { mutableStateOf<String?>(null) }
    var reason by rememberSaveable { mutableStateOf(LaborClubService.DEFAULT_CLUB_APPLICATION_REASON) }
    val selectedClub = directory.firstOrNull { it.id == selectedClubId }
    val filteredClubs = remember(directory, searchQuery) {
        val query = searchQuery.trim()
        if (query.isEmpty()) directory else directory.filter {
            it.name.contains(query, ignoreCase = true) ||
                it.typeName.contains(query, ignoreCase = true) ||
                it.projectName.contains(query, ignoreCase = true)
        }
    }

    LaunchedEffect(Unit) { onLoadDirectory(false) }
    LaunchedEffect(submissionSucceeded) {
        if (submissionSucceeded) {
            onConsumeSuccess()
            onDismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        sheetState = sheetState,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.92f)
                .padding(horizontal = 20.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (selectedClub != null) {
                    IconButton(onClick = { selectedClubId = null }, enabled = !isSubmitting) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回俱乐部目录")
                    }
                }
                Text(
                    if (selectedClub == null) "选择劳动俱乐部" else "确认入会申请",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onDismiss, enabled = !isSubmitting) {
                    Icon(Icons.Default.Close, "关闭")
                }
            }
            Spacer(Modifier.height(12.dp))

            if (selectedClub == null) {
                DirectoryContent(
                    clubs = filteredClubs,
                    searchQuery = searchQuery,
                    onSearchChange = { searchQuery = it },
                    isLoading = isLoading,
                    error = error,
                    onRetry = { onLoadDirectory(true) },
                    onSelect = { selectedClubId = it.id },
                )
            } else {
                ApplicationForm(
                    club = selectedClub,
                    reason = reason,
                    onReasonChange = { reason = it },
                    isSubmitting = isSubmitting,
                    submissionMessage = submissionMessage,
                    onSubmit = { onSubmit(selectedClub.id, reason) },
                )
            }
        }
    }
}

@Composable
private fun DirectoryContent(
    clubs: List<LaborClubDirectoryItem>,
    searchQuery: String,
    onSearchChange: (String) -> Unit,
    isLoading: Boolean,
    error: String?,
    onRetry: () -> Unit,
    onSelect: (LaborClubDirectoryItem) -> Unit,
) {
    OutlinedTextField(
        value = searchQuery,
        onValueChange = onSearchChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        label = { Text("搜索俱乐部") },
        leadingIcon = { Icon(Icons.Default.Search, null) },
        trailingIcon = {
            if (searchQuery.isNotEmpty()) {
                IconButton(onClick = { onSearchChange("") }) { Icon(Icons.Default.Close, "清空搜索") }
            }
        },
    )
    Spacer(Modifier.height(12.dp))
    when {
        isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AppCircularProgressIndicator(Modifier.size(40.dp))
        }
        error != null -> Column(
            Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(Icons.Default.ErrorOutline, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(40.dp))
            Spacer(Modifier.height(10.dp))
            Text(error, color = MaterialTheme.colorScheme.error)
            TextButton(onClick = onRetry) {
                Icon(Icons.Default.Refresh, null)
                Spacer(Modifier.width(6.dp))
                Text("重试")
            }
        }
        clubs.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("没有匹配的俱乐部", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        else -> LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(clubs, key = { it.id }) { club ->
                DirectoryClubCard(club = club, onClick = { onSelect(club) })
            }
            item { Spacer(Modifier.height(28.dp)) }
        }
    }
}

@Composable
private fun DirectoryClubCard(club: LaborClubDirectoryItem, onClick: () -> Unit) {
    OutlinedCard(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 108.dp)
            .then(if (club.canApply) Modifier.clickable(onClick = onClick) else Modifier),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            Box(
                Modifier
                    .size(42.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.secondaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Default.Groups, null, tint = MaterialTheme.colorScheme.onSecondaryContainer)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        club.name,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                    )
                    ClubAvailabilityBadge(club)
                }
                if (club.typeName.isNotBlank() || club.projectName.isNotBlank()) {
                    Text(
                        listOf(club.typeName, club.projectName).filter(String::isNotBlank).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(
                    "${club.memberNum}/${club.peopleNum} 人",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (!club.description.isNullOrBlank()) {
                    Text(
                        club.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (club.canApply) {
                Spacer(Modifier.width(4.dp))
                Icon(Icons.Default.ChevronRight, "选择${club.name}", tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ClubAvailabilityBadge(club: LaborClubDirectoryItem) {
    val (label, color) = when {
        club.isJoined -> "已加入" to Color(0xFF2E7D32)
        !club.isEnabled -> "暂停申请" to MaterialTheme.colorScheme.error
        else -> "可申请" to MaterialTheme.colorScheme.primary
    }
    Surface(color = color.copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}

@Composable
private fun ApplicationForm(
    club: LaborClubDirectoryItem,
    reason: String,
    onReasonChange: (String) -> Unit,
    isSubmitting: Boolean,
    submissionMessage: String?,
    onSubmit: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OutlinedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Groups, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(10.dp))
                        Text(club.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    }
                    HorizontalDivider()
                    Text(
                        listOf(club.typeName, club.projectName).filter(String::isNotBlank).joinToString(" · "),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text("${club.memberNum}/${club.peopleNum} 人", color = MaterialTheme.colorScheme.primary)
                }
            }
            OutlinedTextField(
                value = reason,
                onValueChange = onReasonChange,
                modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
                label = { Text("申请理由") },
                enabled = !isSubmitting,
                maxLines = 6,
                supportingText = { Text("${reason.length}/200") },
            )
            if (!submissionMessage.isNullOrBlank() && !isSubmitting) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.ErrorOutline,
                        null,
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        submissionMessage,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = onSubmit,
            enabled = reason.trim().isNotEmpty() && reason.length <= 200 && !isSubmitting,
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) {
            if (isSubmitting) {
                AppCircularProgressIndicator(Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary)
            } else {
                Icon(Icons.AutoMirrored.Filled.Send, null)
            }
            Spacer(Modifier.width(8.dp))
            Text(if (isSubmitting) "正在提交" else "提交申请")
        }
        Spacer(Modifier.height(20.dp))
    }
}

private data class ClubStatusPresentation(
    val title: String,
    val supporting: String,
    val icon: ImageVector,
    val color: Color,
    val clickable: Boolean = false,
    val refreshable: Boolean = false,
)

private fun applicationSummary(clubName: String?, addTime: String?, reply: String?): String =
    listOfNotNull(
        clubName?.takeIf(String::isNotBlank),
        addTime?.takeIf(String::isNotBlank),
        reply?.takeIf(String::isNotBlank),
    ).joinToString("\n")
