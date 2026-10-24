import SwiftUI

/// 教室行：标题（headline）→ 座位与类型（subheadline）。右侧的空闲状态与标记都带文字和图标，不只靠颜色。
struct FreeClassroomRoomRow: View {
    let room: FcRoom
    /// 楼详情选了时段时才有值：true 空闲，false 占用；nil 不显示状态
    let free: Bool?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let free {
                    Label(free ? "空闲" : "占用", systemImage: free ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.footnote)
                        .foregroundStyle(free ? Color.green : Color.secondary)
                }
                ForEach(stopTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12), in: .capsule)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var detailText: String {
        var parts: [String] = []
        if let seats = room.seats { parts.append("\(seats) 座") }
        parts.append(room.typeName ?? "类型待定")
        return parts.joined(separator: " · ")
    }

    private var stopTags: [String] {
        var tags: [String] = []
        if room.stopReasons.contains(.name) { tags.append("停用") }
        if room.stopReasons.contains(.status02) { tags.append("状态 02") }
        if room.stopReasons.contains(.status03) { tags.append("状态 03") }
        return tags
    }
}

/// 教室详情：基本信息与所选时段的占用周次。
struct FreeClassroomRoomSheet: View {
    let room: FcRoom
    let vm: FreeClassroomViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("教室") {
                    LabeledContent("楼宇", value: "\(room.campusName) · \(room.buildingName)")
                    LabeledContent("房号", value: room.code)
                    LabeledContent("座位", value: room.seats.map { "\($0)" } ?? "—")
                    LabeledContent("类型", value: room.typeName ?? "—")
                }
                Section {
                    occupancyRows
                } header: {
                    Text("占用情况")
                } footer: {
                    Text("按所选时段列出被占用的周次；本周被占用的会用红色标出。")
                }
            }
            .navigationTitle(room.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadOccupancy(for: room) }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var occupancyRows: some View {
        if vm.isLoadingOccupancy {
            ProgressView()
        } else if let error = vm.occupancyError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else if vm.sections.isEmpty {
            Text("选择时段后查看占用情况")
                .foregroundStyle(.secondary)
        } else if let busy = vm.occupancy, vm.occupancyRoomKey == room.roomKey {
            ForEach(vm.sections.sorted(), id: \.self) { section in
                occupancyRow(section: section, busy: busy)
            }
        }
    }

    private func occupancyRow(section: Int, busy: Set<String>) -> some View {
        let weeks = FreeClassroomRules.busyWeeks(in: busy, weekday: vm.weekday, section: section)
        let busyNow = weeks.contains(vm.week)
        return LabeledContent("\(ScheduleFormatting.weekdayName(vm.weekday)) 第 \(section) 节") {
            Text(weeks.isEmpty ? "全周空闲" : "第 \(ScheduleFormatting.formatWeeks(weeks)) 周")
                .foregroundStyle(busyNow ? Color.red : Color.secondary)
        }
    }
}

/// 设置：显示停用教室。文案与 Android 保持一致。
struct FreeClassroomSettingsSheet: View {
    let vm: FreeClassroomViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("显示停用教室", isOn: Binding(
                        get: { vm.showStopped },
                        set: { vm.setShowStopped($0) }
                    ))
                } footer: {
                    Text("默认隐藏停用教学楼的教室，以及状态码为 02 或 03 的教室。打开后：停用楼排在最后；状态码 02、03 和名称含“停用”的教室带标记。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
