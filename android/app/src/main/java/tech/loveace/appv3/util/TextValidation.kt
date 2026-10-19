package tech.loveace.appv3.util

/**
 * 登录输入的全角字符检测：中文输入法很容易混入全角数字/字母/标点/空格，
 * 而教务系统只认半角原文。只提示、不自动转换（不替用户改密码内容）。
 */
private val FULL_WIDTH_RANGES = intArrayOf(
    0x3000, 0x3000, // 全角空格
    0xFF01, 0xFF60, // 全角 ASCII 变体（！＂＃０９ＡＺａｚ等）
    0xFFE0, 0xFFE6, // 全角货币/符号（￠￡￥等）
)

fun findFullWidthChars(text: String): List<Char> =
    text.filter { c ->
        val code = c.code
        var inRange = false
        var i = 0
        while (i < FULL_WIDTH_RANGES.size) {
            if (code in FULL_WIDTH_RANGES[i]..FULL_WIDTH_RANGES[i + 1]) {
                inRange = true
                break
            }
            i += 2
        }
        inRange
    }.toList()

fun hasFullWidthChars(text: String): Boolean = findFullWidthChars(text).isNotEmpty()

/** 错误提示里展示前几个全角字符（全角空格显示成 ␣ 才看得见） */
fun describeFullWidthChars(text: String): String =
    findFullWidthChars(text)
        .take(3)
        .joinToString(" ") { if (it.code == 0x3000) "␣" else "'$it'" }
