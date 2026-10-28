import SwiftUI
import SwiftData
import UIKit

@MainActor
struct CaptureView: View {
    var prefill: String?

    @Environment(AppState.self) private var appState
    @Environment(CacheManager.self) private var cache
    @Environment(\.dismiss) private var dismiss

    @AppStorage("autoTagByPlatform") private var autoTagByPlatform = true
    @AppStorage("autoCache") private var autoCache = false

    @State private var text = ""
    @State private var phase: Phase = .idle
    @State private var result: ParsedContent?
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool

    private enum Phase: Equatable {
        case idle, parsing, success, failed
    }

    private var detectedPlatform: Platform? {
        guard let url = LinkExtractor.bestLink(in: text) else { return nil }
        return Platform.detect(from: url)
    }

    private var canParse: Bool {
        LinkExtractor.bestLink(in: text) != nil && phase != .parsing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    editor

                    if let platform = detectedPlatform {
                        detected(platform)
                    }

                    actionArea

                    if phase == .success, let result {
                        preview(result)
                    }

                    if phase == .failed {
                        failure
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("添加收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let paste = UIPasteboard.general.string {
                            text = paste
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .tint(Theme.ink)
                }
            }
            .interactiveDismissDisabled(phase == .parsing)
        }
        .onAppear {
            if text.isEmpty {
                if let prefill, !prefill.isEmpty {
                    text = prefill
                } else if let paste = UIPasteboard.general.string,
                          LinkExtractor.bestLink(in: paste) != nil {
                    text = paste
                }
            }
        }
        .onDisappear {
            // 深链带入的预填内容只生效一次
            appState.pendingLink = nil
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("粘贴分享链接")
                .font(.system(size: 20, weight: .bold))
            Text("支持小红书、抖音、B 站、知乎、微博、小黑盒的图文与视频")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("把 App 里「复制链接」的内容整段粘进来，链接和文案混在一起也没关系…")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(minHeight: 132, maxHeight: 180)
                .focused($editorFocused)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func detected(_ platform: Platform) -> some View {
        HStack(spacing: 10) {
            Text(platform.shortMark)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(platform.tint))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(platform.displayName) · 已识别链接")
                    .font(.system(size: 13, weight: .semibold))
                Text(LinkExtractor.bestLink(in: text)?.absoluteString ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceMuted)
        )
    }

    @ViewBuilder
    private var actionArea: some View {
        switch phase {
        case .idle, .failed, .success:
            PrimaryButton(title: "解析内容", icon: "wand.and.stars", enabled: canParse) {
                parse()
            }
        case .parsing:
            VStack(spacing: 10) {
                HStack(spacing: 9) {
                    ProgressView()
                    Text("正在解析页面并提取媒体…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.ink)
            }
            .frame(height: 50)
        }
    }

    private func preview(_ content: ParsedContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PlatformBadge(platform: content.platform, size: 18)
                Text(content.authorName.isEmpty ? content.platform.displayName : content.authorName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(content.media.count) 项媒体")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
            }

            if !content.title.isEmpty {
                Text(content.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
            }

            if !content.text.isEmpty {
                Text(content.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)
            }

            if !content.media.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(content.media.prefix(8)) { media in
                        ZStack {
                            AsyncImage(url: media.imageURL ?? media.posterURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(Theme.fill)
                                }
                            }
                            if media.kind == .video {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(Circle().fill(.black.opacity(0.45)))
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }

            HStack(spacing: 8) {
                Text("字 · \(content.characterCount)")
                Text("图 · \(content.images.count + content.livePhotos.count)")
                if !content.videos.isEmpty { Text("视频 · \(content.videos.count)") }
                if !content.livePhotos.isEmpty { Text("实况 · \(content.livePhotos.count)") }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkTertiary)

            HStack(spacing: 10) {
                PrimaryButton(title: "保存并缓存", icon: "arrow.down.to.line") {
                    save(content, cacheAfter: true)
                }
                Button {
                    save(content, cacheAfter: false)
                } label: {
                    Text("仅收藏")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.surface)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text("解析失败")
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(errorMessage ?? "未知错误")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("常见原因：链接需要登录、平台风控、或分享页结构改版。可以先用浏览器打开链接确认内容公开可见，再重试。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.warning.opacity(0.08))
        )
    }

    // MARK: - Actions

    private func parse() {
        editorFocused = false
        phase = .parsing
        errorMessage = nil

        Task {
            do {
                let content = try await ParseRouter.shared.resolve(text: text)
                await MainActor.run {
                    result = content
                    phase = .success
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .failed
                }
            }
        }
    }

    private func save(_ content: ParsedContent, cacheAfter: Bool) {
        do {
            let tags = autoTagByPlatform ? [content.platform.displayName] : []
            let item = try LibraryService.save(content, tags: tags)
            dismiss()
            let shouldCache = cacheAfter || autoCache
            appState.toast = ToastMessage(
                text: shouldCache ? "已收藏，开始缓存" : "已收藏",
                style: .success
            )
            if shouldCache {
                Task { await cache.cache(item) }
            }
        } catch {
            appState.toast = ToastMessage(text: "保存失败：\(error.localizedDescription)", style: .failure)
        }
    }
}
