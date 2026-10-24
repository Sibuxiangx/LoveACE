import SwiftUI

/// 开课查询筛选：学期、课程名称、课程号、教师、星期、开始节次；院系、校区、教学楼、类别只在页面有对应下拉时显示。
struct CourseScheduleFilterSheet: View {
    @Bindable var vm: CourseScheduleQueryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let index = vm.index {
                    Section("学期") {
                        Picker("学期", selection: $vm.draft.termCode) {
                            ForEach(index.terms) { term in
                                Text(term.name).tag(term.code)
                            }
                        }
                    }
                }
                Section("课程与教师") {
                    TextField("课程名称", text: $vm.draft.courseName)
                    TextField("课程号", text: $vm.draft.courseNo)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("授课教师", text: $vm.draft.teacher)
                }
                Section {
                    Picker("星期", selection: $vm.draft.weekday) {
                        Text("不限").tag(Int?.none)
                        ForEach(1...7, id: \.self) { day in
                            Text(ScheduleFormatting.weekdayName(day)).tag(Optional(day))
                        }
                    }
                    sectionGrid
                } header: {
                    Text("上课时间")
                } footer: {
                    Text("开始节次是单选，只匹配课程从该节开始的记录。例如 1–2 节的课，要选 1 才能查到。")
                }
                if let index = vm.index, hasMoreOptions(index) {
                    Section {
                        DisclosureGroup("更多条件") {
                            optionPicker("开课院系", options: index.departments, selection: $vm.draft.departmentCode)
                            optionPicker("开课校区", options: index.campuses, selection: $vm.draft.campusCode)
                            optionPicker("教学楼", options: index.buildings, selection: $vm.draft.buildingCode)
                            optionPicker("课程类别", options: index.categories, selection: $vm.draft.categoryCode)
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") { vm.resetDraft() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        await vm.search()
                        dismiss()
                    }
                } label: {
                    Text("查询")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .compatGlassProminentButtonStyle()
                .disabled(vm.draft.termCode.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .presentationDetents([.large])
    }

    private var sectionGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开始节次")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(1...10, id: \.self) { section in
                    let selected = vm.draft.startSection == section
                    Button {
                        vm.draft.startSection = selected ? nil : section
                    } label: {
                        Text("\(section)")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .accentColor : .gray)
                    .accessibilityLabel("第 \(section) 节")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func hasMoreOptions(_ index: CourseScheduleIndex) -> Bool {
        !index.departments.isEmpty || !index.campuses.isEmpty || !index.buildings.isEmpty || !index.categories.isEmpty
    }

    @ViewBuilder
    private func optionPicker(_ title: String, options: [CourseScheduleOption], selection: Binding<String>) -> some View {
        if !options.isEmpty {
            Picker(title, selection: selection) {
                Text("不限").tag("")
                ForEach(options) { option in
                    Text(option.name).tag(option.code)
                }
            }
        }
    }
}
