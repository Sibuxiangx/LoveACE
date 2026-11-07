import SwiftUI

struct YKTView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.wideLayout) private var wideLayout
    @State private var vm = YKTViewModel()
    @State private var showTransferSheet = false
    @State private var showPasswordDialog = false
    @State private var passwordInput = ""
    @State private var passwordError = false

    var body: some View {
        NavigationStack {
            Group {
                if wideLayout {
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 16) {
                                balanceHero
                                transferButton
                            }
                            .padding()
                        }
                        .frame(width: 380)
                        Divider()
                        ScrollView {
                            VStack(spacing: 16) {
                                recordsContent
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            balanceHero
                            transferButton
                            recordsContent
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("一卡通")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { vm.loadAll() }
            .onAppear {
                if let ykt = authVM.yktService { vm.initialize(service: ykt, portal: authVM.portalService); vm.loadAll() }
            }
            .alert("身份验证", isPresented: $showPasswordDialog) {
                SecureField("校园网关或教务处密码", text: $passwordInput)
                Button("取消", role: .cancel) { passwordInput = ""; passwordError = false }
                Button("确认") {
                    if authVM.verifyPassword(passwordInput) {
                        passwordError = false
                        passwordInput = ""
                        vm.unlockPayment()
                        showTransferSheet = true
                    } else {
                        passwordError = true
                        passwordInput = ""
                        showPasswordDialog = true
                    }
                }
            } message: {
                Text(passwordError ? "密码错误，请重新输入" : "请输入校园网关密码或教务处密码以验证身份")
            }
            .sheet(isPresented: $showTransferSheet, onDismiss: {
                vm.lockPayment()
            }) {
                TransferSheet(yktVM: vm, onDone: {
                    showTransferSheet = false
                    vm.loadAll()
                })
            }
        }
    }

    @ViewBuilder
    private var recordsContent: some View {
        if !vm.consumption.isEmpty { transactionSection }
        else if vm.isConsumptionLoading {
            ProgressView("加载消费记录...")
                .padding(20)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 16)
        } else if let error = vm.consumptionError {
            VStack(spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") { vm.reloadConsumption() }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 16)
        } else if vm.consumptionLoaded {
            Text("本月暂无消费记录")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 16)
        }
    }

    @ViewBuilder
    private var balanceHero: some View {
        VStack(spacing: 12) {
            Text("校园卡余额").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            if let balance = vm.balance {
                Text("¥\(String(format: "%.2f", balance.balance))")
                    .font(AppFont.heroNumber)
                    .foregroundStyle(.white)
            } else if vm.isLoading {
                ProgressView().tint(.white).scaleEffect(1.2)
            } else if let error = vm.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                Button("重试") { vm.loadBalance() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            LinearGradient(colors: [.blue, .teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .teal.opacity(0.3), radius: 16, y: 8)
    }

    @ViewBuilder
    private var transferButton: some View {
        Button {
            showPasswordDialog = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("划转电费")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("从一卡通余额划转至宿舍电费账户")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassInteractiveCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var transactionSection: some View {
        GlassSectionHeader(title: "本月消费", icon: "clock.arrow.circlepath")
        VStack(spacing: 0) {
            ForEach(Array(vm.consumption.enumerated()), id: \.element.id) { index, tx in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.area).font(.subheadline).lineLimit(1)
                        Text("\(tx.date) \(tx.time)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 4)
                    Text("¥\(tx.amount)")
                        .font(.subheadline).monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                if index < vm.consumption.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
            if vm.consumption.count < vm.consumptionTotal {
                Button {
                    vm.loadMoreConsumption()
                } label: {
                    Group {
                        if vm.isConsumptionLoading {
                            ProgressView()
                        } else {
                            Text("加载更多")
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .disabled(vm.isConsumptionLoading)
            }
        }
        .glassCard(cornerRadius: 12)
        Text("已显示 \(vm.consumption.count) 条，共 \(vm.consumptionTotal) 条")
            .font(.caption2)
            .foregroundStyle(.secondary)
        if let error = vm.consumptionError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重试") { vm.loadMoreConsumption() }
                .buttonStyle(.bordered)
        }
    }
}
