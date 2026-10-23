import Foundation

struct ECLoginStatus {
    let success: Bool
    let failNotFoundTwfid: Bool
    let failNotFoundRsaKey: Bool
    let failNotFoundRsaExp: Bool
    let failNotFoundCsrfCode: Bool
    let failInvalidCredentials: Bool
    /// 学校要求输入验证码（尚未提交验证码，或刚提交的验证码被判定需要重新获取）
    let captchaRequired: Bool
    /// 已提交的验证码错误（计入登录失败）
    let captchaInvalid: Bool
    /// 验证码图片（GIF 原始字节）；仅 captchaRequired 时存在
    let captchaImage: Data?
    let failNetworkError: Bool
    let failUnknownError: Bool

    var errorMessage: String {
        if failNotFoundTwfid { return "未找到TwfID" }
        if failNotFoundRsaKey { return "未找到RSA密钥" }
        if failNotFoundRsaExp { return "未找到RSA指数" }
        if failNotFoundCsrfCode { return "未找到CSRF代码" }
        if failInvalidCredentials { return "用户名或密码错误" }
        if captchaRequired { return "学校要求输入验证码" }
        if captchaInvalid { return "验证码错误，请重新输入" }
        if failNetworkError { return "网络连接错误" }
        if failUnknownError { return "未知错误" }
        return ""
    }

    init(success: Bool = false, failNotFoundTwfid: Bool = false,
         failNotFoundRsaKey: Bool = false, failNotFoundRsaExp: Bool = false,
         failNotFoundCsrfCode: Bool = false, failInvalidCredentials: Bool = false,
         captchaRequired: Bool = false, captchaInvalid: Bool = false, captchaImage: Data? = nil,
         failNetworkError: Bool = false, failUnknownError: Bool = false) {
        self.success = success; self.failNotFoundTwfid = failNotFoundTwfid
        self.failNotFoundRsaKey = failNotFoundRsaKey; self.failNotFoundRsaExp = failNotFoundRsaExp
        self.failNotFoundCsrfCode = failNotFoundCsrfCode
        self.failInvalidCredentials = failInvalidCredentials
        self.captchaRequired = captchaRequired; self.captchaInvalid = captchaInvalid
        self.captchaImage = captchaImage
        self.failNetworkError = failNetworkError; self.failUnknownError = failUnknownError
    }
}

/// 学校 UAAP/CAS 强制改密拦截：凭据校验通过（CAS 已铸出 TGT），但不再签发票据，
/// 而是把请求 302 重定向到改密页面（路径含 /mng/acp/completeInfo/password）。
/// 这不是密码错误：调用方不得清除本地凭据、不得计入密码失败次数、不得自动重试。
struct PasswordChangeRequiredError: Error {}

/// 改密拦截的通用指引文案
let passwordChangeGuidance = "学校要求修改密码：请用浏览器登录学校教务系统完成密码修改，然后用新密码重新登录"

struct UAAPLoginStatus {
    let success: Bool
    let failNotFoundLt: Bool
    let failNotFoundExecution: Bool
    let failInvalidCredentials: Bool
    let failPasswordChangeRequired: Bool
    let failNetworkError: Bool
    let failUnknownError: Bool

    var errorMessage: String {
        if failPasswordChangeRequired { return "学校要求修改密码" }
        if failNotFoundLt { return "未找到lt参数" }
        if failNotFoundExecution { return "未找到execution参数" }
        if failInvalidCredentials { return "用户名或密码错误" }
        if failNetworkError { return "网络连接错误" }
        if failUnknownError { return "未知错误" }
        return ""
    }

    init(success: Bool = false, failNotFoundLt: Bool = false,
         failNotFoundExecution: Bool = false, failInvalidCredentials: Bool = false,
         failPasswordChangeRequired: Bool = false,
         failNetworkError: Bool = false, failUnknownError: Bool = false) {
        self.success = success; self.failNotFoundLt = failNotFoundLt
        self.failNotFoundExecution = failNotFoundExecution
        self.failInvalidCredentials = failInvalidCredentials
        self.failPasswordChangeRequired = failPasswordChangeRequired
        self.failNetworkError = failNetworkError; self.failUnknownError = failUnknownError
    }
}
