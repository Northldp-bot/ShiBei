import SwiftUI
import SwiftData

struct TagManagerView: View {
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]
    @Environment(\.modelContext) private var context
    @AppStorage("autoTagByPlatform") private var autoTagByPlatform = true

    private struct TagCount: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { TagCount(name: $0.key, count: $0.value) }
    }

    private var topicCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for item in items {
            for topic in item.topics { counts[topic, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { TagCount(name: $0.key, count: $0.value) }
    }

    var body: some View {
        List {
            Section {
                Toggle("按平台自动打标签", isOn: $autoTagByPlatform)
            } footer: {
                Text("开启后，新收藏会自动带上平台标签，例如「小红书」。")
            }

            Section("标签（\(tagCounts.count)）") {
                if tagCounts.isEmpty {
                    Text("还没有标签，可在收藏卡片上点标签图标添加")
                        .foregroundStyle(Theme.inkTertiary)
                }
                ForEach(tagCounts) { entry in
                    HStack {
                        Text(entry.name)
                        Spacer()
                        Text("\(entry.count) 条")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .onDelete { offsets in
                    delete(offsets.map { tagCounts[$0].name }, isTopic: false)
                }
            }

            Section("话题（\(topicCounts.count)）") {
                if topicCounts.isEmpty {
                    Text("还没有话题，解析时会从正文 #…# 自动提取")
                        .foregroundStyle(Theme.inkTertiary)
                }
                ForEach(topicCounts) { entry in
                    HStack {
                        Text("# \(entry.name)")
                        Spacer()
                        Text("\(entry.count) 条")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .onDelete { offsets in
                    delete(offsets.map { topicCounts[$0].name }, isTopic: true)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("标签管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func delete(_ values: [String], isTopic: Bool) {
        for item in items {
            if isTopic {
                item.topics.removeAll { values.contains($0) }
            } else {
                item.tags.removeAll { values.contains($0) }
            }
            item.lastEditedAt = .now
        }
        try? context.save()
    }
}
