import SwiftUI

struct ElectricityView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = ElectricityViewModel()
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if vm.boundRoomCode == nil {
                    unboundView
                } else {
                    boundContentView
                }
            }
            .navigationTitle("宿舍电费")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let isim = authVM.isimService { vm.initialize(service: isim); vm.autoLoad() }
            }
        }
    }

    // MARK: - Unbound

    @ViewBuilder
    private var unboundView: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow.gradient)
                    Text("选择宿舍房间").font(.headline)
                    Text("依次选择楼栋、楼层、房间").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            if vm.isLoadingOptions && vm.buildings.isEmpty {
                Section { HStack { Spacer(); ProgressView("加载楼栋..."); Spacer() }.padding(.vertical, 20) }
            } else if vm.buildings.isEmpty {
                Section {
                    Button { vm.loadBuildings() } label: {
                        Label("加载楼栋列表", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                }
            } else {
                Section {
                    ForEach(vm.buildings, id: \.["code"]) { b in
                        NavigationLink {
                            FloorPickerView(service: vm.getService()!, buildingCode: b["code"] ?? "", buildingName: b["name"] ?? "", onConfirm: { code, display in
                                vm.bindRoom(code: code, display: display)
                                navPath = NavigationPath()
                            })
                        } label: {
                            Text(b["name"] ?? "")
                        }
                    }
                } header: {
                    Text("选择楼栋")
                } footer: {
                    Text("部分楼栋由于学校系统也没有提供查询，故彩带也无法查询")
                }
            }

            if let error = vm.error {
                Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption) }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { if vm.buildings.isEmpty { vm.loadBuildings() } }
    }

    // MARK: - Bound

    @ViewBuilder
    private var boundContentView: some View {
        List {
            if let display = vm.boundRoomDisplay {
                Section {
                    HStack {
                        Label(display, systemImage: "building.2.fill")
                        Spacer()
                        Button("更换房间") { vm.clearBinding() }.font(.caption)
                    }
                }
            }

            if vm.isLoading {
                Section { HStack { Spacer(); ProgressView("查询电费..."); Spacer() }.padding(.vertical, 20) }
            } else if let info = vm.electricityInfo {
                Section("电费余额") {
                    VStack(spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", info.balance.total))
                                .font(AppFont.heroNumber)
                                .foregroundStyle(info.balance.total > 50 ? .green : info.balance.total > 20 ? .orange : .red)
                            Text("度").font(.title3).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        ProgressView(value: min(info.balance.total / 200.0, 1.0))
                            .tint(info.balance.total > 50 ? .green : info.balance.total > 20 ? .orange : .red)
                        HStack {
                            LabeledContent("购电剩余", value: String(format: "%.1f 度", info.balance.remainingPurchased))
                            Spacer()
                            LabeledContent("补助剩余", value: String(format: "%.1f 度", info.balance.remainingSubsidy))
                        }.font(.caption)
                    }.padding(.vertical, 8)
                }
                if !info.usageRecords.isEmpty {
                    Section("用电记录") {
                        ForEach(info.usageRecords) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) { Text(r.recordTime).font(.subheadline); Text(r.meterName).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(String(format: "%.2f 度", r.usageAmount)).font(.subheadline).fontWeight(.medium).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if !info.payments.isEmpty {
                    Section("缴费记录") {
                        ForEach(info.payments) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) { Text(p.paymentTime).font(.subheadline); Text(p.paymentType).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(String(format: "%.1f 元", p.amount)).font(.subheadline).fontWeight(.medium).foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            if let error = vm.error {
                Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption) }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            if let code = vm.boundRoomCode { vm.loadElectricityInfo(roomCode: code, displayText: vm.boundRoomDisplay) }
        }
    }
}

// MARK: - Transfer Sheet

struct TransferSheet: View {
    @Bindable var yktVM: YKTViewModel
    let onDone: () -> Void
    @State private var amountText = ""
    @State private var showConfirmAlert = false
    @Environment(\.dismiss) private var dismiss

    private var amount: Int? { Int(amountText) }
    private var canPay: Bool {
        guard let amt = amount, amt > 0, yktVM.selectedRoom != nil, !yktVM.isPaying else { return false }
        if let info = yktVM.studentInfo { return Double(amt) <= info.balance }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                if let info = yktVM.studentInfo {
                    Section("一卡通信息") {
                        LabeledContent("姓名", value: info.name)
                        LabeledContent("学号", value: info.studentId)
                        LabeledContent("卡余额", value: String(format: "¥%.2f", info.balance))
                    }
                } else {
                    Section { HStack { Spacer(); ProgressView("加载一卡通信息..."); Spacer() }.padding(.vertical, 16) }
                }

                Section("选择充值房间") {
                    optionPicker(title: "校区", options: yktVM.dorms, selected: yktVM.selectedDorm) { yktVM.selectDorm($0) }
                    if yktVM.selectedDorm != nil {
                        optionPicker(title: "楼栋", options: yktVM.buildings, selected: yktVM.selectedBuilding) { yktVM.selectBuilding($0) }
                    }
                    if yktVM.selectedBuilding != nil {
                        optionPicker(title: "楼层", options: yktVM.floors, selected: yktVM.selectedFloor) { yktVM.selectFloor($0) }
                    }
                    if yktVM.selectedFloor != nil {
                        optionPicker(title: "房间", options: yktVM.rooms, selected: yktVM.selectedRoom) { yktVM.selectRoom($0) }
                    }
                    if yktVM.loadingOptions {
                        HStack { Spacer(); ProgressView().controlSize(.small); Text("加载中...").font(.caption).foregroundStyle(.secondary); Spacer() }
                    }
                }

                if yktVM.selectedRoom != nil {
                    Section("充值金额") {
                        HStack {
                            Text("¥").font(.title2).foregroundStyle(.secondary)
                            TextField("输入金额（元）", text: $amountText)
                                .keyboardType(.numberPad)
                                .font(.title2)
                        }

                        HStack(spacing: 10) {
                            ForEach([10, 20, 50, 100], id: \.self) { preset in
                                Button("\(preset)") {
                                    amountText = "\(preset)"
                                }
                                .font(.subheadline).fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(amountText == "\(preset)" ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
                                .foregroundStyle(amountText == "\(preset)" ? .blue : .primary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button {
                            showConfirmAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                if yktVM.isPaying {
                                    ProgressView().controlSize(.small).tint(.white)
                                    Text("划转中...").foregroundStyle(.white)
                                } else {
                                    Text("确认划转").fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(!canPay)
                        .listRowBackground(canPay ? Color.blue : Color.blue.opacity(0.3))
                        .foregroundStyle(.white)
                    }
                }

                if let result = yktVM.paymentResult {
                    Section {
                        Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .green : .red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("一卡通划转电费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("确认划转", isPresented: $showConfirmAlert) {
                Button("取消", role: .cancel) {}
                Button("确认划转") {
                    guard let amt = amount else { return }
                    yktVM.payElectricity(amount: amt)
                }
            } message: {
                Text("将从一卡通划转 ¥\(amountText) 至电费账户，确认操作？")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(yktVM.isPaying)
    }

    @ViewBuilder
    private func optionPicker(title: String, options: [SelectOption], selected: SelectOption?, onSelect: @escaping (SelectOption) -> Void) -> some View {
        if options.isEmpty && !yktVM.loadingOptions {
            LabeledContent(title, value: "等待上级选择")
                .foregroundStyle(.tertiary)
        } else {
            Menu {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack {
                            Text(option.name)
                            if selected?.value == option.value {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text(selected?.name ?? "请选择")
                        .foregroundStyle(selected != nil ? .primary : .secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Floor Picker (own data, not shared)

struct FloorPickerView: View {
    let service: ISIMService
    let buildingCode: String
    let buildingName: String
    let onConfirm: (String, String) -> Void
    @State private var floors: [[String: String]] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section { HStack { Spacer(); ProgressView("加载楼层..."); Spacer() }.padding(.vertical, 20) }
            } else if floors.isEmpty {
                Section { Text("暂无楼层数据").foregroundStyle(.secondary) }
            } else {
                Section("选择楼层 — \(buildingName)") {
                    ForEach(floors, id: \.["code"]) { f in
                        NavigationLink {
                            RoomPickerView(service: service, floorCode: f["code"] ?? "", floorName: f["name"] ?? "", buildingName: buildingName, onConfirm: onConfirm)
                        } label: {
                            Text(f["name"] ?? "")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("选择楼层")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await service.getFloors(buildingCode: buildingCode)
            floors = result.data ?? []
            isLoading = false
        }
    }
}

// MARK: - Room Picker (own data, not shared)

struct RoomPickerView: View {
    let service: ISIMService
    let floorCode: String
    let floorName: String
    let buildingName: String
    let onConfirm: (String, String) -> Void
    @State private var rooms: [[String: String]] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if isLoading {
                Section { HStack { Spacer(); ProgressView("加载房间..."); Spacer() }.padding(.vertical, 20) }
            } else if rooms.isEmpty {
                Section { Text("暂无房间数据").foregroundStyle(.secondary) }
            } else {
                Section("选择房间 — \(buildingName) \(floorName)") {
                    ForEach(rooms, id: \.["code"]) { r in
                        Button {
                            let display = "\(buildingName) \(floorName) \(r["name"] ?? "")"
                            onConfirm(r["code"] ?? "", display)
                        } label: {
                            HStack {
                                Text(r["name"] ?? "")
                                Spacer()
                                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("选择房间")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await service.getRooms(floorCode: floorCode)
            rooms = result.data ?? []
            isLoading = false
        }
    }
}
