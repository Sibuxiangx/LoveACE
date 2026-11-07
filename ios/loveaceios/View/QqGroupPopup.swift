import SwiftUI
import UIKit

/// 登录页加群入口：醒目卡片，点击打开 `QqGroupPopup`。
struct QqGroupEntryCard: View {
    let manifest: QqGroupManifest
    @State private var showPopup = false

    var body: some View {
        Button {
            showPopup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("加入交流群")
                        .font(.headline.weight(.bold))
                    Text("\(manifest.title) · 点击查看群号与二维码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassInteractiveCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showPopup) {
            QqGroupPopup(manifest: manifest)
                .presentationBackground(.clear)
        }
    }
}

/// "我的"页设置行：与登录页入口打开同一个弹窗。
struct QqGroupSettingsRow: View {
    let manifest: QqGroupManifest
    @State private var showPopup = false

    var body: some View {
        Button {
            showPopup = true
        } label: {
            Label("加入交流群", systemImage: "person.3.fill")
        }
        .fullScreenCover(isPresented: $showPopup) {
            QqGroupPopup(manifest: manifest)
                .presentationBackground(.clear)
        }
    }
}

/// 加群弹窗：居中卡片 + 半透明遮罩，点遮罩或"关闭"退出。
struct QqGroupPopup: View {
    let manifest: QqGroupManifest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                Text(manifest.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                qrImage

                HStack {
                    Text("群号 ") + Text(manifest.groupNumber).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Button(copied ? "已复制" : "复制") {
                        copyGroupNumber()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .font(.subheadline)

                Button {
                    if let url = URL(string: manifest.shareUrl) {
                        openURL(url)
                    }
                } label: {
                    Text("打开加群链接")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("关闭") {
                    dismiss()
                }
                .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .glassCard(cornerRadius: 24)
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private var qrImage: some View {
        AsyncImage(url: URL(string: manifest.qrImageUrl)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image(systemName: "qrcode")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            default:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func copyGroupNumber() {
        UIPasteboard.general.string = manifest.groupNumber
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
