import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.wideLayout) private var wideLayout
    @State private var userId = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var qqGroupManifest: QqGroupManifest?
    @State private var showPasswordHelp = false
    @State private var preloginNotice: PreloginNotice?
    @State private var captchaInput = ""
    @State private var showWeakPasswordAlert = false

    var body: some View {
        Group {
            if wideLayout {
                wideBody
            } else {
                compactBody
            }
        }
        .alert("教务密码可能需要修改", isPresented: $showWeakPasswordAlert) {
            Button("取消", role: .cancel) {}
            Button("继续登录") { submitLogin() }
        } message: {
            Text("你的教务密码是 6 位数字，或 5 位数字加 1 个字母，这类密码较弱，学校系统可能会要求修改。\n\n请先登录学校教务处（智慧校园/教务处），按页面指引修改密码，再用新密码登录本 App。\n\n注意：这里指的是智慧校园/教务处的密码，不是校园网（网关）密码。")
        }
        .sheet(isPresented: $showPasswordHelp) {
            PasswordHelpView()
                .presentationDetents([.medium, .large])
        }
        .task {
            // 登录前公告：拉取失败或未启用时静默隐藏
            preloginNotice = await AnnouncementService.fetchPreloginNotice()
        }
        .task {
            qqGroupManifest = await QqGroupService.fetch()
        }
        .alert(
            "学校要求修改密码",
            isPresented: Binding(
                get: { authVM.passwordChangeRequired },
                set: { if !$0 { authVM.dismissPasswordChange() } }
            )
        ) {
            Button("我知道了", role: .cancel) { authVM.dismissPasswordChange() }
        } message: {
            Text("你的账号被学校要求修改密码（通常是密码到期强制更换），这不是密码错误。请用浏览器登录学校教务系统（智慧校园/教务处），登录时会自动弹出“修改密码”页面，按提示完成修改。完成后回到本 App，用新密码重新登录即可。")
        }
        .onAppear {
            // 只在表单为空时预填：登录页重建时不能覆盖用户正在输入的内容
            if userId.isEmpty && password.isEmpty, let creds = authVM.getRememberedCredentials() {
                userId = creds.userId
                password = creds.password
            }
        }
        .onChange(of: userId) { _, newValue in
            authVM.userIdDidChange(to: newValue)
            captchaInput = ""
        }
        .onChange(of: authVM.captchaImage) { _, _ in
            captchaInput = ""
        }
    }

    // MARK: - Layout

    /// iPhone 与 iPad 竖屏：单列，表单容器限制为 520 宽
    private var compactBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                appBrand
                preloginSection
                inputSection
                disclaimerNotice
                maintenanceNotice
                errorSection
                loginSection
                Spacer(minLength: 40)
            }
            .readableWidth(520)
        }
    }

    /// iPad 横屏：左侧品牌区，右侧表单区（同一组视图，仅调整位置）
    private var wideBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                appBrand
                maintenanceNotice
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        preloginSection
                        inputSection
                        disclaimerNotice
                        errorSection
                        loginSection
                        Spacer(minLength: 0)
                    }
                    .readableWidth(440)
                    .frame(minHeight: geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var appBrand: some View {
        VStack(spacing: 14) {
            Image("LoginAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 20))

            Text("彩带小工具")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("智能学业分析 · 安财专属")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var preloginSection: some View {
        if let notice = preloginNotice {
            preloginBanner(notice)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
    }

    private var inputSection: some View {
        VStack(spacing: 16) {
            inputField(icon: "person.fill", placeholder: "学号", text: $userId, isSecure: false, warning: fullWidthWarning(userId))
                .keyboardType(.numberPad)

            passwordField(placeholder: "教务系统密码", text: $password, warning: fullWidthWarning(password))
            if let captchaImage = authVM.captchaImage {
                captchaField(image: captchaImage)
            }
        }
        .padding(.horizontal, 32)
    }

    private var disclaimerNotice: some View {
        Text("登录即表示同意上传匿名使用统计（本地随机 ID、学号前四位与加盐哈希、版本和基础设备信息），不会上传密码、完整学号或业务内容。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 18)
    }

    private var maintenanceNotice: some View {
        Text("彩带小工具由开源工作者维护，可能与学校系统存在不同步风险，重要信息可能无法及时更新展示，请以学校官方信息为准。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = authVM.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(error).foregroundStyle(.red)
            }
            .font(.subheadline)
            .padding(.top, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var loginSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            loginButton(cooldownRemaining: cooldownRemaining(at: context.date))
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        if let qqGroupManifest {
            QqGroupEntryCard(manifest: qqGroupManifest)
                .padding(.horizontal, 32)
                .padding(.top, 14)
        }

        Button {
            showPasswordHelp = true
        } label: {
            Label("不知道密码是什么？", systemImage: "questionmark.circle")
                .font(.subheadline)
        }
        .padding(.top, 16)
        LoginDiagnosticsButton()
    }

    private var canLogin: Bool {
        !userId.isEmpty && !password.isEmpty
            && !hasFullWidthChars(userId)
            && !hasFullWidthChars(password)
            && captchaReady
    }

    /// 全角字符提示（与 Android LoginScreen 一致）：仅提示、不转换；命中时禁止登录
    private func fullWidthWarning(_ text: String) -> String? {
        hasFullWidthChars(text) ? "含全角字符 \(describeFullWidthChars(text))，请用英文半角" : nil
    }

    // MARK: - Captcha & Cooldown

    private var trimmedCaptchaInput: String {
        captchaInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 验证码激活时必须非空且不含全角字符（全角提示见 captchaField）
    private var captchaReady: Bool {
        authVM.captchaImage == nil || (!trimmedCaptchaInput.isEmpty && !hasFullWidthChars(trimmedCaptchaInput))
    }

    private var captchaWarning: String? {
        hasFullWidthChars(trimmedCaptchaInput) ? "验证码含全角字符，请用英文半角" : nil
    }

    /// 距冷却结束的剩余秒数；0 表示无冷却
    private func cooldownRemaining(at date: Date) -> Int {
        guard let until = authVM.cooldownUntil, until > date else { return 0 }
        return LoginThrottle.remainingSeconds(until: until, now: date)
    }

    /// 登录入口：教务密码为弱密码形式时先弹窗，用户选择"继续登录"后才提交
    private func requestLogin() {
        if isWeakSchoolPassword(password) {
            showWeakPasswordAlert = true
        } else {
            submitLogin()
        }
    }

    private func submitLogin() {
        authVM.login(
            userId: userId,
            password: password,
            gatewayPassword: nil,
            captchaCode: authVM.captchaImage == nil ? nil : trimmedCaptchaInput
        )
    }

    private func loginButton(cooldownRemaining remaining: Int) -> some View {
        let loading = authVM.state == .loading
        return Button {
            requestLogin()
        } label: {
            Group {
                if loading {
                    ProgressView().tint(.white)
                } else if remaining > 0 {
                    Text("请 \(remaining) 秒后再试")
                        .fontWeight(.semibold)
                } else {
                    Text("登录")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.white)
            .background(canLogin && remaining == 0 ? Color.blue : Color.gray.opacity(0.35), in: .rect(cornerRadius: 14))
        }
        .disabled(!canLogin || remaining > 0 || loading)
    }

    private func captchaField(image: Data) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                TextField("验证码", text: $captchaInput)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    captchaInput = ""
                    authVM.refreshCaptcha()
                } label: {
                    captchaImageView(image)
                }
                .disabled(authVM.state == .loading)
                .accessibilityLabel("验证码图片，点击刷新")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .overlay { fieldErrorBorder(captchaWarning) }
            fieldWarning(captchaWarning)
        }
    }

    @ViewBuilder
    private func captchaImageView(_ data: Data) -> some View {
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 44)
        } else {
            Image(systemName: "arrow.clockwise")
                .frame(height: 44)
        }
    }

    // MARK: - Pre-login Notice

    private func preloginBanner(_ notice: PreloginNotice) -> some View {
        let tint: Color = {
            switch notice.level ?? "warning" {
            case "critical": return .red
            case "info": return .blue
            default: return .orange
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "megaphone.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                if let title = notice.title, !title.isEmpty {
                    Text(title).font(.subheadline.weight(.semibold))
                }
                if let content = notice.content, !content.isEmpty {
                    Text(content).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func passwordField(placeholder: String, text: Binding<String>, warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                Group {
                    if showPassword {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .overlay { fieldErrorBorder(warning) }
            fieldWarning(warning)
        }
    }

    private func inputField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool, warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .overlay { fieldErrorBorder(warning) }
            fieldWarning(warning)
        }
    }

    @ViewBuilder
    private func fieldErrorBorder(_ warning: String?) -> some View {
        if warning != nil {
            RoundedRectangle(cornerRadius: 12).stroke(.red, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func fieldWarning(_ warning: String?) -> some View {
        if let warning {
            Text(warning)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }
    }
}

private struct PasswordHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PasswordHelpSection(
                        icon: "lock.fill",
                        title: "教务系统密码",
                        description: "通常只需填写教务系统密码，彩带小工具会使用同一密码建立校内访问并登录教务系统。"
                    )
                    passwordHelpImage("UAAP", description: "UAAP 登录界面")


                    infoCard(
                        icon: "info.circle.fill",
                        tint: .blue,
                        text: "如果没有修改过密码，默认密码通常是身份证后六位。"
                    )
                    infoCard(
                        icon: "lightbulb.fill",
                        tint: .orange,
                        text: "忘记密码时，请通过学校官方教务系统确认或重置。"
                    )
                }
                .padding()
            }
            .navigationTitle("密码说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("我知道了") { dismiss() }
                }
            }
        }
    }

    private func passwordHelpImage(_ name: String, description: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .clipShape(.rect(cornerRadius: 14))
            .accessibilityLabel(description)
    }

    private func infoCard(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

private struct PasswordHelpSection: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
