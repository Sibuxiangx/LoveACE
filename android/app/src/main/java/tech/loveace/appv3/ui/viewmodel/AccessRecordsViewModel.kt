package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.AccessKind
import tech.loveace.appv3.data.model.AccessPage
import tech.loveace.appv3.data.model.AccessRange
import tech.loveace.appv3.data.model.AccessRecord
import tech.loveace.appv3.data.service.PortalService

data class AccessRecordsUiState(
    val kind: AccessKind = AccessKind.DORMITORY,
    val range: AccessRange = AccessRange.THIS_WEEK,
    val records: List<AccessRecord> = emptyList(),
    val total: Int = 0,
    /** 已成功加载的最后一页页码，0 表示尚未加载 */
    val page: Int = 0,
    /** 首次加载（或切换类型/范围后的重新加载）完成 */
    val loaded: Boolean = false,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    /** 首次加载失败时的整页错误 */
    val error: String? = null,
    /** 加载更多失败时的行内错误 */
    val loadMoreError: String? = null,
    val needsLogin: Boolean = false,
)

class AccessRecordsViewModel : ViewModel() {
    private var service: PortalService? = null
    private var generation = 0L
    private val _uiState = MutableStateFlow(AccessRecordsUiState())
    val uiState: StateFlow<AccessRecordsUiState> = _uiState.asStateFlow()

    fun bind(service: PortalService?) {
        this.service = service
    }

    /** 切换门禁类型：清空结果并重新加载 */
    fun selectKind(kind: AccessKind) {
        if (_uiState.value.kind == kind) return
        _uiState.value = _uiState.value.copy(kind = kind)
        load()
    }

    /** 切换查询范围：清空结果并重新加载 */
    fun selectRange(range: AccessRange) {
        if (_uiState.value.range == range) return
        _uiState.value = _uiState.value.copy(range = range)
        load()
    }

    /** 按当前类型与范围从第一页重新加载 */
    fun load() {
        val gen = ++generation
        val current = _uiState.value
        val svc = service
        if (svc == null) {
            _uiState.value = current.copy(
                records = emptyList(), total = 0, page = 0, loaded = false,
                isLoading = false, isLoadingMore = false, error = null,
                loadMoreError = null, needsLogin = true,
            )
            return
        }
        _uiState.value = current.copy(
            records = emptyList(), total = 0, page = 0, loaded = false,
            isLoading = true, isLoadingMore = false, error = null,
            loadMoreError = null, needsLogin = false,
        )
        viewModelScope.launch {
            val result = svc.accessRecords(current.kind, current.range, 1)
            if (gen != generation) return@launch
            val latest = _uiState.value
            if (result.success) {
                val page = result.data ?: AccessPage(emptyList(), 0)
                _uiState.value = latest.copy(
                    records = page.records,
                    total = if (page.records.isEmpty()) 0 else page.total,
                    page = 1,
                    loaded = true,
                    isLoading = false,
                    error = null,
                )
            } else {
                _uiState.value = latest.copy(
                    isLoading = false,
                    error = result.error ?: "加载失败，请稍后重试",
                )
            }
        }
    }

    /** 加载下一页；已加载完或正在加载时不做任何事 */
    fun loadMore() {
        val svc = service ?: return
        val current = _uiState.value
        if (!current.loaded || current.isLoading || current.isLoadingMore) return
        if (current.records.size >= current.total) return
        val gen = generation
        val nextPage = current.page + 1
        _uiState.value = current.copy(isLoadingMore = true, loadMoreError = null)
        viewModelScope.launch {
            val result = svc.accessRecords(current.kind, current.range, nextPage)
            if (gen != generation) return@launch
            val latest = _uiState.value
            if (result.success) {
                val page = result.data ?: AccessPage(emptyList(), latest.records.size)
                val merged = latest.records + page.records
                _uiState.value = latest.copy(
                    records = merged,
                    // 空页视为已到末尾：总数收敛到当前条数，停止分页
                    total = if (page.records.isEmpty()) merged.size else page.total,
                    page = nextPage,
                    isLoadingMore = false,
                    loadMoreError = null,
                )
            } else {
                _uiState.value = latest.copy(
                    isLoadingMore = false,
                    loadMoreError = result.error ?: "加载失败，请稍后重试",
                )
            }
        }
    }

    /** 重试：首次加载失败则重新加载第一页，加载更多失败则重试下一页 */
    fun retry() {
        if (_uiState.value.loaded) loadMore() else load()
    }

    override fun onCleared() {
        generation++
        super.onCleared()
    }
}
