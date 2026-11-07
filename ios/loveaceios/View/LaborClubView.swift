import SwiftUI

struct LaborClubView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = LaborClubViewModel()
    @State private var selectedTab = 0
    @State private var selectedActivity: LaborClubActivity?
    @State private var showScanner = false
    @Environment(\.wideLayout) private var wideLayout
    @State private var wideSelectedActivity: LaborClubActivity?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.progress == nil { LoadingView() }
                else if wideLayout { wideBody }
                else {
                    activityList
                        .detailPanel(item: $selectedActivity) { activity in
                            LaborActivityDetailSheet(activity: activity, vm: vm)
                        }
                }
            }
            .navigationTitle("劳动课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .refreshable { vm.loadAll() }
            .sheet(isPresented: $showScanner) {
                LaborScanSheet(vm: vm, isPresented: $showScanner)
            }
            .alert("报名结果", isPresented: Binding(get: { vm.applyResult != nil }, set: { _ in vm.clearApplyResult() })) {
                Button("确定") { vm.clearApplyResult() }
            } message: { Text(vm.applyResult ?? "") }
            .alert("签到结果", isPresented: Binding(get: { vm.signInResult != nil }, set: { _ in vm.clearSignInResult() })) {
                Button("确定") { vm.clearSignInResult() }
            } message: {
                if let r = vm.signInResult { Text(r.isSuccess ? "签到成功" : r.msg) }
            }
            .onAppear {
                if let svc = authVM.laborClubService { vm.initialize(service: svc); vm.loadAll() }
            }
        }
    }

    // MARK: - Wide Layout

    private var wideBody: some View {
        HStack(spacing: 0) {
            activityList.frame(width: 340)
            Divider()
            wideDetail.frame(maxWidth: .infinity)
        }
        .onAppear { ensureWideSelection() }
        .onChange(of: selectedTab) { _, _ in wideSelectedActivity = wideActiveActivities.first }
        .onChange(of: wideActiveActivities.map(\.activityId)) { _, _ in ensureWideSelection() }
    }

    @ViewBuilder
    private var wideDetail: some View {
        if let activity = wideSelectedActivity {
            LaborActivityDetailContent(activity: activity, vm: vm, onDone: { wideSelectedActivity = nil })
                .id(activity.activityId)
        } else {
            EmptyStateView(title: "选择一个活动查看详情", systemImage: "figure.walk")
        }
    }

    /// 当前标签页下可见的活动，顺序与列表分区一致
    private var wideActiveActivities: [LaborClubActivity] {
        if selectedTab == 0 {
            return vm.ongoingActivities + vm.finishedActivities
        }
        return vm.availableActivities + vm.fullActivities + vm.notStartedActivities + Array(vm.expiredActivities.prefix(20))
    }

    /// 保留仍存在的选中项（刷新为最新数据），否则默认选中第一项
    private func ensureWideSelection() {
        let list = wideActiveActivities
        wideSelectedActivity = wideSelectedActivity.flatMap { sel in list.first { $0.activityId == sel.activityId } } ?? list.first
    }

    private var activityList: some View {
        List {
            if let progress = vm.progress { progressSection(progress) }
            if !vm.clubs.isEmpty { clubsSection }
            tabPickerSection
            if selectedTab == 0 { myActivitiesSection }
            else { addActivitiesSection }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressSection(_ progress: LaborClubProgressInfo) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("劳动修课进度").font(.headline)
                    Spacer()
                    Text(progress.isCompleted ? "已达标" : "未达标")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(progress.isCompleted ? .green : .orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((progress.isCompleted ? Color.green : .orange).opacity(0.12), in: .capsule)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(progress.finishCount)")
                        .font(AppFont.heroNumber)
                    Text("/ 10 次")
                        .font(.title3).foregroundStyle(.secondary)
                }

                ProgressView(value: min(progress.progress, 100), total: 100)
                    .tint(progress.isCompleted ? .green : .blue)

                Text(String(format: "%.0f%%", progress.progress))
                    .font(.caption).foregroundStyle(.secondary)

                if !progress.isCompleted {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(.blue)
                        Text("还需完成 \(10 - progress.finishCount) 次活动")
                            .font(.caption).foregroundStyle(.blue)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: .rect(cornerRadius: 8))
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Clubs

    @ViewBuilder
    private var clubsSection: some View {
        Section {
            DisclosureGroup {
                ForEach(vm.clubs) { club in
                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .font(.subheadline).foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(club.name).font(.subheadline)
                            if let type = club.typeName { Text(type).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text("\(club.memberNum) 人").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } label: {
                HStack {
                    Text("已加入俱乐部").fontWeight(.medium)
                    Spacer()
                    Text("\(vm.clubs.count) 个").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPickerSection: some View {
        Section {
            Picker("", selection: $selectedTab) {
                Text("我的活动 (\(vm.joinedActivities.count))").tag(0)
                Text("添加活动 (\(vm.availableActivities.count + vm.fullActivities.count + vm.notStartedActivities.count + vm.expiredActivities.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - My Activities

    @ViewBuilder
    private var myActivitiesSection: some View {
        if !vm.ongoingActivities.isEmpty {
            Section("待开始 (\(vm.ongoingActivities.count))") {
                ForEach(vm.ongoingActivities) { a in activityRow(a) }
            }
        }
        if !vm.finishedActivities.isEmpty {
            Section("已开始 (\(vm.finishedActivities.count))") {
                ForEach(vm.finishedActivities) { a in activityRow(a) }
            }
        }
        if vm.ongoingActivities.isEmpty && vm.finishedActivities.isEmpty {
            Section { Text("暂无活动记录，去「添加活动」报名吧").foregroundStyle(.secondary) }
        }
    }

    // MARK: - Add Activities

    @ViewBuilder
    private var addActivitiesSection: some View {
        if !vm.availableActivities.isEmpty {
            Section("可报名 (\(vm.availableActivities.count))") {
                ForEach(vm.availableActivities) { a in activityRow(a, showApply: true) }
            }
        }
        if !vm.fullActivities.isEmpty {
            Section("已满员 (\(vm.fullActivities.count))") {
                ForEach(vm.fullActivities) { a in activityRow(a) }
            }
        }
        if !vm.notStartedActivities.isEmpty {
            Section("未开始报名 (\(vm.notStartedActivities.count))") {
                ForEach(vm.notStartedActivities) { a in activityRow(a) }
            }
        }
        if !vm.expiredActivities.isEmpty {
            Section("已过期 (\(vm.expiredActivities.count))") {
                ForEach(vm.expiredActivities.prefix(20)) { a in activityRow(a) }
            }
        }
        if vm.availableActivities.isEmpty && vm.fullActivities.isEmpty && vm.notStartedActivities.isEmpty && vm.expiredActivities.isEmpty {
            Section { Text("当前没有可报名的活动").foregroundStyle(.secondary) }
        }
    }

    // MARK: - Activity Row

    private func activityRow(_ activity: LaborClubActivity, showApply: Bool = false) -> some View {
        Group {
            if wideLayout {
                Button { wideSelectedActivity = activity } label: {
                    activityRowContent(activity, showApply: showApply).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .wideRowSelection(wideSelectedActivity?.activityId == activity.activityId)
                .tint(.primary)
            } else {
                Button { selectedActivity = activity } label: {
                    activityRowContent(activity, showApply: showApply)
                }
                .tint(.primary)
            }
        }
    }

    private func activityRowContent(_ activity: LaborClubActivity, showApply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.title).font(.body).fontWeight(.medium).lineLimit(2)
            HStack(spacing: 8) {
                Label(activity.clubName, systemImage: "person.3.fill")
                Label("\(activity.memberNum)/\(activity.peopleNum)", systemImage: "person.fill")
            }
            .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(activity.startTime, systemImage: "clock")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(activity.signInStatus)
                    .font(.caption2).fontWeight(.medium)
                    .foregroundStyle(.blue)
            }

            if showApply {
                Button {
                    vm.applyActivity(activityId: activity.activityId)
                } label: {
                    Text("报名参加")
                        .font(.caption).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Activity Detail Sheet

struct LaborActivityDetailSheet: View {
    let activity: LaborClubActivity
    @Bindable var vm: LaborClubViewModel
    @DetailDismiss private var dismiss

    var body: some View {
        NavigationStack {
            LaborActivityDetailContent(activity: activity, vm: vm, onDone: { dismiss() })
                .navigationTitle("活动详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Activity Detail Content

struct LaborActivityDetailContent: View {
    let activity: LaborClubActivity
    @Bindable var vm: LaborClubViewModel
    let onDone: () -> Void
    @State private var detail: ActivityDetail?
    @State private var isLoadingDetail = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.title).font(.title3).fontWeight(.bold)
                    HStack(spacing: 8) {
                        Text(activity.typeName)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.orange.opacity(0.12), in: .capsule)
                            .foregroundStyle(.orange)
                        Text(activity.stateName)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.blue.opacity(0.12), in: .capsule)
                            .foregroundStyle(.blue)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("活动信息") {
                LabeledContent("俱乐部", value: activity.clubName)
                LabeledContent("负责人", value: activity.chargeUserName)
                LabeledContent("人数", value: "\(activity.memberNum)/\(activity.peopleNum)")
                LabeledContent("活动开始", value: formatTime(activity.startTime))
                LabeledContent("活动结束", value: formatTime(activity.endTime))
                LabeledContent("报名开始", value: formatTime(activity.signUpStartTime))
                LabeledContent("报名结束", value: formatTime(activity.signUpEndTime))
                if let d = detail, !d.location.isEmpty {
                    LabeledContent("活动地点", value: d.location)
                }
                if let d = detail, !d.teacherNames.isEmpty {
                    LabeledContent("指导老师", value: d.teacherNames)
                }
            }

            if let signList = activity.signList, !signList.isEmpty {
                Section("签到记录 (\(signList.filter { $0.isSign }.count)/\(signList.count))") {
                    ForEach(signList) { sign in
                        HStack {
                            Image(systemName: sign.isSign ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(sign.isSign ? .green : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sign.typeName).font(.subheadline)
                                Text("\(formatTime(sign.startTime)) ~ \(formatTime(sign.endTime))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sign.isSign, let st = sign.signTime, !st.isEmpty {
                                Text(formatTime(st)).font(.caption2).foregroundStyle(.green)
                            } else {
                                Text(sign.statusText).font(.caption).foregroundStyle(sign.isSign ? .green : .red)
                            }
                        }
                    }
                }
            }

            if !vm.joinedActivities.contains(where: { $0.activityId == activity.activityId }) {
                Section {
                    Button {
                        vm.applyActivity(activityId: activity.activityId)
                        onDone()
                    } label: {
                        HStack { Spacer(); Text("报名参加").fontWeight(.semibold); Spacer() }
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            guard let svc = vm.service else { return }
            let result = await svc.getActivityDetail(activityId: activity.activityId)
            if result.success { detail = result.data }
        }
    }

    private func formatTime(_ time: String) -> String {
        time.replacingOccurrences(of: "T", with: " ")
            .components(separatedBy: ".").first ?? time
    }
}

// MARK: - Scan Sheet

import VisionKit
import Vision

struct LaborScanSheet: View {
    @Bindable var vm: LaborClubViewModel
    @Binding var isPresented: Bool
    @State private var qrInput = ""
    @State private var scannedCode: String?

    private var isScannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            if isScannerAvailable {
                ZStack(alignment: .bottom) {
                    QRScannerView { code in
                        guard scannedCode == nil else { return }
                        scannedCode = code
                        vm.scanSignIn(qrData: code)
                        isPresented = false
                    }
                    .ignoresSafeArea()

                    VStack(spacing: 8) {
                        Text("将二维码对准框内")
                            .font(.subheadline).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.black.opacity(0.5), in: .capsule)
                    }
                    .padding(.bottom, 60)
                }
                .navigationTitle("扫码签到")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isPresented = false }.tint(.white)
                    }
                }
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange.gradient)
                        .padding(.top, 40)
                    Text("扫码签到").font(.title2).fontWeight(.bold)
                    Text("当前设备不支持相机扫码，请手动粘贴二维码内容")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    TextField("粘贴二维码内容", text: $qrInput)
                        .textFieldStyle(.roundedBorder).padding(.horizontal, 32)
                    Button {
                        guard !qrInput.isEmpty else { return }
                        vm.scanSignIn(qrData: qrInput)
                        isPresented = false
                    } label: {
                        Text("签到").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .foregroundStyle(.white)
                            .background(.orange, in: .rect(cornerRadius: 14))
                    }
                    .disabled(qrInput.isEmpty).padding(.horizontal, 32)
                    Spacer()
                }
                .navigationTitle("扫码签到")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { isPresented = false } }
                }
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCodeScanned: onCodeScanned) }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCodeScanned: (String) -> Void
        private var handled = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard !handled else { return }
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                handled = true
                onCodeScanned(value)
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    handled = true
                    onCodeScanned(value)
                    return
                }
            }
        }
    }
}
