import SwiftUI

struct DoorCardView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = DoorCardViewModel()
    @State private var bindUserno = ""
    @State private var bindUsername = ""
    @State private var bindPassword = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.isBound { boundView } else { bindFormView }
            }
            .navigationTitle("门卡")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.initialize(userId: authVM.userId) }
        }
    }

    @ViewBuilder
    private var bindFormView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "key.card.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.teal.gradient)
                    .padding(24)
                    .glassCircle()
                    .padding(.top, 40)

                Text("绑定门卡").font(.title2).fontWeight(.bold)
                Text("输入门卡系统的账号信息").font(.subheadline).foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "number").foregroundStyle(.secondary)
                        TextField("学号", text: $bindUserno).keyboardType(.numberPad)
                    }.padding(14).glassCard(cornerRadius: 14)

                    HStack(spacing: 10) {
                        Image(systemName: "person.fill").foregroundStyle(.secondary)
                        TextField("姓名", text: $bindUsername)
                    }.padding(14).glassCard(cornerRadius: 14)

                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        SecureField("密码", text: $bindPassword)
                    }.padding(14).glassCard(cornerRadius: 14)
                }
                .padding(.horizontal, 24)

                if let error = vm.bindError {
                    HStack { Image(systemName: "xmark.circle.fill"); Text(error) }
                        .font(.caption).foregroundStyle(.red)
                        .padding(10).glassCapsule(tint: .red.opacity(0.1))
                }

                Button {
                    vm.bind(userno: bindUserno, username: bindUsername, rawPassword: bindPassword)
                } label: {
                    Group {
                        if vm.isBinding { ProgressView() } else { Text("绑定").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                }
                .padding(.horizontal, 24)
                .glassInteractiveCard(tint: .teal.opacity(0.3), cornerRadius: 14)
                .disabled(bindUserno.isEmpty || bindUsername.isEmpty || bindPassword.isEmpty || vm.isBinding)
            }
        }
    }

    @ViewBuilder
    private var boundView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let info = vm.userInfo {
                    VStack(spacing: 12) {
                        Image(systemName: "key.card.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                        Text(info.personName).font(.title2).fontWeight(.bold).foregroundStyle(.white)
                        Text("ID: \(info.personId)").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(LinearGradient(colors: [.teal, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(.rect(cornerRadius: 20))
                    .shadow(color: .teal.opacity(0.3), radius: 12, y: 6)
                }

                if !vm.rooms.isEmpty {
                    GlassSectionHeader(title: "房间", icon: "door.left.hand.open")
                    ForEach(vm.rooms) { room in
                        Button { vm.selectRoom(room) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(room.roomName).fontWeight(.medium)
                                    Text(room.buildName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vm.selectedRoom?.roomId == room.roomId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                                }
                            }
                            .padding(12)
                            .glassInteractiveCard(cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Circle().fill(bleStatusColor).frame(width: 10, height: 10)
                        Text(bleStatusText).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .glassCard(cornerRadius: 12)

                    Button("连接") { vm.connectBle() }
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity).padding(10)
                        .glassInteractiveCard(tint: .blue.opacity(0.2), cornerRadius: 12)
                        .disabled(vm.bleState == .connected || vm.bleState == .scanning)

                    Button("断开") { vm.disconnectBle() }
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity).padding(10)
                        .glassInteractiveCard(cornerRadius: 12)
                        .disabled(vm.bleState == .disconnected)
                }

                if vm.bleState == .connected {
                    Button { vm.openDoor() } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "lock.open.fill").font(.system(size: 36))
                            Text("开 门").font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 140)
                    }
                    .glassCircle()
                    .shadow(color: .green.opacity(0.4), radius: 20)
                    .disabled(vm.isOperating)
                    .padding(.vertical, 8)

                    CompatGlassContainer {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            OpButton(title: "发卡", icon: "creditcard.fill", tint: .blue) { vm.addCard() }
                            OpButton(title: "冻结", icon: "snowflake", tint: .cyan) { vm.freezeCard() }
                            OpButton(title: "校时", icon: "clock.fill", tint: .orange) { vm.checkTime() }
                        }
                    }
                }

                if let msg = vm.operationMessage {
                    HStack {
                        Image(systemName: msg.contains("成功") ? "checkmark.circle.fill" : msg.contains("失败") ? "xmark.circle.fill" : "info.circle.fill")
                        Text(msg)
                    }
                    .font(.subheadline)
                    .padding(12)
                    .glassCapsule(tint: msg.contains("成功") ? .green.opacity(0.2) : msg.contains("失败") ? .red.opacity(0.2) : .blue.opacity(0.1))
                }

                Button("解绑门卡", role: .destructive) { vm.unbind() }
                    .padding(.top, 16)
            }
            .padding()
        }
    }

    private var bleStatusText: String {
        switch vm.bleState {
        case .disconnected: "未连接"; case .scanning: "搜索中"
        case .connecting: "连接中"; case .connected: "已连接"; case .error: "失败"
        }
    }
    private var bleStatusColor: Color {
        switch vm.bleState {
        case .connected: .green; case .error: .red
        case .scanning, .connecting: .orange; case .disconnected: .gray
        }
    }
}

struct OpButton: View {
    let title: String; let icon: String; var tint: Color = .blue; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(tint.gradient)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassInteractiveCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}
