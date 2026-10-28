import SwiftUI
import SwiftData

@MainActor
struct TagManagerView: View {
    private struct TagCount: Identifiable {
        let id: String
        let count: Int
        var tag: String { id }
    }

    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @AppStorage("autoTagByPlatform") private var autoTagByPlatform = true

    @State private var showAdd = false
    @State private var newTag = ""

    private var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .map { TagCount(id: $0.key, count: $0.value) }
    }

    var body: some View {
        List {
            Section {
                Toggle("按平台自动标记", isOn: $autoTagByPlatform)
                LabeledContent("收藏总数", value: "\(items.count)")
            } header: {
                Text("智能管理")
            } footer: {
                Text("开启后，新收藏会自动带上平台标签，例如「小红书」。")
            }

            Section {
                ForEach(tagCounts) { entry in
                    HStack {
                        Text("#\(entry.tag)")
                            .font(.system(size: 15))
                        Spacer()
                        Text("\(entry.count)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .onDelete(perform: deleteTags)
            } header: {
                Text("标签")
            } footer: {
                if tagCounts.isEmpty {
                    Text("还没有标签。点右上角 + 新建，或在收藏详情里添加。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("标签管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newTag = ""
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(Theme.ink)
            }
        }
        .alert("新建标签", isPresented: $showAdd) {
            TextField("标签名", text: $newTag)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { return }
                appState.toast = ToastMessage(text: "标签「\(tag)」已创建，可在详情页添加", style: .success)
            }
        }
    }

    private func deleteTags(_ offsets: IndexSet) {
        let tags = tagCounts
        for index in offsets {
            guard tags.indices.contains(index) else { continue }
            let tag = tags[index].tag
            for item in items where item.tags.contains(tag) {
                item.tags.removeAll { $0 == tag }
            }
        }
        try? context.save()
    }
}
