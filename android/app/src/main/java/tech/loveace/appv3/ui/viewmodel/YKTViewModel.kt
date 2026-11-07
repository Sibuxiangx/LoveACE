package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.service.PortalService
import tech.loveace.appv3.data.service.YKTService
import java.time.LocalDate
import java.time.format.DateTimeFormatter

data class YKTUiState(
    val isLoading: Boolean = false,
    val balance: CardBalance? = null,
    val error: String? = null,
    // 本月消费（门户）
    val consumption: List<ConsumptionRecord> = emptyList(),
    val consumptionTotal: Int = 0,
    val consumptionPage: Int = 0,
    val isConsumptionLoading: Boolean = false,
    val consumptionError: String? = null,
    /** 本月消费第一页已成功加载（区分"尚未加载"与"本月确实没有记录"） */
    val consumptionLoaded: Boolean = false,
    // 充值解锁
    val isPaymentUnlocked: Boolean = false,
    // 电费充值
    val studentInfo: StudentInfo? = null,
    val dorms: List<SelectOption> = emptyList(),
    val buildings: List<SelectOption> = emptyList(),
    val floors: List<SelectOption> = emptyList(),
    val rooms: List<SelectOption> = emptyList(),
    val selectedDorm: SelectOption? = null,
    val selectedBuilding: SelectOption? = null,
    val selectedFloor: SelectOption? = null,
    val selectedRoom: SelectOption? = null,
    val loadingOptions: Boolean = false,
    val isPaying: Boolean = false,
    val paymentResult: UtilityPaymentResult? = null,
    val purchaseHistory: ElectricPurchaseQueryResult? = null,
)

class YKTViewModel : ViewModel() {
    private var service: YKTService? = null
    private var portal: PortalService? = null
    private val _uiState = MutableStateFlow(YKTUiState())
    val uiState: StateFlow<YKTUiState> = _uiState.asStateFlow()
    /** 每次重新加载本月消费时递增；旧请求返回时丢弃 */
    private var consumptionGeneration = 0

    fun init(service: YKTService, portal: PortalService?) {
        this.service = service
        this.portal = portal
    }

    /** 余额（ykt）与本月消费（门户）各自加载，互不等待 */
    fun loadAll() {
        loadBalance()
        reloadConsumption()
    }

    /** 只加载余额：首页与余额卡重试使用 */
    fun loadBalance() {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            svc.initSession()
            val balanceResult = svc.getBalance()
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                balance = balanceResult.data,
                error = balanceResult.error,
            )
        }
    }

    /** 本月消费第一页：清空旧结果并递增代数，旧请求返回后丢弃 */
    fun reloadConsumption() {
        consumptionGeneration += 1
        val generation = consumptionGeneration
        val svc = portal
        _uiState.value = _uiState.value.copy(
            consumption = emptyList(),
            consumptionTotal = 0,
            consumptionPage = 0,
            consumptionLoaded = false,
            consumptionError = if (svc == null) "请先登录" else null,
            isConsumptionLoading = svc != null,
        )
        if (svc == null) return
        viewModelScope.launch {
            val result = svc.consumptionRecords(1)
            val page = result.data
            if (generation != consumptionGeneration) return@launch
            if (!result.success || page == null) {
                _uiState.value = _uiState.value.copy(
                    isConsumptionLoading = false,
                    consumptionError = result.error ?: "加载失败，请稍后重试",
                )
                return@launch
            }
            _uiState.value = _uiState.value.copy(
                isConsumptionLoading = false,
                consumption = page.records,
                consumptionTotal = page.total,
                consumptionPage = 1,
                consumptionLoaded = true,
            )
        }
    }

    /** 加载下一页：已显示数量未达到总数时才请求；服务端返回空页时停止翻页 */
    fun loadMoreConsumption() {
        val svc = portal ?: return
        val state = _uiState.value
        if (state.isConsumptionLoading || state.consumption.size >= state.consumptionTotal) return
        val generation = consumptionGeneration
        val next = state.consumptionPage + 1
        _uiState.value = state.copy(isConsumptionLoading = true, consumptionError = null)
        viewModelScope.launch {
            val result = svc.consumptionRecords(next)
            val page = result.data
            if (generation != consumptionGeneration) return@launch
            if (!result.success || page == null) {
                _uiState.value = _uiState.value.copy(
                    isConsumptionLoading = false,
                    consumptionError = result.error ?: "加载失败，请稍后重试",
                )
                return@launch
            }
            _uiState.value = if (page.records.isEmpty()) {
                _uiState.value.copy(
                    isConsumptionLoading = false,
                    consumptionTotal = _uiState.value.consumption.size,
                )
            } else {
                _uiState.value.copy(
                    isConsumptionLoading = false,
                    consumption = _uiState.value.consumption + page.records,
                    consumptionTotal = page.total,
                    consumptionPage = next,
                )
            }
        }
    }

    // ── 解锁/锁定 ──

    fun unlockPayment() {
        _uiState.value = _uiState.value.copy(isPaymentUnlocked = true)
        loadStudentInfo()
    }

    fun lockPayment() {
        _uiState.value = _uiState.value.copy(
            isPaymentUnlocked = false, studentInfo = null,
            dorms = emptyList(), buildings = emptyList(), floors = emptyList(), rooms = emptyList(),
            selectedDorm = null, selectedBuilding = null, selectedFloor = null, selectedRoom = null,
            purchaseHistory = null,
        )
    }

    private fun loadStudentInfo() {
        val svc = service ?: return
        viewModelScope.launch {
            val result = svc.getPageInfo()
            if (result.success && result.data != null) {
                _uiState.value = _uiState.value.copy(studentInfo = result.data)
                loadDorms()
            }
        }
    }

    private fun loadDorms() {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(loadingOptions = true)
            val result = svc.getDormList()
            _uiState.value = _uiState.value.copy(dorms = result.data ?: emptyList(), loadingOptions = false)
        }
    }

    fun selectDorm(option: SelectOption) {
        val svc = service ?: return
        _uiState.value = _uiState.value.copy(
            selectedDorm = option, selectedBuilding = null, selectedFloor = null, selectedRoom = null,
            buildings = emptyList(), floors = emptyList(), rooms = emptyList(), loadingOptions = true,
        )
        viewModelScope.launch {
            val result = svc.getBuildingList(option.value, option.name)
            _uiState.value = _uiState.value.copy(buildings = result.data ?: emptyList(), loadingOptions = false)
        }
    }

    fun selectBuilding(option: SelectOption) {
        val svc = service ?: return
        val dorm = _uiState.value.selectedDorm ?: return
        _uiState.value = _uiState.value.copy(
            selectedBuilding = option, selectedFloor = null, selectedRoom = null,
            floors = emptyList(), rooms = emptyList(), loadingOptions = true,
        )
        viewModelScope.launch {
            val result = svc.getFloorList(dorm.value, option.value, dorm.name)
            _uiState.value = _uiState.value.copy(floors = result.data ?: emptyList(), loadingOptions = false)
        }
    }

    fun selectFloor(option: SelectOption) {
        val svc = service ?: return
        val dorm = _uiState.value.selectedDorm ?: return
        val building = _uiState.value.selectedBuilding ?: return
        _uiState.value = _uiState.value.copy(
            selectedFloor = option, selectedRoom = null, rooms = emptyList(), loadingOptions = true,
        )
        viewModelScope.launch {
            val result = svc.getRoomList(dorm.value, building.value, option.value, dorm.name)
            _uiState.value = _uiState.value.copy(rooms = result.data ?: emptyList(), loadingOptions = false)
        }
    }

    fun selectRoom(option: SelectOption) {
        _uiState.value = _uiState.value.copy(selectedRoom = option)
    }

    fun payElectricity(amount: Int) {
        val svc = service ?: return
        val state = _uiState.value
        val info = state.studentInfo ?: return
        val dorm = state.selectedDorm ?: return
        val building = state.selectedBuilding ?: return
        val floor = state.selectedFloor ?: return
        val room = state.selectedRoom ?: return

        _uiState.value = state.copy(isPaying = true, paymentResult = null)
        viewModelScope.launch {
            val request = UtilityPaymentRequest(
                roomId = room.value, dormId = dorm.value, dormName = dorm.name,
                buildName = building.name, floorName = floor.name, roomName = room.name,
                accId = info.accId, balances = "%.2f".format(info.balance), money = amount,
            )
            val result = svc.payElectricity(request)
            _uiState.value = _uiState.value.copy(
                isPaying = false,
                paymentResult = result.data ?: UtilityPaymentResult(false, result.error ?: "充值失败"),
            )
            if (result.data?.success == true) loadAll()
        }
    }

    fun clearPaymentResult() {
        _uiState.value = _uiState.value.copy(paymentResult = null)
    }

    fun loadPurchaseHistory() {
        val svc = service ?: return
        viewModelScope.launch {
            val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val end = LocalDate.now().format(fmt)
            val start = LocalDate.now().minusDays(30).format(fmt)
            val result = svc.getPurchaseHistory(start, end)
            _uiState.value = _uiState.value.copy(purchaseHistory = result.data)
        }
    }
}
