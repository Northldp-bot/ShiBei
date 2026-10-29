import SwiftUI
import SwiftData
import UIKit

@MainActor
struct ItemCard: View {
    @Bindable var item: Item

    @Environment(AppState.self) private var appState
    @Environment(CacheManager.self) private var cache

    @State private var prompt: CardPrompt?
    @State private var showTags = false
    @State private var showEdit = false

    private var assets: [MediaAsset] { item.sortedMedia }

    private enum CardPrompt: String, Identifiable {
        case cache, removeCache, save, resave, delete
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if !item.text.isEmpty {
                Text(item.text)
                    .font(Theme.body(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            mediaArea
            Divider().overlay(Theme.hairline)
            actionRow
        }
        .cardStyle(padding: 16)
        .alert(promptTitle, isPresented: promptBinding) {
            Button("取消", role: .cancel) { prompt = nil }
            Button(promptConfirm, role: destructiveRole) {
                perform(prompt)
                prompt = nil
            }
        } message: {
            Text(promptMessage)
        }
        .sheet(isPresented: $showTags) {
            CardTagSheet(item: item)
        }
        .sheet(isPresented: $showEdit) {
            EditTextSheet(item: item)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            AuthorAvatar(url: item.authorAvatarURL.flatMap(URL.init(string:)), name: item.authorName, size: 32)
                .overlay(alignment: .bottomTrailing) {
                    PlatformIcon(platform: item.platform, size: 16)
                        .offset(x: 4, y: 4)
                }

            Text(item.authorName.isEmpty ? "未知作者" : item.authorName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(Formatters.ago(item.savedAt))
                .font(Theme.meta())
                .foregroundStyle(Theme.inkTertiary)

            if item.isCached {
                Text("· 已缓存")
                    .font(Theme.meta())
                    .foregroundStyle(Theme.success)
            }
        }
    }

    // MARK: Media

    @ViewBuilder
    private var mediaArea: some View {
        if let first = assets.first, first.kind == .video, assets.count == 1 {
            videoCover(first)
        } else if !assets.isEmpty {
            grid
        }
    }

    private func videoCover(_ asset: MediaAsset) -> some View {
        ZStack {
            MediaThumb(local: asset.localPosterURL ?? asset.localImageURL, remote: asset.posterRemote.flatMap(URL.init(string:)) ?? asset.remoteImageURL)
                .aspectRatio(16.0 / 10.0, contentMode: .fill)
            Color.black.opacity(0.18)
            Image(systemName: "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(.white.opacity(0.24)))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            badge("视频").padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            if asset.duration > 0 {
                Text(Formatters.duration(asset.duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
            }
        }
    }

    private var grid: some View {
        let visible = Array(assets.prefix(9))
        let columns = gridColumns(count: visible.count)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(visible.indices, id: \.self) { index in
                let asset = visible[index]
                MediaTile(
                    asset: asset,
                    extraCount: index == 8 ? max(assets.count - 9, 0) : 0,
                    singleColumn: visible.count == 1
                )
            }
        }
    }

    private func gridColumns(count: Int) -> [GridItem] {
        switch count {
        case 1:
            return [GridItem(.flexible())]
        case 2:
            return [GridItem(.flexible(), spacing: 4), GridItem(.flexible())]
        default:
            return Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.45)))
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack {
            actionButton(
                icon: item.isCached ? "arrow.down.circle.fill" : "arrow.down.to.line",
                tint: item.isCached ? Theme.success : Theme.inkSecondary
            ) {
                prompt = item.isCached ? .removeCache : .cache
            }

            Spacer()

            actionButton(icon: "photo.on.rectangle", tint: Theme.inkSecondary) {
                prompt = savedBefore ? .resave : .save
            }

            Spacer()

            ShareLink(item: URL(string: item.sourceURL) ?? URL(string: "https://shibei.app")!) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 44, height: 34)
            }

            Spacer()

            actionButton(icon: "tag", tint: Theme.inkSecondary) {
                showTags = true
            }

            Spacer()

            Menu {
                Button {
                    showEdit = true
                } label: {
                    Label("编辑内容", systemImage: "square.and.pencil")
                }
                Button {
                    UIPasteboard.general.string = item.sourceURL
                    appState.toast = ToastMessage(text: "链接已复制", style: .success)
                } label: {
                    Label("复制原链接", systemImage: "link")
                }
                Divider()
                Button(role: .destructive) {
                    prompt = .delete
                } label: {
                    Label("删除收藏", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(width: 44, height: 34)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func actionButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 34)
        }
        .buttonStyle(.plain)
    }

    private var savedBefore: Bool {
        UserDefaults.standard.bool(forKey: "saved.\(item.id.uuidString)")
    }

    // MARK: Prompt

    private var promptBinding: Binding<Bool> {
        Binding(
            get: { prompt != nil },
            set: { if !$0 { prompt = nil } }
        )
    }

    private var promptTitle: String {
        switch prompt {
        case .cache: return "缓存内容"
        case .removeCache: return "删除缓存"
        case .save: return "保存到相册"
        case .resave: return "重新保存"
        case .delete: return "删除收藏"
        case nil: return ""
        }
    }

    private var promptMessage: String {
        switch prompt {
        case .cache: return "是否将这条内容缓存到本地？"
        case .removeCache: return "删除后需要重新下载才能离线查看，确定删除吗？"
        case .save: return "将图片、视频和实况图保存到系统相册？"
        case .resave: return "该内容曾保存过，是否重新保存？"
        case .delete: return "删除后这条内容将从收藏中移除，确定吗？"
        case nil: return ""
        }
    }

    private var promptConfirm: String {
        switch prompt {
        case .cache: return "缓存"
        case .removeCache, .delete: return "删除"
        case .save: return "保存"
        case .resave: return "重新保存"
        case nil: return "确定"
        }
    }

    private var destructiveRole: ButtonRole? {
        switch prompt {
        case .removeCache, .delete: return .destructive
        default: return nil
        }
    }

    private func perform(_ prompt: CardPrompt?) {
        guard let prompt else { return }
        switch prompt {
        case .cache:
            Task { await cache.cache(item) }
        case .removeCache:
            cache.deleteCache(item)
            appState.toast = ToastMessage(text: "已删除缓存", style: .info)
        case .save, .resave:
            UserDefaults.standard.set(true, forKey: "saved.\(item.id.uuidString)")
            Task { await PhotoSaver.save(item: item, cache: cache, appState: appState) }
        case .delete:
            LibraryService.delete(item)
            appState.toast = ToastMessage(text: "已删除", style: .info)
        }
    }
}

// MARK: - 卡片标签编辑

@MainActor
struct CardTagSheet: View {
    @Bindable var item: Item
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]
    @State private var newTag = ""

    private var allTags: [String] {
        var set = Set(items.flatMap(\.tags))
        item.tags.forEach { set.insert($0) }
        return set.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("已有标签") {
                    if allTags.isEmpty {
                        Text("还没有标签").foregroundStyle(Theme.inkTertiary)
                    }
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Text(tag).foregroundStyle(Theme.ink)
                                Spacer()
                                if item.tags.contains(tag) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.ink)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("新建") {
                    HStack {
                        TextField("标签名", text: $newTag)
                        Button("添加") {
                            let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !tag.isEmpty else { return }
                            if !item.tags.contains(tag) { item.tags.append(tag) }
                            LibraryService.updateTags(item, tags: item.tags)
                            newTag = ""
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ tag: String) {
        if item.tags.contains(tag) {
            item.tags.removeAll { $0 == tag }
        } else {
            item.tags.append(tag)
        }
        LibraryService.updateTags(item, tags: item.tags)
    }
}

// MARK: - 编辑正文

@MainActor
struct EditTextSheet: View {
    @Bindable var item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("修改后只影响本地收藏，不会改动原链接。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceMuted))
            }
            .padding(16)
            .background(Theme.canvas)
            .navigationTitle("编辑内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        LibraryService.updateText(item, text: text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if text.isEmpty { text = item.text }
            }
        }
    }
}

// MARK: - 单个媒体格

struct MediaTile: View {
    let asset: MediaAsset
    var extraCount: Int = 0
    var singleColumn = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MediaThumb(
                    local: asset.localImageURL,
                    remote: asset.remoteImageURL ?? asset.posterRemote.flatMap(URL.init(string:))
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                if asset.kind == .livePhoto {
                    VStack {
                        Spacer()
                        HStack {
                            Text("◎ 实况")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.45)))
                            Spacer()
                        }
                        .padding(6)
                    }
                }

                if asset.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.black.opacity(0.42)))
                }

                if extraCount > 0 {
                    ZStack {
                        Color.black.opacity(0.38)
                        Text("+\(extraCount)")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .aspectRatio(singleColumn ? 4.0 / 3.0 : 1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
