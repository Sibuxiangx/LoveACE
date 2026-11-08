import SwiftUI
import UIKit

/// 登录页的诊断分享入口：存在失败记录时显示。
/// 点击后弹出系统同意弹窗，确认后上传脱敏诊断；成功展示结果页（链接、复制、加入用户群）。
struct LoginDiagnosticsButton: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var showConsent = false
    @State private var consentCount = 0
    @State private var uploading = false
    @State private var errorText: String?
    @State private var uploaded: DiagnosticsUploader.UploadResult?

    var body: some View {
        // 外层容器始终存在：内容为空时 task/onChange 仍会触发
        VStack(spacing: 8) {
            if authVM.diagnosticsAvailable {
                Button(action: requestUpload) {
                    HStack(spacing: 6) {
                        if uploading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("分享登录诊断")
                    }
                    .font(.subheadline)
                }
                .disabled(uploading)
                .padding(.top, 8)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task { authVM.refreshDiagnosticsState() }
        .onChange(of: authVM.errorMessage) { _, _ in authVM.refreshDiagnosticsState() }
        .alert("上传登录诊断", isPresented: $showConsent) {
            Button("取消", role: .cancel) {}
            Button("上传") { startUpload() }
        } message: {
            Text("将上传最近 \(consentCount) 次登录的脱敏诊断（学号部分隐藏，密码、Cookie、令牌等已替换为占位符）。链接 3 天后失效。是否继续？")
        }
        .sheet(item: $uploaded) { result in
            DiagnosticsResultSheet(result: result)
        }
    }

    private func requestUpload() {
        errorText = nil
        Task {
            consentCount = await LoginDiagnostics.shared.attemptCount
            showConsent = true
        }
    }

    private func startUpload() {
        uploading = true
        errorText = nil
        Task {
            defer { uploading = false }
            let body = await LoginDiagnostics.shared.exportJSON(
                appVersion: Self.appVersion,
                appBuild: Self.appBuild,
                device: Self.deviceInfo()
            )
            do {
                uploaded = try await DiagnosticsUploader.upload(body)
            } catch {
                errorText = ((error as? DiagnosticsUploadError) ?? .transport).message
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private static func deviceInfo() -> LoginDiagnostics.DeviceInfo {
        let device = UIDevice.current
        let seconds = TimeZone.current.secondsFromGMT()
        let magnitude = abs(seconds)
        let sign = seconds < 0 ? "-" : "+"
        return LoginDiagnostics.DeviceInfo(
            model: device.model,
            os: device.systemName,
            osVersion: device.systemVersion,
            timezone: "\(sign)\(String(format: "%02ld:%02ld", magnitude / 3600, magnitude % 3600 / 60))",
            locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        )
    }
}

private extension DiagnosticsUploadError {
    var message: String {
        switch self {
        case .notConfigured: "上传失败：客户端未配置上传密钥"
        case .transport: "上传失败：网络连接异常，请稍后再试"
        case .invalidResponse: "上传失败：服务器响应异常"
        case .server(let status, let code): "上传失败：\(code)（HTTP \(status)）"
        }
    }
}

/// 上传成功后的结果页：可选中的链接、复制按钮、加入用户群入口。
private struct DiagnosticsResultSheet: View {
    let result: DiagnosticsUploader.UploadResult
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var group: QqGroupManifest?
    @State private var showGroup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("诊断已上传", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("链接有效期至 \(result.expiresAt.formatted(date: .abbreviated, time: .shortened))，到期后自动失效。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("诊断链接")
                            .font(.subheadline.weight(.semibold))
                        Text(result.url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                        Button(copied ? "已复制" : "复制链接") {
                            copyLink()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }

                    if let group {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("遇到登录问题？加入用户群，把这个链接发给开发者，能更快定位原因。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("加入用户群") {
                                showGroup = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .fullScreenCover(isPresented: $showGroup) {
                                QqGroupPopup(manifest: group)
                                    .presentationBackground(.clear)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("上传成功")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                group = await QqGroupService.fetch()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func copyLink() {
        UIPasteboard.general.string = result.url.absoluteString
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
