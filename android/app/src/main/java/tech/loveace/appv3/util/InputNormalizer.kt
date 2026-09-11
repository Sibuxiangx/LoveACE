package tech.loveace.appv3.util

/**
 * 全角字符归一化。
 *
 * 手机上的中文输入法在登录页学号/密码输入框里也可能打出全角字符
 *（如 ２０２４、ｐｗｄ、？），导致登录凭据被当成错误内容。
 * 将常见全角 ASCII 区段（！～）及全角空格转回半角，其余字符保持不变。
 */
fun String.toHalfWidth(): String {
    if (isEmpty()) return this
    val sb = StringBuilder(length)
    for (c in this) {
        sb.append(
            when (c) {
                '\u3000' -> ' '
                in '\uFF01'..'\uFF5E' -> (c.code - 0xFEE0).toChar()
                else -> c
            }
        )
    }
    return sb.toString()
}
