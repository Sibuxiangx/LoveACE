import SwiftUI

/// 空教室：按时段查询，结果直接按楼、楼层展示全部教室，并标出空闲或占用；点教室看占用周次。
struct FreeClassroomView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = FreeClassroomViewModel()
    @State private var showSettings = false
    @State private var selectedRoom: FcRoom?

    var body: some View {
        List {
            FreeClassroomTimeSection(vm: vm)
            resultSections
        }
        .listStyle(.insetGrouped)
        .navigationTitle("空教室")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await vm.useNow() } } label: {
                    Label("现在有空", systemImage: "clock")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            searchButton
        }
        .sheet(isPresented: $showSettings) {
            FreeClassroomSettingsSheet(vm: vm)
        }
        .sheet(item: $selectedRoom) { room in
            FreeClassroomRoomSheet(room: room, vm: vm)
        }
        .task {
            guard let service = authVM.freeClassroomService else { return }
            vm.initialize(service: service)
            await vm.loadInitial()
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        if vm.isSearching {
            Section {
                ProgressView("正在查询…")
                    .frame(maxWidth: .infinity)
            }
        } else if let distribution = vm.distribution {
            if distribution.isEmpty {
                Section {
                    ContentUnavailableView(
                        "没有可显示的教室",
                        systemImage: "door.left.hand.closed",
                        description: Text("换个节次或范围试试，也可以在设置里打开“显示停用教室”。")
                    )
                }
            } else {
                ForEach(distribution) { item in
                    buildingSection(item)
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "选择时段后查询",
                    systemImage: "building.2",
                    description: Text("默认是本周和今天的当前节次，结果按楼和楼层展示。")
                )
            }
        }
        if let error = vm.searchError, !vm.isSearching {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 一栋楼：标题是楼名与空闲数量，下面按楼层列出教室。
    private func buildingSection(_ item: FcBuildingDistribution) -> some View {
        Section {
            ForEach(item.floors) { floor in
                Text(floor.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(floor.rooms) { room in
                    Button { selectedRoom = room } label: {
                        FreeClassroomRoomRow(room: room, free: vm.isFree(room))
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("\(item.building.campusName) · \(item.building.name) · 空闲 \(item.freeCount)/\(item.totalCount)")
        }
    }

    private var searchButton: some View {
        Button {
            Task { await vm.search() }
        } label: {
            Text("查询空教室")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .compatGlassProminentButtonStyle()
        .disabled(vm.sections.isEmpty || vm.isSearching)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// 时段与范围：教学周、星期、节次（多选）、校区、教学楼、类型。
struct FreeClassroomTimeSection: View {
    @Bindable var vm: FreeClassroomViewModel

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        Section {
            Picker("教学周", selection: $vm.week) {
                ForEach(1...24, id: \.self) { week in
                    Text(weekTitle(week)).tag(week)
                }
            }
            Picker("星期", selection: $vm.weekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Self.weekdayLabels[day - 1]).tag(day)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                Text("节次")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...10, id: \.self) { section in
                        sectionButton(section)
                    }
                }
            }
            .padding(.vertical, 4)
            DisclosureGroup("范围（可不选）") {
                Picker("校区", selection: campusBinding) {
                    Text("全部校区").tag("")
                    Text("西校").tag("2")
                    Text("东校").tag("1")
                }
                Picker("教学楼", selection: buildingBinding) {
                    Text("全部教学楼").tag(String?.none)
                    ForEach(vm.buildingOptions) { building in
                        Text(building.name).tag(Optional(building.id))
                    }
                }
                if !vm.types.isEmpty {
                    Picker("类型", selection: $vm.typeCode) {
                        Text("全部类型").tag("")
                        ForEach(vm.types) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                }
            }
        } header: {
            Text("时段")
        } footer: {
            Text("节次可多选；教室需要在所选的每一节都空闲才算空闲。")
        }
    }

    private func weekTitle(_ week: Int) -> String {
        week == vm.currentWeek ? "第 \(week) 周（本周）" : "第 \(week) 周"
    }

    private func sectionButton(_ section: Int) -> some View {
        let selected = vm.sections.contains(section)
        return Button {
            if selected {
                vm.sections.remove(section)
            } else {
                vm.sections.insert(section)
            }
        } label: {
            Text("\(section)")
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .gray)
        .accessibilityLabel("第 \(section) 节")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var campusBinding: Binding<String> {
        Binding(
            get: { vm.campusNo },
            set: { vm.setCampus($0) }
        )
    }

    private var buildingBinding: Binding<String?> {
        Binding(
            get: { vm.buildingNo.isEmpty ? nil : "\(vm.campusNo)|\(vm.buildingNo)" },
            set: { id in
                let building = vm.buildings.first(where: { $0.id == id })
                vm.setBuilding(building)
                if building == nil { vm.buildingNo = "" }
            }
        )
    }
}
