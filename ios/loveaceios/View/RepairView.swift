import SwiftUI

struct RepairView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = RepairViewModel()
    @State private var selectedTab = 0
    @State private var showSubmitSheet = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tabButton("待处理", count: vm.pending.count, tag: 0)
                        tabButton("已完成", count: vm.completed.count, tag: 1)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if vm.isLoading { LoadingView() }
                    else {
                        let orders = selectedTab == 0 ? vm.pending : vm.completed
                        if orders.isEmpty {
                            EmptyStateView(title: "暂无工单", systemImage: "doc.text.magnifyingglass")
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(orders, id: \.taskId) { order in
                                        RepairOrderCard(order: order) { vm.loadDetail(taskId: order.taskId) }
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }

                Button { showSubmitSheet = true; vm.loadFormData() } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                }
                .glassCircle()
                .shadow(color: .blue.opacity(0.3), radius: 12)
                .padding(20)
            }
            .navigationTitle("报修")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSubmitSheet) {
                RepairSubmitSheet(vm: vm, isPresented: $showSubmitSheet)
            }
            .detailPanel(item: Binding(get: { vm.detail.map { IdentifiableWrapper(value: $0) } }, set: { _ in vm.clearDetail() })) { wrapper in
                RepairDetailSheet(detail: wrapper.value)
            }
            .refreshable { vm.loadOrders() }
            .onAppear {
                if let svc = authVM.repairService { vm.initialize(service: svc); vm.loadOrders() }
            }
        }
    }

    private func tabButton(_ title: String, count: Int, tag: Int) -> some View {
        Button { withAnimation(.snappy) { selectedTab = tag } } label: {
            Text("\(title) (\(count))")
                .font(.subheadline).fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .glassCapsule(tint: selectedTab == tag ? .blue.opacity(0.2) : nil, interactive: selectedTab == tag)
        .foregroundStyle(selectedTab == tag ? .blue : .secondary)
    }
}

struct RepairOrderCard: View {
    let order: RepairOrder
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(order.title).font(.body).fontWeight(.medium)
                    Spacer()
                    GlassBadge(text: order.statusText, tint: order.isPending ? .orange : .green)
                }
                if !order.location.isEmpty {
                    Label(order.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary)
                }
                if !order.createTime.isEmpty {
                    Label(order.createTime, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassInteractiveCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

struct RepairDetailSheet: View {
    let detail: RepairOrderDetail
    @DetailDismiss private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    detailRow("故障区域", detail.faultArea)
                    detailRow("维修项目", detail.repairProject)
                    detailRow("联系电话", detail.phone)
                    detailRow("故障地址", detail.faultAddress)
                    if !detail.description.isEmpty { detailRow("描述", detail.description) }
                    if !detail.progress.isEmpty {
                        GlassSectionHeader(title: "维修进度", icon: "arrow.triangle.branch")
                        ForEach(detail.progress) { p in
                            HStack {
                                Text(p.stage).fontWeight(.medium)
                                Spacer()
                                Text(p.time).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .glassCard(cornerRadius: 10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("工单详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer()
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }
}

// MARK: - Repair Submit Sheet

struct RepairSubmitSheet: View {
    @Bindable var vm: RepairViewModel
    @Binding var isPresented: Bool
    @State private var selectedArea: RepairAreaItem?
    @State private var selectedProject: RepairProjectItem?
    @State private var phone = ""
    @State private var address = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.isFormLoading {
                    LoadingView(message: "加载报修信息...")
                } else if let formError = vm.formError {
                    ErrorView(message: formError) { vm.loadFormData() }
                } else if let formData = vm.formData {
                    Form {
                        Section("故障区域") {
                            ForEach(formData.areas) { group in
                                if !group.items.isEmpty {
                                    DisclosureGroup(group.groupName) {
                                        ForEach(group.items) { item in
                                            Button {
                                                selectedArea = item
                                            } label: {
                                                HStack {
                                                    Text(item.name)
                                                    Spacer()
                                                    if selectedArea?.itemId == item.itemId {
                                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                                    }
                                                }
                                            }
                                            .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                        }

                        Section("维修项目") {
                            ForEach(formData.projects) { group in
                                if !group.items.isEmpty {
                                    DisclosureGroup(group.groupName) {
                                        ForEach(group.items) { item in
                                            Button {
                                                selectedProject = item
                                            } label: {
                                                HStack {
                                                    Text(item.name)
                                                    Spacer()
                                                    if selectedProject?.itemId == item.itemId {
                                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                                    }
                                                }
                                            }
                                            .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                        }

                        Section("已选择") {
                            LabeledContent("区域", value: selectedArea?.name ?? "未选择")
                            LabeledContent("项目", value: selectedProject?.name ?? "未选择")
                        }

                        Section("联系信息") {
                            TextField("联系电话", text: $phone)
                                .keyboardType(.phonePad)
                            TextField("详细地址（如：X栋X室）", text: $address)
                        }

                        Section("故障描述") {
                            TextEditor(text: $description)
                                .frame(minHeight: 80)
                        }

                        if vm.submitError != nil {
                            Section {
                                Label(vm.submitError!, systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red).font(.caption)
                            }
                        }

                        Section {
                            Button {
                                guard let area = selectedArea, let project = selectedProject else { return }
                                vm.submitRepair(request: RepairSubmitRequest(
                                    areaId: area.itemId, areaName: area.name,
                                    projectId: project.itemId, projectName: project.name,
                                    phone: phone, address: address,
                                    description: description, picUrls: nil
                                ))
                            } label: {
                                HStack {
                                    Spacer()
                                    if vm.isSubmitting {
                                        ProgressView()
                                    } else {
                                        Text("提交报修").fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(selectedArea == nil || selectedProject == nil || phone.isEmpty || address.isEmpty || description.isEmpty || vm.isSubmitting)
                        }
                    }
                } else {
                    LoadingView(message: "加载中...")
                }
            }
            .navigationTitle("新建报修")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
            }
            .onChange(of: vm.submitSuccess) {
                if vm.submitSuccess {
                    isPresented = false
                    vm.clearSubmitState()
                    vm.loadOrders()
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(vm.isSubmitting)
    }
}
