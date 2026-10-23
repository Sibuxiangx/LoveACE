package tech.loveace.appv3.data.model

data class ECLoginStatus(
    val success: Boolean = false,
    val failNotFoundTwfid: Boolean = false,
    val failNotFoundRsaKey: Boolean = false,
    val failNotFoundRsaExp: Boolean = false,
    val failNotFoundCsrfCode: Boolean = false,
    val failInvalidCredentials: Boolean = false,
    /** 学校要求输入验证码（RndImg=1 或 20041）：必须携带 [captchaImage]，不计失败 */
    val failCaptchaRequired: Boolean = false,
    /** 已提交的验证码错误（20023）：计失败，需用新认证页与新图片重试 */
    val failCaptchaInvalid: Boolean = false,
    /** 验证码图片原始字节（GIF），仅 [failCaptchaRequired] 时非空。不得记录日志 */
    val captchaImage: ByteArray? = null,
    val failNetworkError: Boolean = false,
    val failUnknownError: Boolean = false,
) {
    val errorMessage: String
        get() = when {
            failNotFoundTwfid -> "未找到TwfID"
            failNotFoundRsaKey -> "未找到RSA密钥"
            failNotFoundRsaExp -> "未找到RSA指数"
            failNotFoundCsrfCode -> "未找到CSRF代码"
            failInvalidCredentials -> "用户名或密码错误"
            failCaptchaRequired -> "学校要求输入验证码"
            failCaptchaInvalid -> "验证码错误，请重新输入"
            failNetworkError -> "网络连接错误"
            failUnknownError -> "未知错误"
            else -> ""
        }
}

data class UAAPLoginStatus(
    val success: Boolean = false,
    val failNotFoundLt: Boolean = false,
    val failNotFoundExecution: Boolean = false,
    val failInvalidCredentials: Boolean = false,
    // 学校 UAAP/CAS 强制改密拦截：凭据校验通过（TGT 已铸出）但不再签发票据，302 到改密页面。
    // 这不是密码错误：调用方不得清除凭据、不得计入密码失败、不得自动重试。
    val failPasswordChangeRequired: Boolean = false,
    val failNetworkError: Boolean = false,
    val failUnknownError: Boolean = false,
) {
    val errorMessage: String
        get() = when {
            failPasswordChangeRequired -> "学校要求修改密码"
            failNotFoundLt -> "未找到lt参数"
            failNotFoundExecution -> "未找到execution参数"
            failInvalidCredentials -> "用户名或密码错误"
            failNetworkError -> "网络连接错误"
            failUnknownError -> "未知错误"
            else -> ""
        }
}
