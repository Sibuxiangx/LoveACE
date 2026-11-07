import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "PortalService")

/// 学校门户（all.aufe.edu.cn，经 VPN）的 cube 搜索接口。
/// 企业邮箱初始密码、门禁记录、借阅记录都走同一套三步接口：getList → counts → datas（分页）。
/// 请求体与日期筛选字段见 docs/research/aufe-portal-*.md；字段按列标题查找，不按下标。
actor PortalService {
    /// 门户 API 基址。CAS 回跳后服务器把 all-aufe-edu-cn.vpn2… 301 到 -s 主机，会话 cookie 落在 -s 上（见 netlog A216E7A5），与 YKT 的 -s 约定一致。
    static let baseURL = "http://all-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118"
    /// 门户 API 地址：补上 sf_request_type（VPN 网页代理对 XHR/fetch 的标记；浏览器的门户 API 请求都带）
    static func apiURL(_ path: String) -> String {
        "\(baseURL)\(path)?sf_request_type=fetch"
    }
    /// 门户 CAS 入口：与 JWC（jwcxk2）、AAC 相同，从 UAAP CAS 登录开始，service 为门户 cas-entrance 的非 VPN 地址；
    /// 回跳地址再经 vpnURL 映射到 VPN 域名。
    static let ssoEntryURL =
        "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3A%2F%2Fall.aufe.edu.cn%2Fwui%2Fcas-entrance.jsp%3Fpath%3Dhttps%253A%252F%252Fall.aufe.edu.cn%252Fwui%252Findex.html%2523%252Fmain%26ssoType%3DCAS"

    private static let hpid = "38522"
    private static let subCompanyId = "21"
    private static let menuIds = "-665,-1001"
    /// cube 请求里的 windowWidth：页面以浏览器宽度发送，这里取常见 iPhone 宽度
    private static let windowWidth = "390"
    private static let maxRedirects = 10
    private static let maxPages = 50
    /// 门禁每页条数（门户 datas 接口固定返回 10 条）
    private static let accessPageSize = 10
    /// 一卡通消费每页条数（门户 datas 接口对 74507 返回 100 条）
    private static let consumptionPageSize = 100

    private enum Cube {
        static let mailInitialPassword = 82510
        static let borrowCurrent = 84509
        static let borrowHistory = 84510
        /// 宿舍门禁日期字段 178950：今天=1，昨天=9，本周=2，本月=3，全部=0
        static let dormAccess = 37501
        static let dormAccessDateField = "178950"
        /// 图书馆门禁日期字段 316587：今天=1，昨天=9，本周=2,,（页面默认值），本月=3，全部=0
        static let libraryAccess = 71001
        static let libraryAccessDateField = "316587"
        /// 一卡通消费 cube 74507：日期字段 299018，默认本月；本周 "2,,"，全部 "0"
        static let consumption = 74507
        static let consumptionDateField = "299018"
    }

    private let connection: AUFEConnection
    private var hrmResourceID: String?
    /// 进行中的会话建立：并发的功能页面共享同一次 SSO
    private var sessionTask: Task<String, Error>?
    /// VPN 安全策略拦截后的冷却截止时间；冷却期内不再发起 SSO
    private var interceptedUntil: Date?
    private static let interceptCooldown: TimeInterval = 180

    init(connection: AUFEConnection) {
        self.connection = connection
    }

    // MARK: - Public reads

    func mailInitialPassword() async throws -> MailInitialPassword? {
        let table = try await fetchTable(Cube.mailInitialPassword)
        guard let row = table.rows.first else { return nil }
        guard let password = table.text(row, table.field(titled: "邮箱初始密码")), !password.isEmpty else {
            throw ServiceError.parseError("门户返回的数据缺少邮箱初始密码")
        }
        return MailInitialPassword(
            loginId: table.text(row, table.field(titled: "登录名")) ?? "",
            password: password
        )
    }

    /// 门禁记录单页读取：最小请求体（只带日期字段），默认第一页，翻页由调用方按需请求
    func accessRecords(_ kind: AccessKind, range: AccessRange, page: Int) async throws -> AccessPage {
        let customid = kind == .dormitory ? Cube.dormAccess : Cube.libraryAccess
        let dateField = kind == .dormitory ? Cube.dormAccessDateField : Cube.libraryAccessDateField
        let result = try await fetchCubePage(customid, dateField: dateField, code: range.code(commaWeek: kind == .library), page: page)
        let table = result.table
        let offset = (page - 1) * Self.accessPageSize
        let records: [AccessRecord] = table.rows.enumerated().map { index, row in
            let id = table.recordID(row, index: offset + index)
            let time = table.text(row, table.field(titled: "通过时间")) ?? ""
            switch kind {
            case .dormitory:
                let direction = Self.direction(table.text(row, table.field(titled: "通过方向")))
                let system = table.text(row, table.field(titled: "系统名称")) ?? ""
                return AccessRecord(id: id, time: time, direction: direction, detail: system)
            case .library:
                let campus = table.text(row, table.field(titled: "校区")) ?? ""
                let date = table.text(row, table.field(titled: "日期")) ?? ""
                return AccessRecord(id: id, time: time, direction: nil, detail: [campus, date].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
        return AccessPage(records: records, total: result.total)
    }

    /// 一卡通消费单页读取：默认本月，翻页由调用方按需请求（门户 cube 74507，不返回交易后余额与交易类型）
    func consumptionRecords(page: Int) async throws -> ConsumptionPage {
        let result = try await fetchCubePage(
            Cube.consumption, dateField: Cube.consumptionDateField,
            code: AccessRange.thisMonth.code(commaWeek: false), page: page)
        let table = result.table
        let offset = (page - 1) * Self.consumptionPageSize
        let records: [ConsumptionRecord] = table.rows.enumerated().map { index, row in
            ConsumptionRecord(
                id: table.recordID(row, index: offset + index),
                date: table.text(row, table.field(titled: "交易日期")) ?? "",
                time: table.text(row, table.field(titled: "交易时间")) ?? "",
                area: table.text(row, table.field(titled: "交易地点")) ?? "",
                amount: table.text(row, table.field(titled: "交易金额")) ?? ""
            )
        }
        return ConsumptionPage(records: records, total: result.total)
    }

    func borrowing() async throws -> (current: [BorrowRecord], history: [BorrowRecord]) {
        let currentTable = try await fetchTable(Cube.borrowCurrent)
        let historyTable = try await fetchTable(Cube.borrowHistory)
        let current = currentTable.rows.enumerated().map { index, row in
            BorrowRecord(
                id: currentTable.recordID(row, index: index),
                title: currentTable.text(row, currentTable.field(titled: "书名")) ?? "",
                borrowedAt: currentTable.text(row, currentTable.field(titled: "借阅时间")) ?? "",
                returnedAt: nil
            )
        }
        let history = historyTable.rows.enumerated().map { index, row in
            BorrowRecord(
                id: historyTable.recordID(row, index: index),
                title: historyTable.text(row, historyTable.field(titled: "书名")) ?? "",
                borrowedAt: historyTable.text(row, historyTable.field(titled: "借书时间")) ?? "",
                returnedAt: historyTable.text(row, historyTable.field(titled: "还书时间"))
            )
        }
        return (current, history)
    }

    // MARK: - Session

    /// 与 AAC、劳动俱乐部一致：VPN 网关通过 sdp-app-session 识别会话；门户自己的 JSESSIONID 仍走 cookie 存储。
    /// 日志里 3 次成功的 hpdata 都带着它，去掉它后两次都失败，所以保留。
    private func apiHeaders() async -> [String: String] {
        var headers = ["X-Requested-With": "XMLHttpRequest", "Referer": "\(Self.baseURL)/spa/portal/static/index.html"]
        if let twf = await connection.twfId { headers["sdp-app-session"] = twf }
        return headers
    }

    /// 门户会话只建立一次：并发的功能页面共享同一次 SSO，失败结果不会被每个页面各自重试。
    private func ensureSession() async throws -> String {
        if let hrmResourceID { return hrmResourceID }
        if let interceptedUntil, Date() < interceptedUntil {
            throw ServiceError.parseError("学校 VPN 暂时拦截了门户请求，请彻底退出 App 后重新打开再试")
        }
        if let sessionTask { return try await sessionTask.value }
        let task = Task { try await self.establishSession() }
        sessionTask = task
        defer { sessionTask = nil }
        return try await task.value
    }

    /// 经 VPN 走一遍门户 CAS 入口（逐跳手动跟随，跳转地址映射到 VPN 域名），再用首页接口取得当前用户的 hrmResourceID。
    /// 首页接口返回的不是 JSON 时视为会话失效；返回 securityIntercept 时进入冷却，不再重试。
    private func establishSession() async throws -> String {
        let noRedirect = await connection.noRedirectClient!
        var next = Self.ssoEntryURL
        for _ in 0..<Self.maxRedirects {
            let (_, response) = try await noRedirect.get(next)
            logger.info("portal sso hop status=\(response.statusCode) host=\(URL(string: next)?.host ?? "-") path=\(URL(string: next)?.path ?? "-")")
            guard (301...308).contains(response.statusCode),
                  let location = response.value(forHTTPHeaderField: "Location") else { break }
            let base = response.url ?? URL(string: next)
            guard let resolved = URL(string: location, relativeTo: base)?.absoluteString else { break }
            next = Self.vpnURL(for: resolved)
        }

        let client = await connection.simpleClient!
        // 浏览器的门户页加载时会先请求一次网页代理配置；这里同样请求，结果不使用，失败不影响后续
        _ = try? await client.get("\(Self.baseURL)/sf-webproxy/api/vpn-config", headers: await apiHeaders())
        let (data, response) = try await client.post(
            Self.apiURL("/api/portal/homepage/hpdata"),
            formData: [
                "hpid": Self.hpid,
                "subCompanyId": Self.subCompanyId,
                "menuIds": Self.menuIds,
                "menuPathIds": Self.menuIds,
                "isSetting": "false",
                "isfromportal": "1",
                "isfromhp": "0",
            ],
            headers: await apiHeaders()
        )
        if response.statusCode == 404, response.value(forHTTPHeaderField: "Errormsg") == "securityIntercept" {
            interceptedUntil = Date().addingTimeInterval(Self.interceptCooldown)
            logger.warning("portal hpdata intercepted by VPN security policy; cooling down")
            throw ServiceError.parseError("学校 VPN 拦截了门户请求。请彻底退出 App 后重新打开再试")
        }
        let json = try Self.parseObject(data)
        guard let hpinfo = json["hpinfo"] as? [String: Any], let uid = jsonText(hpinfo["userid"]) else {
            throw ServiceError.sessionExpired
        }
        hrmResourceID = uid
        interceptedUntil = nil
        logger.info("portal session established")
        return uid
    }

    /// 门禁"通过方向"接口返回 0/1，门户页面显示为 进/出（2026-11-05 宿舍门禁截图逐条核对：0=进，1=出）
    static func direction(_ raw: String?) -> AccessDirection? {
        guard let raw else { return nil }
        switch raw {
        case "0": return .entry
        case "1": return .exit
        default: return nil
        }
    }

    /// `*.aufe.edu.cn` 的跳转地址映射到 VPN 域名：主机名的点换成横杠，http，端口 8118（与仓库其他 VPN 服务一致）。
    static func vpnURL(for urlString: String) -> String {
        guard var components = URLComponents(string: urlString),
              let host = components.host?.lowercased(),
              host.hasSuffix("aufe.edu.cn"),
              !host.hasSuffix("vpn2.aufe.edu.cn") else { return urlString }
        components.scheme = "http"
        components.host = host.replacingOccurrences(of: ".", with: "-") + ".vpn2.aufe.edu.cn"
        components.port = 8118
        return components.string ?? urlString
    }

    // MARK: - Cube

    private struct Table {
        let columns: [[String: Any]]
        let rows: [[String: Any]]

        /// 列标题对应的 dbField（行数据的键）
        func field(titled title: String) -> String? {
            columns.first { ($0["title"] as? String) == title }?["dbField"] as? String
        }

        func text(_ row: [String: Any], _ field: String?) -> String? {
            guard let field else { return nil }
            return jsonText(row[field])
        }

        func recordID(_ row: [String: Any], index: Int) -> String {
            text(row, field(titled: "数据ID")) ?? "row-\(index)"
        }
    }

    /// 读取一个 cube 的全部行（邮箱与借阅数据量很小，整表翻完）
    private func fetchTable(_ customid: Int) async throws -> Table {
        do {
            let uid = try await ensureSession()
            let client = await connection.simpleClient!
            let headers = await apiHeaders()

            let listForm: [String: String] = [
                "customid": String(customid),
                "hrmResourceID": uid,
                "guid": "search",
                "isNewTableSearch": "1",
                "displayType": "",
                "isTempSearch": "",
                "windowWidth": Self.windowWidth,
                "isTreeType": "",
            ]

            let (listData, _) = try await client.post(
                Self.apiURL("/api/cube/search/getList"), formData: listForm, headers: headers)
            let listJson = try Self.parseObject(listData)
            guard let dataKey = jsonText(listJson["datas"]), dataKey.count == 32 else {
                throw ServiceError.parseError("门户列表响应缺少数据键")
            }

            let (countData, _) = try await client.post(
                Self.apiURL("/api/ec/dev/table/counts"), formData: ["dataKey": dataKey], headers: headers)
            let total = jsonInt(try Self.parseObject(countData)["count"]) ?? 0
            guard total > 0 else { return Table(columns: [], rows: []) }

            var columns: [[String: Any]] = []
            var rows: [[String: Any]] = []
            var page = 1
            while rows.count < total && page <= Self.maxPages {
                let (pageData, _) = try await client.post(
                    Self.apiURL("/api/ec/dev/table/datas"),
                    formData: ["dataKey": dataKey, "current": String(page), "sortParams": "[]"],
                    headers: headers)
                let json = try Self.parseObject(pageData)
                if page == 1 { columns = json["columns"] as? [[String: Any]] ?? [] }
                let pageRows = json["datas"] as? [[String: Any]] ?? []
                if pageRows.isEmpty { break }
                rows.append(contentsOf: pageRows)
                page += 1
            }
            logger.info("portal cube \(customid) loaded \(rows.count) of \(total) rows")
            return Table(columns: columns, rows: rows)
        } catch {
            if case ServiceError.sessionExpired = error { hrmResourceID = nil }
            throw error
        }
    }

    /// 单页读取（门禁、一卡通消费共用）：最小请求体只带日期字段（与页面默认加载同形，不带快速搜索参数）；counts 给总数，datas 只取 current 页
    private func fetchCubePage(_ customid: Int, dateField: String, code: String, page: Int) async throws -> (table: Table, total: Int) {
        do {
            let uid = try await ensureSession()
            let client = await connection.simpleClient!
            let headers = await apiHeaders()
            let (listData, _) = try await client.post(
                Self.apiURL("/api/cube/search/getList"),
                formData: [
                    "customid": String(customid),
                    "hrmResourceID": uid,
                    "guid": "search",
                    "canIsQuickSearch": "1",
                    "isNewTableSearch": "1",
                    "displayType": "",
                    "isTempSearch": "",
                    "windowWidth": Self.windowWidth,
                    "isTreeType": "",
                    dateField: code,
                ],
                headers: headers)
            let listJson = try Self.parseObject(listData)
            guard let dataKey = jsonText(listJson["datas"]), dataKey.count == 32 else {
                throw ServiceError.parseError("门户列表响应缺少数据键")
            }
            let (countData, _) = try await client.post(
                Self.apiURL("/api/ec/dev/table/counts"), formData: ["dataKey": dataKey], headers: headers)
            let total = jsonInt(try Self.parseObject(countData)["count"]) ?? 0
            guard total > 0 else { return (Table(columns: [], rows: []), 0) }
            let (pageData, _) = try await client.post(
                Self.apiURL("/api/ec/dev/table/datas"),
                formData: ["dataKey": dataKey, "current": String(page), "sortParams": "[]"],
                headers: headers)
            let json = try Self.parseObject(pageData)
            let table = Table(
                columns: json["columns"] as? [[String: Any]] ?? [],
                rows: json["datas"] as? [[String: Any]] ?? []
            )
            return (table, total)
        } catch {
            if case ServiceError.sessionExpired = error { hrmResourceID = nil }
            throw error
        }
    }

    /// 解析 JSON 对象。解析失败且内容像 HTML（VPN 登录页）时视为会话失效。
    private static func parseObject(_ data: Data) throws -> [String: Any] {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
        if head.contains("<html") || head.contains("login_auth.csp") || head.contains("svpn_name") {
            throw ServiceError.sessionExpired
        }
        throw ServiceError.parseError("门户响应格式异常")
    }
}

/// 把门户错误转成可以直接显示的中文信息
enum PortalErrorMessage {
    static func text(for error: Error) -> String {
        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .sessionExpired: return "门户会话已失效，请重新登录"
            case .parseError(let message): return message
            case .emptyResponse: return "门户没有返回数据"
            }
        }
        if error is URLError { return "网络连接异常，请检查网络后重试" }
        return "加载失败，请稍后重试"
    }
}
