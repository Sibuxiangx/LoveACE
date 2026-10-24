package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.CourseScheduleRecord
import tech.loveace.appv3.data.service.CourseScheduleService
import tech.loveace.appv3.data.service.CourseScheduleService.CourseScheduleOptions
import tech.loveace.appv3.data.service.CourseScheduleService.CourseScheduleQuery
import tech.loveace.appv3.data.service.CourseScheduleService.ScheduleTermItem

data class CourseScheduleUiState(
    val indexLoading: Boolean = false,
    val indexError: String? = null,
    val terms: List<ScheduleTermItem> = emptyList(),
    val options: CourseScheduleOptions = CourseScheduleOptions(),
    val form: CourseScheduleQuery = CourseScheduleQuery(termCode = ""),
    /** 已提交过查询：手机端切到结果页，横屏显示在右侧面板 */
    val showResults: Boolean = false,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    /** 首页失败：整页错误 */
    val error: String? = null,
    /** 追加页失败：列表底部重试 */
    val loadMoreError: String? = null,
    val records: List<CourseScheduleRecord> = emptyList(),
    val totalCount: Int = 0,
    val nextPage: Int = 1,
    val selected: CourseScheduleRecord? = null,
) {
    /** 还有未加载的页；加载中或已到末尾时为 false */
    val hasMore: Boolean
        get() = !isLoading && records.isNotEmpty() && records.size < totalCount
}

/** 开课记录的稳定键：同一课序同一时段视为同一条，用于翻页去重与 LazyColumn key */
internal fun courseRecordKey(record: CourseScheduleRecord): String =
    listOf(record.kch, record.kxh, record.skxq, record.skjc, record.cxjc, record.skzc, record.jxlm, record.jasm)
        .joinToString("|")

class CourseScheduleViewModel : ViewModel() {
    private var service: CourseScheduleService? = null
    private val _uiState = MutableStateFlow(CourseScheduleUiState())
    val uiState: StateFlow<CourseScheduleUiState> = _uiState.asStateFlow()

    /** 查询快照：提交时固定，翻页沿用，避免用户改表单后出现串页 */
    private var activeQuery: CourseScheduleQuery? = null

    /** 每次新查询或返回表单时递增，过期请求的结果直接丢弃 */
    private var generation = 0
    private var job: Job? = null

    fun init(service: CourseScheduleService) {
        this.service = service
    }

    fun loadIndex() {
        val svc = service ?: return
        val current = _uiState.value
        if (current.indexLoading || current.terms.isNotEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(indexLoading = true, indexError = null) }
            val result = svc.loadIndex()
            val index = result.data
            if (result.success && index != null) {
                _uiState.update { s ->
                    val defaultTerm = index.terms.firstOrNull { it.isSelected } ?: index.terms.first()
                    s.copy(
                        indexLoading = false,
                        terms = index.terms,
                        options = index.options,
                        form = s.form.copy(termCode = s.form.termCode.ifEmpty { defaultTerm.termCode }),
                    )
                }
            } else {
                _uiState.update { it.copy(indexLoading = false, indexError = result.error ?: "获取学期列表失败") }
            }
        }
    }

    fun retryIndex() {
        _uiState.update { it.copy(indexError = null) }
        loadIndex()
    }

    fun updateForm(transform: (CourseScheduleQuery) -> CourseScheduleQuery) {
        _uiState.update { it.copy(form = transform(it.form)) }
    }

    /** 清空筛选条件，保留当前学期 */
    fun resetFilters() {
        _uiState.update { it.copy(form = CourseScheduleQuery(termCode = it.form.termCode)) }
    }

    fun search() {
        val svc = service ?: return
        val form = _uiState.value.form
        if (form.termCode.isEmpty()) return
        val query = form.copy(
            kch = form.kch.trim(),
            kcm = form.kcm.trim(),
            skjs = form.skjs.trim(),
        )
        activeQuery = query
        val gen = ++generation
        job?.cancel()
        _uiState.update {
            it.copy(
                showResults = true,
                isLoading = true,
                isLoadingMore = false,
                error = null,
                loadMoreError = null,
                records = emptyList(),
                totalCount = 0,
                nextPage = 1,
                selected = null,
            )
        }
        job = viewModelScope.launch { requestPage(svc, query, page = 1, gen = gen) }
    }

    fun loadMore() {
        val svc = service ?: return
        val query = activeQuery ?: return
        val current = _uiState.value
        if (!current.hasMore || current.isLoadingMore) return
        val gen = generation
        _uiState.update { it.copy(isLoadingMore = true, loadMoreError = null) }
        job = viewModelScope.launch { requestPage(svc, query, page = current.nextPage, gen = gen) }
    }

    fun select(record: CourseScheduleRecord) {
        _uiState.update { it.copy(selected = record) }
    }

    fun dismissDetail() {
        _uiState.update { it.copy(selected = null) }
    }

    /** 从结果页返回表单；表单条件保留，在途请求作废 */
    fun backToForm() {
        generation++
        job?.cancel()
        _uiState.update {
            it.copy(showResults = false, isLoading = false, isLoadingMore = false, selected = null)
        }
    }

    private suspend fun requestPage(
        svc: CourseScheduleService,
        query: CourseScheduleQuery,
        page: Int,
        gen: Int,
    ) {
        val result = svc.queryPage(query, page, CourseScheduleService.PAGE_SIZE)
        if (gen != generation) return
        val data = result.data
        if (result.success && data != null) {
            _uiState.update { s ->
                val merged = mergeRecords(s.records, data.records)
                // 服务端返回空页即已到末尾：收敛 totalCount，避免继续请求
                val total = if (data.records.isEmpty()) merged.size else data.totalCount
                s.copy(
                    isLoading = false,
                    isLoadingMore = false,
                    error = null,
                    loadMoreError = null,
                    records = merged,
                    totalCount = total,
                    nextPage = page + 1,
                )
            }
        } else {
            val message = result.error ?: "查询失败"
            _uiState.update { s ->
                if (page == 1) s.copy(isLoading = false, error = message)
                else s.copy(isLoadingMore = false, loadMoreError = message)
            }
        }
    }

    private fun mergeRecords(
        existing: List<CourseScheduleRecord>,
        incoming: List<CourseScheduleRecord>,
    ): List<CourseScheduleRecord> {
        if (incoming.isEmpty()) return existing
        val seen = existing.mapTo(HashSet()) { courseRecordKey(it) }
        val merged = existing.toMutableList()
        for (record in incoming) {
            if (seen.add(courseRecordKey(record))) merged.add(record)
        }
        return merged
    }
}
