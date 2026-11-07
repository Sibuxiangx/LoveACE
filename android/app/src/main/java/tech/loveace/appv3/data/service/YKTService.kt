package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection

/**
 * 一卡通系统服务 - 余额查询、电费充值
 */
class YKTService(private val connection: AUFEConnection) {

    suspend fun initSession(): UniResponse<Unit> = withContext(Dispatchers.IO) {
        try {
            connection.client.get("$BASE_URL/casLogin.jsp")
            UniResponse.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "initSession failed", e)
            UniResponse.failure(e.message ?: "初始化一卡通会话失败")
        }
    }

    suspend fun getBalance(): UniResponse<CardBalance> = withContext(Dispatchers.IO) {
        try {
            val response = connection.client.get("$BASE_URL/queryUserBalances.action")
            val html = response.body?.string() ?: throw Exception("响应为空")
            val balanceMatch = Regex("余额[：:]?\\s*</label>\\s*<label>\\s*([\\d.]+)\\s*元", RegexOption.IGNORE_CASE).find(html)
                ?: Regex("余额[：:]?\\s*([\\d.]+)\\s*元", RegexOption.IGNORE_CASE).find(html)
                ?: throw Exception("无法解析余额")
            val balance = balanceMatch.groupValues[1].toDoubleOrNull() ?: 0.0
            UniResponse.success(CardBalance(balance, "${balanceMatch.groupValues[1]}元"))
        } catch (e: Exception) {
            Log.e(TAG, "getBalance failed", e)
            UniResponse.failure(e.message ?: "查询余额失败", retryable = true)
        }
    }

    companion object {
        private const val TAG = "YKTService"
        const val BASE_URL = "http://ykt-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118"
    }

    // ── 电费充值相关 ──

    suspend fun getPageInfo(): UniResponse<StudentInfo> = withContext(Dispatchers.IO) {
        try {
            val response = connection.client.get("$BASE_URL/utilityUnBindUserPowerPayInit.action")
            val html = response.body?.string() ?: throw Exception("响应为空")
            UniResponse.success(StudentInfo.fromHtml(html))
        } catch (e: Exception) {
            Log.e(TAG, "getPageInfo failed", e)
            UniResponse.failure(e.message ?: "获取学生信息失败")
        }
    }

    suspend fun getDormList(): UniResponse<List<SelectOption>> = getOptions("", "", "", "")
    suspend fun getBuildingList(dormId: String, dormName: String): UniResponse<List<SelectOption>> = getOptions(dormId, "", "", dormName)
    suspend fun getFloorList(dormId: String, buildingId: String, dormName: String): UniResponse<List<SelectOption>> = getOptions(dormId, buildingId, "", dormName)
    suspend fun getRoomList(dormId: String, buildingId: String, floorId: String, dormName: String): UniResponse<List<SelectOption>> = getOptions(dormId, buildingId, floorId, dormName)

    private suspend fun getOptions(dormId: String, buildingId: String, floorId: String, dormName: String): UniResponse<List<SelectOption>> =
        withContext(Dispatchers.IO) {
            try {
                val response = connection.client.post(
                    "$BASE_URL/utilitBindXiaoQuData.action",
                    formData = mapOf("dormId" to dormId, "buildingId" to buildingId, "floorId" to floorId, "dormName" to dormName),
                )
                val body = response.body?.string() ?: ""
                UniResponse.success(SelectOption.parseList(body))
            } catch (e: Exception) {
                Log.e(TAG, "getOptions failed", e)
                UniResponse.failure(e.message ?: "获取选项失败")
            }
        }

    suspend fun payElectricity(request: UtilityPaymentRequest): UniResponse<UtilityPaymentResult> =
        withContext(Dispatchers.IO) {
            try {
                val response = connection.client.post(
                    "$BASE_URL/utilityUnBindUserPowerPay.action",
                    formData = request.toFormData(),
                )
                val html = response.body?.string() ?: throw Exception("响应为空")
                UniResponse.success(UtilityPaymentResult.fromHtml(html))
            } catch (e: Exception) {
                Log.e(TAG, "payElectricity failed", e)
                UniResponse.failure(e.message ?: "充值失败")
            }
        }

    suspend fun getPurchaseHistory(startDate: String, endDate: String): UniResponse<ElectricPurchaseQueryResult> =
        withContext(Dispatchers.IO) {
            try {
                val response = connection.client.post(
                    "$BASE_URL/utilityQueryRunningAccountInfo.action",
                    formData = mapOf("startDate" to "$startDate 00:00:00", "endDate" to "$endDate 23:59:59"),
                )
                val html = response.body?.string() ?: throw Exception("响应为空")
                UniResponse.success(ElectricPurchaseQueryResult.fromHtml(html, startDate, endDate))
            } catch (e: Exception) {
                Log.e(TAG, "getPurchaseHistory failed", e)
                UniResponse.failure(e.message ?: "获取购电记录失败")
            }
        }
}
