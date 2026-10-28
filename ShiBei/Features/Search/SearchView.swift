import SwiftUI
import SwiftData

struct SearchView: View {
    let items: [Item]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [Item] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        let q = query.lowercased()
        return items.filter {
            ($0.title + "\n" + $0.text + "\n" + $0.authorName + "\n" + $0.tags.joined(separator: " "))
                .lowercased()
                .contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    EmptyStateView(title: "没有找到", message: "换个关键词试试，正文和作者名也在搜索范围内。")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { item in
                                NavigationLink(value: item.id) {
                                    row(item)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.hairline).padding(.leading, 68)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(Theme.canvas)
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索标题、正文、作者、标签")
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            MediaThumb(
                local: item.sortedMedia.first?.localImageURL,
                remote: item.coverURL
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    PlatformBadge(platform: item.platform, size: 12)
                    Text(item.authorName)
                    Text("·")
                    Text(Formatters.day(item.savedAt))
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
