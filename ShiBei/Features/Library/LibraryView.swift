import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]

    @State private var showSearch = false

    private var filtered: [Item] {
        items.filter { item in
            if let platform = appState.selectedPlatform, item.platform != platform { return false }
            if let tag = appState.selectedTag, !item.tags.contains(tag) { return false }
            if !appState.searchText.isEmpty {
                let query = appState.searchText.lowercased()
                let haystack = (item.title + "\n" + item.text + "\n" + item.authorName).lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }

    private var allTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                chipBar
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
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("拾贝")
                    .font(Theme.wordmark())
                    .tracking(4)
                Text("SHIBEI")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(Theme.inkTertiary)
            }

            HStack {
                CircleIconButton(systemName: "gearshape") {
                    appState.selectedTab = .settings
                }
                Spacer()
                HStack(spacing: 8) {
                    CircleIconButton(systemName: appState.galleryMode ? "list.bullet" : "square.grid.2x2") {
                        withAnimation(.snappy(duration: 0.25)) {
                            appState.galleryMode.toggle()
                        }
                    }
                    CircleIconButton(systemName: "magnifyingglass") { showSearch = true }
                    CircleIconButton(systemName: "plus", emphasized: true) {
                        appState.presentCapture = true
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Chips

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "全部",
                    platform: nil,
                    isSelected: appState.selectedPlatform == nil
                ) {
                    appState.selectedPlatform = nil
                }

                ForEach(Platform.allCases.filter { $0 != .web }) { platform in
                    FilterChip(
                        title: platform.displayName,
                        platform: platform,
                        isSelected: appState.selectedPlatform == platform
                    ) {
                        appState.selectedPlatform = appState.selectedPlatform == platform ? nil : platform
                    }
                }

                if appState.selectedTag != nil {
                    FilterChip(title: "#\(appState.selectedTag ?? "")", platform: nil, isSelected: true) {
                        appState.selectedTag = nil
                    }
                }

                Menu {
                    Button("清除筛选") {
                        appState.selectedTag = nil
                        appState.selectedPlatform = nil
                    }
                    if allTags.isEmpty {
                        Text("还没有标签")
                    } else {
                        Divider()
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                appState.selectedTag = tag
                            } label: {
                                Text(tag)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 33, height: 33)
                        .background(Circle().fill(Theme.fill.opacity(0.75)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            ScrollView {
                EmptyStateView(
                    title: "还没有收藏",
                    message: "复制小红书、抖音、B 站、知乎、微博或小黑盒的分享链接，点右上角 + 粘贴进来。",
                    actionTitle: "添加第一条",
                    action: { appState.presentCapture = true }
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
                    .padding(.bottom, 110)
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
        .padding(.bottom, 110)
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
            .aspectRatio(3 / 4, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                PlatformBadge(platform: item.platform, size: 18)
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
