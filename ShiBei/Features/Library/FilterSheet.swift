import SwiftUI
import SwiftData

/// 多选筛选面板；维度之间取交集
struct FilterSheet: View {
    @Binding var filter: FilterState
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [Item]

    private var allTopics: [String] {
        Array(Set(items.flatMap(\.topics))).sorted()
    }

    private var allTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                if filter.dimension == .all || filter.dimension == .platform {
                    platformSection
                }
                if filter.dimension == .all || filter.dimension == .topic {
                    topicSection
                }
                if filter.dimension == .all || filter.dimension == .tag {
                    tagSection
                }
                if filter.dimension == .all || filter.dimension == .time {
                    timeSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清除") { filter.clearDimension() }
                        .foregroundStyle(Theme.danger)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var platformSection: some View {
        Section("平台") {
            ForEach(Platform.allCases.filter { $0 != .web }) { platform in
                row(
                    title: platform.displayName,
                    selected: filter.platforms.contains(platform)
                ) {
                    if filter.platforms.contains(platform) {
                        filter.platforms.remove(platform)
                    } else {
                        filter.platforms.insert(platform)
                    }
                }
            }
        }
    }

    private var topicSection: some View {
        Section("话题") {
            if allTopics.isEmpty {
                Text("还没有话题").foregroundStyle(Theme.inkTertiary)
            }
            ForEach(allTopics, id: \.self) { topic in
                row(title: "# \(topic)", selected: filter.topics.contains(topic)) {
                    if filter.topics.contains(topic) {
                        filter.topics.remove(topic)
                    } else {
                        filter.topics.insert(topic)
                    }
                }
            }
        }
    }

    private var tagSection: some View {
        Section("标签") {
            if allTags.isEmpty {
                Text("还没有标签").foregroundStyle(Theme.inkTertiary)
            }
            ForEach(allTags, id: \.self) { tag in
                row(title: tag, selected: filter.tags.contains(tag)) {
                    if filter.tags.contains(tag) {
                        filter.tags.remove(tag)
                    } else {
                        filter.tags.insert(tag)
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        Section {
            Toggle("启用时间段", isOn: Binding(
                get: { filter.hasTimeFilter },
                set: { on in
                    if on {
                        filter.from = Calendar.current.date(byAdding: .day, value: -7, to: .now)
                        filter.to = .now
                    } else {
                        filter.from = nil
                        filter.to = nil
                    }
                }
            ))

            if filter.hasTimeFilter {
                Picker("按", selection: $filter.timeField) {
                    ForEach(TimeField.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }
                .pickerStyle(.segmented)

                DatePicker("开始日期", selection: Binding(
                    get: { filter.from ?? .now },
                    set: { filter.from = $0 }
                ), displayedComponents: .date)

                DatePicker("结束日期", selection: Binding(
                    get: { filter.to ?? .now },
                    set: { filter.to = $0 }
                ), displayedComponents: .date)

                HStack(spacing: 8) {
                    preset("今天", days: 0)
                    preset("最近 7 天", days: 7)
                    preset("最近 30 天", days: 30)
                }
            }
        } header: {
            Text("时间段")
        } footer: {
            Text("「修改时间」取决于标签、话题或正文的最近编辑。")
        }
    }

    private func preset(_ title: String, days: Int) -> some View {
        Button(title) {
            let now = Date()
            filter.to = now
            filter.from = days == 0 ? now : Calendar.current.date(byAdding: .day, value: -days, to: now)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.fill))
        .buttonStyle(.plain)
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
