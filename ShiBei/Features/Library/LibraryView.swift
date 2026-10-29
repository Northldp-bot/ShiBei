import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]

    @State private var showSearch = false
    @State private var showFilter = false

    private var filtered: [Item] {
        ItemSorter.sorted(
            items.filter { appState.filter.matches($0) },
            by: appState.sortOrder
        )
    }

    var body: some View {
        @Bindable var state = appState

        NavigationStack {
            VStack(spacing: 0) {
                header
                filterRow
                content
            }
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item)
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(items: items)
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(filter: $state.filter)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            Text("拾贝")
                .font(Theme.wordmark())
                .tracking(4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: 8) {
            dimensionMenu

            Button {
                showFilter = true
            } label: {
                toolIcon("line.3.horizontal.decrease")
                    .overlay(alignment: .topTrailing) {
                        if appState.filter.activeCount > 0 {
                            Text("\(appState.filter.activeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Circle().fill(Theme.ink))
                                .overlay(Circle().stroke(Theme.canvas, lineWidth: 1.5))
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    appState.galleryMode.toggle()
                }
            } label: {
                toolIcon(appState.galleryMode ? "list.bullet" : "square.grid.2x2")
            }
            .buttonStyle(.plain)

            sortMenu

            Button {
                showSearch = true
            } label: {
                toolIcon("magnifyingglass")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var dimensionMenu: some View {
        Menu {
            ForEach(FilterDimension.allCases) { dimension in
                Button {
                    appState.filter.dimension = dimension
                } label: {
                    Label(dimension.title, systemImage: dimension.symbol)
                }
            }
        } label: {
            toolIcon(appState.filter.dimension.symbol)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases) { order in
                Button {
                    appState.sortOrder = order
                } label: {
                    if appState.sortOrder == order {
                        Label(order.title, systemImage: "checkmark")
                    } else {
                        Text(order.title)
                    }
                }
            }
        } label: {
            toolIcon("arrow.up.arrow.down")
        }
    }

    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 33, height: 33)
            .background(Circle().fill(Theme.fill.opacity(0.75)))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            ScrollView {
                EmptyStateView(
                    title: "还没有收藏",
                    message: "复制小红书、抖音、B 站、知乎、微博或小黑盒的分享链接，点底部中间的 + 粘贴进来。",
                    actionTitle: "添加第一条",
                    action: { appState.presentCapture = true }
                )
            }
        } else if filtered.isEmpty {
            ScrollView {
                EmptyStateView(
                    title: "没有符合条件的内容",
                    message: "当前筛选条件下没有收藏。可以换个维度，或清除筛选。",
                    actionTitle: "清除筛选",
                    action: { appState.filter.clear() }
                )
            }
        } else {
            ScrollView {
                if appState.galleryMode {
                    galleryGrid
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(filtered) { item in
                            NavigationLink(value: item.id) {
                                ItemCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var galleryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 12
        ) {
            ForEach(filtered) { item in
                NavigationLink(value: item.id) {
                    GalleryCell(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 120)
    }
}

// MARK: - 画廊单元

struct GalleryCell: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MediaThumb(
                local: item.sortedMedia.first?.localImageURL,
                remote: item.coverURL
            )
            .aspectRatio(3.0 / 4.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                PlatformIcon(platform: item.platform, size: 18)
                    .padding(7)
            }
            .overlay(alignment: .bottomTrailing) {
                if item.hasVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .padding(6)
                }
            }

            Text(item.displayTitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
