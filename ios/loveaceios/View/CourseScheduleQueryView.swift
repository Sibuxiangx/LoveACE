import SwiftUI

/// 开课查询：没有搜索框，条件全部在右上角"筛选"里设置；结果分页加载。
struct CourseScheduleQueryView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = CourseScheduleQueryViewModel()
    @State private var showFilters = false
    @State private var selected: CourseScheduleRecord?

    var body: some View {
        content
            .navigationTitle("开课查询")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                CourseScheduleFilterSheet(vm: vm)
            }
            .sheet(item: $selected) { record in
                CourseScheduleDetailSheet(record: record)
            }
            .task {
                guard let service = authVM.courseScheduleService else { return }
                vm.initialize(service: service)
                await vm.loadIndex()
            }
    }

    @ViewBuilder
    private var content: some View {
        if !vm.hasSearched {
            if let error = vm.indexError {
                ContentUnavailableView {
                    Label("无法加载学期", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await vm.loadIndex() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("开课查询", systemImage: "book.closed")
                } description: {
                    Text("点击右上角的「筛选」，选择学期和条件，再点「查询」。")
                }
            }
        } else if vm.records.isEmpty && vm.isLoadingPage {
            ProgressView("正在查询…")
        } else if vm.records.isEmpty {
            if let error = vm.pageError {
                ContentUnavailableView {
                    Label("查询失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await vm.loadNextPage() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView(
                    "没有符合条件的开课",
                    systemImage: "magnifyingglass",
                    description: Text("换个学期或放宽筛选条件试试。")
                )
            }
        } else {
            resultList
        }
    }

    private var resultList: some View {
        List {
            Section {
                ForEach(Array(vm.records.enumerated()), id: \.element.id) { index, record in
                    Button { selected = record } label: {
                        CourseScheduleRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if index >= vm.records.count - 5 {
                            Task { await vm.loadNextPage() }
                        }
                    }
                }
                pagingFooter
            } header: {
                Text(vm.summary)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.search() }
    }

    @ViewBuilder
    private var pagingFooter: some View {
        if vm.isLoadingPage {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if let error = vm.pageError {
            HStack {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重试") { Task { await vm.loadNextPage() } }
            }
        }
    }
}

/// 开课记录行：课程名（headline）→ 教师、课程号、学分（subheadline）→ 时间地点（footnote）。
struct CourseScheduleRow: View {
    let record: CourseScheduleRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.kcm ?? "未命名课程")
                .font(.headline)
                .lineLimit(2)
            Text(record.identityLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(record.scheduleLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension CourseScheduleRecord {
    /// 教师 · 课程号-课序 · 学分
    var identityLine: String {
        var parts: [String] = []
        if let skjs, !skjs.isEmpty { parts.append(skjs) }
        if let kch { parts.append(kxh.map { "\(kch)-\($0)" } ?? kch) }
        if let xf { parts.append("\(xf) 学分") }
        return parts.joined(separator: " · ")
    }

    /// 周几 · 节次 · 周次 · 教学楼 教室
    var scheduleLine: String {
        var parts: [String] = []
        if let weekdayStr { parts.append(weekdayStr) }
        if let classTimeStr { parts.append("第 \(classTimeStr) 节") }
        if let week = skzc ?? zcsm { parts.append(week) }
        let place = [jxlm, jasm].compactMap { $0 }.joined(separator: " ")
        if !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

/// 开课记录详情：课程信息与时间地点。
struct CourseScheduleDetailSheet: View {
    let record: CourseScheduleRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("课程") {
                    LabeledContent("课程名", value: record.kcm ?? "—")
                    LabeledContent("课程号", value: record.kch ?? "—")
                    LabeledContent("课序号", value: record.kxh ?? "—")
                    LabeledContent("学分", value: record.xf.map { "\($0)" } ?? "—")
                    LabeledContent("授课教师", value: record.skjs ?? "—")
                    LabeledContent("课程类别", value: record.kclbmc ?? "—")
                    LabeledContent("考试类型", value: record.kslxmc ?? "—")
                }
                Section("时间地点") {
                    LabeledContent("上课星期", value: record.weekdayStr ?? "—")
                    LabeledContent("上课节次", value: record.classTimeStr.map { "第 \($0) 节" } ?? "—")
                    LabeledContent("周次", value: record.skzc ?? record.zcsm ?? "—")
                    LabeledContent("开课校区", value: record.kkxqm ?? record.xqm ?? "—")
                    LabeledContent("教学楼", value: record.jxlm ?? "—")
                    LabeledContent("教室", value: record.jasm ?? "—")
                }
            }
            .navigationTitle(record.kcm ?? "课程详情")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
