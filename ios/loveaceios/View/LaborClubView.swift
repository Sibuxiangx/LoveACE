import SwiftUI

struct LaborClubView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = LaborClubViewModel()
    @State private var selectedTab = 0
    @State private var selectedActivity: LaborClubActivity?
    @State private var showScanner = false
    @State private var showClubApplicationSheet = false
    @State private var completedClubApplication = false

    private var laborClubServiceIdentity: ObjectIdentifier? {
        authVM.laborClubService.map(ObjectIdentifier.init)
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.progress == nil { LoadingView() }
                else {
                    List {
                        if let progress = vm.progress { progressSection(progress) }
                        if vm.clubs.isEmpty { clubMembershipSection }
                        else { clubsSection }
                        tabPickerSection
                        if selectedTab == 0 { myActivitiesSection }
                        else { addActivitiesSection }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("劳动俱乐部")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .refreshable { vm.loadAll() }
            .sheet(item: $selectedActivity) { activity in
                LaborActivityDetailSheet(activity: activity, vm: vm)
            }
            .sheet(isPresented: $showScanner) {
                LaborScanSheet(vm: vm, isPresented: $showScanner)
            }
            .sheet(isPresented: $showClubApplicationSheet, onDismiss: {
                if completedClubApplication {
                    completedClubApplication = false
                } else {
                    vm.clearClubActionResult()
                }
            }) {
                LaborClubApplicationSheet(vm: vm)
            }
            .alert("报名结果", isPresented: Binding(get: { vm.applyResult != nil }, set: { _ in vm.clearApplyResult() })) {
                Button("确定") { vm.clearApplyResult() }
            } message: { Text(vm.applyResult ?? "") }
            .alert("签到结果", isPresented: Binding(get: { vm.signInResult != nil }, set: { _ in vm.clearSignInResult() })) {
                Button("确定") { vm.clearSignInResult() }
            } message: {
                if let r = vm.signInResult { Text(r.isSuccess ? "签到成功" : r.msg) }
            }
            .alert(
                "俱乐部申请",
                isPresented: Binding(
                    get: { !showClubApplicationSheet && vm.clubActionResult != nil },
                    set: { if !$0 { vm.clearClubActionResult() } }
                )
            ) {
                Button("确定") { vm.clearClubActionResult() }
            } message: {
                Text(vm.clubActionResult ?? "")
            }
            .onAppear {
                initializeForCurrentUser()
            }
            .onChange(of: authVM.userId) { _, _ in
                initializeForCurrentUser()
            }
            .onChange(of: laborClubServiceIdentity) { _, _ in
                initializeForCurrentUser()
            }
            .onChange(of: vm.clubSubmissionSucceeded) { _, succeeded in
                guard succeeded else { return }
                completedClubApplication = true
                showClubApplicationSheet = false
                vm.consumeClubSubmissionSuccess()
            }
        }
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

    @ViewBuilder
    private var clubMembershipSection: some View {
        Section {
            if let statusError = vm.clubStatusError {
                membershipRow(
                    title: "俱乐部状态加载失败",
                    detail: statusError,
                    icon: "exclamationmark.triangle.fill",
                    color: .red,
                    trailingIcon: "arrow.clockwise",
                    trailingAction: vm.loadAll
                )
            } else if vm.submittedStatusSyncing {
                membershipRow(
                    title: "申请已提交，状态同步中",
                    detail: "服务器状态尚未同步",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    trailingIcon: "arrow.clockwise",
                    trailingAction: vm.loadAll
                )
            } else {
                switch vm.membership.status {
                case .pending:
                    membershipRow(
                        title: "俱乐部正在审批",
                        detail: applicationSummary(vm.membership.latestApplication),
                        icon: "hourglass",
                        color: .orange,
                        trailingIcon: "arrow.clockwise",
                        trailingAction: vm.loadAll
                    )
                case .approvedSyncing:
                    membershipRow(
                        title: "审核已通过，正在同步俱乐部信息",
                        detail: applicationSummary(vm.membership.latestApplication),
                        icon: "checkmark.circle.fill",
                        color: .green,
                        trailingIcon: "arrow.clockwise",
                        trailingAction: vm.loadAll
                    )
                case .submitting:
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("正在提交申请").fontWeight(.medium)
                    }
                case .rejected:
                    Button {
                        vm.clearClubActionResult()
                        showClubApplicationSheet = true
                    } label: {
                        membershipRow(
                            title: "上次申请未通过",
                            detail: applicationSummary(vm.membership.latestApplication),
                            icon: "xmark.circle.fill",
                            color: .red,
                            trailingIcon: "chevron.right"
                        )
                    }
                case .notJoined:
                    Button {
                        vm.clearClubActionResult()
                        showClubApplicationSheet = true
                    } label: {
                        membershipRow(
                            title: "申请加入劳动俱乐部",
                            detail: "当前尚未加入俱乐部",
                            icon: "person.3.sequence.fill",
                            color: .blue,
                            trailingIcon: "chevron.right"
                        )
                    }
                case .joined:
                    EmptyView()
                }
            }
        }
    }

    private func membershipRow(
        title: String,
        detail: String,
        icon: String,
        color: Color,
        trailingIcon: String,
        trailingAction: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium).foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            Spacer(minLength: 8)
            if let trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: trailingIcon)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("刷新俱乐部状态")
            } else {
                Image(systemName: trailingIcon).foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }

    private func applicationSummary(_ application: LaborClubApplication?) -> String {
        guard let application else { return "" }
        return [application.clubName, application.addTime, application.replyComment]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func initializeForCurrentUser() {
        guard let service = authVM.laborClubService else { return }
        vm.initialize(service: service, userId: authVM.userId)
        vm.loadAll()
        if showClubApplicationSheet {
            vm.loadClubDirectory()
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
        Button { selectedActivity = activity } label: {
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
        .tint(.primary)
    }
}

private struct LaborClubApplicationSheet: View {
    @Bindable var vm: LaborClubViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedClubId: String?
    @State private var reason = LaborClubService.defaultClubApplicationReason

    private var selectedClub: LaborClubDirectoryItem? {
        vm.clubDirectory.first { $0.id == selectedClubId }
    }

    private var filteredClubs: [LaborClubDirectoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vm.clubDirectory }
        return vm.clubDirectory.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.typeName.localizedCaseInsensitiveContains(query) ||
            $0.projectName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            if let selectedClub {
                applicationForm(selectedClub)
            } else {
                directoryList
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(vm.isSubmittingClub)
        .task { vm.loadClubDirectory() }
    }

    @ViewBuilder
    private var directoryList: some View {
        Group {
            if vm.isDirectoryLoading && vm.clubDirectory.isEmpty {
                ProgressView("正在加载俱乐部")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.directoryError, vm.clubDirectory.isEmpty {
                ContentUnavailableView {
                    Label("目录加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { vm.loadClubDirectory(force: true) }
                }
            } else {
                List(filteredClubs) { club in
                    Button {
                        guard club.canApply else { return }
                        selectedClubId = club.id
                        vm.clearClubActionResult()
                    } label: {
                        directoryRow(club)
                    }
                    .buttonStyle(.plain)
                    .disabled(!club.canApply)
                }
                .overlay {
                    if filteredClubs.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .navigationTitle("选择劳动俱乐部")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索俱乐部")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { vm.loadClubDirectory(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isDirectoryLoading)
                .accessibilityLabel("刷新俱乐部目录")
            }
        }
    }

    private func directoryRow(_ club: LaborClubDirectoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.teal)
                .frame(width: 36, height: 36)
                .background(.teal.opacity(0.12), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(club.name)
                        .font(.body).fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    availabilityBadge(club)
                }
                let metadata = [club.typeName, club.projectName].filter { !$0.isEmpty }
                if !metadata.isEmpty {
                    Text(metadata.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Label("\(club.memberNum)/\(club.peopleNum) 人", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.blue)
                if let description = club.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            if club.canApply {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
    }

    private func availabilityBadge(_ club: LaborClubDirectoryItem) -> some View {
        let label: String
        let color: Color
        if club.isJoined {
            label = "已加入"; color = .green
        } else if !club.isEnabled {
            label = "暂停申请"; color = .red
        } else {
            label = "可申请"; color = .blue
        }
        return Text(label)
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }

    private func applicationForm(_ club: LaborClubDirectoryItem) -> some View {
        Form {
            Section("目标俱乐部") {
                LabeledContent("名称", value: club.name)
                if !club.typeName.isEmpty { LabeledContent("类型", value: club.typeName) }
                if !club.projectName.isEmpty { LabeledContent("项目", value: club.projectName) }
                LabeledContent("人数", value: "\(club.memberNum)/\(club.peopleNum)")
            }

            Section("申请理由") {
                TextField("申请理由", text: $reason, axis: .vertical)
                    .lineLimit(5...8)
                    .disabled(vm.isSubmittingClub)
                HStack {
                    Spacer()
                    Text("\(reason.count)/200")
                        .font(.caption2)
                        .foregroundStyle(reason.count > 200 ? .red : .secondary)
                }
            }

            if let message = vm.clubActionResult, !message.isEmpty, !vm.clubSubmissionSucceeded {
                Section {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    vm.applyClub(clubId: club.id, reason: reason)
                } label: {
                    HStack {
                        Spacer()
                        if vm.isSubmittingClub {
                            ProgressView().controlSize(.small)
                            Text("正在提交")
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("提交申请")
                        }
                        Spacer()
                    }
                    .fontWeight(.semibold)
                }
                .disabled(
                    reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    reason.count > 200 ||
                    vm.isSubmittingClub
                )
            }
        }
        .navigationTitle("确认入会申请")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    vm.clearClubActionResult()
                    selectedClubId = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(vm.isSubmittingClub)
                .accessibilityLabel("返回俱乐部目录")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("取消") { dismiss() }
                    .disabled(vm.isSubmittingClub)
            }
        }
    }
}

// MARK: - Activity Detail Sheet

struct LaborActivityDetailSheet: View {
    let activity: LaborClubActivity
    @Bindable var vm: LaborClubViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ActivityDetail?
    @State private var isLoadingDetail = false

    var body: some View {
        NavigationStack {
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
                            dismiss()
                        } label: {
                            HStack { Spacer(); Text("报名参加").fontWeight(.semibold); Spacer() }
                        }
                        .tint(.orange)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("活动详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
