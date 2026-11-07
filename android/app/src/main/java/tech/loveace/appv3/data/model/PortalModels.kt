package tech.loveace.appv3.data.model

enum class AccessKind(val title: String) { DORMITORY("宿舍"), LIBRARY("图书馆") }

enum class AccessRange(val title: String) {
    TODAY("今天"), YESTERDAY("昨天"), THIS_WEEK("本周"), THIS_MONTH("本月"), ALL("全部");

    /** 门户日期范围编码。宿舍：1,9,2,3,0；图书馆本周为 "2,,"。 */
    fun code(kind: AccessKind): String = when (this) {
        TODAY -> "1"
        YESTERDAY -> "9"
        THIS_WEEK -> if (kind == AccessKind.LIBRARY) "2,," else "2"
        THIS_MONTH -> "3"
        ALL -> "0"
    }
}

/** 进 / 出；图书馆记录没有方向，为 null */
enum class AccessDirection { ENTRY, EXIT }

data class AccessRecord(val id: String, val time: String, val detail: String, val direction: AccessDirection?)
data class AccessPage(val records: List<AccessRecord>, val total: Int)
data class BorrowRecord(val id: String, val title: String, val borrowedAt: String, val returnedAt: String?)
data class BorrowingResult(val current: List<BorrowRecord>, val history: List<BorrowRecord>)
data class ConsumptionRecord(val id: String, val date: String, val time: String, val area: String, val amount: String)
data class ConsumptionPage(val records: List<ConsumptionRecord>, val total: Int)

/** 企业邮箱初始密码，只保存在内存中 */
data class MailInitialPassword(val loginId: String, val password: String)
