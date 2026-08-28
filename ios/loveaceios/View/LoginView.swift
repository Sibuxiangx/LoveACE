import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var userId = ""
    @State private var ecPassword = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showAdvancedOptions = false
    @State private var usesSeparateGatewayPassword = false
    @State private var showPasswordHelp = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                VStack(spacing: 14) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)

                    Text("彩带小工具")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("智能学业分析 · 安财专属")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 44)

                VStack(spacing: 16) {
                    inputField(icon: "person.fill", placeholder: "学号", text: $userId, isSecure: false)
                        .keyboardType(.numberPad)
                        .textContentType(.username)

                    passwordField(placeholder: "教务系统密码", text: $password)

                    DisclosureGroup(isExpanded: $showAdvancedOptions) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("我的网关密码和教务密码不一样", isOn: $usesSeparateGatewayPassword)
                                .font(.subheadline)
                            if usesSeparateGatewayPassword {
                                inputField(icon: "network", placeholder: "网关密码", text: $ecPassword, isSecure: true)
                                    .textContentType(.password)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("高级选项", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(.secondary)
                }
                .padding(.horizontal, 32)

                Text("登录即表示同意上传匿名使用统计（本地随机 ID、学号前四位与加盐哈希、版本和基础设备信息），不会上传密码、完整学号或业务内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 18)

                Text("彩带小工具由开源工作者维护，可能与学校系统存在不同步风险，重要信息可能无法及时更新展示，请以学校官方信息为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                if let error = authVM.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(error).foregroundStyle(.red)
                    }
                    .font(.subheadline)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    authVM.login(
                        userId: userId,
                        password: password,
                        gatewayPassword: usesSeparateGatewayPassword ? ecPassword : nil
                    )
                } label: {
                    Group {
                        if authVM.state == .loading {
                            ProgressView().tint(.white)
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(canLogin ? Color.blue : Color.gray.opacity(0.35), in: .rect(cornerRadius: 14))
                }
                .disabled(!canLogin || authVM.state == .loading)
                .padding(.horizontal, 32)
                .padding(.top, 28)

                Button {
                    showPasswordHelp = true
                } label: {
                    Label("不知道密码是什么？", systemImage: "questionmark.circle")
                        .font(.subheadline)
                }
                .padding(.top, 16)

                Spacer(minLength: 40)
            }
        }
        .sheet(isPresented: $showPasswordHelp) {
            PasswordHelpView()
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if let creds = authVM.getRememberedCredentials() {
                userId = creds.userId
                password = creds.password
                if creds.ecPassword != creds.password {
                    ecPassword = creds.ecPassword
                    showAdvancedOptions = true
                    usesSeparateGatewayPassword = true
                }
            }
        }
    }

    private var canLogin: Bool {
        !userId.isEmpty && !password.isEmpty
            && (!usesSeparateGatewayPassword || !ecPassword.isEmpty)
    }

    private func passwordField(placeholder: String, text: Binding<String>) -> some View {
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
            .textContentType(.password)
            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }

    private func inputField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
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
                        icon: "slider.horizontal.3",
                        tint: .orange,
                        text: "只有在你确认网关密码与教务系统密码不同时，才需要在登录页的高级选项中单独填写网关密码。"
                    )

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
