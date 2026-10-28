import SwiftUI
import SwiftData
import UIKit

@MainActor
struct ItemDetailView: View {
    @Bindable var item: Item

    @Environment(AppState.self) private var appState
    @Environment(CacheManager.self) private var cache
    @Environment(\.dismiss) private var dismiss

    @State private var showTagEditor = false
    @State private var showParseLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if item.sortedMedia.isEmpty {
                    // 纯文字条目（例如没有配图的知乎回答）不显示媒体区
                    Color.clear.frame(height: 54)
                } else {
                    MediaGallery(item: item)
                        .frame(height: 452)
                        .ignoresSafeArea(edges: .top)
                }

                content
                    .background(Theme.canvas)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
                    .offset(y: item.sortedMedia.isEmpty ? 0 : -24)
                    .padding(.bottom, item.sortedMedia.isEmpty ? 0 : -24)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 54)
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button {
                    UIPasteboard.general.string = item.sourceURL
                    appState.toast = ToastMessage(text: "链接已复制", style: .success)
                } label: {
                    Label("复制原链接", systemImage: "link")
                }

                Button {
                    if let url = URL(string: item.sourceURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("在浏览器打开", systemImage: "safari")
                }

                if let notes = item.parseNotes, !notes.isEmpty {
                    Button {
                        showParseLog = true
                    } label: {
                        Label("查看解析日志", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    LibraryService.delete(item)
                    dismiss()
                } label: {
                    Label("删除收藏", systemImage: "trash")
                }
                .disabled(cache.isCaching(item.id))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.black.opacity(0.32)))
            }
            .padding(.trailing, 16)
            .padding(.top, 54)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(item: item)
        }
        .sheet(isPresented: $showParseLog) {
            ParseLogView(
                title: item.displayTitle,
                log: item.parseNotes ?? ""
            )
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AuthorAvatar(
                    url: item.authorAvatarURL.flatMap(URL.init(string:)),
                    name: item.authorName,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.authorName.isEmpty ? "未知作者" : item.authorName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 5) {
                        Text(item.platform.displayName)
                        Text("·")
                        Text(Formatters.day(item.publishedAt ?? item.savedAt))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Text(item.isCached ? "已缓存" : "未缓存")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.isCached ? Theme.success : Theme.inkSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(item.isCached ? Theme.success.opacity(0.12) : Theme.fill))
            }
            .padding(.top, 22)

            if !item.title.isEmpty {
                Text(item.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .padding(.top, 16)
            }

            if !item.text.isEmpty {
                Text(item.text)
                    .font(.system(size: 15.5))
                    .lineSpacing(7)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
            }

            HStack(alignment: .top, spacing: 8) {
                FlowTags(tags: item.tags)
                Button {
                    showTagEditor = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("标签")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(Capsule().fill(Theme.fill.opacity(0.7)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            HStack(spacing: 14) {
                Text("字 · \(item.text.count)")
                Text("图 · \(item.sortedMedia.filter { $0.kind != .video }.count)")
                Text("视频 · \(item.sortedMedia.filter { $0.kind == .video }.count)")
                if item.cacheBytes > 0 {
                    Text(FileSize.string(item.cacheBytes))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.inkTertiary)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().overlay(Theme.hairline)

            Button {
                if let url = URL(string: item.sourceURL) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: 12))
                    Text(item.sourceURL)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.inkSecondary)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 120)
    }

    // MARK: - Bottom bar

    private var actionBar: some View {
        HStack(spacing: 22) {
            ShareLink(item: URL(string: item.sourceURL) ?? URL(string: "https://shibei.app")!) {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .medium))
                    Text("分享").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Theme.ink)
            }

            Button {
                Task { await PhotoSaver.save(item: item, cache: cache, appState: appState) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 19, weight: .medium))
                    Text("存相册").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Theme.ink)
            }

            Spacer()

            Button {
                Task { await cache.cache(item) }
            } label: {
                HStack(spacing: 6) {
                    if cache.isCaching(item.id) {
                        ProgressView().tint(.white).scaleEffect(0.8)
                        Text("缓存中 \(Int((cache.progress(for: item.id) ?? 0) * 100))%")
                    } else {
                        Image(systemName: item.isCached ? "checkmark" : "arrow.down.to.line")
                        Text(item.isCached ? "已缓存到本地" : "缓存到本地")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(Theme.ink))
            }
            .disabled(cache.isCaching(item.id))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
    }
}

// MARK: - 解析日志

struct ParseLogView: View {
    let title: String
    let log: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)

                    Text(log)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
            .background(Theme.canvas)
            .navigationTitle("解析日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = log
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 标签编辑

@MainActor
struct TagEditorSheet: View {
    @Bindable var item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("输入标签名", text: $draft)
                            .submitLabel(.done)
                            .onSubmit(addTag)
                        Button("添加") { addTag() }
                            .disabled(trimmedDraft.isEmpty)
                    }
                } header: {
                    Text("新建")
                } footer: {
                    Text("标签会同时用于首页筛选。")
                }

                if !item.tags.isEmpty {
                    Section("已有标签") {
                        ForEach(item.tags, id: \.self) { tag in
                            HStack {
                                Text("#\(tag)")
                                Spacer()
                                Button(role: .destructive) {
                                    remove(tag)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Theme.danger)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTag() {
        let tag = trimmedDraft
        guard !tag.isEmpty, !item.tags.contains(tag) else {
            draft = ""
            return
        }
        item.tags.append(tag)
        LibraryService.updateTags(item, tags: item.tags)
        draft = ""
    }

    private func remove(_ tag: String) {
        item.tags.removeAll { $0 == tag }
        LibraryService.updateTags(item, tags: item.tags)
    }
}

// MARK: - 标签流

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 27)
                    .background(Capsule().fill(Theme.fill.opacity(0.7)))
            }
        }
    }
}

/// 简易流式布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if width + size.width > maxWidth, width > 0 {
                height += rowHeight + spacing
                width = 0
                rowHeight = 0
            }
            width += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth == .infinity ? width : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
