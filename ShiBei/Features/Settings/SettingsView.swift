import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("themeMode") private var themeMode = "system"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("外观", selection: $themeMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("外观")
                } footer: {
                    Text("跟随系统时会随 iOS 的深色模式自动切换；也可以在这里固定浅色或深色。")
                }

                Section("内容") {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        SettingsMenuRow(icon: "gearshape.fill", color: Color(rgb: 0x8E8E93), title: "通用", subtitle: "外观、字体、默认排序")
                    }
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        SettingsMenuRow(icon: "chart.bar.fill", color: Color(rgb: 0x5B8DEF), title: "统计", subtitle: "收藏、文字、图片、话题")
                    }
                    NavigationLink {
                        TagManagerView()
                    } label: {
                        SettingsMenuRow(icon: "tag.fill", color: Color(rgb: 0xF6B26B), title: "标签管理", subtitle: "标签、话题、自动标记")
                    }
                }

                Section("存储与网络") {
                    NavigationLink {
                        CacheView()
                    } label: {
                        SettingsMenuRow(icon: "cylinder.fill", color: Color(rgb: 0xC77700), title: "缓存", subtitle: "占用、自动缓存、上限")
                    }
                    NavigationLink {
                        DownloadSettingsView()
                    } label: {
                        SettingsMenuRow(icon: "arrow.down.circle.fill", color: Color(rgb: 0x2BA24C), title: "下载", subtitle: "清晰度、并发、仅 Wi-Fi")
                    }
                }

                Section("其他") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsMenuRow(icon: "info.circle.fill", color: Color(rgb: 0x0A7CFF), title: "关于", subtitle: "版本 1.0.0 · 使用说明 · 反馈")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 56)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("拾贝")
                        .font(Theme.wordmark())
                        .tracking(4)
                }
            }
        }
    }
}

private struct SettingsMenuRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 通用

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("themeMode") private var themeMode = "system"
    @AppStorage("defaultSort") private var defaultSort = SortOrder.saved.rawValue
    @AppStorage("defaultDimension") private var defaultDimension = FilterDimension.all.rawValue

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $themeMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("默认分类维度", selection: $defaultDimension) {
                    ForEach(FilterDimension.allCases) { dimension in
                        Text(dimension.title).tag(dimension.rawValue)
                    }
                }
                Picker("默认排序", selection: $defaultSort) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.title).tag(order.rawValue)
                    }
                }
            } header: {
                Text("列表")
            } footer: {
                Text("修改后立即生效，下次启动也会沿用。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: defaultDimension) { _, raw in
            if let dimension = FilterDimension(rawValue: raw) {
                appState.filter.dimension = dimension
            }
        }
        .onChange(of: defaultSort) { _, raw in
            if let order = SortOrder(rawValue: raw) {
                appState.sortOrder = order
            }
        }
    }
}

// MARK: - 下载

struct DownloadSettingsView: View {
    @AppStorage("downloadQuality") private var downloadQuality = "1080P"
    @AppStorage("maxConcurrentDownloads") private var maxConcurrent = 3
    @AppStorage("saveLiveAsLivePhoto") private var saveLiveAsLivePhoto = true

    var body: some View {
        Form {
            Section {
                Picker("默认清晰度", selection: $downloadQuality) {
                    Text("最高").tag("最高")
                    Text("1080P").tag("1080P")
                    Text("720P").tag("720P")
                }
                Stepper("同时下载 \(maxConcurrent) 项", value: $maxConcurrent, in: 1...6)
                LabeledContent("B 站音视频合并", value: "自动")
            } header: {
                Text("视频")
            } footer: {
                Text("B 站高清视频的音轨与画面是分离的，保存时会自动合并为一个 MP4。")
            }

            Section("媒体与登录") {
                Toggle("实况图保存为实况", isOn: $saveLiveAsLivePhoto)
                NavigationLink("登录态 Cookie") {
                    AdvancedSettingsView()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 统计

struct StatisticsView: View {
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]

    private var characterCount: Int {
        items.reduce(0) { $0 + $1.text.count }
    }

    private var imageCount: Int {
        items.reduce(0) { partial, item in
            partial + item.media.filter { $0.kind != .video }.count
        }
    }

    private var tagCount: Int {
        Set(items.flatMap(\.tags)).count
    }

    private var topicCount: Int {
        Set(items.flatMap(\.topics)).count
    }

    private var platformCounts: [PlatformCount] {
        var counts: [Platform: Int] = [:]
        for item in items { counts[item.platform, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map {
            PlatformCount(platform: $0.key, count: $0.value)
        }
    }

    private struct PlatformCount: Identifiable {
        let platform: Platform
        let count: Int
        var id: String { platform.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(items.count)")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-1)
                Text("收藏总数")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkTertiary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    statCard("\(characterCount)", "文字")
                    statCard("\(imageCount)", "图片")
                    statCard("\(tagCount)", "标签")
                    statCard("\(topicCount)", "话题")
                }
                .padding(.top, 18)

                if !platformCounts.isEmpty {
                    Text("平台分布")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(platformCounts) { entry in
                            HStack(spacing: 8) {
                                Circle().fill(entry.platform.tint).frame(width: 7, height: 7)
                                Text(entry.platform.displayName).font(.system(size: 13))
                                Spacer()
                                Text("\(entry.count)").font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
    }
}

// MARK: - 关于

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.ink)
                    .frame(width: 88, height: 88)
                    .overlay(
                        Text("拾")
                            .font(.system(size: 44, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.onInk)
                    )
                    .padding(.top, 24)

                Text("拾贝")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .tracking(3)

                Text("把小红书的图文、B 站的高清视频、微博的实况图，连同完整正文一起收进本地。链接失效也能继续看。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)

                VStack(alignment: .leading, spacing: 12) {
                    bullet("支持平台", "小红书 / 抖音 / B 站 / 知乎 / 微博 / 小黑盒")
                    bullet("媒体类型", "图片、视频、实况图（Live Photo）")
                    bullet("离线能力", "全部媒体落地到本地，断网可浏览与播放")
                    bullet("隐私", "不登录、不上传，所有数据只存在本机")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
                .padding(.horizontal, 20)

                VStack(spacing: 6) {
                    Text("版本 1.0.0 (1)")
                    NavigationLink("快捷指令设置") { ShortcutsHelpView() }
                        .foregroundStyle(Color(rgb: 0x0A7CFF))
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 6)
            }
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("在任意 App 里分享链接时，直接调用拾贝解析，省去复制粘贴。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)

                step(1, "打开「快捷指令」App，新建快捷指令")
                step(2, "添加操作 → 搜索「拾贝」→ 选择「收藏链接到拾贝」")
                step(3, "在操作参数里选择「快捷指令输入」，并勾选「接收 URL、文本」")
                step(4, "分享面板中把该快捷指令添加到收藏，之后从任何 App 分享即可一键收藏")
                step(5, "也可以直接使用链接：shibei://parse?url=<链接地址>")

                Text("提示：快捷指令在后台执行，不会打开 App，只负责收藏；需要离线缓存时再进 App 点一下缓存。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Theme.canvas)
        .navigationTitle("快捷指令")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.onInk)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.ink))
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}
