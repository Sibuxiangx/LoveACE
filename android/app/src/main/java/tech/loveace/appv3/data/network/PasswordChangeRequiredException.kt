package tech.loveace.appv3.data.network

/**
 * 学校 UAAP/CAS 强制要求修改密码的拦截。
 *
 * 凭据校验通过（CAS 已铸出 TGT），但不再签发票据，而是把请求 302 重定向到改密页面
 * （路径含 /mng/acp/completeInfo/password）。
 *
 * 这不是密码错误：调用方不得清除本地凭据、不得计入密码失败次数、不得自动重试。
 */
class PasswordChangeRequiredException : Exception("学校要求修改密码")
