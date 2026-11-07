package tech.loveace.appv3.data.network

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * 智能 CookieJar，支持 VPN 子域名共享
 * 所有 *.vpn2.aufe.edu.cn 的 cookie 自动共享
 */
class SmartCookieJar : CookieJar {
    private val cookieStore = mutableMapOf<String, MutableList<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val domain = extractDomain(url.host)
        val existing = cookieStore.getOrPut(domain) { mutableListOf() }
        for (cookie in cookies) {
            existing.removeAll { it.name == cookie.name && it.path == cookie.path }
            existing.add(cookie)
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val now = System.currentTimeMillis()
        val result = mutableListOf<Cookie>()
        val domain = extractDomain(url.host)

        cookieStore[domain]?.let { cookies ->
            cookies.removeAll { it.expiresAt < now }
            result.addAll(cookies.filter { it.matches(url) })
        }
        // Also check the VPN shared domain
        if (url.host.contains("vpn2.aufe.edu.cn")) {
            cookieStore["vpn2.aufe.edu.cn"]?.let { cookies ->
                cookies.removeAll { it.expiresAt < now }
                for (c in cookies) {
                    if (result.none { it.name == c.name }) result.add(c)
                }
            }
        }
        return result
    }

    fun setCookie(name: String, value: String, domain: String) {
        val cookie = Cookie.Builder()
            .name(name)
            .value(value)
            .domain(domain)
            .path("/")
            .build()
        val key = extractDomain(domain)
        val existing = cookieStore.getOrPut(key) { mutableListOf() }
        existing.removeAll { it.name == name }
        existing.add(cookie)
    }

    fun getCookie(name: String): String? {
        for (cookies in cookieStore.values) {
            cookies.find { it.name == name }?.let { return it.value }
        }
        return null
    }

    fun copyFrom(other: SmartCookieJar) {
        cookieStore.clear()
        for ((k, v) in other.cookieStore) {
            cookieStore[k] = v.toMutableList()
        }
    }
    /** 合并 other 的 Cookie：同名同路径以 other 为准，本地其它 Cookie 保留（copyFrom 会整体替换，会冲掉其它服务的会话） */
    fun mergeFrom(other: SmartCookieJar) {
        for ((domain, cookies) in other.cookieStore) {
            val existing = cookieStore.getOrPut(domain) { mutableListOf() }
            for (cookie in cookies) {
                existing.removeAll { it.name == cookie.name && it.path == cookie.path }
                existing.add(cookie)
            }
        }
    }

    fun clear() = cookieStore.clear()

    private fun extractDomain(host: String): String {
        return if (host.contains("vpn2.aufe.edu.cn")) "vpn2.aufe.edu.cn" else host
    }
}
